import test from "node:test";
import assert from "node:assert/strict";

import {
  countReadingUnits,
  contextWindow,
  durationForToken,
  estimateMinutes,
  getFocusIndex,
  getProgress,
  joinTokensForDisplay,
  nextArticleProgressState,
  rangeValueFromPageX,
  rangeValueFromLocation,
  shouldRestartPlayback,
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
  assert.equal(joinTokensForDisplay(tokenize("JustRead 支援中文。")), "JustRead 支援中文。");
  assert.equal(joinTokensForDisplay(tokenize("JustRead，真的可以。")), "JustRead，真的可以。");
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

test("contextWindow keeps reader previews bounded", () => {
  assert.deepEqual(contextWindow(0, 0), {
    lowerBound: 0,
    upperBound: 0,
    count: 0,
    hasLeadingOverflow: false,
    hasTrailingOverflow: false,
  });

  assert.deepEqual(contextWindow(10, 0), {
    lowerBound: 0,
    upperBound: 10,
    count: 10,
    hasLeadingOverflow: false,
    hasTrailingOverflow: false,
  });

  assert.deepEqual(contextWindow(1000, 500), {
    lowerBound: 482,
    upperBound: 537,
    count: 55,
    hasLeadingOverflow: true,
    hasTrailingOverflow: true,
  });

  assert.equal(contextWindow(50_000, 25_000).count, 55);
});

test("playback restarts when saved reader state is already at the end", () => {
  assert.equal(shouldRestartPlayback(0, 10, false), false);
  assert.equal(shouldRestartPlayback(9, 10, false), true);
  assert.equal(shouldRestartPlayback(4, 10, true), true);
  assert.equal(shouldRestartPlayback(0, 0, true), false);
});

test("range input maps finger location continuously and clamps edges", () => {
  assert.equal(rangeValueFromLocation(0, 200), 0);
  assert.equal(rangeValueFromLocation(50, 200), 0.25);
  assert.equal(rangeValueFromLocation(100, 200), 0.5);
  assert.equal(rangeValueFromLocation(240, 200), 1);
  assert.equal(rangeValueFromLocation(-20, 200), 0);
  assert.equal(rangeValueFromLocation(50, 0), 1);
});

test("range input maps absolute page location from track bounds", () => {
  assert.equal(rangeValueFromPageX(180, 100, 200), 0.4);
  assert.equal(rangeValueFromPageX(80, 100, 200), 0);
  assert.equal(rangeValueFromPageX(360, 100, 200), 1);

  const wpm425Value = (425 - 150) / 850;
  assert.ok(Math.abs(rangeValueFromPageX(100 + wpm425Value * 320, 100, 320) - wpm425Value) < 0.000001);
});

test("article progress sync is idempotent to avoid playback render loops", () => {
  const reading = { id: "a", progress: 0.5, tagKey: "readingNow", finishedAt: null };
  assert.equal(nextArticleProgressState(reading, 0.5, "2026-05-03T00:00:00.000Z"), reading);

  assert.deepEqual(nextArticleProgressState(reading, 0.75, "2026-05-03T00:00:00.000Z"), {
    id: "a",
    progress: 0.75,
    tagKey: "readingNow",
    finishedAt: null,
  });

  const finished = nextArticleProgressState(reading, 1, "2026-05-03T00:00:00.000Z");
  assert.deepEqual(finished, {
    id: "a",
    progress: 1,
    tagKey: "finished",
    finishedAt: "2026-05-03T00:00:00.000Z",
  });
  assert.equal(nextArticleProgressState(finished, 1, "2026-05-04T00:00:00.000Z"), finished);
});
