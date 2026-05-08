// End-to-end EPUB ingest test against a real Readmoo export.
//
// Drives the full pipeline that the app uses for an EPUB pick:
//   file bytes -> importDocument({kind:"epub"}) -> Document
//                 -> flattenText -> tokenize -> simulated playback
//                 -> v2 storage round-trip
//
// Skipped if the EPUB is not present so CI and other machines stay green.
// Override the path via FASTREAD_E2E_EPUB.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { importDocument } from "../src/importers/index.js";
import { flattenText, sectionBoundaries, tokenizeDocument } from "../src/document.js";
import {
  containsCjk,
  durationForToken,
  estimateMinutes,
  nextArticleProgressState,
  splitForFocus,
  tokenize,
} from "../src/reader-core.js";
import { migrateLibraryItem, detectVersion } from "../src/storage-migration.js";

const DEFAULT_EPUB =
  process.env.FASTREAD_E2E_EPUB ||
  join(homedir(), "proj", "readmoo", "exports", "all", "房思琪的初戀樂園.epub");

const epubAvailable = existsSync(DEFAULT_EPUB);

function loadEpubBytes(path) {
  const buf = readFileSync(path);
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
}

if (!epubAvailable) {
  test(`epub-e2e: skipped — EPUB not found at ${DEFAULT_EPUB}`, { skip: true }, () => {});
} else {
  test("epub-e2e: 房思琪的初戀樂園 imports as a multi-chapter Document", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });

    assert.equal(document.sourceKind, "epub", "sourceKind should be epub");
    assert.ok(document.title && document.title.length > 0, `expected non-empty title, got: ${JSON.stringify(document.title)}`);
    assert.ok(document.sections.length > 1, `expected a multi-chapter document, got ${document.sections.length} section(s)`);

    const titledSections = document.sections.filter((s) => s.title && s.title.trim().length > 0);
    assert.ok(titledSections.length > 0, "expected at least one section to have a title from the TOC");

    const flat = flattenText(document);
    assert.ok(flat.length > 50_000, `expected > 50k chars of body text, got ${flat.length}`);
    assert.ok(containsCjk(flat), "expected CJK content in a Traditional Chinese novel");
  });

  test("epub-e2e: tokenization yields a reasonable reading workload", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });
    const tokens = tokenizeDocument(document);

    assert.ok(tokens.length > 5000, `expected > 5k reading tokens for a novel, got ${tokens.length}`);

    const minutes = estimateMinutes(tokens.length, 450);
    assert.ok(minutes > 30, `expected estimated read time > 30min at 450wpm, got ${minutes.toFixed(1)}min`);
    assert.ok(minutes < 2000, `estimated read time should not be absurd, got ${minutes.toFixed(1)}min`);
  });

  test("epub-e2e: section boundaries are monotonically increasing and cover all tokens", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });

    const boundaries = sectionBoundaries(document);
    assert.equal(boundaries.length, document.sections.length, "one boundary per section");
    assert.equal(boundaries[0].tokenStart, 0, "first section starts at 0");

    for (let i = 0; i < boundaries.length; i += 1) {
      const b = boundaries[i];
      assert.ok(b.tokenEnd >= b.tokenStart, `section ${b.sectionId}: tokenEnd >= tokenStart`);
      if (i > 0) {
        assert.equal(boundaries[i].tokenStart, boundaries[i - 1].tokenEnd, `section ${b.sectionId} starts where ${boundaries[i - 1].sectionId} ended`);
      }
    }

    const totalTokens = tokenizeDocument(document).length;
    assert.equal(boundaries[boundaries.length - 1].tokenEnd, totalTokens, "last boundary ends at total token count");
  });

  test("epub-e2e: simulated RSVP playback over a 500-token sample stays within sane bounds", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });
    const tokens = tokenizeDocument(document);

    const sampleSize = Math.min(500, tokens.length);
    const wpm = 450;
    let totalMs = 0;
    for (let i = 0; i < sampleSize; i += 1) {
      const token = tokens[i];
      const split = splitForFocus(token);
      assert.ok(typeof split.before === "string", "splitForFocus.before is a string");
      assert.ok(typeof split.focus === "string", "splitForFocus.focus is a string");
      assert.ok(typeof split.after === "string", "splitForFocus.after is a string");

      const ms = durationForToken(token, wpm, true);
      assert.ok(Number.isFinite(ms), `duration for token ${JSON.stringify(token)} must be finite`);
      assert.ok(ms >= 50 && ms <= 2000, `duration for token ${JSON.stringify(token)} out of bounds: ${ms}ms`);
      totalMs += ms;
    }

    // Average 60_000/wpm = 133ms baseline; tolerate anywhere in 60–600ms average for a Chinese novel
    // (CJK multiplier 1.5x, punctuation 1.65x, length penalty up to 1.6x).
    const avgMs = totalMs / sampleSize;
    assert.ok(avgMs >= 60 && avgMs <= 600, `average per-token duration out of bounds: ${avgMs.toFixed(1)}ms`);
  });

  test("epub-e2e: progress sync drives a Document-backed article from 0 to finished", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });
    const tokens = tokenizeDocument(document);
    const flat = flattenText(document);

    const article = {
      id: "epub-e2e-1",
      title: document.title,
      text: flat,
      document,
      progress: 0,
      tagKey: "readingNow",
      finishedAt: null,
    };

    const halfway = nextArticleProgressState(article, 0.5, "2026-05-08T00:00:00.000Z");
    assert.equal(halfway.tagKey, "readingNow");
    assert.equal(halfway.finishedAt, null);
    assert.equal(halfway.progress, 0.5);

    const finished = nextArticleProgressState(halfway, 1, "2026-05-08T00:00:00.000Z");
    assert.equal(finished.tagKey, "finished");
    assert.equal(finished.progress, 1);
    assert.ok(finished.finishedAt, "finishedAt should be set when progress hits 1");
    // sanity: the article's tokens are still derivable for re-open
    assert.equal(tokens.length, tokenize(finished.text).length, "stored text re-tokenizes to the same count");
  });

  test("epub-e2e: round-trips through the v1 -> v2 storage migrator without losing the Document", () => {
    const bytes = loadEpubBytes(DEFAULT_EPUB);
    const document = importDocument({ kind: "epub", input: bytes });
    const flat = flattenText(document);

    // Simulate a legacy v1 library entry (text-only, no document field).
    const legacyItem = {
      id: "legacy-1",
      title: document.title,
      source: "EPUB",
      author: "You",
      text: flat,
      progress: 0,
      tagKey: "readingNow",
    };
    const legacyPayload = { schemaVersion: 1, library: [legacyItem] };

    assert.equal(detectVersion(legacyPayload), 1, "detect v1 input");
    const migrated = migrateLibraryItem(legacyItem);
    assert.ok(migrated.document, "v2 item has a document");
    assert.equal(migrated.document.sections.length, 1, "v1 -> v2 wraps text into a single body section");
    assert.equal(migrated.document.sections[0].kind, "body");
    assert.equal(migrated.document.sections[0].text, flat, "no text loss across migration");

    // Idempotent on already-v2 items (where document was created by the EPUB importer).
    const v2Item = { ...legacyItem, document };
    const reMigrated = migrateLibraryItem(v2Item);
    assert.equal(reMigrated.document, document, "already-v2 items are returned untouched");
  });
}
