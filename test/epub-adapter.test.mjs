import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { importDocument, getAdapter } from "../src/importers/index.js";
import { EpubAdapter } from "../src/importers/epub-adapter.js";
import { flattenText, tokenizeDocument } from "../src/document.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(here, "fixtures", "epub");

function loadFixture(name) {
  const buf = readFileSync(join(fixturesDir, name));
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
}

test("EpubAdapter is registered under kind 'epub'", () => {
  assert.equal(getAdapter("epub"), EpubAdapter);
});

test("EpubAdapter.canHandle: zip magic + .epub filename", () => {
  const buf = loadFixture("pride-and-prejudice.epub");
  assert.equal(EpubAdapter.canHandle(buf), true);
  // ArrayBuffer copy whose offset 0 starts at the zip magic.
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  assert.equal(EpubAdapter.canHandle(ab), true);
  assert.equal(EpubAdapter.canHandle("book.epub"), true);
  assert.equal(EpubAdapter.canHandle("book.txt"), false);
  assert.equal(EpubAdapter.canHandle(new Uint8Array([1, 2, 3, 4])), false);
});

test("importDocument({kind:'epub'}): Pride and Prejudice", () => {
  const buf = loadFixture("pride-and-prejudice.epub");
  const doc = importDocument({ kind: "epub", input: buf });
  assert.equal(doc.title, "Pride and Prejudice");
  assert.equal(doc.author, "Jane Austen");
  assert.equal(doc.sourceKind, "epub");
  assert.equal(doc.sections.length, 2);
  assert.equal(doc.sections[0].kind, "chapter");
  assert.equal(doc.sections[0].id, "ch1");
  assert.equal(doc.sections[0].title, "Chapter 1");
  assert.equal(doc.sections[1].title, "Chapter 2");

  const flat = flattenText(doc);
  assert.ok(
    flat.includes(
      "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
    ),
    "expected Chapter 1 sentence in flattened text",
  );

  const baseline = 44;
  const tokens = tokenizeDocument(doc).length;
  const drift = Math.abs(tokens - baseline) / baseline;
  assert.ok(
    drift <= 0.02,
    `tokens (${tokens}) drifted >2% from baseline (${baseline})`,
  );
});

test("importDocument({kind:'epub'}): 道德經 (zh-Hant, NCX)", () => {
  const buf = loadFixture("tao-te-ching.epub");
  const doc = importDocument({ kind: "epub", input: buf });
  assert.equal(doc.title, "道德經");
  assert.equal(doc.author, "老子");
  assert.equal(doc.sourceKind, "epub");
  assert.equal(doc.sections.length, 3);
  assert.equal(doc.sections[0].title, "第一章");
  assert.equal(doc.sections[1].title, "第二章");
  assert.equal(doc.sections[2].title, "第三章");

  const flat = flattenText(doc);
  assert.ok(
    flat.includes("道可道，非常道。名可名，非常名。"),
    "expected Chapter 1 sentence in flattened text",
  );

  const baseline = 41;
  const tokens = tokenizeDocument(doc).length;
  const drift = Math.abs(tokens - baseline) / baseline;
  assert.ok(
    drift <= 0.02,
    `tokens (${tokens}) drifted >2% from baseline (${baseline})`,
  );
});
