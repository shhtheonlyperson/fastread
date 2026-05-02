import test from "node:test";
import assert from "node:assert/strict";

import {
  durationForToken,
  estimateMinutes,
  getFocusIndex,
  getProgress,
  splitForFocus,
  tokenize,
} from "../src/reader-core.js";

test("tokenize normalizes whitespace and preserves word punctuation", () => {
  assert.deepEqual(tokenize("  Read\tfast.\nNow  "), ["Read", "fast.", "Now"]);
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
});

test("durationForToken respects WPM, punctuation pauses, and long words", () => {
  const base = durationForToken("read", 600, false);
  assert.equal(base, 100);
  assert.ok(durationForToken("read.", 600, true) > base);
  assert.ok(durationForToken("internationalization", 600, false) > base);
});

test("progress and ETA helpers handle empty and non-empty input", () => {
  assert.equal(getProgress(0, 0), 0);
  assert.equal(getProgress(4, 10), 50);
  assert.equal(estimateMinutes(900, 900), 1);
});
