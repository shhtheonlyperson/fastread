import test from "node:test";
import assert from "node:assert/strict";

import {
  fetchAndExtract,
  InvalidURL,
  HttpError,
  OversizedError,
  UnsupportedContentType,
  TimeoutError,
} from "../src/url-ingest.js";

function makeResponse({ status = 200, headers = {}, body = "", url = "" } = {}) {
  const lowered = new Map();
  for (const [k, v] of Object.entries(headers)) lowered.set(k.toLowerCase(), String(v));
  let bytes;
  if (body instanceof Uint8Array) bytes = body;
  else if (body && body.buffer instanceof ArrayBuffer) bytes = new Uint8Array(body.buffer);
  else bytes = new TextEncoder().encode(String(body ?? ""));
  return {
    ok: status >= 200 && status < 300,
    status,
    url,
    headers: { get: (name) => lowered.get(String(name).toLowerCase()) ?? null },
    async text() {
      return new TextDecoder("utf-8").decode(bytes);
    },
    async arrayBuffer() {
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    },
  };
}

const HAPPY_HTML = `<!doctype html><html><head><title>Hello World</title></head>
  <body><article>
    <p>${"This article body has plenty of meaningful words so the reader extractor will accept it. ".repeat(6)}</p>
  </article></body></html>`;

test("fetchAndExtract: 200 OK happy path returns article and finalUrl", async () => {
  const fetcher = async (url) => makeResponse({
    status: 200,
    headers: { "content-type": "text/html; charset=utf-8" },
    body: HAPPY_HTML,
    url,
  });
  const { article, finalUrl } = await fetchAndExtract({
    url: "https://example.com/post",
    fetcher,
  });
  assert.equal(finalUrl, "https://example.com/post");
  assert.equal(article.title, "Hello World");
  assert.ok(article.wordCount >= 20, `expected wordCount>=20, got ${article.wordCount}`);
  assert.match(article.text, /meaningful words/);
});

test("fetchAndExtract: 404 throws HttpError", async () => {
  const fetcher = async () => makeResponse({ status: 404, headers: { "content-type": "text/html" } });
  await assert.rejects(
    fetchAndExtract({ url: "https://example.com/missing", fetcher }),
    (err) => err instanceof HttpError && err.status === 404,
  );
});

test("fetchAndExtract: content-length over maxBytes throws OversizedError", async () => {
  const fetcher = async () => makeResponse({
    status: 200,
    headers: { "content-type": "text/html", "content-length": String(50 * 1024 * 1024) },
    body: "x",
  });
  await assert.rejects(
    fetchAndExtract({ url: "https://example.com/big", fetcher, maxBytes: 1024 }),
    (err) => err instanceof OversizedError,
  );
});

test("fetchAndExtract: body bigger than maxBytes after read throws OversizedError", async () => {
  const big = "y".repeat(2048);
  const fetcher = async () => makeResponse({
    status: 200,
    headers: { "content-type": "text/html" }, // no content-length
    body: big,
  });
  await assert.rejects(
    fetchAndExtract({ url: "https://example.com/streamed", fetcher, maxBytes: 512 }),
    (err) => err instanceof OversizedError,
  );
});

test("fetchAndExtract: application/pdf throws UnsupportedContentType", async () => {
  const fetcher = async () => makeResponse({
    status: 200,
    headers: { "content-type": "application/pdf" },
    body: "%PDF-1.4...",
  });
  await assert.rejects(
    fetchAndExtract({ url: "https://example.com/file.pdf", fetcher }),
    (err) => err instanceof UnsupportedContentType && err.contentType === "application/pdf",
  );
});

test("fetchAndExtract: AbortSignal triggers TimeoutError", async () => {
  const fetcher = async (_url, opts) => {
    const err = new Error("aborted");
    err.name = "AbortError";
    if (opts?.signal?.aborted) throw err;
    await new Promise((resolve, reject) => {
      opts.signal.addEventListener("abort", () => reject(err), { once: true });
    });
    return makeResponse();
  };
  const controller = new AbortController();
  const promise = fetchAndExtract({
    url: "https://example.com/slow",
    fetcher,
    signal: controller.signal,
  });
  controller.abort();
  await assert.rejects(promise, (err) => err instanceof TimeoutError);
});

test("fetchAndExtract: non-http(s) URL throws InvalidURL", async () => {
  const fetcher = async () => {
    throw new Error("fetcher should not be called");
  };
  await assert.rejects(
    fetchAndExtract({ url: "ftp://example.com/file.txt", fetcher }),
    (err) => err instanceof InvalidURL,
  );
  await assert.rejects(
    fetchAndExtract({ url: "javascript:alert(1)", fetcher }),
    (err) => err instanceof InvalidURL,
  );
});

test("fetchAndExtract: latin-1 body decoded via charset fallback", async () => {
  // "café" encoded in ISO-8859-1: 63 61 66 E9
  const latin1Body = new Uint8Array([
    0x3c, 0x68, 0x31, 0x3e, // <h1>
    0x63, 0x61, 0x66, 0xe9, // café
    0x3c, 0x2f, 0x68, 0x31, 0x3e, // </h1>
    0x3c, 0x70, 0x3e, // <p>
    ...new TextEncoder().encode(
      "This article paragraph has plenty of words to satisfy the extractor minimum threshold for tokens. ".repeat(3),
    ),
    0x63, 0x61, 0x66, 0xe9, // café (latin-1)
    0x3c, 0x2f, 0x70, 0x3e, // </p>
  ]);
  const fetcher = async (url) => makeResponse({
    status: 200,
    headers: { "content-type": "text/html; charset=ISO-8859-1" },
    body: latin1Body,
    url,
  });
  const { article } = await fetchAndExtract({
    url: "https://example.com/latin",
    fetcher,
  });
  assert.match(article.text, /café/);
});
