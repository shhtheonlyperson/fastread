/**
 * Gold-corpus parity test — runs the TS tokenizer over the same human-
 * curated corpus the iOS RSVPEngine is scored against
 * (Tests/Fixtures/rsvp-gold-corpus.tsv) and asserts the boundary-F1
 * score stays above a floor.
 *
 * iOS baseline at last measurement: F1 = 0.828.
 * TS port (Intl.Segmenter('zh-Hant') + same ChunkShaper passes) doesn't
 * match NLTokenizer's segmentation exactly; the threshold is calibrated
 * to the measured TS score with a small margin so the gate flags real
 * drift without false-positiving on platform tokenizer noise.
 *
 * Scoring mirrors Tools/FastReadTokenizerStats/main.swift:
 *   - "internal boundaries" = cumulative-char-count positions between
 *     chunks, excluding 0 and the end-of-string (so end-of-string isn't
 *     a trivial true-positive).
 *   - macro-averaged precision / recall / F1 across rows.
 *   - trailing CJK + ASCII pause punctuation is stripped from BOTH
 *     actual and gold chunks before scoring, so "閱讀，" ≡ "閱讀".
 *
 * If you intentionally change the corpus or the tokenizer in a way
 * that moves the score, update PARITY_F1_FLOOR + commit the corpus
 * change in the same diff.
 */

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import { tokenize } from './tokenizer';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = resolve(__dirname, '../../../Tests/Fixtures/rsvp-gold-corpus.tsv');

// Hand-set floor based on measured TS macro-F1.
//   2026-05-15 measurement: TS F1 = 0.795 (iOS baseline F1 = 0.828).
// The floor sits ~0.04 below measured to absorb Intl.Segmenter
// dictionary drift between Chrome releases without false-failing,
// while still catching real regressions of two-row scale or larger.
// Bump down only with a recorded justification; bump up freely as the
// tokenizer improves.
const PARITY_F1_FLOOR = 0.75;

// Per-row F1 below this triggers a soft-warn (logged, not failed) so the
// "worst rows" list stays visible the way the iOS tool prints it.
const PER_ROW_WARN = 0.4;

interface Row { id: string; input: string; gold: string[] }

function loadCorpus(): Row[] {
  const raw = readFileSync(CORPUS_PATH, 'utf8');
  const rows: Row[] = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const parts = trimmed.split('\t');
    if (parts.length < 3) continue;
    const [id, input, goldRaw] = parts as [string, string, string];
    const gold = goldRaw.split('|');
    rows.push({ id, input, gold });
  }
  return rows;
}

/** Punctuation set that's stripped from chunk tails before comparison.
 *  Matches Tools/FastReadTokenizerStats/main.swift `isPunctuation`. */
function isTrailPunct(ch: string): boolean {
  const v = ch.codePointAt(0);
  if (v === undefined) return false;
  if (v >= 0x3000 && v <= 0x303f) return true;
  if (v >= 0xff00 && v <= 0xffef) return true;
  return '.,!?;:'.includes(ch);
}

function stripTrailingPunct(s: string): string {
  let i = s.length;
  while (i > 0 && isTrailPunct(s[i - 1]!)) i--;
  return s.slice(0, i);
}

/** Internal boundaries = cumulative scalar offsets between consecutive
 *  chunks, excluding 0 and the total length. Scalar count == Swift's
 *  `unicodeScalars.count`; for BMP-only content (the corpus is all BMP
 *  CJK + ASCII), this equals JS string `.length`. */
function internalBoundaries(chunks: string[]): Set<number> {
  const out = new Set<number>();
  let running = 0;
  const total = chunks.reduce((acc, c) => acc + c.length, 0);
  for (let i = 0; i < chunks.length - 1; i++) {
    running += chunks[i]!.length;
    if (running > 0 && running < total) out.add(running);
  }
  return out;
}

function boundaryF1(gold: string[], actual: string[]): { p: number; r: number; f: number } {
  const g = internalBoundaries(gold);
  const a = internalBoundaries(actual);
  if (g.size === 0 && a.size === 0) return { p: 1, r: 1, f: 1 };
  let tp = 0;
  for (const x of a) if (g.has(x)) tp++;
  const p = a.size === 0 ? 0 : tp / a.size;
  const r = g.size === 0 ? 0 : tp / g.size;
  const f = p + r === 0 ? 0 : (2 * p * r) / (p + r);
  return { p, r, f };
}

describe('gold-corpus parity (vs Tests/Fixtures/rsvp-gold-corpus.tsv)', () => {
  const rows = loadCorpus();

  it('corpus loaded with at least 40 rows', () => {
    expect(rows.length).toBeGreaterThan(40);
  });

  it('macro-F1 stays above the parity floor', () => {
    let sumP = 0, sumR = 0, sumF = 0;
    const perRow: Array<{ id: string; input: string; gold: string[]; actual: string[]; f: number }> = [];
    for (const row of rows) {
      const actual = tokenize(row.input).map(stripTrailingPunct);
      const gold = row.gold.map(stripTrailingPunct);
      const { p, r, f } = boundaryF1(gold, actual);
      sumP += p; sumR += r; sumF += f;
      perRow.push({ id: row.id, input: row.input, gold: row.gold, actual, f });
    }
    const n = rows.length;
    const macroP = sumP / n;
    const macroR = sumR / n;
    const macroF = sumF / n;

    // Print the same summary the Swift stats tool prints, so a CI
    // failure carries enough context to act on.
    const fmt = (x: number) => x.toFixed(3);
    const log: string[] = [];
    log.push(`parity: precision=${fmt(macroP)} recall=${fmt(macroR)} F1=${fmt(macroF)}  (floor ${PARITY_F1_FLOOR})`);
    const worst = [...perRow].sort((a, b) => a.f - b.f).slice(0, 5);
    log.push(`worst 5:`);
    for (const w of worst) {
      log.push(`  [${w.id}] F1=${w.f.toFixed(2)}  ${w.input}`);
      log.push(`    gold:   ${w.gold.join(' | ')}`);
      log.push(`    actual: ${w.actual.join(' | ')}`);
    }
    // Always-visible report via console.info — vitest pipes this to the
    // test output without needing a custom reporter.
    // eslint-disable-next-line no-console
    console.info('\n' + log.join('\n'));

    // Count of obviously-broken rows (< 0.4) shouldn't balloon either —
    // catches the case where macro-F1 looks fine but a cluster of edge
    // rows are tanked.
    const broken = perRow.filter(r => r.f < PER_ROW_WARN).length;
    expect(macroF, `macro-F1 ${fmt(macroF)} below floor ${PARITY_F1_FLOOR}`).toBeGreaterThanOrEqual(PARITY_F1_FLOOR);
    expect(broken, `${broken} rows scored below ${PER_ROW_WARN} — see worst-5 log above`).toBeLessThan(Math.ceil(rows.length * 0.3));
  });
});
