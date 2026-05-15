import { Readability, isProbablyReaderable } from '@mozilla/readability';

export interface ExtractedArticle {
  title: string;
  byline: string | null;
  siteName: string | null;
  contentHtml: string;
  textContent: string;
  excerpt: string | null;
  lang: string | null;
  length: number;
  readingTimeMin: number;
  publishedAt: string | null;
}

function findPublished(doc: Document): string | null {
  const sel = doc.querySelector<HTMLMetaElement>(
    'meta[property="article:published_time"], meta[name="pubdate"], meta[name="date"], meta[itemprop="datePublished"], time[datetime]',
  );
  if (!sel) return null;
  return sel.getAttribute('content') ?? sel.getAttribute('datetime');
}

export function canRead(doc: Document = document): boolean {
  try { return isProbablyReaderable(doc); } catch { return false; }
}

export function extract(doc: Document = document): ExtractedArticle | null {
  const clone = doc.cloneNode(true) as Document;
  const article = new Readability(clone).parse();
  if (article && (article.textContent ?? '').trim().length > 40) {
    const words = (article.textContent || '').trim().split(/\s+/).filter(Boolean).length;
    return {
      title: article.title || doc.title,
      byline: article.byline,
      siteName: article.siteName,
      contentHtml: article.content || '',
      textContent: article.textContent || '',
      excerpt: article.excerpt,
      lang: article.lang || doc.documentElement.lang || null,
      length: words,
      readingTimeMin: Math.max(1, Math.round(words / 230)),
      publishedAt: findPublished(doc),
    };
  }
  return fallbackExtract(doc);
}

// Fallback for short-content pages (e.g. Substack notes) where Readability bails.
// Picks the densest text-bearing element and wraps it.
function fallbackExtract(doc: Document): ExtractedArticle | null {
  // Substack note shortcut: ProseMirror block holds just the note prose.
  const pm = doc.querySelector<HTMLElement>('.ProseMirror.FeedProseMirror, .ProseMirror');
  if (pm) {
    const text = (pm.innerText || '').trim();
    if (text.length >= 20) {
      const words = text.split(/\s+/).filter(Boolean).length;
      return {
        title: doc.title.replace(/\s+\|.*$/, '').trim() || doc.title,
        byline: doc.querySelector('[class*="byline"], [rel="author"]')?.textContent?.trim() ?? null,
        siteName: location.hostname,
        contentHtml: pm.outerHTML,
        textContent: text,
        excerpt: text.slice(0, 160),
        lang: doc.documentElement.lang || null,
        length: words,
        readingTimeMin: Math.max(1, Math.round(words / 230)),
        publishedAt: findPublished(doc),
      };
    }
  }
  const candidates = Array.from(doc.querySelectorAll<HTMLElement>([
    'article', '[role="article"]', 'main',
    '.ProseMirror', '.FeedProseMirror',
    '[class*="feedComment"]', '[class*="feedPermalink"]',
    '[data-component-name*="Note"]',
    '[class*="note"]', '[class*="post"]', '[class*="content"]',
  ].join(',')));
  let best: { el: HTMLElement; score: number } | null = null;
  const score = (el: HTMLElement) => {
    const text = (el.innerText || '').trim();
    if (text.length < 20) return 0;
    const links = el.querySelectorAll('a').length;
    const linkPenalty = links * 30;
    return text.length - linkPenalty;
  };
  for (const el of candidates) {
    const s = score(el);
    if (!best || s > best.score) best = { el, score: s };
  }
  if (!best) {
    const body = doc.body;
    if (!body || (body.innerText || '').trim().length < 20) return null;
    best = { el: body, score: 1 };
  }
  const text = (best.el.innerText || '').trim();
  if (text.length < 20) return null;
  const words = text.split(/\s+/).filter(Boolean).length;
  return {
    title: doc.title,
    byline: null,
    siteName: location.hostname,
    contentHtml: `<div>${escapeHtml(text).replace(/\n+/g, '</p><p>')}</div>`,
    textContent: text,
    excerpt: text.slice(0, 160),
    lang: doc.documentElement.lang || null,
    length: words,
    readingTimeMin: Math.max(1, Math.round(words / 230)),
    publishedAt: findPublished(doc),
  };
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));
}
