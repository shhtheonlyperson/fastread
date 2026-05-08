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
