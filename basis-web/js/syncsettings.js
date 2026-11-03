// Settings → Cloud Sync: connect Google Drive, see status, sync now, disconnect.

import { h, relativeTime } from './util.js';
import { icon } from './icons.js';
import { toast, confirmDialog } from './ui.js';
import { syncConnected, syncAccount, syncState, syncStatus, syncEvents, syncServerConfig, connectGoogle, disconnectGoogle, googleSetupValues } from './sync.js';

export function cloudSyncGroup(app) {
  const group = h('div', { class: 'settings-group sync-group' });
  const render = async () => {
    if (!group.isConnected && group.dataset.rendered) { syncEvents.removeEventListener('status', onStatus); return; }
    group.dataset.rendered = '1';
    const head = h('h2', { class: 'list-title' }, 'Cloud Sync');
    if (!syncConnected()) {
      const cfg = await syncServerConfig();
      group.replaceChildren(head,
        h('p', { class: 'muted' }, 'Keep your notebooks in your own Google Drive, backed up and the same on every device. Basis can only see the files it creates there, and your notes go straight to your Drive. ', h('a', { href: 'privacy.html', target: '_blank', rel: 'noopener' }, 'Privacy Policy')),
        cfg.configured
          ? h('div', { class: 'row-actions' }, h('button', { class: 'btn primary', onclick: async (e) => {
            e.currentTarget.disabled = true;
            try { await connectGoogle(); } catch (err) { toast(err.message); e.currentTarget.disabled = false; }
          } }, icon('cloud', 18), 'Connect Google Drive'))
          : h('p', { class: 'muted small' }, 'Google sign-in isn’t set up on this site yet. The person who runs this Basis site needs to add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in Vercel (see the README).'),
        setupDetails(cfg));
      return;
    }
    const a = syncAccount(), st = syncState(), s = syncStatus();
    const line = s.state === 'syncing' ? `Syncing${s.total ? ` ${s.n} of ${s.total}` : ''}…`
      : s.state === 'offline' ? 'Offline. Changes will sync when you’re back online.'
        : s.state === 'error' ? `Couldn’t sync: ${s.message}`
          : st.lastSync ? `Last synced ${relativeTime(st.lastSync)}.` : 'Not synced yet.';
    group.replaceChildren(head,
      h('div', { class: 'sync-account' }, h('span', { class: `sync-dot ${s.state}` }),
        h('div', {}, h('div', { class: 'sync-title' }, `Google Drive${a.email ? ` · ${a.email}` : ''}`), h('div', { class: `muted small ${s.state === 'error' ? 'sync-error' : ''}` }, line))),
      h('div', { class: 'row-actions' },
        s.state === 'error' && s.reconnect
          ? h('button', { class: 'btn primary', onclick: () => connectGoogle().catch((err) => toast(err.message)) }, 'Reconnect')
          : h('button', { class: 'btn', disabled: s.state === 'syncing', onclick: async () => {
            const r = await app.sync?.run();
            if (r) toast(r.uploaded || r.downloaded || r.deleted || r.conflicts ? `Synced: ${r.uploaded} up, ${r.downloaded} down${r.deleted ? `, ${r.deleted} removed` : ''}${r.conflicts ? `, ${r.conflicts} kept as copies` : ''}.` : 'Everything’s up to date.');
          } }, icon('cloud', 18), 'Sync Now'),
        h('button', { class: 'btn', onclick: async () => {
          if (!(await confirmDialog({ title: 'Disconnect Google Drive?', message: 'Notebooks stay on this device and in your Drive; they just stop syncing here.', confirm: 'Disconnect' }))) return;
          await disconnectGoogle(); toast('Google Drive disconnected'); render();
        } }, 'Disconnect')),
      h('p', { class: 'muted small' }, 'Syncs when Basis opens, a little after you make changes, and every few minutes. If a notebook was changed on two devices at once, both versions are kept.'));
  };
  const onStatus = () => render();
  syncEvents.addEventListener('status', onStatus);
  render();
  return group;
}

/** The exact values to enter in Google Cloud, so a typo can't cause redirect_uri_mismatch. */
function setupDetails(cfg) {
  const v = googleSetupValues();
  const row = (label, value) => h('div', { class: 'setup-row' },
    h('span', { class: 'muted small' }, label),
    h('code', {}, value),
    h('button', { class: 'btn ghost small', onclick: async () => {
      try { await navigator.clipboard.writeText(value); toast('Copied'); } catch { toast(value); }
    } }, 'Copy'));
  return h('details', { class: 'setup-details' },
    h('summary', { class: 'muted small' }, 'Setting up Google sign-in for this site'),
    h('p', { class: 'muted small' }, 'In Google Cloud → Google Auth Platform → Clients, use a “Web application” client with exactly these:'),
    row('Authorized JavaScript origin', v.origin),
    row('Authorized redirect URI', v.redirect),
    h('p', { class: 'muted small' }, cfg.configured
      ? `This site is using the client ending in …${cfg.clientId.split('.')[0].slice(-6)}. It should match the Client ID in Google Cloud.`
      : 'Then add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in Vercel and redeploy.'));
}
