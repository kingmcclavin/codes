// Tiny IndexedDB key-value store used for the ROM, the autosave and snapshot
// slots. Works in the page and in the emulation worker. Falls back to memory if
// IndexedDB is unavailable (private browsing, sandboxed previews).

const DB_NAME = 'ti84ce';
const STORE = 'kv';
let dbPromise = null;
const memory = new Map();

function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve) => {
    try {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return dbPromise;
}

function tx(db, mode, fn) {
  return new Promise((resolve, reject) => {
    const t = db.transaction(STORE, mode);
    const req = fn(t.objectStore(STORE));
    t.oncomplete = () => resolve(req ? req.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

export async function get(key) {
  const db = await open();
  if (!db) return memory.get(key);
  try { return await tx(db, 'readonly', (s) => s.get(key)); } catch { return memory.get(key); }
}

export async function put(key, value) {
  const db = await open();
  if (!db) { memory.set(key, value); return false; }
  try { await tx(db, 'readwrite', (s) => s.put(value, key)); return true; } catch { memory.set(key, value); return false; }
}

export async function del(key) {
  memory.delete(key);
  const db = await open();
  if (!db) return;
  try { await tx(db, 'readwrite', (s) => s.delete(key)); } catch { /* ignore */ }
}

export async function persistent() {
  return (await open()) !== null;
}
