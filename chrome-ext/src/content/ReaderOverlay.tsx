import { useEffect, useMemo, useRef, useState } from 'react';
import type { ExtractedArticle } from '../lib/extract';
import {
  DEFAULTS,
  getSettings,
  onSettingsChange,
  setSettings,
  recordRecent,
  type Settings,
} from '../lib/storage';
import { resolveLocale, t, localeHtmlLang } from '../lib/i18n';
import { FastReadPanel } from './FastReadPanel';
import {
  IconType,
  IconMinus,
  IconPlus,
  IconSun,
  IconMoon,
  IconSettings,
  IconClose,
  IconZap,
} from '../lib/icons';

type Mode = 'reader' | 'fastread';

interface Props {
  article: ExtractedArticle;
  initialMode: Mode;
  onExit: () => void;
}

type ResolvedTheme = 'light' | 'dark';

export function ReaderOverlay({ article, initialMode, onExit }: Props) {
  const [mode, setMode] = useState<Mode>(initialMode);
  const [settings, setLocal] = useState<Settings>(DEFAULTS);
  const [progress, setProgress] = useState(0);
  const [resumeParaIdx, setResumeParaIdx] = useState<number | null>(null);
  const overlayRef = useRef<HTMLDivElement | null>(null);
  const articleRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    getSettings().then(setLocal);
    return onSettingsChange(setLocal);
  }, []);

  const locale = useMemo(() => resolveLocale(settings.locale), [settings.locale]);
  const tr = useMemo(() => (k: string) => t(k, locale), [locale]);

  const theme: ResolvedTheme = settings.theme;

  /* Scroll progress on the overlay (it's the scrollable container). */
  useEffect(() => {
    const el = overlayRef.current;
    if (!el) return;
    const onScroll = () => {
      const max = el.scrollHeight - el.clientHeight;
      setProgress(max > 0 ? el.scrollTop / max : 0);
    };
    el.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => el.removeEventListener('scroll', onScroll);
  }, [mode]);

  /* Resume scroll to the paragraph containing the current RSVP word when
     coming back from fast read. */
  useEffect(() => {
    if (mode === 'reader' && resumeParaIdx !== null) {
      const overlay = overlayRef.current;
      const art = articleRef.current;
      if (overlay && art) {
        const paras = art.querySelectorAll('p');
        const target = paras[resumeParaIdx];
        if (target) {
          const offsetTop = target.getBoundingClientRect().top - overlay.getBoundingClientRect().top + overlay.scrollTop;
          overlay.scrollTo({ top: offsetTop - overlay.clientHeight * 0.25, behavior: 'smooth' });
        }
      }
      setResumeParaIdx(null);
    }
  }, [mode, resumeParaIdx]);

  /* Keyboard handling (reader-level): F (exit), Shift+F (fastread), Esc. */
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (mode === 'fastread') return; // FastReadPanel owns its keys
      if (e.key === 'Escape') { onExit(); return; }
      if (e.target && (e.target as HTMLElement).matches('input, textarea')) return;
      if (e.key === 'f' || e.key === 'F') {
        e.preventDefault();
        if (e.shiftKey) setMode('fastread');
        else onExit();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [mode, onExit]);

  /* Record the article in recents on mount. */
  useEffect(() => {
    recordRecent({
      url: location.href,
      title: article.title,
      source: article.siteName ?? location.hostname,
      progress: 0,
    });
  }, [article.title, article.siteName]);

  const sourceLabel = article.siteName ?? location.hostname;
  const dateLabel = article.publishedAt
    ? new Date(article.publishedAt).toLocaleDateString(locale === 'zh_TW' ? 'zh-Hant' : 'en', { month: 'short', day: 'numeric', year: 'numeric' })
    : '';

  const articleBodyStyle = {
    ['--jr-fs-base' as const]: `${settings.fontSize}px`,
    ['--jr-lh-base' as const]: String(settings.lineHeight),
    ['--jr-column-w' as const]: `${settings.columnWidth}px`,
  };

  return (
    <div
      className="jr-root"
      data-theme={theme}
      data-font={settings.font}
      data-mode={mode}
      lang={localeHtmlLang(locale)}
      style={articleBodyStyle as React.CSSProperties}
    >
      <div
        ref={overlayRef}
        className="jr-overlay"
        role="region"
        aria-label={article.title}
      >
        <div className="jr-progress-track">
          <div className="jr-progress-fill" style={{ ['--jr-progress' as never]: `${progress * 100}%` }} />
        </div>

        <div className="jr-toolbar" role="toolbar" aria-label={tr('settings')}>
          <button
            className={`jr-tb-btn ${settings.font === 'serif' ? 'is-active' : ''}`}
            onClick={() => setSettings({ font: 'serif' })}
            aria-label={tr('serif')}
            title={tr('serif')}
          ><span style={{ fontFamily: 'var(--jr-font-display)', fontWeight: 500 }}>Aa</span></button>
          <button
            className={`jr-tb-btn ${settings.font === 'sans' ? 'is-active' : ''}`}
            onClick={() => setSettings({ font: 'sans' })}
            aria-label={tr('sans')}
            title={tr('sans')}
          ><IconType size={14} /></button>

          <span className="jr-toolbar-divider" />

          <button
            className="jr-tb-btn"
            onClick={() => setSettings({ fontSize: Math.max(14, settings.fontSize - 1) })}
            aria-label={tr('smaller')}
          ><IconMinus size={14} /></button>
          <span className="jr-tb-size" aria-live="polite">{settings.fontSize}</span>
          <button
            className="jr-tb-btn"
            onClick={() => setSettings({ fontSize: Math.min(22, settings.fontSize + 1) })}
            aria-label={tr('larger')}
          ><IconPlus size={14} /></button>

          <span className="jr-toolbar-divider" />

          <button
            className="jr-tb-btn"
            onClick={() => setSettings({ theme: theme === 'dark' ? 'light' : 'dark' })}
            aria-label={tr(theme === 'dark' ? 'light' : 'dark')}
            title={tr(theme === 'dark' ? 'light' : 'dark')}
          >{theme === 'dark' ? <IconSun size={14} /> : <IconMoon size={14} />}</button>

          <span className="jr-toolbar-divider" />

          <button
            className="jr-tb-btn"
            onClick={() => setSettings({ locale: locale === 'zh_TW' ? 'en' : 'zh_TW' })}
            aria-label={tr('language')}
            title={tr('language')}
            style={{ fontSize: 11, fontWeight: 600, letterSpacing: 0.3 }}
          >{locale === 'zh_TW' ? '中' : 'EN'}</button>

          <span className="jr-toolbar-divider" />

          <button
            className="jr-tb-btn"
            onClick={() => chrome.runtime.openOptionsPage?.()}
            aria-label={tr('settings')}
          ><IconSettings size={14} /></button>
          <button
            className="jr-tb-btn"
            onClick={onExit}
            aria-label={tr('exit')}
          ><IconClose size={14} /></button>
        </div>

        <article ref={articleRef} className="jr-article">
          <div className="jr-article-eyebrow">
            <span className="left">
              <span>{tr('article')}</span>
              <span className="dot" />
              <span>{sourceLabel}</span>
            </span>
            {dateLabel && <span>{dateLabel}</span>}
          </div>
          <h1 className="jr-article-title">{article.title}</h1>
          {article.byline && (
            <p className="jr-article-byline">
              {tr('by')} {article.byline}
              {article.readingTimeMin ? ` — ${article.readingTimeMin} ${tr('minRead')}` : ''}
            </p>
          )}
          <div
            className="jr-content"
            dangerouslySetInnerHTML={{ __html: withDropCap(article.contentHtml) }}
          />
        </article>

        <button
          className="jr-fab"
          onClick={() => setMode('fastread')}
          aria-label={tr('startFastRead')}
        >
          <IconZap size={16} />
          <span>{tr('startFastRead')}</span>
          <kbd>⇧F</kbd>
        </button>
      </div>

      {mode === 'fastread' && (
        <FastReadPanel
          article={article}
          settings={settings}
          locale={locale}
          onExitToReader={(paraIdx: number | null) => {
            setResumeParaIdx(paraIdx);
            setMode('reader');
          }}
          onExit={onExit}
        />
      )}
    </div>
  );
}

/* Mark the first paragraph with the drop-cap class. Done as a one-shot DOM
   transform on the extracted HTML string so we don't depend on framework
   ref ordering. */
function withDropCap(html: string): string {
  if (!html) return html;
  const idx = html.indexOf('<p');
  if (idx < 0) return html;
  const close = html.indexOf('>', idx);
  if (close < 0) return html;
  const tag = html.slice(idx, close);
  if (/class\s*=/.test(tag)) {
    const replaced = tag.replace(/class\s*=\s*"([^"]*)"/, 'class="$1 jr-drop-cap"');
    return html.slice(0, idx) + replaced + html.slice(close);
  }
  return html.slice(0, idx) + '<p class="jr-drop-cap"' + html.slice(idx + 2);
}
