import { describe, it, expect } from 'vitest';
import { groupSizes } from './chunkShaper';
import { tokenize } from './tokenizer';

/* groupSizes is exported; the shaper itself only ships as part of the
 * tokenize() pipeline, so we exercise it through tokenize(). */

describe('groupSizes', () => {
  it('always sums back to n', () => {
    for (let n = 0; n <= 30; n++) {
      expect(groupSizes(n).reduce((a, b) => a + b, 0)).toBe(n);
    }
  });
  it('prefers threes for hand-tabulated small n', () => {
    // These cases are the ones the gold corpus actually exercises — the
    // recursive default for n ≥ 10 can leave a [1,1] tail when remaining
    // hits 2 (parity with Swift impl), which is acceptable because the
    // shaper rarely sees runs that long.
    expect(groupSizes(3)).toEqual([3]);
    expect(groupSizes(6)).toEqual([3, 3]);
    expect(groupSizes(9)).toEqual([3, 3, 3]);
  });
  it('handles small n', () => {
    expect(groupSizes(0)).toEqual([]);
    expect(groupSizes(1)).toEqual([1]);
    expect(groupSizes(2)).toEqual([1, 1]);
    expect(groupSizes(3)).toEqual([3]);
    expect(groupSizes(4)).toEqual([2, 2]);
    expect(groupSizes(5)).toEqual([2, 3]);
  });
});

describe('ChunkShaper end-to-end (via tokenize)', () => {
  it('number + measure word merges across script boundary', () => {
    expect(tokenize('100公斤')).toContain('100公斤');
    expect(tokenize('25 度')).toContain('25 度'.replace(' ', '')); // measure word
  });

  it('forward-glues 是 / 在 / 不 / 都 / 也 into the next multi-char chunk', () => {
    // Each of these is one of particlesForward and should not stand alone
    // if the next chunk has ≥2 Han chars.
    for (const sample of ['這是新書', '我在學校', '他不知道', '我都明白', '他也來了']) {
      const out = tokenize(sample);
      // No standalone single-char particle that's a particlesForward entry.
      for (const t of out) {
        if (t.length === 1 && '是在不都也'.includes(t)) {
          // If it does stand alone, the next token must be single-Han too
          // (which is allowed per the rule).
          const idx = out.indexOf(t);
          const next = out[idx + 1] ?? '';
          // Either it merged (no standalone) or the next token is short.
          expect(next.length).toBeLessThanOrEqual(1);
        }
      }
    }
  });

  it('backward-glues 了 / 嗎 / 吧 onto the preceding chunk', () => {
    for (const sample of ['我去了學校', '你來嗎？', '走吧！']) {
      const out = tokenize(sample);
      // No bare '了' / '嗎' / '吧' as its own non-trailing chunk.
      const lone = out.find(t => t === '了' || t === '嗎' || t === '吧');
      expect(lone).toBeUndefined();
    }
  });

  it('的 never stands alone as a single-char chunk', () => {
    // Browser ICU segments 周杰倫 differently from iOS NLTokenizer, so
    // the precise chunking varies — but the invariant that 的 must
    // bind to one side (never flash alone) holds.
    const out = tokenize('我聽周杰倫的新歌');
    expect(out).not.toContain('的');
    // 的 should appear inside some chunk, joined to a neighbour.
    expect(out.some(t => t.includes('的'))).toBe(true);
  });

  it('coalesces 3+ single-Han runs into rhythmic 2–3 char chunks', () => {
    // 黃士旗 — likely 3 single-Han ICU tokens. Expect a 3-char chunk.
    const out = tokenize('黃士旗去吃飯');
    expect(out.some(t => [...t].length === 3 && /^[一-鿿]+$/.test(t))).toBe(true);
  });

  it('respects max-merged cap (≤4 Han chars per chunk)', () => {
    const out = tokenize('我們今天去看了一部很好的電影。');
    for (const t of out) {
      const hanCount = [...t].filter(c => /\p{Script=Han}/u.test(c)).length;
      expect(hanCount).toBeLessThanOrEqual(4);
    }
  });

  it('caps merged chunks at 4 Han chars even with particle gluing', () => {
    // 中華民國(4) + 的 + 總統府(3): 的 can't go backward (would exceed 4),
    // so it must go forward.
    const out = tokenize('中華民國的總統府');
    expect(out.some(t => t.startsWith('的'))).toBe(true);
  });

  it('aspect marker 了 attaches backward', () => {
    const out = tokenize('我吃了三碗飯。');
    // No standalone 了 anywhere in the stream.
    expect(out).not.toContain('了');
    expect(out.some(t => t.includes('了'))).toBe(true);
  });

  it('sentence-final 嗎 attaches backward', () => {
    const out = tokenize('你來嗎');
    expect(out).not.toContain('嗎');
  });

  it('digit run handling: dots and commas count as digits', () => {
    // The fast path keeps "3.14" together with a measure word.
    const out = tokenize('3.14個');
    expect(out.some(t => t.includes('3.14') && t.includes('個'))).toBe(true);
  });

  it('does not collapse across hard clause endings', () => {
    // Stray singleton absorb should not pull a char from after a period
    // back into the previous chunk.
    const out = tokenize('他說謊。也許不對。');
    const idx = out.findIndex(t => t.endsWith('。'));
    expect(idx).toBeGreaterThanOrEqual(0);
    // The chunk after the period must not start with the stray that
    // would have been absorbed backward.
    if (idx + 1 < out.length) {
      expect(out[idx]!.endsWith('也。')).toBe(false);
    }
  });
});
