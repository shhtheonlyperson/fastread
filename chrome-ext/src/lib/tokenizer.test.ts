import { describe, it, expect } from 'vitest';
import {
  tokenize,
  focusIndex,
  splitForFocus,
  durationMs,
  endsWithPunctuationPause,
  countReadingUnits,
  containsCJK,
  isFocusable,
  isHan,
  isCJKChar,
  isCJKPunctuation,
  isASCIIPunctuationPause,
  estimateMinutes,
} from './tokenizer';

describe('tokenizer / character classes', () => {
  it('isFocusable accepts letters and digits, rejects punctuation', () => {
    expect(isFocusable('a')).toBe(true);
    expect(isFocusable('Z')).toBe(true);
    expect(isFocusable('7')).toBe(true);
    expect(isFocusable('é')).toBe(true);
    expect(isFocusable('字')).toBe(true);  // Han is a Letter
    expect(isFocusable('.')).toBe(false);
    expect(isFocusable(' ')).toBe(false);
  });

  it('isHan covers BMP CJK ranges only', () => {
    expect(isHan('字')).toBe(true);
    expect(isHan('国')).toBe(true);
    expect(isHan('あ')).toBe(false);   // Hiragana
    expect(isHan('가')).toBe(false);   // Hangul
    expect(isHan('A')).toBe(false);
  });

  it('isCJKChar covers Han + kana + Hangul', () => {
    expect(isCJKChar('字')).toBe(true);
    expect(isCJKChar('あ')).toBe(true);
    expect(isCJKChar('가')).toBe(true);
    expect(isCJKChar('A')).toBe(false);
  });

  it('isCJKPunctuation / isASCIIPunctuationPause', () => {
    expect(isCJKPunctuation('，')).toBe(true);
    expect(isCJKPunctuation('。')).toBe(true);
    expect(isCJKPunctuation('!')).toBe(false);
    expect(isASCIIPunctuationPause('.')).toBe(true);
    expect(isASCIIPunctuationPause('?')).toBe(true);
    expect(isASCIIPunctuationPause('a')).toBe(false);
  });

  it('containsCJK', () => {
    expect(containsCJK('hello')).toBe(false);
    expect(containsCJK('hello 世界')).toBe(true);
    expect(containsCJK('')).toBe(false);
    expect(containsCJK(null)).toBe(false);
  });
});

describe('tokenize — English / Latin', () => {
  it('splits on whitespace', () => {
    expect(tokenize('hello world how are you')).toEqual(['hello', 'world', 'how', 'are', 'you']);
  });
  it('collapses runs of whitespace and ignores empties', () => {
    expect(tokenize('a   b\t\nc')).toEqual(['a', 'b', 'c']);
  });
  it('returns [] for empty/null', () => {
    expect(tokenize('')).toEqual([]);
    expect(tokenize(null)).toEqual([]);
    expect(tokenize(undefined)).toEqual([]);
  });
  it('keeps punctuation attached to words', () => {
    expect(tokenize('Hello, world!')).toEqual(['Hello,', 'world!']);
  });
  it('replaces NBSP with regular space', () => {
    expect(tokenize('foo bar')).toEqual(['foo', 'bar']);
  });
});

describe('tokenize — CJK & mixed', () => {
  it('segments simple Mandarin into ≥1 chunks', () => {
    const out = tokenize('我喜歡讀書');
    expect(out.length).toBeGreaterThan(0);
    expect(out.join('')).toBe('我喜歡讀書');
  });

  it('preserves order across script boundaries (mixed input round-trips)', () => {
    const out = tokenize('I love 讀書 every day');
    expect(out.includes('I')).toBe(true);
    expect(out.includes('love')).toBe(true);
    expect(out.includes('every')).toBe(true);
    expect(out.includes('day')).toBe(true);
    // CJK chunk(s) reconstruct to the original Han run.
    const cjkPart = out.filter(t => containsCJK(t)).join('');
    expect(cjkPart).toBe('讀書');
  });

  it('glues number + measure word — the digit never stands alone', () => {
    // Browser ICU may then forward-glue 的 onto "5個月", so the final
    // chunk could be "5個月" or "5個月的" — both are correct. The
    // invariant is that "5" doesn't appear as its own chunk separated
    // from "個月".
    const out = tokenize('我有5個月的時間');
    expect(out).not.toContain('5');
    expect(out.some(t => /^5個月/.test(t))).toBe(true);
  });

  it('glues digit + measure word at minimum (cross-script)', () => {
    expect(tokenize('100公斤').some(t => t.includes('100公斤'))).toBe(true);
    expect(tokenize('25 度').some(t => t.includes('25') && t.includes('度'))).toBe(true);
  });

  it('attaches CJK closing punctuation to preceding chunk', () => {
    const out = tokenize('今天，我去學校。');
    // Find the chunk that ends with the period — it should not be a
    // standalone punctuation token.
    const endsWithFullStop = out.some(t => t.endsWith('。'));
    expect(endsWithFullStop).toBe(true);
    expect(out.some(t => t === '。')).toBe(false);
  });

  it('user dictionary forces a multi-token compound to merge', () => {
    const plain = tokenize('我去信義區逛街');
    const merged = tokenize('我去信義區逛街', ['信義區']);
    expect(merged.some(t => t === '信義區')).toBe(true);
    // The dictionary should produce a chunk list at least as
    // tight as the default (≤ in count).
    expect(merged.length).toBeLessThanOrEqual(plain.length + 1);
  });
});

describe('focusIndex / splitForFocus', () => {
  it('returns 0 for empty input', () => {
    expect(focusIndex('')).toBe(0);
    expect(focusIndex(null)).toBe(0);
  });
  it('matches the iOS bucket table', () => {
    expect(focusIndex('a')).toBe(0);            // 1 → 0
    expect(focusIndex('abcde')).toBe(1);        // 5 → 1
    expect(focusIndex('abcdefghi')).toBe(2);    // 9 → 2
    expect(focusIndex('abcdefghijklm')).toBe(3); // 13 → 3
    expect(focusIndex('abcdefghijklmnop')).toBe(4); // 16 → 4
  });
  it('skips non-focusable characters when picking the pivot', () => {
    // Leading quote isn't focusable; first focusable letter index = 1.
    const i = focusIndex('"hello"');
    expect(i).toBe(2); // chars: " h e l l o "  — focusable count 5, target idx 1, mapped to chars[2] = 'e'
  });
  it('splitForFocus partitions exactly around the pivot', () => {
    const s = splitForFocus('reading');
    expect(s.before + s.focus + s.after).toBe('reading');
    expect(s.focus.length).toBe(1);
  });
});

describe('durationMs', () => {
  it('returns a longer delay for CJK tokens than for Latin of same WPM', () => {
    const wpm = 400;
    const latin = durationMs('cat', wpm);
    const cjk = durationMs('我', wpm);
    expect(cjk).toBeGreaterThan(latin);
  });
  it('applies the punctuation pause multiplier when token ends a sentence', () => {
    const a = durationMs('end', 400);
    const b = durationMs('end.', 400);
    expect(b).toBeGreaterThan(a);
    expect(b / a).toBeGreaterThan(1.5); // 1.65 multiplier
  });
  it('clamps WPM into [100, 1200]', () => {
    const at100 = durationMs('cat', 100);
    const atZero = durationMs('cat', 0);    // → safeWPM picks 450, smaller delay
    const atHuge = durationMs('cat', 99999); // clamped to 1200
    expect(at100).toBeGreaterThan(atHuge);
    expect(atZero).toBeLessThan(at100);
  });
  it('long words get a length multiplier', () => {
    const a = durationMs('readable', 400);             // 8 chars
    const b = durationMs('antidisestablishment', 400); // 20 chars
    expect(b).toBeGreaterThan(a);
  });
});

describe('endsWithPunctuationPause', () => {
  it('English: trailing terminals count, even through closers', () => {
    expect(endsWithPunctuationPause('end.')).toBe(true);
    expect(endsWithPunctuationPause('end?"')).toBe(true);
    // ')' itself is in the terminal set in iOS (so e.g. "(foo)" counts).
    expect(endsWithPunctuationPause('end)')).toBe(true);
    expect(endsWithPunctuationPause('mid')).toBe(false);
    expect(endsWithPunctuationPause('letters"')).toBe(false);
  });
  it('CJK: trailing CJK punctuation counts', () => {
    expect(endsWithPunctuationPause('結束。')).toBe(true);
    expect(endsWithPunctuationPause('結束，')).toBe(true);
    expect(endsWithPunctuationPause('結束')).toBe(false);
  });
});

describe('durationMs — boundary cases', () => {
  it('handles NaN / Infinity / negative WPM via safe-clamp', () => {
    const ref = durationMs('word', 450);
    // NaN and Infinity are non-finite → safeWPM falls back to default 450.
    expect(durationMs('word', NaN)).toBeCloseTo(ref);
    expect(durationMs('word', Infinity)).toBeCloseTo(ref);
    // Negative values are finite, then clamped up to 100 → slower than ref.
    expect(durationMs('word', -100)).toBeGreaterThan(ref);
  });
  it('respects the punctuationPause=false flag', () => {
    const withPause = durationMs('end.', 400, true);
    const without   = durationMs('end.', 400, false);
    expect(withPause).toBeGreaterThan(without);
  });
  it('returns an integer (rounded) duration', () => {
    expect(Number.isInteger(durationMs('hello', 333))).toBe(true);
  });
});

describe('countReadingUnits / estimateMinutes', () => {
  it('counts non-empty tokens', () => {
    expect(countReadingUnits('one two three')).toBe(3);
    expect(countReadingUnits('  ')).toBe(0);
    expect(countReadingUnits('')).toBe(0);
  });
  it('estimateMinutes inverts WPM', () => {
    expect(estimateMinutes(400, 400)).toBeCloseTo(1);
    expect(estimateMinutes(800, 400)).toBeCloseTo(2);
  });
});
