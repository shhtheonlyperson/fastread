import test from "node:test";
import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";

import { htmlToText } from "../src/article-extract.js";
import { contextWindow, durationForToken, tokenize } from "../src/reader-core.js";

function budget(baseMillis) {
  const multiplier = Number(process.env.FASTREAD_PERF_BUDGET_MULTIPLIER || "1");
  return baseMillis * Math.max(multiplier, 1);
}

function measure(name, baseBudgetMillis, operation) {
  const start = performance.now();
  const result = operation();
  const elapsed = performance.now() - start;
  const allowed = budget(baseBudgetMillis);

  assert.ok(
    elapsed <= allowed,
    `${name} took ${elapsed.toFixed(2)}ms; budget is ${allowed.toFixed(2)}ms`,
  );
  return result;
}

function makeLongArticle(wordCount) {
  return Array.from({ length: wordCount }, (_, index) => {
    if (index % 11 === 0) return "performance,";
    if (index % 11 === 5) return "reader.";
    return `word${index}`;
  }).join(" ");
}

function makeHtml(paragraphs) {
  const body = Array.from(
    { length: paragraphs },
    (_, index) => `<p>Paragraph&nbsp;${index} keeps readable content &ldquo;fast&rdquo; while page chrome stays out.</p>`,
  ).join("\n");

  return `
    <html>
      <head><style>.hidden { display: none; }</style></head>
      <body>
        <nav>Share Related Subscribe</nav>
        ${body}
        <script>window.bad = true;</script>
      </body>
    </html>`;
}

test("reader core stress paths stay within practical budgets", () => {
  const longArticle = makeLongArticle(50_000);

  const tokens = measure("tokenize 50k words", 250, () => tokenize(longArticle));
  assert.equal(tokens.length, 50_000);

  const preview = contextWindow(tokens.length, 25_000);
  assert.equal(preview.count, 55);
  assert.equal(preview.hasLeadingOverflow, true);
  assert.equal(preview.hasTrailingOverflow, true);

  measure("compute 100k bounded preview windows", 80, () => {
    let total = 0;
    for (let index = 0; index < 100_000; index += 1) {
      total += contextWindow(tokens.length, index).count;
    }
    assert.ok(total > 0);
  });

  measure("simulate 20k cached playback ticks", 80, () => {
    let totalDuration = 0;
    for (let index = 0; index < 20_000; index += 1) {
      totalDuration += durationForToken(tokens[index % tokens.length], 540);
    }
    assert.ok(totalDuration > 0);
  });

  const text = measure("extract text from large HTML", 500, () => htmlToText(makeHtml(8_000)));
  assert.match(text, /Paragraph 7999/);
  assert.doesNotMatch(text, /window.bad/);
});
