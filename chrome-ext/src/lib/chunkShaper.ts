/**
 * Ported from Sources/FastReadCore/ChunkShaper.swift. Read the Swift
 * file's leading comment for the design rationale — every rule here
 * exists because the gold corpus at Tests/Fixtures/rsvp-gold-corpus.tsv
 * scored worse without it. Constants must stay in lockstep with iOS +
 * Android. See ParityTests.swift / RSVPEngineParityTest.kt.
 */

import { isHan, isCJKChar, isCJKPunctuation } from './tokenizer';

/* ---------- helpers ---------- */

function cjkCount(chunk: string): number {
  let n = 0;
  for (const ch of chunk) if (isHan(ch)) n++;
  return n;
}

function isHanCharacter(ch: string): boolean {
  // ChunkShaper's Han check is stricter than tokenizer's CJK (excludes
  // Hiragana/Katakana/Hangul on purpose — those don't follow the Chinese
  // rhythm rules below).
  return isHan(ch);
}

function isPureSingleHan(chunk: string): boolean {
  const chars = [...chunk];
  return chars.length === 1 && isHanCharacter(chars[0]!);
}

function isDigitRun(s: string): boolean {
  if (!s) return false;
  for (const c of s) {
    const code = c.charCodeAt(0);
    if (code > 127) return false;
    if ((code >= 48 && code <= 57) || c === '.' || c === ',') continue;
    return false;
  }
  return true;
}

/* ---------- constants ---------- */

const prepositionsForCompound = new Set(['在', '從', '到', '向', '於']);

const measureWords = new Set([
  '個', '位', '件', '種', '名', '次', '回', '張', '把', '條', '場', '份',
  '年', '月', '日', '時', '分', '秒', '週', '季', '點', '天',
  '小時', '分鐘', '秒鐘',
  '公斤', '公克', '公尺', '公里', '公分', '公升',
  '元', '塊', '毛', '億', '萬',
  '度',
  '個月', '個人', '歲',
]);

const particlesBackward = new Set([
  '了', '著', '過',
  '之', '矣', '哉', '焉', '乎', '而',
  '嗎', '呢', '吧', '啊', '喔', '耶', '呀', '嘛', '呵',
]);

const particlesForward = new Set([
  '在', '從', '對', '向', '把', '被', '給',
  '及', '或',
  '是', '為',
  '也', '又', '都', '還', '才', '就', '便',
  '很', '更', '最', '太',
  '不', '沒', '未', '別',
  '新', '舊',
]);

const POSSESSIVE_DE = '的';
const MAX_MERGED_CJK = 4;

const pronouns = new Set(['我', '你', '他', '她', '它', '您', '咱', '妳']);

const peelForwardVerbs = new Set([
  '去', '來', '回', '走', '上', '下', '進', '出',
  '看', '說', '講', '做', '想', '聽', '讀', '寫',
  '吃', '喝', '買', '賣', '找',
]);

const hardClauseEndings = new Set([
  '。', '，', '！', '？', '；', '：',
  '」', '』', '）', '》', '〉',
  '.', ',', '!', '?', ';', ':',
]);

function endsInHardPunct(chunk: string): boolean {
  const last = [...chunk].at(-1);
  return !!last && hardClauseEndings.has(last);
}

function isAnyParticle(chunk: string): boolean {
  const chars = [...chunk];
  if (chars.length !== 1) return false;
  const c = chars[0]!;
  return c === POSSESSIVE_DE || particlesForward.has(c) || particlesBackward.has(c);
}

function singleCJKParticle(chunk: string): string | null {
  let han = '';
  for (const ch of chunk) if (isHanCharacter(ch)) han += ch;
  const chars = [...han];
  return chars.length === 1 ? chars[0]! : null;
}

/* ---------- pipeline ---------- */

export function shape(tokens: string[]): string[] {
  let result = mergeCrossScriptUnits(tokens);
  result = mergePrepDigitNoun(result);
  result = coalesceSingleCharRuns(result);
  result = glueFunctionParticles(result);
  result = absorbStraySingletons(result);
  return result;
}

/* Pass 1a — preposition + digit + multi-Han noun */

function mergePrepDigitNoun(tokens: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < tokens.length) {
    const cur = tokens[i]!;
    if (
      [...cur].length === 1 &&
      prepositionsForCompound.has(cur) &&
      i + 2 < tokens.length &&
      isDigitRun(tokens[i + 1]!) &&
      cjkCount(tokens[i + 2]!) >= 2
    ) {
      out.push(cur + tokens[i + 1] + tokens[i + 2]);
      i += 3;
      continue;
    }
    out.push(cur);
    i++;
  }
  return out;
}

/* Pass 1 — number + measure word */

function mergeCrossScriptUnits(tokens: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < tokens.length) {
    const cur = tokens[i]!;
    if (isDigitRun(cur) && i + 1 < tokens.length && measureWords.has(tokens[i + 1]!)) {
      out.push(cur + tokens[i + 1]);
      i += 2;
      continue;
    }
    out.push(cur);
    i++;
  }
  return out;
}

/* Pass 2 — particle gluing */

function glueFunctionParticles(tokens: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < tokens.length) {
    const cur = tokens[i]!;
    const particle = singleCJKParticle(cur);
    if (particle) {
      const leftLen = out.length ? cjkCount(out[out.length - 1]!) : 0;
      const rightLen = i + 1 < tokens.length ? cjkCount(tokens[i + 1]!) : 0;

      if (particle === POSSESSIVE_DE) {
        const preferBackward = leftLen <= rightLen && leftLen >= 1;
        if (preferBackward && leftLen + 1 <= MAX_MERGED_CJK) {
          out[out.length - 1] = out[out.length - 1] + cur;
          i++;
          continue;
        }
        if (rightLen >= 1 && rightLen + 1 <= MAX_MERGED_CJK) {
          out.push(cur + tokens[i + 1]);
          i += 2;
          continue;
        }
        if (leftLen >= 1 && leftLen + 1 <= MAX_MERGED_CJK) {
          out[out.length - 1] = out[out.length - 1] + cur;
          i++;
          continue;
        }
        out.push(cur);
        i++;
        continue;
      }

      if (particlesBackward.has(particle) && leftLen >= 1 && leftLen + 1 <= MAX_MERGED_CJK) {
        out[out.length - 1] = out[out.length - 1] + cur;
        i++;
        continue;
      }
      if (particlesForward.has(particle) && rightLen >= 2 && rightLen + 1 <= MAX_MERGED_CJK) {
        out.push(cur + tokens[i + 1]);
        i += 2;
        continue;
      }
    }
    out.push(cur);
    i++;
  }
  return out;
}

/* Pass 3 — coalesce runs of single Han chunks */

function coalesceSingleCharRuns(tokens: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < tokens.length) {
    let j = i;
    while (j < tokens.length && isPureSingleHan(tokens[j]!) && !isAnyParticle(tokens[j]!)) j++;
    const runLen = j - i;

    if (runLen >= 3) {
      const nextHasRoom = j < tokens.length
        && cjkCount(tokens[j]!) > 0
        && cjkCount(tokens[j]!) <= 2;
      let runHasPronoun = false;
      for (let k = i; k < j; k++) {
        const first = [...tokens[k]!][0];
        if (first && pronouns.has(first)) { runHasPronoun = true; break; }
      }

      if (runLen === 3 && runHasPronoun && nextHasRoom) {
        out.push(tokens.slice(i, i + 2).join(''));
        out.push(tokens[i + 2]! + tokens[j]!);
        i = j + 1;
        continue;
      }
      if (runLen === 4 && nextHasRoom) {
        const fourthChar = [...tokens[i + 3]!][0];
        const peel = runHasPronoun || (!!fourthChar && peelForwardVerbs.has(fourthChar));
        if (peel) {
          out.push(tokens.slice(i, i + 3).join(''));
          out.push(tokens[i + 3]! + tokens[j]!);
          i = j + 1;
          continue;
        }
      }
      if (runLen === 5 && nextHasRoom && cjkCount(tokens[j]!) === 1) {
        out.push(tokens.slice(i, i + 3).join(''));
        out.push(tokens[i + 3]! + tokens[i + 4]! + tokens[j]!);
        i = j + 1;
        continue;
      }

      let offset = i;
      for (const size of groupSizes(runLen)) {
        out.push(tokens.slice(offset, offset + size).join(''));
        offset += size;
      }
      i = j;
    } else if (runLen === 2) {
      const nextNotMultiCJK = j >= tokens.length || cjkCount(tokens[j]!) < 2;
      const first0 = [...tokens[i]!][0];
      const first1 = [...tokens[i + 1]!][0];
      const neitherIsPronoun =
        !(first0 && pronouns.has(first0)) && !(first1 && pronouns.has(first1));
      if (nextNotMultiCJK || neitherIsPronoun) {
        out.push(tokens.slice(i, j).join(''));
        i = j;
      } else {
        out.push(tokens[i]!);
        i++;
      }
    } else {
      out.push(tokens[i]!);
      i++;
    }
  }
  return out;
}

/* Pass 4 — absorb stray single-Han chunks */

function absorbStraySingletons(tokens: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < tokens.length) {
    const cur = tokens[i]!;
    const chars = [...cur];
    const isStray = chars.length === 1 && isHanCharacter(chars[0]!);
    if (!isStray) { out.push(cur); i++; continue; }

    const last = out[out.length - 1];
    if (last && cjkCount(last) >= 2 && cjkCount(last) + 1 <= 3 && !endsInHardPunct(last)) {
      out[out.length - 1] = last + cur;
      i++;
      continue;
    }
    const next = tokens[i + 1];
    if (next && cjkCount(next) >= 2 && cjkCount(next) + 1 <= 4) {
      out.push(cur + next);
      i += 2;
      continue;
    }
    out.push(cur);
    i++;
  }
  return out;
}

/* ---------- group-size rhythm rulebook ---------- */

export function groupSizes(n: number): number[] {
  switch (n) {
    case 0: return [];
    case 1: return [1];
    case 2: return [1, 1];
    case 3: return [3];
    case 4: return [2, 2];
    case 5: return [2, 3];
    case 6: return [3, 3];
    case 7: return [3, 2, 2];
    case 8: return [3, 3, 2];
    case 9: return [3, 3, 3];
    default: {
      const sizes: number[] = [];
      let remaining = n;
      while (remaining > 4) {
        sizes.push(3);
        remaining -= 3;
      }
      return [...sizes, ...groupSizes(remaining)];
    }
  }
}

/* Suppress unused warnings — kept exports/imports for parity with Swift */
void isCJKChar; void isCJKPunctuation;
