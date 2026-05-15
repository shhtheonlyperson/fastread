import { describe, it, expect, beforeEach, vi } from 'vitest';
import { resetChromeMock, getChromeMock } from '../test/setup';
import { sendToTab } from './ensureContent';

beforeEach(() => {
  resetChromeMock();
  // Stub fetch for manifest fetches.
  vi.stubGlobal('fetch', vi.fn(async () => ({
    ok: true,
    json: async () => ({ content_scripts: [{ js: ['assets/content.js'] }] }),
  })));
});

describe('sendToTab', () => {
  it('passes through when the listener responds on first try', async () => {
    const chrome = getChromeMock();
    let injectCalls = 0;
    chrome.tabs.sendMessage.setImpl(async () => ({ ok: true, readerable: true }));
    chrome.scripting.executeScript.setImpl(async () => { injectCalls++; return [{}]; });
    const res = await sendToTab(7, { type: 'get-article-meta' });
    expect(res).toEqual({ ok: true, readerable: true });
    expect(injectCalls).toBe(0);
  });

  it('injects and retries when the first sendMessage throws', async () => {
    const chrome = getChromeMock();
    let callsBeforeInject = 0;
    let injected = false;
    chrome.tabs.sendMessage.setImpl(async () => {
      if (!injected) { callsBeforeInject++; throw new Error('Receiving end does not exist.'); }
      return { ok: true, readerable: true };
    });
    chrome.scripting.executeScript.setImpl(async () => { injected = true; return [{}]; });

    const res = await sendToTab(99, { type: 'get-article-meta' });
    expect(res).toEqual({ ok: true, readerable: true });
    expect(callsBeforeInject).toBeGreaterThan(0);
    expect(injected).toBe(true);
  });

  it('surfaces a friendly error when the content script file is missing', async () => {
    const chrome = getChromeMock();
    chrome.tabs.sendMessage.setImpl(async () => { throw new Error('no listener'); });
    chrome.scripting.executeScript.setImpl(async () => {
      throw new Error('Could not load file: assets/content.js.');
    });
    await expect(sendToTab(1, { type: 'ping' })).rejects.toThrow(/reload it at chrome:\/\/extensions/i);
  });

  it('also injects CSS when the manifest declares css files', async () => {
    const chrome = getChromeMock();
    // Override fresh-manifest fetch to advertise a CSS file.
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => ({ content_scripts: [{ js: ['assets/content.js'], css: ['assets/content.css'] }] }),
    })));
    let injected = false;
    let cssInjected = false;
    chrome.tabs.sendMessage.setImpl(async () => {
      if (!injected) throw new Error('no listener');
      return { ok: true, readerable: true };
    });
    chrome.scripting.executeScript.setImpl(async () => { injected = true; return [{}]; });
    chrome.scripting.insertCSS.setImpl(async () => { cssInjected = true; });
    await sendToTab(1, { type: 'ping' });
    expect(cssInjected).toBe(true);
  });

  it('falls back to chrome.runtime.getManifest when fetching manifest.json fails', async () => {
    const chrome = getChromeMock();
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    let injected = false;
    chrome.tabs.sendMessage.setImpl(async () => {
      if (!injected) throw new Error('no listener');
      return { ok: true, readerable: true };
    });
    chrome.scripting.executeScript.setImpl(async () => { injected = true; return [{}]; });
    const res = await sendToTab(1, { type: 'ping' });
    expect(res.ok).toBe(true);
  });

  it('throws after retries if the listener never appears', async () => {
    const chrome = getChromeMock();
    chrome.tabs.sendMessage.setImpl(async () => { throw new Error('no listener'); });
    chrome.scripting.executeScript.setImpl(async () => [{}]);
    // Attach the expectation BEFORE the promise can settle so vitest doesn't
    // flag it as an unhandled rejection.
    const promise = sendToTab(1, { type: 'ping' });
    const settled = expect(promise).rejects.toThrow(/did not respond/i);
    await settled;
  }, 10_000);
});
