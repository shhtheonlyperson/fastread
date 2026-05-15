import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { tokenize, groupTokens, RsvpEngine, focusIndex, type RsvpToken } from './rsvp';

describe('rsvp.tokenize', () => {
  it('emits RsvpToken objects with orpIndex and sentenceIndex', () => {
    const out = tokenize('hello world.');
    expect(out.length).toBe(2);
    expect(out[0]!.word).toBe('hello');
    expect(out[0]!.sentenceIndex).toBe(0);
    expect(out[1]!.word).toBe('world.');
    // Sentence index doesn't increment for the *current* sentence-ender.
    expect(out[1]!.sentenceIndex).toBe(0);
  });

  it('increments sentenceIndex across multiple sentences', () => {
    const out = tokenize('One. Two. Three.');
    const last = out.at(-1)!;
    expect(last.sentenceIndex).toBe(2);
  });

  it('treats CJK 。 ！ ？ as sentence ends', () => {
    const out = tokenize('你好。世界！再見？結束');
    const ends = new Set(out.map(t => t.sentenceIndex));
    expect(ends.size).toBeGreaterThan(1);
  });

  it('handles empty input', () => {
    expect(tokenize('')).toEqual([]);
  });
});

describe('RsvpEngine — control flow', () => {
  let ticks: Array<{ t: RsvpToken; i: number }>;
  let ended = false;
  let engine: RsvpEngine;
  const tokens: RsvpToken[] = [
    { word: 'a', orpIndex: 0, sentenceIndex: 0 },
    { word: 'b', orpIndex: 0, sentenceIndex: 0 },
    { word: 'c.', orpIndex: 0, sentenceIndex: 0 },
    { word: 'd', orpIndex: 0, sentenceIndex: 1 },
    { word: 'e.', orpIndex: 0, sentenceIndex: 1 },
    { word: 'f', orpIndex: 0, sentenceIndex: 2 },
  ];

  beforeEach(() => {
    vi.useFakeTimers();
    ticks = [];
    ended = false;
    engine = new RsvpEngine({
      wpm: 600,
      onTick: (t, i) => ticks.push({ t, i }),
      onEnd: () => { ended = true; },
    });
    engine.load(tokens);
  });

  afterEach(() => { vi.useRealTimers(); });

  it('starts paused; load() does not auto-emit', () => {
    expect(engine.isPlaying).toBe(false);
    expect(ticks).toEqual([]);
  });

  it('play() emits each token in order and ends', () => {
    engine.play();
    expect(engine.isPlaying).toBe(true);
    // Advance enough virtual time to fire well past the last token.
    vi.advanceTimersByTime(10_000);
    expect(ticks.length).toBe(tokens.length);
    expect(ticks.map(x => x.t.word)).toEqual(tokens.map(t => t.word));
    expect(ended).toBe(true);
    expect(engine.isPlaying).toBe(false);
  });

  it('pause() stops scheduling further ticks', () => {
    engine.play();
    vi.advanceTimersByTime(150);
    const seenBefore = ticks.length;
    engine.pause();
    vi.advanceTimersByTime(5_000);
    expect(ticks.length).toBe(seenBefore);
    expect(engine.isPlaying).toBe(false);
  });

  it('toggle() flips play/pause', () => {
    engine.toggle();
    expect(engine.isPlaying).toBe(true);
    engine.toggle();
    expect(engine.isPlaying).toBe(false);
  });

  it('seek(i) clamps to [0, n-1] and emits the new token', () => {
    engine.seek(2);
    expect(engine.currentIndex).toBe(2);
    expect(ticks.at(-1)!.t.word).toBe('c.');
    engine.seek(-5);
    expect(engine.currentIndex).toBe(0);
    engine.seek(99);
    expect(engine.currentIndex).toBe(tokens.length - 1);
  });

  it('skipSentence(+1) jumps to the first token of the next sentence', () => {
    engine.seek(0);
    engine.skipSentence(1);
    expect(engine.currentToken!.sentenceIndex).toBe(1);
    expect(engine.currentToken!.word).toBe('d');
  });

  it('skipSentence(-1) goes back', () => {
    engine.seek(3); // sentence 1
    engine.skipSentence(-1);
    expect(engine.currentToken!.sentenceIndex).toBe(0);
    expect(engine.currentToken!.word).toBe('a');
  });

  it('setWpm changes scheduling cadence', () => {
    engine.play();
    vi.advanceTimersByTime(50);
    const fast = ticks.length;
    engine.pause();
    engine.seek(0);
    ticks.length = 0;
    engine.setWpm(120); // much slower
    engine.play();
    vi.advanceTimersByTime(50);
    const slow = ticks.length;
    expect(fast).toBeGreaterThanOrEqual(slow);
  });
});

describe('groupTokens', () => {
  const tok = (word: string, sentenceIndex = 0): RsvpToken =>
    ({ word, orpIndex: focusIndex(word), sentenceIndex });

  it('chunkSize=1 is a no-op (returns the same array reference)', () => {
    const input = [tok('a'), tok('b'), tok('c')];
    expect(groupTokens(input, 1)).toBe(input);
  });

  it('chunkSize=2 joins Latin tokens with a single space', () => {
    const out = groupTokens([tok('the'), tok('quick'), tok('brown'), tok('fox')], 2);
    expect(out.map(t => t.word)).toEqual(['the quick', 'brown fox']);
  });

  it('chunkSize=3 leaves a smaller tail at the end', () => {
    const out = groupTokens([tok('a'), tok('b'), tok('c'), tok('d')], 3);
    expect(out.map(t => t.word)).toEqual(['a b c', 'd']);
  });

  it('chunkSize=2 joins CJK chunks with no separator', () => {
    const out = groupTokens([tok('我去'), tok('學校'), tok('上課')], 2);
    expect(out[0]!.word).toBe('我去學校');
    expect(out[1]!.word).toBe('上課');
  });

  it('sentenceIndex of a merged chunk follows the LAST inner token', () => {
    const out = groupTokens([tok('a', 0), tok('b.', 0), tok('c', 1)], 2);
    expect(out[0]!.sentenceIndex).toBe(0); // [a, b.] → 0
    expect(out[1]!.sentenceIndex).toBe(1); // [c]    → 1
  });

  it('orpIndex is recomputed against the merged string', () => {
    const merged = groupTokens([tok('the'), tok('quick'), tok('brown')], 3);
    const m = merged[0]!;
    expect(m.word).toBe('the quick brown');
    expect(m.orpIndex).toBe(focusIndex(m.word));
  });

  it('empty input returns empty', () => {
    expect(groupTokens([], 2)).toEqual([]);
    expect(groupTokens([], 3)).toEqual([]);
  });
});

describe('RsvpEngine — empty / edge', () => {
  it('immediately ends when given no tokens', () => {
    let ended = false;
    const engine = new RsvpEngine({
      wpm: 400,
      onTick: () => undefined,
      onEnd: () => { ended = true; },
    });
    engine.load([]);
    engine.play();
    expect(ended).toBe(true);
  });
});
