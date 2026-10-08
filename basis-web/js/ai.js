// Bring your own key: each person connects their own Claude (Anthropic) or
// Gemini (Google) account. The key is kept only in this browser and requests
// go straight from here to that provider; nothing passes through Basis.

import { storage } from './util.js';

const KEY = 'basis.ai';

export const PROVIDERS = {
  claude: {
    name: 'Claude',
    company: 'Anthropic',
    console: 'Claude Console',
    signup: 'https://console.anthropic.com/',
    billing: 'https://console.anthropic.com/settings/billing',
    keys: 'https://console.anthropic.com/settings/keys',
    keyPrefix: 'sk-ant-',
    models: [
      { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', note: 'Best at messy handwriting and math' },
      { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', note: 'About half the cost' },
      { id: 'claude-haiku-5-5', label: 'Claude Haiku 5.5', note: 'Cheapest, less accurate' },
    ],
    defaultModel: 'claude-opus-5-5',
  },
  gemini: {
    name: 'Gemini',
    company: 'Google',
    console: 'Google AI Studio',
    signup: 'https://aistudio.google.com/',
    keys: 'https://aistudio.google.com/app/apikey',
    keyPrefix: 'AIza',
    models: null, // picked from the account's available models when connecting
    defaultModel: null,
  },
};

/** { provider, key, model, connectedAt } or null. */
export function aiConfig() {
  const c = storage.get(KEY, null);
  return c && PROVIDERS[c.provider] && c.key ? c : null;
}

export function saveAIConfig(cfg) { storage.set(KEY, { ...cfg, connectedAt: Date.now() }); }
export function setAIModel(model) { const c = aiConfig(); if (c) storage.set(KEY, { ...c, model }); }
export function clearAIConfig() { storage.set(KEY, null); }

export function maskKey(key) {
  const k = String(key || '');
  return k.length > 12 ? `${k.slice(0, k.startsWith('sk-ant-') ? 7 : 4)}…${k.slice(-4)}` : '••••';
}

// ---------- Claude ----------

let sdk = null;
async function anthropic(key) {
  sdk ||= import('../vendor/anthropic-sdk.mjs').then((m) => m.default);
  const Anthropic = await sdk;
  // The key belongs to the person using this browser and only goes to Anthropic.
  return { Anthropic, client: new Anthropic({ apiKey: key, dangerouslyAllowBrowser: true, maxRetries: 1 }) };
}

/** Plain-language reasons for Claude API errors (most specific first). */
function claudeError(Anthropic, e) {
  if (e instanceof Anthropic.AuthenticationError) return 'That key wasn’t accepted. Check that you copied all of it (it starts with “sk-ant-”).';
  if (e instanceof Anthropic.PermissionDeniedError) return 'This key isn’t allowed to do that. Make a new key in the Claude Console.';
  if (e instanceof Anthropic.NotFoundError) return 'This model isn’t available on your account. Pick a different one.';
  if (e instanceof Anthropic.RateLimitError) return 'Too many requests right now. Wait a minute and try again.';
  if (e instanceof Anthropic.APIConnectionError) return 'Couldn’t reach Anthropic. Check your internet connection.';
  if (e instanceof Anthropic.APIError) {
    if (e.status === 402 || e.type === 'billing_error') return 'Your Anthropic account needs credit. Add some under Billing in the Claude Console.';
    if (e.status >= 500) return 'Anthropic is having trouble right now. Try again in a few minutes.';
    return `Anthropic returned an error (${e.status ?? 'unknown'}): ${e.message}`;
  }
  return e?.message || String(e);
}

async function testClaude(key, model) {
  const { Anthropic, client } = await anthropic(key);
  try {
    // Looking up the model checks the key and access without using any credit.
    await client.models.retrieve(model);
    return { model };
  } catch (e) {
    throw new Error(claudeError(Anthropic, e));
  }
}

// ---------- Gemini ----------

const GEMINI = 'https://generativelanguage.googleapis.com/v1beta';

class GeminiError extends Error {
  constructor(message, status, raw = '') {
    super(message);
    this.status = status;
    // The model itself can't be used (retired, not on this account, or no free allowance): try another.
    this.modelProblem = status === 404 || (status === 400 && /model/i.test(raw)) || (status === 429 && /limit:\s*0\b/.test(raw));
    this.stop = !this.modelProblem && (status === 401 || status === 403 || status === 429 || /API_KEY_INVALID/.test(raw));
  }
}

async function gemini(path, key, init = {}) {
  let res;
  try {
    res = await fetch(`${GEMINI}/${path}`, { ...init, headers: { 'x-goog-api-key': key, ...(init.headers || {}) } });
  } catch {
    throw new GeminiError('Couldn’t reach Google. Check your internet connection.', 0);
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const raw = `${body?.error?.status || ''} ${body?.error?.message || ''} ${JSON.stringify(body?.error?.details || '')}`;
    const reason = body?.error?.details?.find?.((d) => d.reason)?.reason;
    if (res.status === 400 && reason === 'API_KEY_INVALID') throw new GeminiError('That key wasn’t accepted. Check that you copied all of it (it starts with “AIza”).', 400, raw);
    if (res.status === 403) throw new GeminiError('This key isn’t allowed to use the Gemini API. Make a new key in Google AI Studio.', 403, raw);
    if (res.status === 429 && !/limit:\s*0\b/.test(raw)) throw new GeminiError('You’ve hit the free tier’s limit for now. Wait a bit and try again.', 429, raw);
    throw new GeminiError(`Google said: ${body?.error?.message || res.statusText || `error ${res.status}`}`, res.status, raw);
  }
  return body;
}

/** Usable models, best first: stable "flash" models (newest first), then other flash, lite and pro models. */
function geminiCandidates(models) {
  const names = models.filter((m) => m.supportedGenerationMethods?.includes('generateContent')).map((m) => m.name.replace(/^models\//, ''))
    .filter((n) => /^gemini/.test(n) && !/image|tts|audio|live|embed|vision|learnlm|robotics|computer/.test(n));
  const version = (n) => parseFloat(/gemini-(\d+(?:\.\d+)?)/.exec(n)?.[1] || '0');
  const tier = (n) => (/^gemini-[\d.]+-flash$/.test(n) ? 0 : n === 'gemini-flash-latest' ? 1 : /flash-lite/.test(n) ? 3 : /flash/.test(n) ? 2 : /pro/.test(n) ? 4 : 5);
  return [...new Set(names)].sort((a, b) => tier(a) - tier(b) || version(b) - version(a) || a.length - b.length);
}

async function geminiModels(key) {
  return geminiCandidates((await gemini('models?pageSize=200', key)).models || []);
}

/** One generateContent call. Resolves to the reply's text. */
async function geminiGenerate(key, model, system, parts) {
  const body = await gemini(`models/${encodeURIComponent(model)}:generateContent`, key, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
      contents: [{ role: 'user', parts }],
      generationConfig: { temperature: 0, maxOutputTokens: 16000 },
    }),
  });
  const cand = body.candidates?.[0];
  if (!cand) throw new GeminiError(body.promptFeedback?.blockReason ? `Gemini declined to read this (${body.promptFeedback.blockReason}).` : 'Gemini didn’t return anything.', 200);
  const text = (cand.content?.parts || []).filter((x) => !x.thought).map((x) => x.text || '').join('').trim();
  if (!text && cand.finishReason && !['STOP', 'FINISH_REASON_UNSPECIFIED'].includes(cand.finishReason)) {
    throw new GeminiError(`Gemini stopped before answering (${cand.finishReason}).`, 200);
  }
  return text;
}

/** Tries models in order until one actually answers; resolves to { model, text }. */
async function geminiWithFallback(key, preferred, system, parts) {
  const tried = new Set();
  let last = null;
  const attempt = async (model) => {
    tried.add(model);
    return { model, text: await geminiGenerate(key, model, system, parts) };
  };
  if (preferred) {
    try { return await attempt(preferred); } catch (e) { if (!(e instanceof GeminiError) || !e.modelProblem) throw e; last = e; }
  }
  for (const model of (await geminiModels(key)).slice(0, 6)) {
    if (tried.has(model)) continue;
    try { return await attempt(model); } catch (e) { if (!(e instanceof GeminiError) || !e.modelProblem) throw e; last = e; }
  }
  throw last || new GeminiError('No Gemini model on this account can be used. Check Google AI Studio.', 0);
}

async function testGemini(key) {
  // Ask for a one-word reply: proves the key can actually generate, not just list models.
  const { model } = await geminiWithFallback(key, null, null, [{ text: 'Reply with the single word OK.' }]);
  return { model };
}

/** Checks a key without spending anything. Resolves to { model } or throws an Error with a readable message. */
export function testConnection(provider, key, model) {
  const k = String(key || '').trim();
  if (!k) return Promise.reject(new Error('Paste your API key first.'));
  if (provider === 'claude') return testClaude(k, model || PROVIDERS.claude.defaultModel);
  if (provider === 'gemini') return testGemini(k);
  return Promise.reject(new Error('Choose a provider first.'));
}

// ---------- Reading handwriting ----------

const AUTO_KEY = 'basis.ai.auto';
/** Whether pages you write on are read automatically (on unless turned off). */
export const autoRecognize = () => storage.get(AUTO_KEY, true) !== false;
export const setAutoRecognize = (on) => storage.set(AUTO_KEY, !!on);

const TRANSCRIBE = [
  'You transcribe images of pages from a student’s notebook so the notes can be searched.',
  'Transcribe all handwritten and printed text in reading order, one line per line of writing.',
  'Write math in LaTeX inside $…$, for example $\\int_0^\\pi \\sin^2(t)\\,dt$.',
  'Describe drawings, graphs and diagrams briefly in square brackets, for example [graph of y = x^2].',
  'Do not add commentary, headings or explanations, and do not correct or complete the writing.',
  'If there is no writing at all, reply with nothing.',
].join(' ');

const ERR_KEY = 'basis.ai.lastError';
/** The most recent problem reading pages, shown in the AI tab. */
export const lastAIError = () => storage.get(ERR_KEY, null);
export const setLastAIError = (message) => storage.set(ERR_KEY, message ? { message, at: Date.now() } : null);

export class AIError extends Error {
  constructor(message, { stop = false } = {}) { super(message); this.stop = stop; }
}

/** Transcribes one image (base64 JPEG) of notebook writing. Resolves to plain text with $LaTeX$ math. */
export async function transcribeImage(base64) {
  const cfg = aiConfig();
  if (!cfg) throw new AIError('AI isn’t set up.', { stop: true });
  return cfg.provider === 'claude' ? transcribeClaude(cfg, base64) : transcribeGemini(cfg, base64);
}

async function transcribeClaude(cfg, base64) {
  const { Anthropic, client } = await anthropic(cfg.key);
  const params = {
    model: cfg.model,
    max_tokens: 8000,
    output_config: { effort: 'low' }, // transcription doesn't need deep thinking
    system: TRANSCRIBE,
    messages: [{ role: 'user', content: [
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: base64 } },
      { type: 'text', text: 'Transcribe this page.' },
    ] }],
  };
  // Opus and Sonnet can retry a (rare, false-positive) safety decline on another model server-side.
  const fallback = cfg.model !== 'claude-haiku-5-5';
  let res;
  try {
    res = fallback
      ? await client.beta.messages.create({ ...params, betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' })
      : await client.messages.create(params);
  } catch (e) {
    const stop = e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError || e instanceof Anthropic.NotFoundError
      || (e instanceof Anthropic.APIError && (e.status === 402 || e.type === 'billing_error'));
    throw new AIError(claudeError(Anthropic, e), { stop: stop || e instanceof Anthropic.RateLimitError });
  }
  if (res.stop_reason === 'refusal') throw new AIError('Claude declined to read this page.');
  return res.content.filter((b) => b.type === 'text').map((b) => b.text).join('').trim();
}

async function transcribeGemini(cfg, base64) {
  try {
    const { model, text } = await geminiWithFallback(cfg.key, cfg.model, TRANSCRIBE,
      [{ inline_data: { mime_type: 'image/jpeg', data: base64 } }, { text: 'Transcribe this page.' }]);
    if (model !== cfg.model) setAIModel(model); // remember the model that works
    return text;
  } catch (e) {
    throw new AIError(e.message, { stop: !!e.stop });
  }
}
