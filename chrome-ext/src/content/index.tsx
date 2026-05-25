import { createRoot, type Root } from 'react-dom/client';
import { StrictMode } from 'react';
import { ReaderOverlay } from './ReaderOverlay';
import { extract, canRead, type ExtractedArticle } from '../lib/extract';
import type { Msg, MsgResponse } from '../lib/messages';
import overlayCss from '../styles/overlay.css?inline';
import tokensCss from '../styles/tokens.css?inline';

const HOST_ID = '__justread_host__';

interface MountState {
  host: HTMLElement;
  root: Root;
  mode: 'reader' | 'fastread';
}

let state: MountState | null = null;
let cached: ExtractedArticle | null = null;
let cachedHref = '';

function getArticle(): ExtractedArticle | null {
  if (cached && cachedHref === location.href) return cached;
  cached = extract();
  cachedHref = location.href;
  return cached;
}

const invalidate = () => { cached = null; cachedHref = ''; };
window.addEventListener('popstate', invalidate);
const origPush = history.pushState;
history.pushState = function (...args) { const r = origPush.apply(this, args); invalidate(); return r; };
const origReplace = history.replaceState;
history.replaceState = function (...args) { const r = origReplace.apply(this, args); invalidate(); return r; };

function mount(mode: 'reader' | 'fastread') {
  const article = getArticle();
  if (!article) {
    console.warn('[JustRead] No article extracted');
    return;
  }
  if (state) {
    state.mode = mode;
    renderOverlay(state.root, article, mode);
    return;
  }
  const host = document.createElement('div');
  host.id = HOST_ID;
  host.style.cssText = 'all: initial; position: fixed; inset: 0; z-index: 2147483647;';
  const shadow = host.attachShadow({ mode: 'open' });
  const tokenStyle = document.createElement('style');
  tokenStyle.textContent = tokensCss;
  shadow.appendChild(tokenStyle);
  const style = document.createElement('style');
  style.textContent = overlayCss;
  shadow.appendChild(style);
  const mountPoint = document.createElement('div');
  shadow.appendChild(mountPoint);
  document.documentElement.appendChild(host);
  document.documentElement.style.overflow = 'hidden';
  const root = createRoot(mountPoint);
  state = { host, root, mode };
  renderOverlay(root, article, mode);
}

function renderOverlay(root: Root, article: ExtractedArticle, mode: 'reader' | 'fastread') {
  root.render(
    <StrictMode>
      <ReaderOverlay article={article} initialMode={mode} onExit={unmount} />
    </StrictMode>,
  );
}

function unmount() {
  if (!state) return;
  state.root.unmount();
  state.host.remove();
  document.documentElement.style.overflow = '';
  state = null;
}

function toggle(mode: 'reader' | 'fastread') {
  if (state && state.mode === mode) { unmount(); return; }
  mount(mode);
}

chrome.runtime.onMessage.addListener((msg: Msg, _sender, sendResponse) => {
  if (msg.type === 'ping') {
    sendResponse({ ok: true, readerable: canRead() } satisfies MsgResponse);
    return;
  }
  if (msg.type === 'get-article-meta') {
    const a = getArticle();
    sendResponse({
      ok: true,
      readerable: !!a,
      title: a?.title,
      byline: a?.byline ?? undefined,
      source: a?.siteName ?? location.hostname,
      readingTimeMin: a?.readingTimeMin,
    } satisfies MsgResponse);
    return;
  }
  if (msg.type === 'toggle-reader') { toggle('reader'); sendResponse({ ok: true, readerable: true }); return; }
  if (msg.type === 'toggle-fastread') { toggle('fastread'); sendResponse({ ok: true, readerable: true }); return; }
});
