/**
 * RSVP tokenizer ported from Sources/FastReadCore/RSVPEngine.swift +
 * Sources/FastReadCore/ChunkShaper.swift. Behaviour and constants must
 * stay in lockstep with the iOS/Android core — see ParityTests.swift /
 * RSVPEngineParityTest.kt for the gold corpus that locks the shape of
 * the output. When you change a constant here, update the iOS+Android
 * versions in the same commit.
 */

import { shape } from './chunkShaper';

/** Bump when the tokenizer or shaper produces a materially different
 * chunking for the same input. Persisted token state with a different
 * version is discarded and recomputed. */
export const TOKENIZER_VERSION = 1;

const NBSP = ' ';

/* ---------- character-class helpers (parity with Swift) ---------- */

const focusableRegex = /[\p{L}\p{N}]/u;

export function isFocusable(ch: string): boolean {
  return focusableRegex.test(ch);
}

export function isHan(ch: string): boolean {
  const v = ch.codePointAt(0);
  if (v === undefined) return false;
  return (
    (v >= 0x3400 && v <= 0x4dbf) || // CJK Ext A
    (v >= 0x4e00 && v <= 0x9fff) || // CJK Unified
    (v >= 0xf900 && v <= 0xfaff)    // CJK Compat
  );
}

export function isCJKChar(ch: string): boolean {
  const v = ch.codePointAt(0);
  if (v === undefined) return false;
  return (
    (v >= 0x3040 && v <= 0x30ff) || // Hiragana/Katakana
    (v >= 0x3400 && v <= 0x4dbf) ||
    (v >= 0x4e00 && v <= 0x9fff) ||
    (v >= 0xf900 && v <= 0xfaff) ||
    (v >= 0xac00 && v <= 0xd7af)    // Hangul
  );
}

export function isCJKPunctuation(ch: string): boolean {
  const v = ch.codePointAt(0);
  if (v === undefined) return false;
  return (v >= 0x3000 && v <= 0x303f) || (v >= 0xff00 && v <= 0xffef);
}

const ASCII_PAUSE = new Set(['.', ',', '!', '?', ';', ':']);
export function isASCIIPunctuationPause(ch: string): boolean {
  return ASCII_PAUSE.has(ch);
}

export function containsCJK(s: string | null | undefined): boolean {
  if (!s) return false;
  for (const ch of s) if (isCJKChar(ch)) return true;
  return false;
}

/* ---------- main entry point ---------- */

export function tokenize(input: string | null | undefined, userDictionary: string[] = []): string[] {
  if (!input) return [];
  const normalized = input.replaceAll(NBSP, ' ');
  if (!containsCJK(normalized)) {
    return normalized.split(/\s+/).filter(Boolean);
  }
  return tokenizeMixed(normalized, userDictionary);
}

function tokenizeMixed(input: string, userDictionary: string[]): string[] {
  const out: string[] = [];
  for (const seg of splitByScript(input)) {
    if (seg.cjk) {
      out.push(...tokenizeCJKSegment(seg.text, userDictionary));
    } else {
      out.push(...seg.text.split(/\s+/).filter(Boolean));
    }
  }
  return shape(out);
}

interface ScriptSegment { text: string; cjk: boolean }

function splitByScript(input: string): ScriptSegment[] {
  const segs: ScriptSegment[] = [];
  let buf = '';
  let bufIsCJK: boolean | null = null;
  for (const ch of input) {
    const cjk = isCJKChar(ch) || isCJKPunctuation(ch);
    if (bufIsCJK !== null && bufIsCJK !== cjk) {
      segs.push({ text: buf, cjk: bufIsCJK });
      buf = '';
    }
    buf += ch;
    bufIsCJK = cjk;
  }
  if (bufIsCJK !== null && buf.length) segs.push({ text: buf, cjk: bufIsCJK });
  return segs;
}

interface Span { text: string; lo: number; hi: number }

// Lazily build the Segmenter — it's a relatively heavy object and we
// only need it on pages that actually contain CJK content.
let segmenter: Intl.Segmenter | null = null;
function getSegmenter(): Intl.Segmenter {
  if (segmenter) return segmenter;
  segmenter = new Intl.Segmenter('zh-Hant', { granularity: 'word' });
  return segmenter;
}

function tokenizeCJKSegment(text: string, userDictionary: string[]): string[] {
  const seg = getSegmenter();
  const raw: Span[] = [];
  for (const part of seg.segment(text)) {
    if (!part.segment) continue;
    // Mirror NLTokenizer(unit: .word): keep word-like spans (any
    // letter/number); drop pure-punct/whitespace spans (we handle
    // punctuation separately in the interstitial pass).
    if (!hasAnyFocusable(part.segment)) continue;
    raw.push({ text: part.segment, lo: part.index, hi: part.index + part.segment.length });
  }
  const merged = applyUserDictionary(raw, text, userDictionary);

  const tokens: string[] = [];
  let leadingPunct = '';
  let lastEnd = 0;
  for (const span of merged) {
    if (lastEnd < span.lo) {
      const gap = text.slice(lastEnd, span.lo);
      for (const ch of gap) {
        if (!(isCJKPunctuation(ch) || isASCIIPunctuationPause(ch))) continue;
        if (tokens.length === 0) leadingPunct += ch;
        else tokens[tokens.length - 1] += ch;
      }
    }
    if (tokens.length === 0 && leadingPunct.length) {
      tokens.push(leadingPunct + span.text);
      leadingPunct = '';
    } else {
      tokens.push(span.text);
    }
    lastEnd = span.hi;
  }
  if (lastEnd < text.length) {
    for (const ch of text.slice(lastEnd)) {
      if (!(isCJKPunctuation(ch) || isASCIIPunctuationPause(ch))) continue;
      if (tokens.length) tokens[tokens.length - 1] += ch;
    }
  }
  return tokens;
}

function hasAnyFocusable(s: string): boolean {
  for (const ch of s) if (isFocusable(ch)) return true;
  return false;
}

function applyUserDictionary(raw: Span[], source: string, dictionary: string[]): Span[] {
  const entries = new Set(dictionary.filter(s => s.length > 0));
  if (entries.size === 0 || raw.length === 0) return raw;
  let maxLen = 0;
  for (const e of entries) if ([...e].length > maxLen) maxLen = [...e].length;
  if (maxLen === 0) return raw;

  const out: Span[] = [];
  let i = 0;
  while (i < raw.length) {
    let bestEnd: number | null = null;
    let concat = '';
    let probe = i;
    while (probe < raw.length) {
      concat += raw[probe]!.text;
      if ([...concat].length > maxLen) break;
      if (entries.has(concat)) bestEnd = probe;
      probe++;
    }
    if (bestEnd !== null) {
      const lo = raw[i]!.lo;
      const hi = raw[bestEnd]!.hi;
      out.push({ text: source.slice(lo, hi), lo, hi });
      i = bestEnd + 1;
    } else {
      out.push(raw[i]!);
      i++;
    }
  }
  return out;
}

/* ---------- focus index (ORP) ---------- */

export function focusIndex(token: string | null | undefined): number {
  const chars = [...(token ?? '')];
  if (chars.length === 0) return 0;
  const focusable: number[] = [];
  for (let i = 0; i < chars.length; i++) if (isFocusable(chars[i]!)) focusable.push(i);
  if (focusable.length === 0) return Math.floor(chars.length / 2);
  let target: number;
  const n = focusable.length;
  if (n <= 1) target = 0;
  else if (n <= 5) target = 1;
  else if (n <= 9) target = 2;
  else if (n <= 13) target = 3;
  else target = 4;
  return focusable[Math.min(target, focusable.length - 1)]!;
}

export interface FocusSplit { before: string; focus: string; after: string }

export function splitForFocus(token: string | null | undefined): FocusSplit {
  const chars = [...(token ?? '')];
  if (chars.length === 0) return { before: '', focus: '', after: '' };
  const i = focusIndex(token);
  return {
    before: chars.slice(0, i).join(''),
    focus: chars[i]!,
    after: chars.slice(i + 1).join(''),
  };
}

/* ---------- per-token duration (matches iOS) ---------- */

const TRAILING_CLOSERS = new Set(['"', "'", ')', ']']);
const ENGLISH_PAUSE = new Set(['.', '!', '?', ';', ':', ')']);

export function endsWithPunctuationPause(token: string): boolean {
  if (containsCJK(token)) {
    const last = [...token].at(-1);
    if (!last) return false;
    return isCJKPunctuation(last) || isASCIIPunctuationPause(last);
  }
  const chars = [...token];
  for (let i = chars.length - 1; i >= 0; i--) {
    const c = chars[i]!;
    if (ENGLISH_PAUSE.has(c)) {
      for (let j = i + 1; j < chars.length; j++) {
        if (!TRAILING_CLOSERS.has(chars[j]!)) return false;
      }
      return true;
    }
    if (!TRAILING_CLOSERS.has(c)) return false;
  }
  return false;
}

function safeWPM(wpm: number): number {
  const raw = Number.isFinite(wpm) && wpm !== 0 ? wpm : 450;
  return Math.min(1200, Math.max(100, raw));
}

export function durationMs(token: string, wpm: number, punctuationPause = true): number {
  const safe = safeWPM(wpm);
  const base = 60_000 / safe;
  const chars = [...token];
  const cjk = containsCJK(token);
  const focusableCount = chars.filter(c => isFocusable(c) || isCJKChar(c)).length;
  const cjkMultiplier = cjk ? 1.5 : 1;
  const lengthMultiplier = focusableCount > 9
    ? 1 + Math.min((focusableCount - 9) * 0.07, 0.6)
    : 1;
  const pauseMultiplier = punctuationPause && endsWithPunctuationPause(token) ? 1.65 : 1;
  return Math.round(base * cjkMultiplier * lengthMultiplier * pauseMultiplier);
}

export function countReadingUnits(input: string | null | undefined): number {
  return tokenize(input).filter(t => {
    for (const ch of t) if (isFocusable(ch) || isCJKChar(ch)) return true;
    return false;
  }).length;
}

export function estimateMinutes(wordCount: number, wpm: number): number {
  return wordCount / safeWPM(wpm);
}
