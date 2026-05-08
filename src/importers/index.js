import { extractArticle, normalizeText } from "../article-extract.js";
import { createDocument, createSection } from "../document.js";
import { EpubAdapter } from "./epub-adapter.js";

export class UnknownImporterKind extends Error {
  constructor(kind) {
    super(`Unknown importer kind: ${kind}`);
    this.name = "UnknownImporterKind";
    this.kind = kind;
  }
}

export const PlainTextAdapter = {
  kind: "text",
  canHandle(input) {
    return typeof input === "string";
  },
  import(input, opts = {}) {
    if (typeof input !== "string") {
      throw new TypeError("PlainTextAdapter.import: input must be a string");
    }
    const text = normalizeText(input);
    const section = createSection({ id: "body", title: "", kind: "body", text });
    return createDocument({
      title: opts.title || "",
      author: opts.author || "",
      sourceUrl: opts.sourceUrl || "",
      sourceKind: "text",
      sections: [section],
    });
  },
};

export const HtmlAdapter = {
  kind: "html",
  canHandle(input) {
    return typeof input === "string";
  },
  import(input, opts = {}) {
    if (typeof input !== "string") {
      throw new TypeError("HtmlAdapter.import: input must be a string");
    }
    const sourceUrl = opts.sourceUrl || "";
    const article = extractArticle(input, sourceUrl);
    const section = createSection({
      id: "body",
      title: "",
      kind: "body",
      text: article.text,
    });
    return createDocument({
      title: article.title || opts.title || "",
      author: opts.author || "",
      sourceUrl: article.url || sourceUrl,
      sourceKind: "html",
      sections: [section],
    });
  },
};

const REGISTRY = new Map();

export function registerAdapter(adapter) {
  if (!adapter || typeof adapter.kind !== "string" || typeof adapter.import !== "function") {
    throw new TypeError("registerAdapter: adapter must have { kind, import }");
  }
  REGISTRY.set(adapter.kind, adapter);
}

export function getAdapter(kind) {
  return REGISTRY.get(kind);
}

export function listAdapters() {
  return [...REGISTRY.values()];
}

registerAdapter(PlainTextAdapter);
registerAdapter(HtmlAdapter);
registerAdapter(EpubAdapter);

export function importDocument({ kind, input, sourceUrl, ...rest } = {}) {
  const adapter = REGISTRY.get(kind);
  if (!adapter) {
    throw new UnknownImporterKind(kind);
  }
  return adapter.import(input, { sourceUrl, ...rest });
}
