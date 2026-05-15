import { createRoot } from 'react-dom/client';
import { StrictMode, useEffect, useMemo, useState } from 'react';
import { sendToTab } from '../lib/ensureContent';
import { getSettings, getRecents, type RecentItem } from '../lib/storage';
import { resolveLocale, t, localeHtmlLang } from '../lib/i18n';
import { IconSettings, IconClose, IconBook, IconZap } from '../lib/icons';

interface ArticleMeta {
  readerable: boolean;
  title?: string;
  byline?: string;
  source?: string;
  readingTimeMin?: number;
}

function Popup() {
  const [meta, setMeta] = useState<ArticleMeta | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [recents, setRecents] = useState<RecentItem[]>([]);
  const [locale, setLocale] = useState<'en' | 'zh_TW'>('en');

  useEffect(() => {
    (async () => {
      const s = await getSettings();
      const resolved = resolveLocale(s.locale);
      setLocale(resolved);
      document.documentElement.lang = localeHtmlLang(resolved);
      setRecents(await getRecents());

      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab?.id || !tab.url || /^(chrome|edge|about|chrome-extension):/.test(tab.url)) {
        setMeta({ readerable: false });
        return;
      }
      try {
        const res = await sendToTab(tab.id, { type: 'get-article-meta' });
        if (res.ok) {
          setMeta({
            readerable: res.readerable,
            title: res.title,
            byline: res.byline,
            source: res.source ?? new URL(tab.url).hostname,
            readingTimeMin: res.readingTimeMin,
          });
        } else {
          setErr(res.error);
        }
      } catch (e) {
        setErr(`Inject failed: ${(e as Error).message}`);
      }
    })();
  }, []);

  const tr = useMemo(() => (key: string) => t(key, locale), [locale]);

  const send = async (type: 'toggle-reader' | 'toggle-fastread', force = false) => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) return;
    try { await sendToTab(tab.id, { type, force }); } catch { /* ignore */ }
    window.close();
  };

  const openOptions = () => chrome.runtime.openOptionsPage();

  return (
    <div className="popup" role="dialog" aria-label={tr('appName')}>
      <header className="popup-header">
        <h1 className="popup-wordmark">{tr('appName')}</h1>
        <div className="popup-header-actions">
          <button className="popup-icon-btn" onClick={openOptions} aria-label={tr('settings')}>
            <IconSettings size={16} />
          </button>
          <button className="popup-icon-btn" onClick={() => window.close()} aria-label={tr('exit')}>
            <IconClose size={16} />
          </button>
        </div>
      </header>

      {meta?.readerable ? (
        <section className="popup-article">
          <div className="popup-eyebrow">
            <span>{tr('articleDetected')}</span>
            <span className="dot" />
            <span>{meta.source}</span>
          </div>
          <h2 className="popup-title" title={meta.title}>{meta.title}</h2>
          <p className="popup-byline">
            {meta.byline ? `${tr('by')} ${meta.byline}` : null}
            {meta.byline && meta.readingTimeMin ? ' — ' : null}
            {meta.readingTimeMin ? `${meta.readingTimeMin} ${tr('minRead')}` : null}
          </p>
        </section>
      ) : (
        <section className="popup-empty" aria-live="polite">
          <span className="glyph" aria-hidden>?</span>
          <h2 className="title">{tr('couldntExtract')}</h2>
          <p className="body">{tr('couldntExtractBody')}</p>
          {err && <p className="body" style={{ opacity: 0.7 }}>{err}</p>}
        </section>
      )}

      <div className="popup-ctas">
        {meta?.readerable ? (
          <>
            <button className="popup-btn primary" onClick={() => send('toggle-reader')}>
              <IconBook size={16} />
              <span className="label">{tr('openReader')}</span>
              <kbd>Alt+R</kbd>
            </button>
            <button className="popup-btn secondary" onClick={() => send('toggle-fastread')}>
              <IconZap size={16} />
              <span className="label">{tr('fastRead')}</span>
              <kbd>Alt+⇧R</kbd>
            </button>
          </>
        ) : (
          <>
            <button className="popup-btn primary" onClick={() => send('toggle-reader', true)}>
              <span className="label">{tr('tryAnyway')}</span>
            </button>
            <button className="popup-btn ghost" onClick={() => window.close()}>
              <span className="label">{tr('cancel')}</span>
            </button>
          </>
        )}
      </div>

      <section className="popup-recent">
        <div className="popup-recent-head">{tr('recent')}</div>
        {recents.length === 0 ? (
          <div className="popup-recent-empty">—</div>
        ) : (
          <ul className="popup-recent-list" style={{ margin: 0, padding: 0, listStyle: 'none' }}>
            {recents.slice(0, 3).map(r => (
              <li key={r.url}>
                <button
                  className="popup-recent-item"
                  onClick={() => chrome.tabs.create({ url: r.url })}
                  title={r.title}
                >
                  <span className="ri-title">{r.title}</span>
                  <span className="ri-row">
                    <span>{r.source}</span>
                    <span className="ri-bar">
                      <span
                        className="ri-bar-fill"
                        style={{ width: `${Math.round(r.progress * 100)}%` }}
                      />
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <footer className="popup-footer">
        <button className="popup-footer-link" onClick={openOptions}>{tr('settings')}</button>
        <span>{tr('version')} · {locale === 'zh_TW' ? '繁中' : 'EN'}</span>
      </footer>
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<StrictMode><Popup /></StrictMode>);
