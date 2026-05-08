import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createDocument,
  createSection,
  flattenText,
  tokenizeDocument,
  sectionBoundaries,
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
