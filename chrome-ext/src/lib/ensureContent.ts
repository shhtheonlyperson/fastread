import type { Msg, MsgResponse } from './messages';

interface ManifestLite {
  content_scripts?: Array<{ js?: string[]; css?: string[] }>;
}

async function readFreshManifest(): Promise<ManifestLite> {
  try {
    const res = await fetch(chrome.runtime.getURL('manifest.json'), { cache: 'no-store' });
    if (res.ok) return await res.json() as ManifestLite;
  } catch { /* fall through */ }
  return chrome.runtime.getManifest() as ManifestLite;
}

async function injectContentScript(tabId: number): Promise<void> {
  const manifest = await readFreshManifest();
  const files = manifest.content_scripts?.flatMap(cs => cs.js ?? []) ?? [];
  const css = manifest.content_scripts?.flatMap(cs => cs.css ?? []) ?? [];
  if (files.length) {
    try {
      await chrome.scripting.executeScript({ target: { tabId }, files });
    } catch (e) {
      const msg = (e as Error).message ?? '';
      if (/Could not load file/i.test(msg)) {
        throw new Error('Extension was rebuilt — reload it at chrome://extensions and refresh this tab.');
      }
      throw e;
    }
  }
  if (css.length) {
    await chrome.scripting.insertCSS({ target: { tabId }, files: css });
  }
}

async function trySend(tabId: number, msg: Msg): Promise<MsgResponse | null> {
  try { return await chrome.tabs.sendMessage(tabId, msg) as MsgResponse; }
  catch { return null; }
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

export async function sendToTab(tabId: number, msg: Msg): Promise<MsgResponse> {
  const first = await trySend(tabId, msg);
  if (first) return first;
  await injectContentScript(tabId);
  // CRXJS loader dynamic-imports the real script; wait for the listener.
  for (let i = 0; i < 25; i++) {
    await sleep(80);
    const res = await trySend(tabId, msg);
    if (res) return res;
  }
  throw new Error('content script did not respond after injection');
}
