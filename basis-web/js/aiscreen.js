// The AI tab: connect your own Claude or Gemini account, step by step.

import { h } from './util.js';
import { icon } from './icons.js';
import { toast, confirmDialog, selectField, toggle } from './ui.js';
import { PROVIDERS, aiConfig, saveAIConfig, setAIModel, clearAIConfig, maskKey, testConnection, autoRecognize, setAutoRecognize } from './ai.js';

const STEPS = ['Choose', 'Account', 'Key', 'Connect', 'Done'];

export function aiScreen(app) {
  const root = h('section', { class: 'screen ai-screen' });
  const state = { step: 0, provider: aiConfig()?.provider || 'claude', key: '', model: null, error: '', busy: false };
  let wizard = false;

  const render = () => {
    const cfg = aiConfig();
    root.replaceChildren(
      h('header', { class: 'screen-header' }, h('h1', {}, 'AI')),
      wizard ? wizardView() : cfg ? connectedView(cfg) : introView());
  };
  const startWizard = () => { wizard = true; Object.assign(state, { step: 0, key: '', error: '', busy: false }); render(); };

  // ---------- Not set up ----------

  function introView() {
    return h('div', { class: 'ai-body' },
      h('div', { class: 'settings-group ai-hero' },
        h('span', { class: 'ai-hero-icon' }, icon('sparkle', 30)),
        h('h2', { class: 'ai-title' }, 'Bring your own AI'),
        h('p', { class: 'muted' }, 'Connect your own Claude or Gemini account to use AI study tools in Basis: search your handwriting, and make practice exams, flashcards and summaries from your notes.'),
        h('ul', { class: 'ai-points' },
          h('li', {}, icon('lock', 18), h('span', {}, 'Your key stays on this device. Your notes go only to the provider you choose, never to Basis.')),
          h('li', {}, icon('dollar', 18), h('span', {}, 'Any cost is on your own account. Gemini has a free tier; Claude is pay as you go (usually a few dollars a month).')),
          h('li', {}, icon('clock', 18), h('span', {}, 'Takes about 5 minutes, and it’s optional.'))),
        h('div', { class: 'row-actions' }, h('button', { class: 'btn primary', onclick: startWizard }, 'Set Up AI'))));
  }

  // ---------- Connected ----------

  function connectedView(cfg) {
    const p = PROVIDERS[cfg.provider];
    const status = h('p', { class: 'muted small ai-status' });
    const modelRow = p.models
      ? h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Model'),
        selectField('ai-model', p.models.map((m) => ({ value: m.id, label: `${m.label} · ${m.note}` })), cfg.model, (v) => { setAIModel(v); toast('Model changed'); }))
      : h('div', { class: 'form-row inline' }, h('span', { class: 'form-label' }, 'Model'), h('span', {}, cfg.model || 'Automatic'));
    return h('div', { class: 'ai-body' },
      h('div', { class: 'settings-group' },
        h('div', { class: 'ai-connected' }, h('span', { class: 'ai-check' }, icon('check', 20)),
          h('div', {}, h('div', { class: 'ai-title' }, `Connected to ${p.name}`), h('div', { class: 'muted small' }, `${p.company} · key ${maskKey(cfg.key)}`))),
        modelRow,
        h('div', { class: 'row-actions' },
          h('button', { class: 'btn', onclick: async (e) => {
            const b = e.currentTarget; b.disabled = true; status.textContent = 'Checking…';
            try { await testConnection(cfg.provider, cfg.key, cfg.model); status.textContent = 'Everything’s working.'; } catch (err) { status.textContent = err.message; }
            b.disabled = false;
          } }, 'Test Connection'),
          h('button', { class: 'btn', onclick: startWizard }, 'Change Provider or Key'),
          h('button', { class: 'btn danger', onclick: async () => {
            if (!(await confirmDialog({ title: 'Disconnect AI?', message: 'Your key will be removed from this device. You can set it up again any time.', confirm: 'Disconnect' }))) return;
            clearAIConfig(); toast('AI disconnected'); render();
          } }, 'Disconnect')),
        status),
      h('div', { class: 'settings-group' },
        h('h2', { class: 'list-title' }, 'Handwriting search'),
        h('p', { class: 'muted' }, 'AI reads your handwriting (math included) so you can find it with Find in Notebook (⌘F or the ⋯ menu) and in Search.'),
        toggle('ai-auto', 'Read pages as I write', autoRecognize(), (on) => { setAutoRecognize(on); toast(on ? 'Pages you write on will be read a few seconds after you stop.' : 'Pages won’t be read automatically. Use Make Notebook Searchable in a notebook’s ⋯ menu.'); }),
        h('p', { class: 'muted small' }, 'Each page is read once, and again only after it changes. To read the pages already in a notebook, open it and choose Make Notebook Searchable in the ⋯ menu.')),
      h('div', { class: 'settings-group' },
        h('h2', { class: 'list-title' }, 'Coming soon'),
        h('ul', { class: 'ai-points' },
          h('li', {}, icon('graduation', 18), h('span', {}, h('b', {}, 'Study Buddy. '), 'Practice exams, flashcards and summaries made from your notes.')))),
      h('p', { class: 'muted small about' }, `Your key is stored only in this browser on this device and isn’t included in backups. Requests go straight from here to ${p.company}. You can see usage and set spending limits in ${p.console}.`));
  }

  // ---------- Step by step ----------

  function wizardView() {
    const p = PROVIDERS[state.provider];
    const go = (n) => { state.step = n; state.error = ''; render(); };
    const next = (label = 'Next', disabled = false) => h('button', { class: 'btn primary', disabled, onclick: () => go(state.step + 1) }, label);
    const back = state.step > 0 && state.step < 4 ? h('button', { class: 'btn ghost', onclick: () => go(state.step - 1) }, 'Back') : null;
    const cancel = state.step < 4 ? h('button', { class: 'btn ghost', onclick: () => { wizard = false; render(); } }, 'Cancel') : null;
    const link = (href, label) => h('a', { class: 'btn', href, target: '_blank', rel: 'noopener noreferrer' }, icon('export', 18), label);
    const steps = (...items) => h('ol', { class: 'ai-steps' }, ...items.map((x) => h('li', {}, x)));

    let title, body, actions;
    switch (state.step) {
      case 0: {
        title = 'Choose an AI provider';
        const card = (id, badge, lines) => h('button', {
          class: `ai-choice ${state.provider === id ? 'on' : ''}`, 'aria-pressed': String(state.provider === id),
          onclick: () => { state.provider = id; render(); },
        }, h('span', { class: 'ai-choice-head' }, h('b', {}, `${PROVIDERS[id].name}`), h('span', { class: 'muted small' }, `by ${PROVIDERS[id].company}`), h('span', { class: 'ai-badge' }, badge)),
        ...lines.map((l) => h('span', { class: 'ai-choice-line' }, l)));
        body = h('div', { class: 'ai-choices' },
          card('claude', 'Best results', ['Best at reading messy handwriting and math.', 'Pay as you go: a few cents per page, usually a few dollars a month.', 'Needs a payment method.']),
          card('gemini', 'Free to start', ['Google’s free tier has daily limits, enough to try things out.', 'On the free tier, Google may use what you send to improve its products.', 'Needs a Google account.']));
        actions = [next()];
        break;
      }
      case 1:
        title = `Create your ${p.name} account`;
        body = state.provider === 'claude'
          ? steps(
            h('span', {}, 'Open the Claude Console and sign up (or sign in).'),
            h('span', {}, 'Go to ', h('b', {}, 'Billing'), ' and add a small amount of credit, for example $5.'),
            h('span', {}, 'While you’re there, set a ', h('b', {}, 'monthly spend limit'), ' so you’re never surprised.'))
          : steps(
            h('span', {}, 'Open Google AI Studio.'),
            h('span', {}, 'Sign in with your Google account and accept the terms.'));
        body = h('div', { class: 'ai-step-body' }, body, h('div', { class: 'row-actions' }, link(p.signup, `Open ${p.console}`), state.provider === 'claude' ? link(p.billing, 'Open Billing') : null));
        actions = [next('I’ve Done This')];
        break;
      case 2:
        title = 'Create an API key';
        body = h('div', {},
          state.provider === 'claude'
            ? steps(
              h('span', {}, 'Open ', h('b', {}, 'API Keys'), ' in the Claude Console.'),
              h('span', {}, 'Tap ', h('b', {}, 'Create Key'), ' and name it “Basis”.'),
              h('span', {}, 'Copy the key. It starts with ', h('code', {}, 'sk-ant-'), '. You’ll only see it once.'))
            : steps(
              h('span', {}, 'Open ', h('b', {}, 'Get API key'), ' in Google AI Studio.'),
              h('span', {}, 'Tap ', h('b', {}, 'Create API key'), '.'),
              h('span', {}, 'Copy the key. It starts with ', h('code', {}, 'AIza'), '.')),
          h('p', { class: 'muted small' }, 'Treat the key like a password: anyone who has it can use your account.'));
        body.append(h('div', { class: 'row-actions' }, link(p.keys, 'Open API Keys')));
        actions = [next('I’ve Copied It')];
        break;
      case 3: {
        title = 'Paste your key';
        const input = h('input', { class: 'field', id: 'ai-key', type: 'password', autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false', placeholder: `${p.keyPrefix}…`, value: state.key, 'aria-label': 'API key' });
        input.addEventListener('input', () => { state.key = input.value; });
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') connect(); });
        const show = h('button', { class: 'btn ghost small', onclick: () => { input.type = input.type === 'password' ? 'text' : 'password'; } }, 'Show');
        const paste = navigator.clipboard?.readText ? h('button', { class: 'btn small', onclick: async () => {
          try { input.value = state.key = (await navigator.clipboard.readText()).trim(); } catch { toast('Couldn’t read the clipboard. Tap the box and paste instead.'); }
        } }, 'Paste') : null;
        async function connect() {
          state.key = input.value.trim();
          state.busy = true; state.error = ''; render();
          try {
            const { model } = await testConnection(state.provider, state.key, PROVIDERS[state.provider].defaultModel);
            saveAIConfig({ provider: state.provider, key: state.key, model });
            state.busy = false; state.step = 4; state.key = ''; render();
          } catch (e) {
            state.busy = false; state.error = e.message; render();
          }
        }
        body = h('div', {},
          h('div', { class: 'ai-key-row' }, input, show, paste),
          state.error ? h('p', { class: 'ai-error', role: 'alert' }, state.error) : null,
          h('p', { class: 'muted small' }, `Basis checks the key with ${p.company} (this doesn’t use any credit), then keeps it only on this device.`));
        actions = [h('button', { class: 'btn primary', disabled: state.busy, onclick: connect }, state.busy ? 'Checking…' : 'Connect')];
        setTimeout(() => document.getElementById('ai-key')?.focus(), 50);
        break;
      }
      default:
        title = 'You’re connected';
        body = h('div', {},
          h('div', { class: 'ai-connected' }, h('span', { class: 'ai-check' }, icon('check', 20)), h('span', {}, `Basis is connected to your ${p.name} account.`)),
          h('p', { class: 'muted' }, 'You can change the model, test the connection or disconnect any time from this tab.'));
        actions = [h('button', { class: 'btn primary', onclick: () => { wizard = false; render(); } }, 'Done')];
    }

    return h('div', { class: 'ai-body' },
      h('div', { class: 'ai-progress', 'aria-label': `Step ${state.step + 1} of ${STEPS.length}` },
        ...STEPS.map((s, i) => h('span', { class: `ai-progress-step ${i < state.step ? 'done' : i === state.step ? 'on' : ''}` }, h('span', { class: 'ai-progress-dot' }, i < state.step ? icon('check', 14) : String(i + 1)), h('span', { class: 'ai-progress-label' }, s)))),
      h('div', { class: 'settings-group ai-step' },
        h('h2', { class: 'ai-title' }, title),
        body,
        h('div', { class: 'ai-actions' }, cancel, h('span', { class: 'spacer' }), back, ...actions.filter(Boolean))));
  }

  render();
  return root;
}
