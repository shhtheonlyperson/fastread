import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { ExtractedArticle } from '../lib/extract';
import { RsvpEngine, tokenize, groupTokens, type RsvpToken } from '../lib/rsvp';
import { setSettings, type Settings } from '../lib/storage';
import { t, type Locale } from '../lib/i18n';
import { IconPlay, IconPause, IconRewind, IconForward, IconMinus, IconPlus } from '../lib/icons';

interface Props {
  article: ExtractedArticle;
  settings: Settings;
  locale: Locale;
  onExitToReader: (resumeParaIdx: number | null) => void;
  onExit: () => void;
}

export function FastReadPanel({ article, settings, locale, onExitToReader, onExit }: Props) {
  const tokens = useMemo(
    () => groupTokens(tokenize(article.textContent), settings.chunkSize),
    [article.textContent, settings.chunkSize],
  );
  const [current, setCurrent] = useState<RsvpToken | null>(tokens[0] ?? null);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const engineRef = useRef<RsvpEngine | null>(null);
  const tr = (k: string) => t(k, locale);

  useEffect(() => {
    const engine = new RsvpEngine({
      wpm: settings.wpm,
      onTick: (tok, i) => { setCurrent(tok); setIndex(i); },
      onEnd: () => setPlaying(false),
    });
    engine.load(tokens, 0);
    engineRef.current = engine;
    return () => engine.pause();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tokens]);

  useEffect(() => { engineRef.current?.setWpm(settings.wpm); }, [settings.wpm]);

  const togglePlay = () => {
    const eng = engineRef.current; if (!eng) return;
    eng.toggle();
    setPlaying(eng.isPlaying);
  };

  const adjustWpm = (delta: number) => {
    const next = Math.min(1200, Math.max(150, settings.wpm + delta));
    setSettings({ wpm: next });
  };

  /* Keyboard — installed on window per spec. Don't fire when typing
     into an input/textarea/contenteditable. */
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tgt = e.target as HTMLElement | null;
      if (tgt?.closest('input, textarea, [contenteditable="true"]')) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      switch (e.code === 'Space' ? 'Space' : e.key) {
        case 'Space':
          e.preventDefault(); togglePlay(); return;
        case 'ArrowLeft':
        case 'h': case 'H':
          e.preventDefault(); engineRef.current?.skipSentence(-1); return;
        case 'ArrowRight':
        case 'l': case 'L':
          e.preventDefault(); engineRef.current?.skipSentence(1); return;
        case 'ArrowUp':
        case 'k': case 'K':
          e.preventDefault(); adjustWpm(25); return;
        case 'ArrowDown':
        case 'j': case 'J':
          e.preventDefault(); adjustWpm(-25); return;
        case 'Escape': {
          e.preventDefault();
          const idx = paragraphIndexFor(article.textContent, index);
          onExitToReader(idx);
          return;
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings.wpm, index, article.textContent]);

  /* Compute sentence context — pull words around the current sentence. */
  const sentence = useMemo(() => buildSentence(tokens, current?.sentenceIndex ?? 0), [tokens, current?.sentenceIndex]);

  const progress = tokens.length ? (index / tokens.length) * 100 : 0;
  const word = current?.word ?? '';
  const orp = current?.orpIndex ?? 0;
  const before = word.slice(0, orp);
  const pivot = word.slice(orp, orp + 1);
  const after = word.slice(orp + 1);

  /* ORP letter centering: measure before+pivot widths and translate left so
     the pivot column sits at the page center. */
  const wordInnerRef = useRef<HTMLSpanElement | null>(null);
  const beforeRef = useRef<HTMLSpanElement | null>(null);
  const pivotRef = useRef<HTMLSpanElement | null>(null);
  const [orpOffset, setOrpOffset] = useState(0);
  useLayoutEffect(() => {
    const inner = wordInnerRef.current;
    const b = beforeRef.current;
    const p = pivotRef.current;
    if (!inner || !p) return;
    const innerW = inner.offsetWidth;
    const beforeW = b?.offsetWidth ?? 0;
    const pivotW = p.offsetWidth || 1;
    const pivotCenter = beforeW + pivotW / 2;
    setOrpOffset(innerW / 2 - pivotCenter);
  }, [word, orp]);

  const handleBack = () => {
    const idx = paragraphIndexFor(article.textContent, index);
    onExitToReader(idx);
  };

  return (
    <section
      className="jr-fastread"
      role="region"
      aria-label={tr('fastRead')}
      data-mode="fastread"
    >
      <div className="jr-fr-top">
        <div className="jr-eyebrow">{article.title}</div>
      </div>

      <div className="jr-fr-stage">
        <span className="jr-fr-tick top" aria-hidden />
        <div
          className="jr-fr-word"
          aria-live={playing ? 'off' : 'polite'}
          aria-atomic="true"
        >
          <span
            className="jr-fr-word-inner"
            ref={wordInnerRef}
            style={{ ['--jr-orp-offset' as never]: `${orpOffset}px` }}
          >
            <span ref={beforeRef} className="jr-fr-before">{before}</span>
            <span ref={pivotRef} className="jr-fr-pivot">{pivot}</span>
            <span className="jr-fr-after">{after}</span>
          </span>
        </div>
        <span className="jr-fr-tick bottom" aria-hidden />
      </div>

      <div className="jr-fr-sentence">{sentence}</div>

      <div className="jr-fr-progress" aria-hidden>
        <div className="jr-fr-progress-fill" style={{ ['--jr-progress' as never]: `${progress}%` }} />
      </div>

      <div className="jr-fr-controls">
        <div className="jr-fr-controls-left">
          <div className="jr-fr-chunk">
            <div className="jr-fr-chunk-row">
              {[1, 2, 3].map(n => (
                <button
                  key={n}
                  className={`jr-fr-chunk-btn ${settings.chunkSize === n ? 'is-active' : ''}`}
                  onClick={() => setSettings({ chunkSize: n as 1 | 2 | 3 })}
                  aria-label={`${tr('chunk')} ${n}`}
                >{n}</button>
              ))}
            </div>
            <span className="jr-fr-dial-label">{tr('chunk')}</span>
          </div>
        </div>

        <div className="jr-fr-controls-mid">
          <button
            className="jr-fr-skip"
            onClick={() => engineRef.current?.skipSentence(-1)}
            aria-label="Previous sentence"
          ><IconRewind size={16} /></button>
          <button
            className="jr-fr-play"
            onClick={togglePlay}
            aria-label={playing ? tr('pause') : tr('play')}
          >{playing ? <IconPause size={20} /> : <IconPlay size={20} />}</button>
          <button
            className="jr-fr-skip"
            onClick={() => engineRef.current?.skipSentence(1)}
            aria-label="Next sentence"
          ><IconForward size={16} /></button>
        </div>

        <div className="jr-fr-controls-right">
          <div className="jr-fr-dial">
            <div className="jr-fr-dial-row">
              <button
                className="jr-fr-dial-btn"
                onClick={() => adjustWpm(-25)}
                aria-label="Decrease WPM"
              ><IconMinus size={12} /></button>
              <span className="jr-fr-dial-num">{settings.wpm}</span>
              <button
                className="jr-fr-dial-btn"
                onClick={() => adjustWpm(25)}
                aria-label="Increase WPM"
              ><IconPlus size={12} /></button>
            </div>
            <span className="jr-fr-dial-label">{tr('wpm')}</span>
          </div>
        </div>
      </div>

      <div className="jr-fr-footer">
        <button className="jr-fr-back" onClick={handleBack}>{tr('backToReader')}</button>
        <span className="jr-fr-hint">{tr('keyboardHints')}</span>
        <button className="jr-fr-back" onClick={onExit}>Esc · {tr('exit')}</button>
      </div>
    </section>
  );
}

/* Build a centered sentence preview from the tokens at the current sentence
   index — useful for context. Truncated to ~120 chars. */
function buildSentence(tokens: RsvpToken[], sentenceIndex: number): string {
  let s = '';
  for (const tok of tokens) {
    if (tok.sentenceIndex !== sentenceIndex) {
      if (s) break;
      continue;
    }
    s += (s ? ' ' : '') + tok.word;
    if (s.length > 140) { s = s.slice(0, 138) + '…'; break; }
  }
  return s;
}

/* Given the full text and a word index, estimate which paragraph it belongs
   to (paragraphs split on double newline / common para boundaries). */
function paragraphIndexFor(text: string, wordIndex: number): number | null {
  if (!text) return null;
  const paras = text.split(/\n{2,}/);
  let acc = 0;
  for (let i = 0; i < paras.length; i++) {
    const part = paras[i] ?? '';
    const w = part.split(/\s+/).filter(Boolean).length;
    if (wordIndex < acc + w) return i;
    acc += w;
  }
  return paras.length - 1;
}
