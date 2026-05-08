import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { parseEpub } from "../src/importers/epub-parse.js";
import { readEpubEntries } from "../src/importers/epub-zip.js";
import { zipSync, strToU8 } from "fflate";

const here = dirname(fileURLToPath(import.meta.url));
const fixturesDir = join(here, "fixtures", "epub");

function loadFixture(name) {
  return readFileSync(join(fixturesDir, name));
}

test("readEpubEntries returns container.xml and OPF for Pride and Prejudice", () => {
  const buf = loadFixture("pride-and-prejudice.epub");
  const entries = readEpubEntries(buf);
  assert.ok(entries.has("META-INF/container.xml"));
  assert.ok(entries.has("OEBPS/content.opf"));
  assert.ok(entries.has("OEBPS/chapter1.xhtml"));
  assert.equal(entries.get("mimetype") instanceof Uint8Array, true);
});

test("parseEpub: Pride and Prejudice (EPUB3 nav)", () => {
  const buf = loadFixture("pride-and-prejudice.epub");
  const { metadata, spine } = parseEpub(buf);
  assert.equal(metadata.title, "Pride and Prejudice");
  assert.equal(metadata.author, "Jane Austen");
  assert.equal(metadata.language, "en");
  assert.equal(spine.length, 2);
  assert.equal(spine[0].id, "ch1");
  assert.equal(spine[0].href, "chapter1.xhtml");
  assert.equal(spine[0].mediaType, "application/xhtml+xml");
  assert.equal(spine[0].navTitle, "Chapter 1");
  assert.equal(spine[1].navTitle, "Chapter 2");
});

test("parseEpub: 道德經 (EPUB2 NCX, zh-Hant)", () => {
  const buf = loadFixture("tao-te-ching.epub");
  const { metadata, spine } = parseEpub(buf);
  assert.equal(metadata.title, "道德經");
  assert.equal(metadata.author, "老子");
  assert.equal(metadata.language, "zh-Hant");
  assert.equal(spine.length, 3);
  assert.equal(spine[0].navTitle, "第一章");
  assert.equal(spine[1].navTitle, "第二章");
  assert.equal(spine[2].navTitle, "第三章");
});

test("parseEpub: throws on missing container.xml", () => {
  const bogus = zipSync({ "hello.txt": strToU8("hi") });
  assert.throws(() => parseEpub(bogus), /container\.xml/);
});
