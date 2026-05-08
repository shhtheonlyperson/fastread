// Walk a real-world EPUB corpus and assert every file imports cleanly.
//
// Gated: only runs when FASTREAD_RUN_EPUB_CORPUS=1 AND the corpus dir exists.
// Default dir is the user's local EPUB export at ~/proj/local-epub/exports/all,
// override with FASTREAD_EPUB_CORPUS_DIR. The npm script
//   bun run test:epub-corpus
// flips the env flag and runs only this file.
//
// For each *.epub:
//   1. importDocument({kind:"epub"}) succeeds without throwing
//   2. Document has at least one section with non-empty text
//   3. flattenText + tokenize produces > 50 reading units
//
// Failures are aggregated into a single report so a noisy file doesn't hide
// the others.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { importDocument } from "../src/importers/index.js";
import { flattenText } from "../src/document.js";
import { tokenize } from "../src/reader-core.js";

const enabled = process.env.FASTREAD_RUN_EPUB_CORPUS === "1";
const corpusDir =
  process.env.FASTREAD_EPUB_CORPUS_DIR ||
  join(homedir(), "proj", "local-epub", "exports", "all");
const limit = Number(process.env.FASTREAD_EPUB_CORPUS_LIMIT || "0") || Infinity;

function listEpubs(dir) {
  return readdirSync(dir)
    .filter((name) => name.toLowerCase().endsWith(".epub"))
    .map((name) => join(dir, name))
    .filter((path) => {
      try {
        return statSync(path).isFile();
      } catch {
        return false;
      }
    });
}

if (!enabled) {
  test("epub-corpus: skipped (set FASTREAD_RUN_EPUB_CORPUS=1 to run)", { skip: true }, () => {});
} else if (!existsSync(corpusDir)) {
  test(`epub-corpus: skipped — corpus dir not found at ${corpusDir}`, { skip: true }, () => {});
} else {
  const allFiles = listEpubs(corpusDir);
  const files = Number.isFinite(limit) ? allFiles.slice(0, limit) : allFiles;

  test(`epub-corpus: discovered ${allFiles.length} EPUB(s) under ${corpusDir}`, () => {
    assert.ok(allFiles.length > 0, `expected at least one .epub under ${corpusDir}`);
  });

  test(`epub-corpus: every EPUB imports as a non-empty Document (${files.length} file(s))`, () => {
    const failures = [];
    for (const path of files) {
      const name = path.split("/").pop();
      try {
        const buf = readFileSync(path);
        const bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
        const document = importDocument({ kind: "epub", input: bytes });

        if (document.sourceKind !== "epub") {
          failures.push({ name, reason: `sourceKind=${document.sourceKind}` });
          continue;
        }
        if (!Array.isArray(document.sections) || document.sections.length === 0) {
          failures.push({ name, reason: "no sections" });
          continue;
        }
        const nonEmpty = document.sections.filter((s) => s.text && s.text.trim().length > 0);
        if (nonEmpty.length === 0) {
          failures.push({ name, reason: "all sections empty" });
          continue;
        }
        const tokenCount = tokenize(flattenText(document)).length;
        if (tokenCount < 50) {
          failures.push({ name, reason: `only ${tokenCount} reading units` });
          continue;
        }
      } catch (error) {
        failures.push({ name, reason: error.message || String(error) });
      }
    }

    if (failures.length > 0) {
      const detail = failures.map((f) => `  - ${f.name}: ${f.reason}`).join("\n");
      assert.fail(`${failures.length}/${files.length} EPUB(s) failed import:\n${detail}`);
    }
  });
}
