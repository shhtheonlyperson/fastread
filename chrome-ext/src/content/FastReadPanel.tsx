import { useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { ExtractedArticle } from '../lib/extract';
import { tokenize, groupTokens, type RsvpToken } from '../lib/rsvp';
import { setSettings, WPM_STEP, type Settings } from '../lib/storage';
import { t, type Locale } from '../lib/i18n';
import { IconPlay, IconPause, IconRewind, IconForward, IconMinus, IconPlus } from '../lib/icons';
import { useRsvpPlayback } from './useRsvpPlayback';

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
  const tr = (k: string) => t(k, locale);

  const { current, index, playing, togglePlay, adjustWpm, skipSentence, exitToReader } =
    useRsvpPlayback({
      tokens,
      wpm: settings.wpm,
      textContent: article.textContent,
      onExitToReader,
    });

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
            onClick={() => skipSentence(-1)}
            aria-label="Previous sentence"
          ><IconRewind size={16} /></button>
          <button
            className="jr-fr-play"
            onClick={togglePlay}
            aria-label={playing ? tr('pause') : tr('play')}
          >{playing ? <IconPause size={20} /> : <IconPlay size={20} />}</button>
          <button
            className="jr-fr-skip"
            onClick={() => skipSentence(1)}
            aria-label="Next sentence"
          ><IconForward size={16} /></button>
        </div>

        <div className="jr-fr-controls-right">
          <div className="jr-fr-dial">
            <div className="jr-fr-dial-row">
              <button
                className="jr-fr-dial-btn"
                onClick={() => adjustWpm(-WPM_STEP)}
                aria-label="Decrease WPM"
              ><IconMinus size={12} /></button>
              <span className="jr-fr-dial-num">{settings.wpm}</span>
              <button
                className="jr-fr-dial-btn"
                onClick={() => adjustWpm(WPM_STEP)}
                aria-label="Increase WPM"
              ><IconPlus size={12} /></button>
            </div>
            <span className="jr-fr-dial-label">{tr('wpm')}</span>
          </div>
        </div>
      </div>

      <div className="jr-fr-footer">
        <button className="jr-fr-back" onClick={exitToReader}>{tr('backToReader')}</button>
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
