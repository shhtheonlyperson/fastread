import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ExtractedArticle } from '../lib/extract';
import { getChromeMock, resetChromeMock } from '../test/setup';
import { ReaderOverlay } from './ReaderOverlay';

const article: ExtractedArticle = {
  title: 'A Useful Article',
  byline: 'H. Reader',
  siteName: 'Example',
  contentHtml: '<p>First paragraph for the reader shell.</p><p>Second paragraph has enough words to render context.</p>',
  textContent: 'First paragraph for the reader shell. Second paragraph has enough words to render context.',
  excerpt: 'First paragraph for the reader shell.',
  lang: 'en',
  length: 13,
  readingTimeMin: 1,
  publishedAt: '2026-05-15T12:00:00Z',
};

describe('ReaderOverlay rendered shell', () => {
  let container: HTMLDivElement;
  let root: Root | null;

  beforeEach(() => {
    resetChromeMock();
    // React 18 act() checks this flag outside Jest.
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    container = document.createElement('div');
    document.body.appendChild(container);
    root = null;
  });

  afterEach(() => {
    if (root) {
      act(() => root?.unmount());
    }
    container.remove();
    vi.restoreAllMocks();
  });

  it('renders reader mode with article chrome and records the recent item', async () => {
    renderOverlay('reader');
    await flushEffects();

    expect(container.querySelector('.jr-root')?.getAttribute('data-mode')).toBe('reader');
    expect(container.querySelector('.jr-article-title')?.textContent).toBe('A Useful Article');
    expect(container.querySelector('.jr-drop-cap')?.textContent).toContain('First paragraph');
    expect(container.querySelector('.jr-fab')?.textContent).toContain('快速閱讀');

    const recent = getChromeMock().storage.local.data.jr_recent_v1 as Array<{ title: string }> | undefined;
    expect(recent?.[0]?.title).toBe('A Useful Article');
  });

  it('switches to fastread mode and renders the RSVP controls', async () => {
    renderOverlay('reader');
    await flushEffects();

    await act(async () => {
      container.querySelector<HTMLButtonElement>('.jr-fab')?.click();
    });

    expect(container.querySelector('.jr-root')?.getAttribute('data-mode')).toBe('fastread');
    expect(container.querySelector('.jr-fastread')).not.toBeNull();
    expect(container.querySelector('.jr-fr-word')?.textContent?.trim().length).toBeGreaterThan(0);
    expect(container.querySelector('.jr-fr-pivot')).not.toBeNull();
    expect(container.querySelector('.jr-fr-play')).not.toBeNull();
  });

  function renderOverlay(initialMode: 'reader' | 'fastread') {
    root = createRoot(container);
    act(() => {
      root?.render(<ReaderOverlay article={article} initialMode={initialMode} onExit={vi.fn()} />);
    });
  }
});

async function flushEffects() {
  await act(async () => {
    await Promise.resolve();
    await new Promise(resolve => setTimeout(resolve, 0));
  });
}
