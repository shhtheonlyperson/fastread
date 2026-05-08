import test from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, extname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";

import { extractArticle, normalizeText } from "../src/article-extract.js";
import { countReadingUnits } from "../src/reader-core.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = join(__dirname, "fixtures", "articles");

function loadFixtures() {
  const entries = readdirSync(FIXTURES_DIR);
  const inputs = entries.filter((name) => /\.(html|txt)$/i.test(name)).sort();
  return inputs.map((name) => {
    const ext = extname(name).toLowerCase();
    const stem = basename(name, ext);
    const expectedPath = join(FIXTURES_DIR, `${stem}.expected.json`);
    return {
      name,
      stem,
      ext,
      inputPath: join(FIXTURES_DIR, name),
      expectedPath,
    };
  });
}

function computeActual(fixture) {
  const raw = readFileSync(fixture.inputPath, "utf8");
  if (fixture.ext === ".txt") {
    const text = normalizeText(raw);
    return {
      title: "",
      source: "plaintext",
      wordCount: countReadingUnits(text),
      head: text.slice(0, 200),
      tail: text.slice(Math.max(0, text.length - 200)),
    };
  }
  const result = extractArticle(raw);
  return {
    title: result.title,
    source: result.source,
    wordCount: result.wordCount,
    head: result.text.slice(0, 200),
    tail: result.text.slice(Math.max(0, result.text.length - 200)),
  };
}

const fixtures = loadFixtures();

assert.ok(fixtures.length >= 6, `expected at least 6 fixtures, found ${fixtures.length}`);

for (const fixture of fixtures) {
  test(`golden: ${fixture.name}`, () => {
    const expectedRaw = readFileSync(fixture.expectedPath, "utf8");
    const expected = JSON.parse(expectedRaw);
    const actual = computeActual(fixture);
    try {
      assert.deepStrictEqual(actual, expected);
    } catch (err) {
      const diff = {
        fixture: fixture.name,
        expected,
        actual,
      };
      err.message = `Golden fixture diverged: ${fixture.name}\n${JSON.stringify(diff, null, 2)}\n${err.message}`;
      throw err;
    }
  });
}
