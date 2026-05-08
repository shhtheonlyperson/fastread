import test from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, extname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";

import { extractArticle, normalizeText } from "../src/article-extract.js";
import { flattenText } from "../src/document.js";
import {
  importDocument,
  PlainTextAdapter,
  HtmlAdapter,
  registerAdapter,
  getAdapter,
  UnknownImporterKind,
} from "../src/importers/index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = join(__dirname, "fixtures", "articles");

function loadHtmlFixtures() {
  return readdirSync(FIXTURES_DIR)
    .filter((name) => /\.html$/i.test(name))
    .sort()
    .map((name) => {
      const stem = basename(name, extname(name));
      return {
        name,
        stem,
        inputPath: join(FIXTURES_DIR, name),
        expectedPath: join(FIXTURES_DIR, `${stem}.expected.json`),
      };
    });
}

const htmlFixtures = loadHtmlFixtures();
assert.ok(htmlFixtures.length >= 5, `expected several html fixtures, found ${htmlFixtures.length}`);

for (const fixture of htmlFixtures) {
  test(`importers: HtmlAdapter replays golden ${fixture.name}`, () => {
    const raw = readFileSync(fixture.inputPath, "utf8");
    const expected = JSON.parse(readFileSync(fixture.expectedPath, "utf8"));
    const direct = extractArticle(raw);
    const doc = importDocument({ kind: "html", input: raw });
    const text = flattenText(doc);
    assert.equal(text, direct.text, "flattenText must equal extractArticle().text");
    assert.equal(text.slice(0, 200), expected.head);
    assert.equal(
      text.slice(Math.max(0, text.length - 200)),
      expected.tail,
    );
    assert.equal(doc.sourceKind, "html");
    assert.equal(doc.sections.length, 1);
    assert.equal(doc.sections[0].kind, "body");
    assert.equal(doc.sections[0].id, "body");
    assert.equal(doc.title, direct.title);
  });
}

test("importers: PlainTextAdapter normalizes and wraps as single body section", () => {
  const input = "  hello   world\n\nsecond  paragraph  ";
  const doc = importDocument({ kind: "text", input });
  assert.equal(doc.sourceKind, "text");
  assert.equal(doc.sections.length, 1);
  assert.equal(doc.sections[0].id, "body");
  assert.equal(doc.sections[0].kind, "body");
  assert.equal(flattenText(doc), normalizeText(input));
});

test("importers: PlainTextAdapter replays plaintext golden fixture", () => {
  const txt = readFileSync(join(FIXTURES_DIR, "05-plaintext.txt"), "utf8");
  const expected = JSON.parse(
    readFileSync(join(FIXTURES_DIR, "05-plaintext.expected.json"), "utf8"),
  );
  const doc = importDocument({ kind: "text", input: txt });
  const text = flattenText(doc);
  assert.equal(text, normalizeText(txt));
  assert.equal(text.slice(0, 200), expected.head);
  assert.equal(text.slice(Math.max(0, text.length - 200)), expected.tail);
});

test("importers: importDocument throws UnknownImporterKind for unregistered kind", () => {
  assert.throws(
    () => importDocument({ kind: "pdf", input: "" }),
    (err) => err instanceof UnknownImporterKind && err.kind === "pdf",
  );
});

test("importers: registry exposes registered adapters by kind", () => {
  assert.equal(getAdapter("text"), PlainTextAdapter);
  assert.equal(getAdapter("html"), HtmlAdapter);
});

test("importers: registerAdapter adds a custom adapter", () => {
  const fake = {
    kind: "fake-test-kind",
    canHandle: () => true,
    import: (input) => ({ marker: input }),
  };
  registerAdapter(fake);
  assert.equal(getAdapter("fake-test-kind"), fake);
  const result = importDocument({ kind: "fake-test-kind", input: "x" });
  assert.deepEqual(result, { marker: "x" });
});

test("importers: HtmlAdapter passes sourceUrl through", () => {
  const html = "<html><head><title>T</title></head><body><article><p>Hello world this is text.</p></article></body></html>";
  const doc = importDocument({ kind: "html", input: html, sourceUrl: "https://example.com/x" });
  assert.equal(doc.sourceKind, "html");
  assert.equal(doc.title, "T");
  assert.ok(flattenText(doc).includes("Hello world"));
});
