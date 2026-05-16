import { createRoot } from 'react-dom/client';
import { StrictMode, useEffect, useMemo, useState } from 'react';
import {
  DEFAULTS,
  WPM_MAX,
  WPM_MIN,
  WPM_STEP,
  getSettings,
  setSettings,
  type Settings,
  type OrpAccent,
} from '../lib/storage';
import { resolveLocale, t, localeHtmlLang } from '../lib/i18n';

type SectionKey = 'defaults' | 'allowlist' | 'blocklist' | 'shortcuts' | 'language' | 'about';

const ORP_SWATCHES: Array<{ key: OrpAccent; color: string }> = [
  { key: 'coral',  color: '#a9583e' },
  { key: 'merlot', color: '#9a4d35' },
  { key: 'teal',   color: '#5db8a6' },
  { key: 'amber',  color: '#e8a55a' },
];

function Options() {
  const [s, setS] = useState<Settings>(DEFAULTS);
  const [section, setSection] = useState<SectionKey>('defaults');

  useEffect(() => { getSettings().then(setS); }, []);

  const locale = useMemo(() => resolveLocale(s.locale), [s.locale]);
  const tr = useMemo(() => (k: string) => t(k, locale), [locale]);

  useEffect(() => {
    document.documentElement.lang = localeHtmlLang(locale);
  }, [locale]);

  const update = (patch: Partial<Settings>) => {
    setS(prev => ({ ...prev, ...patch }));
    setSettings(patch);
  };

  const themeSeg: Array<[Settings['theme'], string]> = [
    ['light', tr('light')], ['dark', tr('dark')],
  ];
  const fontSeg: Array<[Settings['font'], string]> = [
    ['serif', tr('serif')], ['sans', tr('sans')],
  ];
  const chunkSeg: Array<[Settings['chunkSize'], string]> = [[1, '1'], [2, '2'], [3, '3']];
  const localeSeg: Array<[Settings['locale'], string]> = [
    ['zh_TW', '繁體中文'], ['en', 'English'],
  ];

  return (
    <div className="opt-page">
      <header className="opt-header">
        <h1 className="opt-wordmark">{tr('appName')} — {tr('options')}</h1>
        <span className="opt-version">{tr('version')}</span>
      </header>

      <nav className="opt-sidebar" aria-label="Sections">
        {(['defaults', 'allowlist', 'blocklist', 'shortcuts', 'language', 'about'] as SectionKey[]).map(k => (
          <button
            key={k}
            className={`opt-sidebar-btn ${section === k ? 'is-active' : ''}`}
            onClick={() => setSection(k)}
          >{tr(k)}</button>
        ))}
      </nav>

      <main className="opt-main">
        {section === 'defaults' && (
          <>
            <section className="opt-section">
              <h2>{tr('reading')}</h2>
              <div className="opt-row">
                <span className="label">{tr('theme')}</span>
                <span className="value">
                  <Segmented value={s.theme} options={themeSeg} onChange={v => update({ theme: v })} />
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('font')}</span>
                <span className="value">
                  <Segmented value={s.font} options={fontSeg} onChange={v => update({ font: v })} />
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('fontSize')}</span>
                <span className="value">
                  <input
                    type="range" min={14} max={22} step={1}
                    value={s.fontSize}
                    onChange={e => update({ fontSize: Number(e.target.value) })}
                  />
                  <span className="num">{s.fontSize} px</span>
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('lineHeight')}</span>
                <span className="value">
                  <input
                    type="range" min={1.3} max={1.9} step={0.05}
                    value={s.lineHeight}
                    onChange={e => update({ lineHeight: Number(e.target.value) })}
                  />
                  <span className="num">{s.lineHeight.toFixed(2)}</span>
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('width')}</span>
                <span className="value">
                  <input
                    type="range" min={560} max={820} step={20}
                    value={s.columnWidth}
                    onChange={e => update({ columnWidth: Number(e.target.value) })}
                  />
                  <span className="num">{s.columnWidth} px</span>
                </span>
              </div>
            </section>

            <section className="opt-section">
              <h2>{tr('fastRead')}</h2>
              <div className="opt-row">
                <span className="label">{tr('defaultWpm')}</span>
                <span className="value">
                  <input
                    type="range" min={WPM_MIN} max={WPM_MAX} step={WPM_STEP}
                    value={s.wpm}
                    onChange={e => update({ wpm: Number(e.target.value) })}
                  />
                  <span className="num">{s.wpm}</span>
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('chunk')}</span>
                <span className="value">
                  <Segmented<Settings['chunkSize']> value={s.chunkSize} options={chunkSeg} onChange={v => update({ chunkSize: v })} />
                </span>
              </div>
              <div className="opt-row">
                <span className="label">{tr('orpAccent')}</span>
                <span className="value opt-swatches">
                  {ORP_SWATCHES.map(sw => (
                    <button
                      key={sw.key}
                      className={`opt-swatch ${s.orpAccent === sw.key ? 'is-active' : ''}`}
                      style={{ background: sw.color }}
                      onClick={() => update({ orpAccent: sw.key })}
                      aria-label={sw.key}
                      title={sw.key}
                    />
                  ))}
                </span>
              </div>
            </section>
          </>
        )}

        {section === 'shortcuts' && (
          <section className="opt-section">
            <h2>{tr('shortcuts')}</h2>
            <table className="opt-shortcuts">
              <tbody>
                <tr><td>{tr('openReader')}</td><td><kbd>Alt</kbd><kbd>R</kbd> · <kbd>F</kbd></td></tr>
                <tr><td>{tr('startFastRead')}</td><td><kbd>Alt</kbd><kbd>⇧</kbd><kbd>R</kbd> · <kbd>⇧</kbd><kbd>F</kbd></td></tr>
                <tr><td>{tr('play')} / {tr('pause')}</td><td><kbd>Space</kbd></td></tr>
                <tr><td>Sentence</td><td><kbd>←</kbd> <kbd>→</kbd></td></tr>
                <tr><td>{tr('wpm')} ±25</td><td><kbd>↑</kbd> <kbd>↓</kbd></td></tr>
                <tr><td>{tr('exit')}</td><td><kbd>Esc</kbd></td></tr>
              </tbody>
            </table>
            <p style={{ color: 'var(--jr-muted)', fontSize: 12, marginTop: 16 }}>
              Modifier-required shortcuts are rebindable in <code>chrome://extensions/shortcuts</code>.
            </p>
          </section>
        )}

        {section === 'language' && (
          <section className="opt-section">
            <h2>{tr('language')}</h2>
            <div className="opt-row">
              <span className="label">{tr('language')}</span>
              <span className="value">
                <Segmented<Settings['locale']> value={s.locale} options={localeSeg} onChange={v => update({ locale: v })} />
              </span>
            </div>
          </section>
        )}

        {section === 'allowlist' && (
          <section className="opt-section">
            <h2>{tr('allowlist')}</h2>
            <p style={{ color: 'var(--jr-muted)', fontSize: 13, margin: 0 }}>—</p>
          </section>
        )}
        {section === 'blocklist' && (
          <section className="opt-section">
            <h2>{tr('blocklist')}</h2>
            <p style={{ color: 'var(--jr-muted)', fontSize: 13, margin: 0 }}>—</p>
          </section>
        )}
        {section === 'about' && (
          <section className="opt-section">
            <h2>{tr('about')}</h2>
            <p style={{ color: 'var(--jr-muted)', fontSize: 13 }}>JustRead — Reader View + Fast Read · {tr('version')}</p>
          </section>
        )}
      </main>
    </div>
  );
}

interface SegmentedProps<T extends string | number> {
  value: T;
  options: Array<[T, string]>;
  onChange: (v: T) => void;
}
function Segmented<T extends string | number>({ value, options, onChange }: SegmentedProps<T>) {
  return (
    <div className="opt-segmented" role="radiogroup">
      {options.map(([v, label]) => (
        <button
          key={String(v)}
          role="radio"
          aria-checked={value === v}
          className={value === v ? 'is-active' : ''}
          onClick={() => onChange(v)}
        >{label}</button>
      ))}
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<StrictMode><Options /></StrictMode>);
