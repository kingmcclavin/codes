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

async function gemini(path, key, init = {}) {
  let res;
  try {
    res = await fetch(`${GEMINI}/${path}`, { ...init, headers: { 'x-goog-api-key': key, ...(init.headers || {}) } });
  } catch {
    throw new Error('Couldn’t reach Google. Check your internet connection.');
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const reason = body?.error?.details?.find?.((d) => d.reason)?.reason;
    if (res.status === 400 && reason === 'API_KEY_INVALID') throw new Error('That key wasn’t accepted. Check that you copied all of it (it starts with “AIza”).');
    if (res.status === 403) throw new Error('This key isn’t allowed to use the Gemini API. Make a new key in Google AI Studio.');
    if (res.status === 429) throw new Error('You’ve hit the free tier’s limit for now. Wait a bit and try again.');
    throw new Error(`Google returned an error (${res.status}): ${body?.error?.message || res.statusText}`);
  }
  return body;
}

/** Newest "flash" model the account can use (fast, and the one with the most generous free tier). */
function pickGeminiModel(models) {
  const usable = models.filter((m) => m.supportedGenerationMethods?.includes('generateContent'));
  const version = (name) => parseFloat(/gemini-(\d+(?:\.\d+)?)/.exec(name)?.[1] || '0');
  const rank = (m) => {
    const n = m.name.replace(/^models\//, '');
    if (!/^gemini-[\d.]+-flash$/.test(n)) return -1; // stable flash only (no lite, preview or dated builds)
    return version(n);
  };
  const best = usable.map((m) => ({ m, r: rank(m) })).filter((x) => x.r >= 0).sort((a, b) => b.r - a.r)[0]?.m
    || usable.find((m) => /flash/.test(m.name) && !/lite|image|tts|audio|live/.test(m.name));
  return best?.name.replace(/^models\//, '') || null;
}

async function testGemini(key) {
  const body = await gemini('models?pageSize=200', key);
  const model = pickGeminiModel(body.models || []);
  if (!model) throw new Error('Your key works, but no suitable Gemini model is available on this account.');
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
