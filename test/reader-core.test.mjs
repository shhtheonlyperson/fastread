import test from "node:test";
import assert from "node:assert/strict";

import {
  countReadingUnits,
  durationForToken,
  estimateMinutes,
  getFocusIndex,
  getProgress,
  joinTokensForDisplay,
  splitForFocus,
  tokenize,
} from "../src/reader-core.js";

test("tokenize normalizes whitespace and preserves word punctuation", () => {
  assert.deepEqual(tokenize("  Read\tfast.\nNow  "), ["Read", "fast.", "Now"]);
});

test("tokenize splits Traditional Chinese into two-character chunks", () => {
  assert.deepEqual(tokenize("快速閱讀，眼睛更輕鬆。"), ["快速", "閱讀，", "眼睛", "更輕", "鬆。"]);
});

test("tokenize splits Simplified Chinese into two-character chunks", () => {
  assert.deepEqual(tokenize("快速阅读让注意力更稳定。"), ["快速", "阅读", "让注", "意力", "更稳", "定。"]);
});

test("joinTokensForDisplay preserves Chinese spacing while keeping mixed-language gaps", () => {
  assert.equal(joinTokensForDisplay(tokenize("FastRead 支援中文。")), "FastRead 支援中文。");
  assert.equal(joinTokensForDisplay(tokenize("FastRead，真的可以。")), "FastRead，真的可以。");
});

test("getFocusIndex places the focus letter near the optimal recognition point", () => {
  assert.equal(getFocusIndex("a"), 0);
  assert.equal(getFocusIndex("read"), 1);
  assert.equal(getFocusIndex("focused"), 2);
  assert.equal(getFocusIndex("recognition"), 3);
});

test("getFocusIndex ignores leading punctuation when picking the focus letter", () => {
  assert.equal(getFocusIndex('"read'), 2);
  assert.deepEqual(splitForFocus('"read'), { before: '"r', focus: "e", after: "ad" });
  assert.deepEqual(splitForFocus("讀。"), { before: "", focus: "讀", after: "。" });
});

test("durationForToken respects WPM, punctuation pauses, and long words", () => {
  const base = durationForToken("read", 600, false);
  assert.equal(base, 100);
  assert.ok(durationForToken("read.", 600, true) > base);
  assert.equal(durationForToken("閱讀", 600, false), 150);
  assert.ok(durationForToken("讀。", 600, true) > durationForToken("閱讀", 600, false));
  assert.ok(durationForToken("internationalization", 600, false) > base);
});

test("progress and ETA helpers handle empty and non-empty input", () => {
  assert.equal(getProgress(0, 0), 0);
  assert.equal(getProgress(4, 10), 50);
  assert.equal(estimateMinutes(900, 900), 1);
  assert.equal(countReadingUnits("快速閱讀"), 2);
});
