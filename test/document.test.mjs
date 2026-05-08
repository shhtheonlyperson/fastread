import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createDocument,
  createSection,
  flattenText,
  tokenizeDocument,
  sectionBoundaries,
  detectFrontMatter,
} from "../src/document.js";
import { tokenize } from "../src/reader-core.js";

test("empty document flattens, tokenizes, and yields no boundaries", () => {
  const doc = createDocument();
  assert.deepEqual(doc.sections, []);
  assert.equal(flattenText(doc), "");
  assert.deepEqual(tokenizeDocument(doc), []);
  assert.deepEqual(sectionBoundaries(doc), []);
});

test("single body section round-trips text and tokens", () => {
  const text = "Hello world this is a tiny article.";
  const doc = createDocument({
    title: "Tiny",
    author: "Anon",
    sourceUrl: "https://example.com/tiny",
    sourceKind: "text",
    sections: [createSection({ id: "s1", kind: "body", text })],
  });
  assert.equal(flattenText(doc), text);
  assert.deepEqual(tokenizeDocument(doc), tokenize(text));
  const boundaries = sectionBoundaries(doc);
  assert.equal(boundaries.length, 1);
  assert.equal(boundaries[0].sectionId, "s1");
  assert.equal(boundaries[0].tokenStart, 0);
  assert.equal(boundaries[0].tokenEnd, tokenize(text).length);
});

test("multi-chapter document with CJK title and content", () => {
  const ch1 = "第一章。這是中文段落，用來測試章節邊界。";
  const ch2 = "Chapter two has plain ASCII text for the boundary math.";
  const ch3 = "終章：混合 CJK 與 latin words 一起。";
  const doc = createDocument({
    title: "混合標題 — A Mixed Title",
    author: "張三",
    sourceUrl: "https://example.com/zh",
    sourceKind: "epub",
    sections: [
      createSection({ id: "c1", title: "第一章", kind: "chapter", text: ch1 }),
      createSection({ id: "c2", title: "Chapter Two", kind: "chapter", text: ch2 }),
      createSection({ id: "c3", title: "終章", kind: "chapter", text: ch3 }),
    ],
  });

  const flat = flattenText(doc);
  assert.equal(flat, [ch1, ch2, ch3].join("\n\n"));

  // tokenizeDocument equals tokenize(flattenText)
  assert.deepEqual(tokenizeDocument(doc), tokenize(flat));

  const boundaries = sectionBoundaries(doc);
  assert.equal(boundaries.length, 3);
  assert.equal(boundaries[0].sectionId, "c1");
  assert.equal(boundaries[2].sectionId, "c3");

  // Boundary math: last tokenEnd equals total token count
  const totalTokens = tokenize(flat).length;
  assert.equal(boundaries[boundaries.length - 1].tokenEnd, totalTokens);

  // Each section's [tokenStart, tokenEnd) is contiguous with the next
  for (let i = 1; i < boundaries.length; i += 1) {
    assert.equal(boundaries[i].tokenStart, boundaries[i - 1].tokenEnd);
  }

  // tokenStart values are monotonically non-decreasing and start at 0
  assert.equal(boundaries[0].tokenStart, 0);
});

test("createSection rejects bad kind / missing id", () => {
  assert.throws(() => createSection({ id: "", kind: "body" }), TypeError);
  assert.throws(() => createSection({ id: "x", kind: "weird" }), TypeError);
});

function chapterText(words) {
  return new Array(words).fill("word").join(" ");
}

test("detectFrontMatter on an empty document returns the trivial result", () => {
  assert.deepEqual(detectFrontMatter(createDocument()), {
    firstChapterSectionIndex: null,
    firstChapterTokenIndex: 0,
    frontMatterSectionIds: [],
    totalTokens: 0,
  });
});

test("detectFrontMatter recognizes zh-Hant front matter titles", () => {
  const doc = createDocument({
    sourceKind: "epub",
    sections: [
      createSection({ id: "cov", title: "封面", kind: "chapter", text: "封面" }),
      createSection({ id: "ver", title: "版權頁", kind: "chapter", text: "版權所有 翻印必究" }),
      createSection({ id: "tof", title: "目錄", kind: "chapter", text: "第一章 第二章" }),
      createSection({ id: "rec", title: "推薦序 · 房思琪是個謎", kind: "chapter", text: chapterText(120) }),
      createSection({ id: "ch1", title: "樂園", kind: "chapter", text: chapterText(2500) }),
      createSection({ id: "ch2", title: "失樂園", kind: "chapter", text: chapterText(2500) }),
    ],
  });

  const result = detectFrontMatter(doc);
  assert.equal(result.firstChapterSectionIndex, 4, "should skip 4 front-matter sections");
  assert.deepEqual(result.frontMatterSectionIds, ["cov", "ver", "tof", "rec"]);
  assert.ok(result.firstChapterTokenIndex > 0, "token index moves past front matter");
  assert.equal(result.totalTokens > result.firstChapterTokenIndex, true);
});

test("detectFrontMatter recognizes English front matter titles", () => {
  const doc = createDocument({
    sourceKind: "epub",
    sections: [
      createSection({ id: "cover", title: "Cover", kind: "chapter", text: "" }),
      createSection({ id: "title", title: "Title Page", kind: "chapter", text: "Pride and Prejudice" }),
      createSection({ id: "copy", title: "Copyright", kind: "chapter", text: "Public domain." }),
      createSection({ id: "fore", title: "Foreword", kind: "chapter", text: chapterText(50) }),
      createSection({ id: "ch1", title: "Chapter 1", kind: "chapter", text: chapterText(2000) }),
    ],
  });

  const result = detectFrontMatter(doc);
  assert.equal(result.firstChapterSectionIndex, 4);
  assert.deepEqual(result.frontMatterSectionIds, ["cover", "title", "copy", "fore"]);
});

test("detectFrontMatter falls back to short-section heuristic when titles are generic", () => {
  // Section titles all read like generic placeholders ("Section N") so the
  // length+position heuristic has to do the work.
  const doc = createDocument({
    sourceKind: "epub",
    sections: [
      createSection({ id: "s0", title: "Section 0", kind: "chapter", text: chapterText(40) }),
      createSection({ id: "s1", title: "Section 1", kind: "chapter", text: chapterText(60) }),
      createSection({ id: "s2", title: "Section 2", kind: "chapter", text: chapterText(3000) }),
      createSection({ id: "s3", title: "Section 3", kind: "chapter", text: chapterText(3000) }),
    ],
  });

  const result = detectFrontMatter(doc);
  assert.equal(result.firstChapterSectionIndex, 2);
  assert.deepEqual(result.frontMatterSectionIds, ["s0", "s1"]);
});

test("detectFrontMatter returns index 0 / no skip when the first section is already a chapter", () => {
  const doc = createDocument({
    sourceKind: "epub",
    sections: [
      createSection({ id: "ch1", title: "Chapter 1", kind: "chapter", text: chapterText(3000) }),
      createSection({ id: "ch2", title: "Chapter 2", kind: "chapter", text: chapterText(3000) }),
    ],
  });

  const result = detectFrontMatter(doc);
  assert.equal(result.firstChapterSectionIndex, 0);
  assert.deepEqual(result.frontMatterSectionIds, []);
  assert.equal(result.firstChapterTokenIndex, 0);
});

test("detectFrontMatter does NOT misclassify a long-titled chapter that begins with 前", () => {
  // "前進的勇氣" should not match the "前言" front-matter prefix.
  const doc = createDocument({
    sourceKind: "epub",
    sections: [
      createSection({ id: "fmw", title: "推薦序", kind: "chapter", text: chapterText(50) }),
      createSection({ id: "ch1", title: "前進的勇氣", kind: "chapter", text: chapterText(2500) }),
    ],
  });

  const result = detectFrontMatter(doc);
  assert.equal(result.firstChapterSectionIndex, 1);
  assert.deepEqual(result.frontMatterSectionIds, ["fmw"]);
});
