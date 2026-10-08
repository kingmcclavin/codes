// Emulation worker: runs the TI-84 Plus CE off the main thread.
import { Runner } from './runner.js';

const runner = new Runner((msg, transfer) => self.postMessage(msg, transfer || []));
self.onmessage = (e) => runner.handle(e.data);
