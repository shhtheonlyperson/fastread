const FOCUS_RE = /[\p{L}\p{N}]/u;

export const DEFAULT_TEXT = `Paste an article, memo, or transcript here. FastRead will turn it into one focused word at a time, with the red letter held at the same visual anchor so your eyes move less.`;

export function tokenize(input) {
  if (typeof input !== "string") {
    return [];
  }

  return input
    .replace(/\u00a0/g, " ")
    .match(/\S+/gu) || [];
}

export function getFocusIndex(token) {
  const chars = Array.from(token || "");
  if (chars.length === 0) {
    return 0;
  }

  const focusable = [];
  chars.forEach((char, index) => {
    if (FOCUS_RE.test(char)) {
      focusable.push(index);
    }
  });

  if (focusable.length === 0) {
    return Math.floor(chars.length / 2);
  }

  const letterCount = focusable.length;
  let target = 0;

  if (letterCount <= 1) {
    target = 0;
  } else if (letterCount <= 5) {
    target = 1;
  } else if (letterCount <= 9) {
    target = 2;
  } else if (letterCount <= 13) {
    target = 3;
  } else {
    target = 4;
  }

  return focusable[Math.min(target, focusable.length - 1)];
}

export function splitForFocus(token) {
  const chars = Array.from(token || "");
  if (chars.length === 0) {
    return { before: "", focus: "", after: "" };
  }

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
  const focusableCount = Array.from(token || "").filter((char) => FOCUS_RE.test(char)).length;
  const lengthMultiplier = focusableCount > 9 ? 1 + Math.min((focusableCount - 9) * 0.07, 0.6) : 1;
  const pauseMultiplier = punctuationPause && /[.!?;:)]["')\]]*$/u.test(token || "") ? 1.65 : 1;

  return Math.round(base * lengthMultiplier * pauseMultiplier);
}

export function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

export function getProgress(index, total) {
  if (!total) {
    return 0;
  }

  return Math.round(((index + 1) / total) * 100);
}

export function estimateMinutes(wordCount, wpm) {
  const safeWpm = clamp(Number(wpm) || 450, 100, 1200);
  return wordCount / safeWpm;
}
