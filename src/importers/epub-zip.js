import { unzipSync } from "fflate";

/**
 * Synchronously unzip an EPUB ArrayBuffer / Uint8Array into a Map<path, Uint8Array>.
 * @param {ArrayBuffer | Uint8Array} arrayBuffer
 * @returns {Map<string, Uint8Array>}
 */
export function readEpubEntries(arrayBuffer) {
  if (!arrayBuffer) {
    throw new TypeError("readEpubEntries: arrayBuffer is required");
  }
  const bytes =
    arrayBuffer instanceof Uint8Array
      ? arrayBuffer
      : new Uint8Array(arrayBuffer);
  const entries = unzipSync(bytes);
  const out = new Map();
  for (const [path, data] of Object.entries(entries)) {
    out.set(path, data);
  }
  return out;
}
