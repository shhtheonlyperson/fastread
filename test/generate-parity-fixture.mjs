#!/usr/bin/env node
// Regenerates Tests/Fixtures/parity-corpus.json from reader-core.js (JS is source of truth).
// Run: node test/generate-parity-fixture.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tokenize, splitForFocus, durationForToken } from "../src/reader-core.js";

const here = dirname(fileURLToPath(import.meta.url));
const outPath = join(here, "..", "Tests", "Fixtures", "parity-corpus.json");

const inputs = [
  { id: "ascii-simple", description: "Plain ASCII sentence", input: "Read fast and stay focused." },
  { id: "cjk-zh-hant", description: "Traditional Chinese with full-width punctuation", input: "快速閱讀，眼睛更輕鬆。" },
  { id: "cjk-mixed-latin", description: "CJK mixed with latin", input: "JustRead 支援中文。" },
  { id: "punctuation-runs", description: "Runs of ASCII punctuation", input: "Wait... really?! Yes; absolutely: done." },
  { id: "hyphens", description: "Hyphenated tokens", input: "state-of-the-art well-known co-author" },
  { id: "em-dash", description: "Em-dash and en-dash separators", input: "Reading—fast—is fun – really." },
  { id: "nbsp", description: "Non-breaking space normalized to space", input: "Read fast now" },
  { id: "very-long-token", description: "Very long single token", input: "supercalifragilisticexpialidocious" },
  { id: "single-token", description: "One short word", input: "Hi" },
  { id: "empty", description: "Empty string", input: "" },
  { id: "whitespace-only", description: "Whitespace-only string", input: "   \t\n  " },
  { id: "rtl-arabic", description: "Arabic RTL text", input: "اقرأ بسرعة وركز." },
  { id: "cjk-japanese", description: "Japanese hiragana and kanji", input: "速読で集中力が上がる。" },
  { id: "trailing-quote", description: "Token ending with punctuation followed by closing quote", input: 'He said "done."' },
];

const corpus = inputs.map((entry) => {
  const tokens = tokenize(entry.input);
  const focusSplits = tokens.map((token) => {
    const { before, focus, after } = splitForFocus(token);
    return { before, focus, after };
  });
  const durations = tokens.map((token) => durationForToken(token, 450, true));
  return {
    id: entry.id,
    description: entry.description,
    input: entry.input,
    tokens,
    focusSplits,
    durations,
    wpm: 450,
    punctuationPause: true,
  };
});

const payload = {
  generatedBy: "test/generate-parity-fixture.mjs",
  source: "src/reader-core.js",
  wpm: 450,
  punctuationPause: true,
  entries: corpus,
};

writeFileSync(outPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
console.log(`Wrote ${corpus.length} parity entries to ${outPath}`);
