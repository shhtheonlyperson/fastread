import { test } from "node:test";
import assert from "node:assert/strict";

// Mirrors the library item shape constructed by addArticle in
// components/fast-read-screen.jsx. Kept inline (not imported from the RN
// component, which depends on react-native) so this stays a pure node test.
function makeLibraryItem({
  id,
  title,
  source,
  sourceURL = null,
  author = "You",
  date,
  createdAt,
  lastOpenedAt,
  finishedAt = null,
  readTime,
  progress = 0,
  lede,
  tagKey = "readingNow",
  text,
  timesOpened = 1,
}) {
  return {
    id,
    title,
    source,
    sourceURL,
    author,
    date,
    createdAt,
    lastOpenedAt,
    finishedAt,
    readTime,
    progress,
    lede,
    tagKey,
    text,
    timesOpened,
  };
}

test("library-storage: round-trips a full library item", () => {
  const now = "2026-05-07T12:34:56.000Z";
  const item = makeLibraryItem({
    id: "article-1714000000000",
    title: "Round-Trip 你好 Title",
    source: "example.com",
    sourceURL: "https://example.com/post",
    date: "May 7, 2026",
    createdAt: now,
    lastOpenedAt: now,
    finishedAt: null,
    readTime: "5 min",
    progress: 0.42,
    lede: "Lede with CJK 中文 and emoji 📚.",
    text: "Body — em-dash, NBSP runs, and 漢字.",
    timesOpened: 3,
  });

  const restored = JSON.parse(JSON.stringify(item));
  assert.deepEqual(restored, item);

  // Spot-check critical persistence fields explicitly.
  assert.equal(restored.id, item.id);
  assert.equal(restored.progress, 0.42);
  assert.equal(restored.timesOpened, 3);
  assert.equal(restored.tagKey, "readingNow");
  assert.equal(restored.sourceURL, "https://example.com/post");
  assert.equal(restored.finishedAt, null);
  assert.equal(restored.text, item.text);
});

test("library-storage: preserves null/finished-edge fields", () => {
  const item = makeLibraryItem({
    id: "article-finished",
    title: "Finished",
    source: "Clipboard",
    sourceURL: null,
    date: "May 7, 2026",
    createdAt: "2026-05-01T00:00:00.000Z",
    lastOpenedAt: "2026-05-07T00:00:00.000Z",
    finishedAt: "2026-05-07T00:30:00.000Z",
    readTime: "1 min",
    progress: 1,
    lede: "Done.",
    text: "Tiny body.",
    timesOpened: 9,
  });

  const restored = JSON.parse(JSON.stringify(item));
  assert.deepEqual(restored, item);
  assert.equal(restored.progress, 1);
  assert.equal(restored.finishedAt, "2026-05-07T00:30:00.000Z");
  assert.equal(restored.sourceURL, null);
});

test("library-storage: list of items survives round-trip", () => {
  const items = [
    makeLibraryItem({
      id: "a-1",
      title: "One",
      source: "Clipboard",
      date: "May 7, 2026",
      createdAt: "2026-05-07T00:00:00.000Z",
      lastOpenedAt: "2026-05-07T00:00:00.000Z",
      readTime: "2 min",
      lede: "lede 1",
      text: "text 1",
    }),
    makeLibraryItem({
      id: "a-2",
      title: "Two",
      source: "example.com",
      sourceURL: "https://example.com/2",
      date: "May 7, 2026",
      createdAt: "2026-05-07T01:00:00.000Z",
      lastOpenedAt: "2026-05-07T01:00:00.000Z",
      readTime: "4 min",
      progress: 0.5,
      lede: "lede 2",
      text: "text 2",
      timesOpened: 2,
    }),
  ];

  const wrapper = { library: items, articleId: "a-2", wordIndex: 12, wpm: 450 };
  const restored = JSON.parse(JSON.stringify(wrapper));
  assert.deepEqual(restored, wrapper);
  assert.equal(restored.library.length, 2);
  assert.equal(restored.library[1].id, "a-2");
  assert.equal(restored.library[1].progress, 0.5);
});
