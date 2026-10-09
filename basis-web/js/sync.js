// Cloud Sync with the person's own Google Drive.
//
// Notebooks sync to a "Basis" folder in their Drive: one compressed file per
// notebook, one file per image or PDF (uploaded once), and library.json with
// folders and deletions. The browser talks to Drive directly; the only server
// piece is /api/google-oauth, which completes sign-in with the client secret.
// Basis asks only for access to files it creates (drive.file).

import { storage, uuid } from './util.js';
import { store, encodeDoc, decodeDoc, collectAssetIds } from './store.js';

const AUTH = 'basis.sync.google';     // { refresh, access, exp, email, name, folderId }
const STATE = 'basis.sync.state';     // { docs: { id: { fileId, base } }, lastSync, lastError }
const DELETED = 'basis.sync.deleted'; // notebooks deleted here, not yet recorded in Drive { id: time }
const DELETED_FOLDERS = 'basis.sync.deletedFolders';
const PKCE = 'basis.sync.pkce';
const API = 'api/google-oauth';
const DRIVE = 'https://www.googleapis.com/drive/v3';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3';
const SCOPE = 'https://www.googleapis.com/auth/drive.file';
const KEEP_TOMBSTONES = 120 * 24 * 3600e3; // deletions are remembered for 120 days

export class SyncError extends Error {
  constructor(message, { reconnect = false } = {}) { super(message); this.reconnect = reconnect; }
}

const auth = () => storage.get(AUTH, null);
const setAuth = (a) => storage.set(AUTH, a);
const state = () => ({ docs: {}, ...storage.get(STATE, {}) });
const setState = (s) => storage.set(STATE, s);

export const syncConnected = () => !!auth()?.refresh;
export const syncAccount = () => auth();
export const syncState = () => state();

// ---------- Sign-in ----------

const redirectURI = () => new URL('./', location.href).href.split('?')[0].split('#')[0];

const b64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/** Whether the site has Google sign-in set up (GOOGLE_CLIENT_ID and _SECRET on Vercel). */
export async function syncServerConfig() {
  try {
    const r = await fetch(API, { cache: 'no-store' });
    if (!r.ok) return { configured: false };
    const j = await r.json();
    return j.clientId ? { configured: true, clientId: j.clientId } : { configured: false };
  } catch {
    return { configured: false };
  }
}

/** Sends the person to Google to allow access; they come back to this page with a code. */
export async function connectGoogle() {
  const cfg = await syncServerConfig();
  if (!cfg.configured) throw new SyncError('Google sign-in isn’t set up on this site yet.');
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(48)));
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
  const st = b64url(crypto.getRandomValues(new Uint8Array(16)));
  storage.set(PKCE, { verifier, state: st, at: Date.now() });
  const u = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  u.search = new URLSearchParams({
    client_id: cfg.clientId, redirect_uri: redirectURI(), response_type: 'code', scope: SCOPE,
    access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true',
    code_challenge: challenge, code_challenge_method: 'S256', state: st,
  });
  location.assign(u.href);
}

/** Finishes sign-in when Google sends the person back. Returns true if this page load was a sign-in. */
export async function finishGoogleSignIn() {
  const q = new URLSearchParams(location.search);
  if (!q.has('state') || !(q.has('code') || q.has('error'))) return false;
  const pk = storage.get(PKCE, null);
  history.replaceState(null, '', redirectURI() + location.hash);
  if (!pk || pk.state !== q.get('state')) return false;
  storage.set(PKCE, null);
  if (q.get('error')) throw new SyncError(q.get('error') === 'access_denied' ? 'Google Drive access wasn’t allowed.' : `Google sign-in failed (${q.get('error')}).`);
  const tok = await tokenCall({ action: 'exchange', code: q.get('code'), code_verifier: pk.verifier, redirect_uri: redirectURI() });
  if (!tok.refresh_token) throw new SyncError('Google didn’t allow ongoing access. Try connecting again.');
  setAuth({ refresh: tok.refresh_token, access: tok.access_token, exp: Date.now() + (tok.expires_in || 3600) * 1000 });
  try {
    const about = await drive('about?fields=user(emailAddress,displayName)');
    setAuth({ ...auth(), email: about.user?.emailAddress, name: about.user?.displayName });
  } catch { /* the account name is only for display */ }
  return true;
}

async function tokenCall(body) {
  let r;
  try {
    r = await fetch(API, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  } catch {
    throw new SyncError('Couldn’t reach the sign-in service. Check your connection.');
  }
  const j = await r.json().catch(() => ({}));
  if (r.ok) return j;
  if (j.error === 'invalid_grant') throw new SyncError('Google Drive access has expired or was removed. Connect again.', { reconnect: true });
  if (j.error === 'not_configured') throw new SyncError('Google sign-in isn’t set up on this site yet.');
  throw new SyncError(`Google sign-in failed (${j.error || r.status}).`);
}

async function accessToken(force = false) {
  const a = auth();
  if (!a?.refresh) throw new SyncError('Not connected to Google Drive.', { reconnect: true });
  if (!force && a.access && a.exp - Date.now() > 60e3) return a.access;
  const tok = await tokenCall({ action: 'refresh', refresh_token: a.refresh });
  setAuth({ ...auth(), access: tok.access_token, exp: Date.now() + (tok.expires_in || 3600) * 1000 });
  return tok.access_token;
}

/** Disconnects this device (local notebooks stay; Drive files stay). */
export async function disconnectGoogle() {
  const a = auth();
  setAuth(null);
  setState({ docs: {} });
  if (a?.refresh) fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(a.refresh)}`, { method: 'POST' }).catch(() => {});
}

// ---------- Drive ----------

async function drive(path, { method = 'GET', body, headers = {}, base = DRIVE, raw = false } = {}, retried = false) {
  const token = await accessToken(retried);
  let r;
  try {
    r = await fetch(`${base}/${path}`, { method, body, headers: { Authorization: `Bearer ${token}`, ...headers } });
  } catch {
    throw new SyncError('Couldn’t reach Google Drive. Check your connection.');
  }
  if (r.status === 401 && !retried) return drive(path, { method, body, headers, base, raw }, true);
  if (!r.ok) {
    const j = await r.json().catch(() => ({}));
    const msg = j.error?.message || r.statusText;
    if (r.status === 403 && /storage|quota/i.test(msg)) throw new SyncError('Your Google Drive is full.');
    if (r.status === 403 || r.status === 401) throw new SyncError(`Google Drive refused access: ${msg}`, { reconnect: r.status === 401 });
    if (r.status === 404) { const e = new SyncError('A synced file is missing from Google Drive.'); e.notFound = true; throw e; }
    throw new SyncError(`Google Drive error (${r.status}): ${msg}`);
  }
  if (raw) return r;
  return r.status === 204 ? null : r.json();
}

const q = (s) => s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");

async function ensureFolder() {
  const a = auth();
  if (a.folderId) {
    try {
      const f = await drive(`files/${a.folderId}?fields=id,trashed`);
      if (!f.trashed) return a.folderId;
    } catch (e) { if (!e.notFound) throw e; }
  }
  const found = await drive(`files?q=${encodeURIComponent(`mimeType='application/vnd.google-apps.folder' and trashed=false and appProperties has { key='basisRoot' and value='1' }`)}&fields=files(id)&spaces=drive`);
  let id = found.files?.[0]?.id;
  if (!id) {
    const f = await drive('files?fields=id', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Basis', mimeType: 'application/vnd.google-apps.folder', appProperties: { basisRoot: '1' }, description: 'Notebooks synced by Basis. Please don’t edit these files.' }) });
    id = f.id;
  }
  setAuth({ ...auth(), folderId: id });
  return id;
}

async function listFolder(folderId) {
  const files = [];
  let page = '';
  do {
    const r = await drive(`files?q=${encodeURIComponent(`'${q(folderId)}' in parents and trashed=false`)}&fields=${encodeURIComponent('nextPageToken,files(id,name,appProperties,size)')}&pageSize=1000${page ? `&pageToken=${page}` : ''}`);
    files.push(...(r.files || []));
    page = r.nextPageToken || '';
  } while (page);
  return files;
}

/** Creates or replaces a file. Small files go up in one request; big ones resumably. */
async function putFile({ fileId, name, parent, appProperties, blob }) {
  const meta = fileId ? { name, appProperties } : { name, appProperties, parents: [parent] };
  const type = blob.type || 'application/octet-stream';
  if (blob.size < 4.5 * 1024 * 1024) {
    const boundary = `basis${uuid().replace(/-/g, '')}`;
    const body = new Blob([
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n--${boundary}\r\nContent-Type: ${type}\r\n\r\n`,
      blob, `\r\n--${boundary}--`,
    ]);
    return drive(fileId ? `files/${fileId}?uploadType=multipart&fields=id` : 'files?uploadType=multipart&fields=id', {
      base: UPLOAD, method: fileId ? 'PATCH' : 'POST', headers: { 'content-type': `multipart/related; boundary=${boundary}` }, body,
    });
  }
  const start = await drive(fileId ? `files/${fileId}?uploadType=resumable&fields=id` : 'files?uploadType=resumable&fields=id', {
    base: UPLOAD, method: fileId ? 'PATCH' : 'POST', raw: true,
    headers: { 'content-type': 'application/json; charset=UTF-8', 'X-Upload-Content-Type': type, 'X-Upload-Content-Length': String(blob.size) }, body: JSON.stringify(meta),
  });
  const loc = start.headers.get('Location');
  if (!loc) throw new SyncError('Google Drive didn’t accept the upload.');
  const r = await fetch(loc, { method: 'PUT', headers: { 'content-type': type }, body: blob });
  if (!r.ok) throw new SyncError(`Uploading to Google Drive failed (${r.status}).`);
  return r.json();
}

const getFile = async (id) => (await drive(`files/${id}?alt=media`, { raw: true })).blob();
const trashFile = (id) => drive(`files/${id}?fields=id`, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ trashed: true }) }).catch((e) => { if (!e.notFound) throw e; });

// ---------- Notebook files ----------

async function gzip(text) {
  if (typeof CompressionStream === 'undefined') return { blob: new Blob([text], { type: 'application/json' }), enc: 'json' };
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
  return { blob: new Blob([await new Response(stream).arrayBuffer()], { type: 'application/gzip' }), enc: 'gzip' };
}
async function gunzip(blob, enc) {
  if (enc !== 'gzip') return blob.text();
  return new Response(blob.stream().pipeThrough(new DecompressionStream('gzip'))).text();
}

// ---------- The sync itself ----------

/** Merges folder lists: newest version of each folder wins; deleted folders stay deleted. */
function mergeFolders(local, remote, deleted) {
  const byId = new Map();
  for (const f of [...remote, ...local]) {
    if (deleted[f.id]) continue;
    const cur = byId.get(f.id);
    if (!cur || (f.updatedAt || f.createdAt || 0) > (cur.updatedAt || cur.createdAt || 0)) byId.set(f.id, f);
  }
  return [...byId.values()];
}

const sameFolders = (a, b) => JSON.stringify([...a].sort((x, y) => x.id.localeCompare(y.id))) === JSON.stringify([...b].sort((x, y) => x.id.localeCompare(y.id)));

/**
 * One full sync. `hooks.isOpenAndDirty(id)` keeps a notebook that's open with
 * unsaved changes from being replaced; `hooks.reloaded(id)` is called after an
 * open notebook was updated from Drive.
 */
export async function syncNow(hooks = {}, onProgress = () => {}) {
  const st = state();
  const folderId = await ensureFolder();
  const files = await listFolder(folderId);
  const remoteDocs = new Map(), remoteAssets = new Map();
  let libFile = null;
  for (const f of files) {
    const p = f.appProperties || {};
    if (p.basis === 'doc' && p.docId) remoteDocs.set(p.docId, { fileId: f.id, syncAt: Number(p.syncAt) || 0, enc: p.enc || 'gzip' });
    else if (p.basis === 'asset' && p.assetId) remoteAssets.set(p.assetId, f.id);
    else if (p.basis === 'library') libFile = f;
  }

  // Library: folders and deletions.
  const lib = libFile ? JSON.parse(await (await getFile(libFile.id)).text()) : {};
  const now = Date.now();
  const prune = (o) => Object.fromEntries(Object.entries(o || {}).filter(([, t]) => now - t < KEEP_TOMBSTONES));
  const deletedDocs = prune({ ...lib.deletedDocs, ...storage.get(DELETED, {}) });
  const deletedFolders = prune({ ...lib.deletedFolders, ...storage.get(DELETED_FOLDERS, {}) });
  const folders = mergeFolders(store.folders, lib.folders || [], deletedFolders);
  if (!sameFolders(folders, store.folders)) await store.setFolders(folders);

  const ids = new Set([...store.summaries.map((s) => s.id), ...remoteDocs.keys()]);
  let step = 0;
  const total = ids.size;
  const result = { uploaded: 0, downloaded: 0, deleted: 0, conflicts: 0 };

  const uploadDoc = async (id) => {
    const doc = await store.loadDocument(id);
    if (!doc) return;
    for (const a of collectAssetIds(doc)) {
      if (remoteAssets.has(a)) continue;
      const blob = await store.assetBlob(a);
      if (!blob) continue;
      const f = await putFile({ name: `asset-${a}`, parent: folderId, appProperties: { basis: 'asset', assetId: a }, blob });
      remoteAssets.set(a, f.id);
    }
    const { blob, enc } = await gzip(JSON.stringify(encodeDoc(doc)));
    const r = remoteDocs.get(id);
    const f = await putFile({ fileId: r?.fileId, name: `notebook-${id}.json${enc === 'gzip' ? '.gz' : ''}`, parent: folderId, appProperties: { basis: 'doc', docId: id, syncAt: String(doc.syncAt || 0), enc }, blob });
    remoteDocs.set(id, { fileId: f.id, syncAt: doc.syncAt || 0, enc });
    st.docs[id] = { fileId: f.id, base: doc.syncAt || 0 };
    result.uploaded++;
  };

  const fetchDoc = async (id) => {
    const r = remoteDocs.get(id);
    const doc = decodeDoc(JSON.parse(await gunzip(await getFile(r.fileId), r.enc)));
    for (const a of collectAssetIds(doc)) {
      if (await store.hasAsset(a)) continue;
      const fileId = remoteAssets.get(a);
      if (fileId) await store.putAsset(await getFile(fileId), a);
    }
    return doc;
  };

  for (const id of ids) {
    onProgress(++step, total);
    const local = store.summary(id);
    const remote = remoteDocs.get(id);
    const base = st.docs[id]?.base;
    const lAt = local?.syncAt ?? 0;

    // Deleted on some device: delete here too, unless it was edited after that.
    if (deletedDocs[id]) {
      if (local && lAt > deletedDocs[id]) { delete deletedDocs[id]; } else {
        if (local && !hooks.isOpenAndDirty?.(id)) { await store.deleteDocument(id); result.deleted++; }
        if (remote) await trashFile(remote.fileId);
        delete st.docs[id];
        continue;
      }
    }
    if (local && !remote) { await uploadDoc(id); continue; }
    if (!local && remote) {
      const doc = await fetchDoc(id);
      await store.saveDocument(doc, { touch: false, quiet: true });
      st.docs[id] = { fileId: remote.fileId, base: remote.syncAt };
      result.downloaded++;
      continue;
    }
    if (lAt === remote.syncAt) { st.docs[id] = { fileId: remote.fileId, base: lAt }; continue; }
    const localChanged = base === undefined || lAt !== base;
    const remoteChanged = base === undefined || remote.syncAt !== base;
    if (localChanged && !remoteChanged) { await uploadDoc(id); continue; }
    if (hooks.isOpenAndDirty?.(id)) continue; // try again once it's saved
    if (remoteChanged && !localChanged) {
      const doc = await fetchDoc(id);
      await store.saveDocument(doc, { touch: false, quiet: true });
      st.docs[id] = { fileId: remote.fileId, base: remote.syncAt };
      result.downloaded++;
      hooks.reloaded?.(id);
      continue;
    }
    // Changed on both: keep this device's version, and the other device's as a copy.
    const other = await fetchDoc(id);
    other.id = uuid();
    other.title = `${other.title || 'Untitled'} (from another device)`;
    await store.saveDocument(other, { touch: false });
    await uploadDoc(id);
    await uploadDoc(other.id);
    result.conflicts++;
  }

  // Record deletions and folders for other devices.
  const newLib = { folders: store.folders, deletedDocs, deletedFolders, updatedAt: now };
  if (!libFile || JSON.stringify({ ...lib, updatedAt: 0 }) !== JSON.stringify({ ...newLib, updatedAt: 0 })) {
    await putFile({ fileId: libFile?.id, name: 'library.json', parent: folderId, appProperties: { basis: 'library' }, blob: new Blob([JSON.stringify(newLib)], { type: 'application/json' }) });
  }
  storage.set(DELETED, {});
  storage.set(DELETED_FOLDERS, {});
  st.lastSync = Date.now();
  st.lastError = null;
  setState(st);
  return result;
}

/** Remembers local deletions so other devices delete them too. */
export function trackDeletions() {
  store.addEventListener('docdeleted', (e) => { if (syncConnected()) storage.set(DELETED, { ...storage.get(DELETED, {}), [e.detail]: Date.now() }); });
  store.addEventListener('folderdeleted', (e) => { if (syncConnected()) storage.set(DELETED_FOLDERS, { ...storage.get(DELETED_FOLDERS, {}), [e.detail]: Date.now() }); });
}

export function recordSyncError(message) { const st = state(); st.lastError = message ? { message, at: Date.now() } : null; setState(st); }

// ---------- Running automatically ----------

export const syncEvents = new EventTarget();
let status = { state: 'idle' };
export const syncStatus = () => status;
const setStatus = (s) => { status = s; syncEvents.dispatchEvent(new Event('status')); };

/**
 * Syncs when Basis opens or comes back to the foreground, a little while after
 * changes, every few minutes, and right away when the app is put away.
 * `enabled()` gates it (Developer Mode while in testing).
 */
export function startAutoSync(app, enabled = () => true) {
  trackDeletions();
  let running = false, again = false, timer = null;
  const hooks = {
    isOpenAndDirty: (id) => { const ed = app.editor; return ed?.doc.id === id && !!(ed.dirty || ed.syncDirty || ed.canvas?.interaction); },
    reloaded: (id) => app.reloadDocument?.(id),
  };
  const run = async () => {
    clearTimeout(timer);
    if (!enabled() || !syncConnected()) return null;
    if (!navigator.onLine) { setStatus({ state: 'offline' }); return null; }
    if (running) { again = true; return null; }
    running = true;
    setStatus({ state: 'syncing' });
    try {
      // Save the open notebook first so its latest changes go up.
      await app.editor?.saveNow?.();
      const r = await syncNow(hooks, (n, total) => setStatus({ state: 'syncing', n, total }));
      synced = signature();
      again = false;
      setStatus({ state: 'ok', result: r, at: Date.now() });
      return r;
    } catch (e) {
      recordSyncError(e.message);
      setStatus({ state: 'error', message: e.message, reconnect: !!e.reconnect });
      return null;
    } finally {
      running = false;
      if (again) { again = false; schedule(3000); }
    }
  };
  const schedule = (ms) => { clearTimeout(timer); timer = setTimeout(run, ms); };
  // Only changes that need syncing count (not, say, the scroll position being saved).
  const signature = () => store.summaries.map((x) => `${x.id}:${x.syncAt}`).sort().join() + '|' + store.folders.map((f) => `${f.id}:${f.updatedAt || 0}`).sort().join();
  let synced = null;
  store.addEventListener('change', () => {
    if (!enabled() || !syncConnected() || signature() === synced) return;
    if (running) again = true; else schedule(20000);
  });
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') schedule(800); else run(); });
  window.addEventListener('online', () => schedule(800));
  setInterval(() => { if (!running && document.visibilityState === 'visible') run(); }, 3 * 60e3);
  schedule(600);
  return { run };
}
