import { extractArticle } from "./article-extract.js";

const DEFAULT_MAX_BYTES = 6 * 1024 * 1024;

const ACCEPT_HEADER = "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2";

const SUPPORTED_CONTENT_TYPE = /text\/html|application\/xhtml\+xml|text\/plain/i;

export class InvalidURL extends Error {
  constructor(message) {
    super(message);
    this.name = "InvalidURL";
  }
}

export class HttpError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

export class OversizedError extends Error {
  constructor(message) {
    super(message);
    this.name = "OversizedError";
  }
}

export class UnsupportedContentType extends Error {
  constructor(message, contentType) {
    super(message);
    this.name = "UnsupportedContentType";
    this.contentType = contentType;
  }
}

export class TimeoutError extends Error {
  constructor(message) {
    super(message);
    this.name = "TimeoutError";
  }
}

export async function fetchAndExtract({
  url,
  fetcher = globalThis.fetch,
  maxBytes = DEFAULT_MAX_BYTES,
  signal,
} = {}) {
  if (typeof url !== "string" || !url.trim()) {
    throw new InvalidURL("URL is empty.");
  }
  const trimmed = url.trim();

  const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(trimmed);
  let parsed;
  try {
    parsed = new URL(hasScheme ? trimmed : `https://${trimmed}`);
  } catch {
    throw new InvalidURL(`Invalid URL: ${trimmed}`);
  }
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new InvalidURL("Only http and https URLs are supported.");
  }

  if (typeof fetcher !== "function") {
    throw new TypeError("fetchAndExtract requires a fetcher function.");
  }

  let response;
  try {
    response = await fetcher(parsed.toString(), {
      headers: { accept: ACCEPT_HEADER },
      signal,
    });
  } catch (err) {
    if (isAbortError(err)) throw new TimeoutError("Fetch aborted.");
    throw err;
  }

  if (!response || !response.ok) {
    const status = response?.status ?? 0;
    throw new HttpError(`Fetch failed with HTTP ${status}.`, status);
  }

  const contentLengthHeader = response.headers?.get("content-length");
  const contentLength = Number(contentLengthHeader || 0);
  if (contentLength && contentLength > maxBytes) {
    throw new OversizedError(`Content-Length ${contentLength} exceeds ${maxBytes}.`);
  }

  const contentType = response.headers?.get("content-type") || "";
  if (contentType && !SUPPORTED_CONTENT_TYPE.test(contentType)) {
    throw new UnsupportedContentType(`Unsupported content type: ${contentType}.`, contentType);
  }

  let buffer;
  try {
    buffer = await response.arrayBuffer();
  } catch (err) {
    if (isAbortError(err)) throw new TimeoutError("Fetch aborted.");
    throw err;
  }

  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  if (bytes.byteLength > maxBytes) {
    throw new OversizedError(`Body ${bytes.byteLength} exceeds ${maxBytes}.`);
  }

  const html = decodeBody(bytes, contentType);
  const finalUrl = response.url || parsed.toString();
  const article = extractArticle(html, finalUrl);
  return { article, finalUrl };
}

function isAbortError(err) {
  return err && (err.name === "AbortError" || err.code === "ABORT_ERR");
}

function decodeBody(bytes, contentType) {
  const charsetMatch = /charset\s*=\s*"?([^";]+)"?/i.exec(contentType || "");
  const declared = (charsetMatch?.[1] || "").trim().toLowerCase();

  if (declared && declared !== "utf-8" && declared !== "utf8") {
    try {
      return new TextDecoder(declared).decode(bytes);
    } catch {
      // fall through to utf-8 / latin-1 fallback
    }
  }

  const utf8 = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  if (!utf8.includes("�")) return utf8;

  try {
    return new TextDecoder("iso-8859-1").decode(bytes);
  } catch {
    return utf8;
  }
}
