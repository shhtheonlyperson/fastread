const FOCUS_RE = /[\p{L}\p{N}]/u;
const CJK_CHAR_RE = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]/u;
const CJK_PUNCT_RE = /[\u3000-\u303f\uff00-\uffef]/u;
const CJK_JOIN_LEFT_RE = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af\u3000-\u303f\uff00-\uffef]$/u;
const CJK_JOIN_RIGHT_RE = /^[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af\u3000-\u303f\uff00-\uffef]/u;

export const DEFAULT_TEXT = "";

export function tokenize(input) {
  if (typeof input !== "string") return [];
  const normalized = input.replace(/\u00a0/g, " ");
  if (containsCjk(normalized)) return tokenizeCjk(normalized);
  return normalized.match(/\S+/gu) || [];
}

function tokenizeCjk(input) {
  const tokens = [];
  let buffer = "";
  const chars = Array.from(input);

  const flush = () => {
    if (buffer) {
      tokens.push(buffer);
      buffer = "";
    }
  };

  for (let index = 0; index < chars.length; index += 1) {
    const char = chars[index];
    if (/\s/u.test(char)) {
      flush();
      continue;
    }

    if (CJK_PUNCT_RE.test(char) || /[.,!?;:]/u.test(char)) {
      if (buffer) {
        buffer += char;
        flush();
      } else if (tokens.length) {
        tokens[tokens.length - 1] += char;
      }
      continue;
    }

    if (CJK_CHAR_RE.test(char)) {
      buffer += char;
      if (Array.from(buffer).filter((item) => CJK_CHAR_RE.test(item)).length >= 2) {
        flush();
      }
      continue;
    }

    flush();
    let word = char;
    while (
      index + 1 < chars.length &&
      !/\s/u.test(chars[index + 1]) &&
      !CJK_CHAR_RE.test(chars[index + 1]) &&
      !CJK_PUNCT_RE.test(chars[index + 1])
    ) {
      index += 1;
      word += chars[index];
    }
    tokens.push(word);
  }

  flush();
  return tokens;
}

export function countReadingUnits(input) {
  return tokenize(input).filter((token) => Array.from(token).some((char) => FOCUS_RE.test(char) || CJK_CHAR_RE.test(char))).length;
}

export function containsCjk(input) {
  return CJK_CHAR_RE.test(String(input || ""));
}

export function tokenSeparator(leftToken, rightToken) {
  if (!leftToken || !rightToken) return "";
  return CJK_JOIN_LEFT_RE.test(leftToken) && CJK_JOIN_RIGHT_RE.test(rightToken) ? "" : " ";
}

export function joinTokensForDisplay(tokens) {
  return tokens.reduce((text, token, index) => `${text}${index ? tokenSeparator(tokens[index - 1], token) : ""}${token}`, "");
}

export function getFocusIndex(token) {
  const chars = Array.from(token || "");
  if (chars.length === 0) return 0;

  const focusable = [];
  chars.forEach((char, index) => {
    if (FOCUS_RE.test(char)) focusable.push(index);
  });

  if (focusable.length === 0) return Math.floor(chars.length / 2);

  const letterCount = focusable.length;
  let target = 0;
  if (letterCount <= 1) target = 0;
  else if (letterCount <= 5) target = 1;
  else if (letterCount <= 9) target = 2;
  else if (letterCount <= 13) target = 3;
  else target = 4;

  return focusable[Math.min(target, focusable.length - 1)];
}

export function splitForFocus(token) {
  const chars = Array.from(token || "");
  if (chars.length === 0) return { before: "", focus: "", after: "" };

  const focusIndex = getFocusIndex(token);
  return {
    before: chars.slice(0, focusIndex).join(""),
    focus: chars[focusIndex] || "",
    after: chars.slice(focusIndex + 1).join(""),
  };
}

export function durationForToken(token, wpm, punctuationPause = true) {
  const safeWpm = clamp(Number(wpm) || 450, 100, 1200);
  const base = 60000 / safeWpm;
  const isCjk = containsCjk(token);
  const focusableCount = Array.from(token || "").filter((char) => FOCUS_RE.test(char) || CJK_CHAR_RE.test(char)).length;
  const cjkMultiplier = isCjk ? 1.5 : 1;
  const lengthMultiplier = focusableCount > 9 ? 1 + Math.min((focusableCount - 9) * 0.07, 0.6) : 1;
  const punctuation = isCjk ? /[\u3000-\u303f\uff00-\uffef.,!?;:]$/u : /[.!?;:)]["')\]]*$/u;
  const pauseMultiplier = punctuationPause && punctuation.test(token || "") ? 1.65 : 1;

  return Math.round(base * cjkMultiplier * lengthMultiplier * pauseMultiplier);
}

export function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

export function getProgress(index, total) {
  if (!total) return 0;
  return Math.round(((index + 1) / total) * 100);
}

export function estimateMinutes(wordCount, wpm) {
  const safeWpm = clamp(Number(wpm) || 450, 100, 1200);
  return wordCount / safeWpm;
}
