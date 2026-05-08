import { fetchHtml } from "./url-ingest.js";
import { importDocument } from "./importers/index.js";
import { flattenText } from "./document.js";

let state = { document: null, finalUrl: null };

export function getWebFlowState() {
  return state;
}

export function resetWebFlowState() {
  state = { document: null, finalUrl: null };
}

export async function loadUrlDocument({ url, fetcher, maxBytes, signal } = {}) {
  const { html, finalUrl } = await fetchHtml({ url, fetcher, maxBytes, signal });
  const document = importDocument({ kind: "html", input: html, sourceUrl: finalUrl });
  state = { document, finalUrl };
  return { document, finalUrl, text: flattenText(document) };
}
