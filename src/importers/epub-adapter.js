import { htmlToText } from "../article-extract.js";
import { createDocument, createSection } from "../document.js";
import { parseEpub } from "./epub-parse.js";

const TEXT_DECODER = new TextDecoder("utf-8");

const EPUB_ZIP_MAGIC = [0x50, 0x4b, 0x03, 0x04];

function toUint8Array(input) {
  if (input instanceof Uint8Array) return input;
  if (input instanceof ArrayBuffer) return new Uint8Array(input);
  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  }
  return null;
}

function hasZipMagic(bytes) {
  if (!bytes || bytes.length < 4) return false;
  for (let i = 0; i < 4; i += 1) {
    if (bytes[i] !== EPUB_ZIP_MAGIC[i]) return false;
  }
  return true;
}

function joinPath(base, rel) {
  if (!rel) return rel;
  if (/^[a-z][a-z0-9+.-]*:/i.test(rel)) return rel;
  const hashIdx = rel.indexOf("#");
  const cleanRel = hashIdx >= 0 ? rel.slice(0, hashIdx) : rel;
  const baseDir = base.includes("/") ? base.replace(/\/[^/]*$/, "/") : "";
  const parts = (baseDir + cleanRel).split("/");
  const stack = [];
  for (const p of parts) {
    if (p === "" || p === ".") continue;
    if (p === "..") stack.pop();
    else stack.push(p);
  }
  return stack.join("/");
}

export const EpubAdapter = {
  kind: "epub",
  canHandle(input) {
    if (typeof input === "string") {
      return /\.epub$/i.test(input);
    }
    const bytes = toUint8Array(input);
    return hasZipMagic(bytes);
  },
  import(input, opts = {}) {
    const bytes = toUint8Array(input);
    if (!bytes) {
      throw new TypeError(
        "EpubAdapter.import: input must be ArrayBuffer or Uint8Array",
      );
    }
    const { metadata, spine, opfPath, entries } = parseEpub(bytes);
    const sections = [];
    for (const item of spine) {
      const hrefNoFrag = item.href.replace(/#.*$/, "");
      const chapterPath = joinPath(opfPath, hrefNoFrag);
      const chapterBytes = entries.get(chapterPath);
      if (!chapterBytes) continue;
      const html = TEXT_DECODER.decode(chapterBytes);
      const text = htmlToText(html);
      if (!text) continue;
      sections.push(
        createSection({
          id: item.id,
          title: item.navTitle || "",
          kind: "chapter",
          text,
        }),
      );
    }
    return createDocument({
      title: metadata.title || opts.title || "",
      author: metadata.author || opts.author || "",
      sourceUrl: opts.sourceUrl || "",
      sourceKind: "epub",
      sections,
    });
  },
};
