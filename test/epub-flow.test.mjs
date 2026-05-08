import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { importDocument } from "../src/importers/index.js";
import { flattenText } from "../src/document.js";
import { tokenize, estimateMinutes } from "../src/reader-core.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(here, "fixtures", "epub");

function loadFixture(name) {
  const buf = readFileSync(join(fixturesDir, name));
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
}

// Mirrors the library-item construction in components/fast-read-screen.jsx addArticle()
// for the EPUB import path: starts from an ArrayBuffer, runs through importDocument,
// asserts the resulting library item has tokens > 0.
function buildLibraryItemFromEpub(buf, fallbackTitle = "EPUB") {
  const document = importDocument({ kind: "epub", input: buf });
  const flatText = flattenText(document);
  const tokens = tokenize(flatText);
  const now = new Date().toISOString();
  return {
    id: `article-${Date.now()}`,
    title: document.title || fallbackTitle,
    source: document.author || "EPUB",
    sourceURL: null,
    author: "You",
    date: now,
    createdAt: now,
    lastOpenedAt: now,
    finishedAt: null,
    readTime: `${Math.max(1, Math.ceil(estimateMinutes(tokens.length, 450)))} min`,
    progress: 0,
    lede: flatText.slice(0, 80),
    tagKey: "readingNow",
    text: flatText,
    document,
    timesOpened: 1,
  };
}

test("epub-flow: Pride and Prejudice fixture yields library item with tokens > 0", () => {
  const buf = loadFixture("pride-and-prejudice.epub");
  const item = buildLibraryItemFromEpub(buf, "pride.epub");
  assert.equal(item.title, "Pride and Prejudice");
  assert.equal(item.document.sourceKind, "epub");
  assert.equal(item.document.sections.length, 2);
  assert.ok(tokenize(item.text).length > 0, "expected library item text to tokenize");
  assert.ok(item.text.includes("universally acknowledged"), "expected chapter text in flattened library item");
});

test("epub-flow: 道德經 fixture yields library item with tokens > 0", () => {
  const buf = loadFixture("tao-te-ching.epub");
  const item = buildLibraryItemFromEpub(buf, "tao.epub");
  assert.equal(item.title, "道德經");
  assert.equal(item.document.sections.length, 3);
  assert.ok(tokenize(item.text).length > 0, "expected library item text to tokenize");
});

test("epub-flow: non-EPUB ArrayBuffer surfaces a typed error", () => {
  const garbage = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
  assert.throws(() => importDocument({ kind: "epub", input: garbage }));
});
