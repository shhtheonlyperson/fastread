import { tokenize } from "./reader-core.js";

/**
 * @typedef {"chapter"|"page"|"body"} SectionKind
 *
 * @typedef {Object} Section
 * @property {string} id
 * @property {string} title
 * @property {SectionKind} kind
 * @property {string} text
 *
 * @typedef {Object} Document
 * @property {string} title
 * @property {string} author
 * @property {string} sourceUrl
 * @property {string} sourceKind
 * @property {Section[]} sections
 */

const VALID_KINDS = new Set(["chapter", "page", "body"]);

export function createSection({ id, title = "", kind = "body", text = "" } = {}) {
  if (typeof id !== "string" || id.length === 0) {
    throw new TypeError("createSection: id must be a non-empty string");
  }
  if (!VALID_KINDS.has(kind)) {
    throw new TypeError(`createSection: kind must be one of ${[...VALID_KINDS].join("|")}`);
  }
  return {
    id,
    title: typeof title === "string" ? title : "",
    kind,
    text: typeof text === "string" ? text : "",
  };
}

export function createDocument({
  title = "",
  author = "",
  sourceUrl = "",
  sourceKind = "text",
  sections = [],
} = {}) {
  if (!Array.isArray(sections)) {
    throw new TypeError("createDocument: sections must be an array");
  }
  return {
    title: typeof title === "string" ? title : "",
    author: typeof author === "string" ? author : "",
    sourceUrl: typeof sourceUrl === "string" ? sourceUrl : "",
    sourceKind: typeof sourceKind === "string" ? sourceKind : "text",
    sections: sections.map((s) =>
      // accept either pre-built section objects or partials
      s && typeof s === "object" && VALID_KINDS.has(s.kind) && typeof s.id === "string"
        ? { id: s.id, title: s.title || "", kind: s.kind, text: s.text || "" }
        : createSection(s),
    ),
  };
}

export function flattenText(document) {
  if (!document || !Array.isArray(document.sections)) return "";
  return document.sections.map((s) => s.text || "").join("\n\n");
}

export function tokenizeDocument(document) {
  return tokenize(flattenText(document));
}

export function sectionBoundaries(document) {
  if (!document || !Array.isArray(document.sections)) return [];
  const boundaries = [];
  let cursor = 0;
  let runningText = "";
  for (let i = 0; i < document.sections.length; i += 1) {
    const section = document.sections[i];
    const prefix = i === 0 ? "" : "\n\n";
    const candidate = runningText + prefix + (section.text || "");
    const tokensSoFar = tokenize(candidate).length;
    boundaries.push({
      sectionId: section.id,
      tokenStart: cursor,
      tokenEnd: tokensSoFar,
    });
    cursor = tokensSoFar;
    runningText = candidate;
  }
  return boundaries;
}

// Sections whose title matches one of these prefixes are treated as
// front matter. Patterns are anchored at the start so chapter titles like
// "前進的勇氣" don't match "前". Combines zh-Hant, zh-Hans, en, and a
// handful of conventional EPUB section names.
const FRONT_MATTER_TITLE_RE = new RegExp(
  "^(" +
    [
      "封面",
      "扉頁",
      "扉页",
      "版權",
      "版权",
      "獻詞",
      "献词",
      "推薦序",
      "推薦語",
      "推薦文",
      "推薦$",
      "推荐序",
      "推荐语",
      "名人推薦",
      "各界推薦",
      "自序",
      "序言",
      "序$",
      "代序",
      "前言",
      "引言",
      "試讀本",
      "试读本",
      "目錄",
      "目录",
      "致謝",
      "致谢",
      "譯者序",
      "译者序",
      "作者簡介",
      "作者简介",
      "Foreword",
      "Preface",
      "Copyright",
      "Acknowledg",
      "Dedication",
      "Title\\s*Page",
      "Cover\\s*Page",
      "^Cover$",
      "Contents$",
      "Table\\s*of\\s*Contents",
      "Imprint",
      "Colophon",
      "Frontispiece",
      "Half\\s*Title",
      "About\\s*the\\s*Author",
      "Praise\\s*for",
      "Epigraph",
      "Note\\s*to\\s*the\\s*Reader",
    ].join("|") +
    ")",
  "i",
);

const FRONT_MATTER_HEAD_FRACTION = 0.15;
// Sections under this many reading units that fall inside the leading
// FRONT_MATTER_HEAD_FRACTION of the book are treated as front matter even
// when their title doesn't match a known prefix. Chosen empirically against
// the Readmoo Traditional Chinese export corpus, where recommendation
// blurbs and dedications run a few hundred CJK characters long.
const FRONT_MATTER_SHORT_UNITS = 500;

/**
 * Classify the leading sections of a document as front matter (cover,
 * copyright, foreword, etc.) and return the index/token at which the
 * actual reading material begins.
 *
 * @param {Document} document
 * @returns {{
 *   firstChapterSectionIndex: number|null,
 *   firstChapterTokenIndex: number,
 *   frontMatterSectionIds: string[],
 *   totalTokens: number
 * }}
 */
export function detectFrontMatter(document) {
  const empty = {
    firstChapterSectionIndex: null,
    firstChapterTokenIndex: 0,
    frontMatterSectionIds: [],
    totalTokens: 0,
  };
  if (!document || !Array.isArray(document.sections) || document.sections.length === 0) {
    return empty;
  }

  const boundaries = sectionBoundaries(document);
  const totalTokens = boundaries[boundaries.length - 1]?.tokenEnd || 0;
  if (totalTokens === 0) return { ...empty, totalTokens: 0 };

  const headLimit = totalTokens * FRONT_MATTER_HEAD_FRACTION;
  let firstChapterSectionIndex = null;

  for (let i = 0; i < document.sections.length; i += 1) {
    const section = document.sections[i];
    const b = boundaries[i];
    const units = b.tokenEnd - b.tokenStart;
    const inHead = b.tokenStart < headLimit;
    const titleHit = FRONT_MATTER_TITLE_RE.test(String(section.title || "").trim());
    const looksShort = units < FRONT_MATTER_SHORT_UNITS && inHead;

    if (titleHit || looksShort) continue;

    firstChapterSectionIndex = i;
    break;
  }

  if (firstChapterSectionIndex === null || firstChapterSectionIndex === 0) {
    return {
      firstChapterSectionIndex: firstChapterSectionIndex,
      firstChapterTokenIndex: firstChapterSectionIndex === 0 ? 0 : 0,
      frontMatterSectionIds: [],
      totalTokens,
    };
  }

  const frontMatterSectionIds = boundaries
    .slice(0, firstChapterSectionIndex)
    .map((b) => b.sectionId);
  return {
    firstChapterSectionIndex,
    firstChapterTokenIndex: boundaries[firstChapterSectionIndex].tokenStart,
    frontMatterSectionIds,
    totalTokens,
  };
}
