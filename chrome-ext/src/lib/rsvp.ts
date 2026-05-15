import {
  tokenize as rawTokenize,
  focusIndex,
  splitForFocus,
  durationMs,
  containsCJK,
  TOKENIZER_VERSION,
} from './tokenizer';

export { focusIndex, splitForFocus, TOKENIZER_VERSION };

export interface RsvpToken {
  word: string;
  orpIndex: number;
  sentenceIndex: number;
}

const SENTENCE_END_ASCII = new Set(['.', '!', '?', '…']);
const SENTENCE_END_CJK = new Set(['。', '！', '？', '．']);

function endsSentence(token: string): boolean {
  for (let i = token.length - 1; i >= 0; i--) {
    const c = token[i]!;
    if (SENTENCE_END_ASCII.has(c) || SENTENCE_END_CJK.has(c)) return true;
    // Allow trailing closer / quote marks before the terminal punct.
    if ([')', ']', '"', "'", '」', '』', '）', '》', '〉'].includes(c)) continue;
    return false;
  }
  return false;
}

export function tokenize(text: string, userDictionary: string[] = []): RsvpToken[] {
  const words = rawTokenize(text, userDictionary);
  const out: RsvpToken[] = [];
  let sentenceIndex = 0;
  for (const w of words) {
    if (!w) continue;
    out.push({ word: w, orpIndex: focusIndex(w), sentenceIndex });
    if (endsSentence(w)) sentenceIndex++;
  }
  return out;
}

/** Group N base tokens into one displayed RSVP chunk. CJK chunks join
 *  with no separator (我去學校), Latin chunks with a space. ORP is
 *  recomputed against the merged string; sentenceIndex follows the last
 *  inner token so sentence-skip still lands on the right boundary. */
export function groupTokens(base: RsvpToken[], chunkSize: 1 | 2 | 3): RsvpToken[] {
  if (chunkSize === 1 || base.length === 0) return base;
  const out: RsvpToken[] = [];
  for (let i = 0; i < base.length; i += chunkSize) {
    const slice = base.slice(i, i + chunkSize);
    const joiner = containsCJK(slice[0]!.word) ? '' : ' ';
    const word = slice.map(t => t.word).join(joiner);
    out.push({
      word,
      orpIndex: focusIndex(word),
      sentenceIndex: slice[slice.length - 1]!.sentenceIndex,
    });
  }
  return out;
}

export interface RsvpEngineOptions {
  wpm: number;
  onTick: (token: RsvpToken, index: number) => void;
  onEnd: () => void;
  punctuationPause?: boolean;
}

export class RsvpEngine {
  private tokens: RsvpToken[] = [];
  private index = 0;
  private timer: number | null = null;
  private playing = false;

  constructor(private opts: RsvpEngineOptions) {}

  load(tokens: RsvpToken[], startIndex = 0) {
    this.tokens = tokens;
    this.index = Math.min(Math.max(startIndex, 0), Math.max(tokens.length - 1, 0));
  }
  setWpm(wpm: number) { this.opts.wpm = wpm; }
  play() { if (!this.playing) { this.playing = true; this.scheduleNext(); } }
  pause() {
    this.playing = false;
    if (this.timer !== null) { clearTimeout(this.timer); this.timer = null; }
  }
  toggle() { this.playing ? this.pause() : this.play(); }
  seek(index: number) {
    this.index = Math.min(Math.max(index, 0), Math.max(this.tokens.length - 1, 0));
    this.emit();
  }
  skipSentence(dir: 1 | -1) {
    const cur = this.tokens[this.index]?.sentenceIndex ?? 0;
    const target = cur + dir;
    const i = this.tokens.findIndex(t => t.sentenceIndex === target);
    if (i >= 0) this.seek(i);
  }
  get isPlaying() { return this.playing; }
  get currentIndex() { return this.index; }
  get total() { return this.tokens.length; }
  get currentToken(): RsvpToken | undefined { return this.tokens[this.index]; }

  private emit() {
    const t = this.tokens[this.index];
    if (t) this.opts.onTick(t, this.index);
  }
  private scheduleNext() {
    if (!this.playing) return;
    const t = this.tokens[this.index];
    if (!t) { this.playing = false; this.opts.onEnd(); return; }
    this.emit();
    const delay = durationMs(t.word, this.opts.wpm, this.opts.punctuationPause ?? true);
    this.timer = setTimeout(() => {
      this.index++;
      this.scheduleNext();
    }, delay) as unknown as number;
  }
}
