import { test } from "node:test";
import assert from "node:assert/strict";

import { loadUrlDocument, getWebFlowState, resetWebFlowState } from "../src/web-flow.js";
import { flattenText } from "../src/document.js";

function makeResponse({ status = 200, body = "", contentType = "text/html; charset=utf-8", url = "https://example.com/article" } = {}) {
  const bytes = new TextEncoder().encode(body);
  return {
    ok: status >= 200 && status < 300,
    status,
    url,
    headers: {
      get(name) {
        const lower = String(name).toLowerCase();
        if (lower === "content-type") return contentType;
        if (lower === "content-length") return String(bytes.byteLength);
        return null;
      },
    },
    arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    text: async () => body,
  };
}

test("loadUrlDocument fetches HTML and lands a Document in in-memory state", async () => {
  resetWebFlowState();
  const html = `<!doctype html>
<html><head><title>Sample Article</title></head>
<body>
<article>
  <h1>Sample Article</h1>
  <p>This is the first paragraph of the article body. It has plenty of words to count.</p>
  <p>This is a second paragraph with even more words to make sure the extractor finds enough.</p>
</article>
</body></html>`;

  let calledUrl = null;
  const fetcher = async (url) => {
    calledUrl = url;
    return makeResponse({ body: html, url });
  };

  const { document, finalUrl, text } = await loadUrlDocument({ url: "https://example.com/article", fetcher });

  assert.equal(calledUrl, "https://example.com/article");
  assert.equal(finalUrl, "https://example.com/article");
  assert.equal(document.sourceKind, "html");
  assert.ok(document.sections.length >= 1, "expected at least one section");
  assert.equal(document.sections[0].kind, "body");
  assert.ok(text.includes("first paragraph"), "flattened text contains article body");
  assert.equal(flattenText(document), text);

  const state = getWebFlowState();
  assert.equal(state.document, document, "in-memory state holds the imported Document");
  assert.equal(state.finalUrl, finalUrl);
});

test("loadUrlDocument propagates fetcher errors and leaves prior state untouched", async () => {
  resetWebFlowState();
  const fetcher = async () => makeResponse({ status: 404, body: "" });
  await assert.rejects(
    loadUrlDocument({ url: "https://example.com/missing", fetcher }),
    (err) => err.name === "HttpError",
  );
  assert.equal(getWebFlowState().document, null);
});
