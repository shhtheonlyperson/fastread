import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LEGACY_STORAGE_KEY,
  STORAGE_KEY,
  SCHEMA_VERSION,
  migrateLibraryItem,
  migratePayload,
  detectVersion,
  loadAndMigrate,
} from "../src/storage-migration.js";
import { flattenText } from "../src/document.js";

function makeMemoryStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem(key) {
      return map.has(key) ? map.get(key) : null;
    },
    setItem(key, value) {
      map.set(key, String(value));
    },
    removeItem(key) {
      map.delete(key);
    },
    _dump() {
      return Object.fromEntries(map);
    },
  };
}

const sampleV1Payload = {
  library: [
    {
      id: "article-1",
      title: "Sample Post",
      source: "example.com",
      sourceURL: "https://example.com/post",
      author: "You",
      date: "May 1, 2026",
      readTime: "3 min",
      progress: 0.25,
      lede: "Sample Post lede.",
      tagKey: "readingNow",
      text: "First paragraph.\n\nSecond paragraph with more text.",
      timesOpened: 2,
    },
    {
      id: "article-2",
      title: "中文文章",
      source: "Pasted text",
      sourceURL: null,
      author: "You",
      date: "May 2, 2026",
      readTime: "1 min",
      progress: 0,
      lede: "閱讀中。",
      tagKey: "readingNow",
      text: "閱讀是一種技能。",
      timesOpened: 1,
    },
  ],
  articleId: "article-1",
  wordIndex: 12,
  wpm: 540,
  punctuationPause: true,
};

test("migrateLibraryItem wraps legacy text into a Document with one body section", () => {
  const item = sampleV1Payload.library[0];
  const migrated = migrateLibraryItem(item);

  assert.equal(migrated.id, item.id);
  assert.equal(migrated.title, item.title);
  assert.equal(migrated.tagKey, "readingNow");
  assert.equal(migrated.timesOpened, 2);
  assert.ok(!("text" in migrated), "legacy text field should be removed");
  assert.ok(migrated.document, "document field should be present");
  assert.equal(migrated.document.sourceKind, "text");
  assert.equal(migrated.document.sourceUrl, item.sourceURL);
  assert.equal(migrated.document.title, item.title);
  assert.equal(migrated.document.sections.length, 1);
  const [section] = migrated.document.sections;
  assert.equal(section.id, "body");
  assert.equal(section.kind, "body");
  assert.equal(section.text, item.text);
  assert.equal(flattenText(migrated.document), item.text);
});

test("migrateLibraryItem is idempotent on already-v2 items", () => {
  const v2 = migrateLibraryItem(sampleV1Payload.library[0]);
  const again = migrateLibraryItem(v2);
  assert.deepEqual(again, v2);
});

test("migratePayload migrates every library entry and stamps schemaVersion", () => {
  const migrated = migratePayload(sampleV1Payload);
  assert.equal(migrated.schemaVersion, SCHEMA_VERSION);
  assert.equal(migrated.library.length, 2);
  assert.equal(migrated.articleId, "article-1");
  assert.equal(migrated.wordIndex, 12);
  assert.equal(migrated.wpm, 540);
  for (const item of migrated.library) {
    assert.ok(item.document);
    assert.equal(item.document.sections.length, 1);
    assert.equal(item.document.sections[0].kind, "body");
  }
  assert.equal(flattenText(migrated.library[1].document), "閱讀是一種技能。");
});

test("detectVersion identifies v1 vs v2 payloads", () => {
  assert.equal(detectVersion(sampleV1Payload), 1);
  assert.equal(detectVersion(migratePayload(sampleV1Payload)), 2);
  assert.equal(detectVersion({ library: [] }), 2);
  assert.equal(detectVersion({ schemaVersion: 1, library: [] }), 1);
});

test("loadAndMigrate reads a recorded v1 localStorage snapshot, migrates, and writes back v2", () => {
  const storage = makeMemoryStorage({
    [LEGACY_STORAGE_KEY]: JSON.stringify(sampleV1Payload),
  });

  const result = loadAndMigrate(storage);
  assert.equal(result.fromVersion, 1);
  assert.equal(result.migrated, true);
  assert.equal(result.payload.library.length, 2);
  for (let i = 0; i < sampleV1Payload.library.length; i += 1) {
    const original = sampleV1Payload.library[i];
    const migrated = result.payload.library[i];
    assert.equal(migrated.document.sections.length, 1);
    assert.equal(migrated.document.sections[0].text, original.text);
  }

  const dump = storage._dump();
  assert.ok(STORAGE_KEY in dump, "v2 key should be written");
  assert.ok(!(LEGACY_STORAGE_KEY in dump), "legacy v1 key should be removed");

  const reread = loadAndMigrate(storage);
  assert.equal(reread.migrated, false);
  assert.equal(reread.fromVersion, 2);
  assert.equal(reread.payload.library.length, 2);
});

test("loadAndMigrate returns an empty v2 payload when storage is empty", () => {
  const storage = makeMemoryStorage();
  const result = loadAndMigrate(storage);
  assert.equal(result.fromVersion, 2);
  assert.equal(result.migrated, false);
  assert.deepEqual(result.payload, { schemaVersion: SCHEMA_VERSION, library: [] });
});
