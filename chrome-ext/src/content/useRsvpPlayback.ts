import { useEffect, useMemo, useRef, useState } from 'react';
import { RsvpEngine, type RsvpToken } from '../lib/rsvp';
import { containsCJK } from '../lib/tokenizer';
import { RSVP_SPEC } from '../lib/rsvpSpec.generated';
import { setSettings, WPM_MAX, WPM_STEP } from '../lib/storage';

interface Args {
  tokens: RsvpToken[];
  wpm: number;
  /** Full article text, used to map the current word back to a paragraph
   *  index when exiting to the reader. */
  textContent: string;
  onExitToReader: (resumeParaIdx: number | null) => void;
}

export interface RsvpPlayback {
  current: RsvpToken | null;
  index: number;
  playing: boolean;
  togglePlay: () => void;
  adjustWpm: (delta: number) => void;
  skipSentence: (dir: -1 | 1) => void;
  exitToReader: () => void;
}

/**
 * Owns the RSVP playback loop for FastReadPanel: engine lifecycle, play/pace
 * state, WPM adjustment, sentence skipping, and the window keyboard shortcuts.
 * Keeping it out of the component leaves the panel as pure presentation and
 * makes the playback behavior reusable/testable on its own.
 */
export function useRsvpPlayback({ tokens, wpm, textContent, onExitToReader }: Args): RsvpPlayback {
  const [current, setCurrent] = useState<RsvpToken | null>(tokens[0] ?? null);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const engineRef = useRef<RsvpEngine | null>(null);

  // CJK is denser per glyph and carries a duration multiplier, so it reads
  // comfortably slower — its WPM floor drops below the Latin one.
  const minWpm = useMemo(
    () => (containsCJK(textContent) ? RSVP_SPEC.wpm.minimumUser.cjk : RSVP_SPEC.wpm.minimumUser.latin),
    [textContent],
  );

  useEffect(() => {
    const engine = new RsvpEngine({
      wpm,
      onTick: (tok, i) => { setCurrent(tok); setIndex(i); },
      onEnd: () => setPlaying(false),
    });
    engine.load(tokens, 0);
    engineRef.current = engine;
    return () => engine.pause();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tokens]);

  useEffect(() => { engineRef.current?.setWpm(wpm); }, [wpm]);

  // Track the latest WPM / index in refs so the keydown handler sees fresh
  // values without the effect re-installing on every change. Without this,
  // rapid j/k presses are lost: the handler would capture the value at install
  // time and re-apply the same delta to the same start value (a no-op).
  const wpmRef = useRef(wpm);
  useEffect(() => { wpmRef.current = wpm; }, [wpm]);
  const indexRef = useRef(0);
  useEffect(() => { indexRef.current = index; }, [index]);

  const togglePlay = () => {
    const eng = engineRef.current; if (!eng) return;
    eng.toggle();
    setPlaying(eng.isPlaying);
  };

  const adjustWpm = (delta: number) => {
    const next = Math.min(WPM_MAX, Math.max(minWpm, wpmRef.current + delta));
    setSettings({ wpm: next });
    wpmRef.current = next; // optimistic — keeps batched presses coherent.
  };

  const skipSentence = (dir: -1 | 1) => { engineRef.current?.skipSentence(dir); };

  const exitToReader = () => onExitToReader(paragraphIndexFor(textContent, indexRef.current));

  /* Keyboard — installed on window per spec. Don't fire when typing into an
     input/textarea/contenteditable. Listener stays installed for the panel's
     lifetime; fresh values are read through refs. */
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
          e.preventDefault(); skipSentence(-1); return;
        case 'ArrowRight':
        case 'l': case 'L':
          e.preventDefault(); skipSentence(1); return;
        case 'ArrowUp':
        case 'k': case 'K':
          e.preventDefault(); adjustWpm(WPM_STEP); return;
        case 'ArrowDown':
        case 'j': case 'J':
          e.preventDefault(); adjustWpm(-WPM_STEP); return;
        case 'Escape':
          e.preventDefault(); exitToReader(); return;
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { current, index, playing, togglePlay, adjustWpm, skipSentence, exitToReader };
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
