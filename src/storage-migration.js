import { createDocument, createSection } from "./document.js";

export const LEGACY_STORAGE_KEY = "fastread-state-v1";
export const STORAGE_KEY = "fastread-state-v2";
export const SCHEMA_VERSION = 2;

/**
 * @typedef {Object} LegacyLibraryItem
 * @property {string} id
 * @property {string} title
 * @property {string} [source]
 * @property {string|null} [sourceURL]
 * @property {string} text
 *
 * @typedef {Object} LegacyPayload
 * @property {LegacyLibraryItem[]} library
 * @property {string} [articleId]
 * @property {number} [wordIndex]
 * @property {number} [wpm]
 */

/**
 * Wraps a legacy library item (with a flat `text` field) into the v2 shape
 * where the article carries a `Document` with a single body Section.
 * Other fields are preserved as-is. The original `text` field is removed.
 */
export function migrateLibraryItem(item) {
  if (!item || typeof item !== "object") {
    throw new TypeError("migrateLibraryItem: item must be an object");
  }
  if (item.document && Array.isArray(item.document.sections)) {
    return item;
  }
  const text = typeof item.text === "string" ? item.text : "";
  const { text: _legacyText, ...rest } = item;
  const document = createDocument({
    title: typeof item.title === "string" ? item.title : "",
    author: typeof item.author === "string" ? item.author : "",
    sourceUrl: typeof item.sourceURL === "string" ? item.sourceURL : "",
    sourceKind: "text",
    sections: [createSection({ id: "body", kind: "body", text })],
  });
  return { ...rest, document };
}

/**
 * Migrates a v1 root payload `{ library, articleId, wordIndex, wpm, ... }`
 * into v2 by rewrapping each library item's text into a Document.
 */
export function migratePayload(payload) {
  if (!payload || typeof payload !== "object") return { schemaVersion: SCHEMA_VERSION, library: [] };
  const library = Array.isArray(payload.library) ? payload.library.map(migrateLibraryItem) : [];
  return { ...payload, library, schemaVersion: SCHEMA_VERSION };
}

/**
 * Detects the version of a parsed payload. v2 if every library item has a
 * `document` field (or the explicit `schemaVersion === 2`), v1 otherwise.
 */
export function detectVersion(payload) {
  if (!payload || typeof payload !== "object") return 2;
  if (payload.schemaVersion === 2) return 2;
  const library = Array.isArray(payload.library) ? payload.library : [];
  if (library.length === 0) return payload.schemaVersion === 1 ? 1 : 2;
  const allHaveDocument = library.every(
    (item) => item && typeof item === "object" && item.document && Array.isArray(item.document.sections),
  );
  return allHaveDocument ? 2 : 1;
}

/**
 * Storage-shape: anything implementing `getItem(key)` and `setItem(key, value)`,
 * matching the localStorage / AsyncStorage subset used here.
 *
 * Returns `{ payload, fromVersion, migrated }`. When migration runs, the
 * returned payload is also written back under STORAGE_KEY and the legacy key
 * is removed (idempotent on subsequent reads).
 */
export function loadAndMigrate(storage) {
  if (!storage) return { payload: { schemaVersion: SCHEMA_VERSION, library: [] }, fromVersion: 2, migrated: false };

  const v2Raw = storage.getItem(STORAGE_KEY);
  if (typeof v2Raw === "string" && v2Raw.length > 0) {
    try {
      const parsed = JSON.parse(v2Raw);
      const version = detectVersion(parsed);
      if (version === 2) return { payload: parsed, fromVersion: 2, migrated: false };
      const migrated = migratePayload(parsed);
      storage.setItem(STORAGE_KEY, JSON.stringify(migrated));
      return { payload: migrated, fromVersion: 1, migrated: true };
    } catch {
      // fall through to legacy lookup
    }
  }

  const v1Raw = storage.getItem(LEGACY_STORAGE_KEY);
  if (typeof v1Raw === "string" && v1Raw.length > 0) {
    try {
      const parsed = JSON.parse(v1Raw);
      const migrated = migratePayload(parsed);
      storage.setItem(STORAGE_KEY, JSON.stringify(migrated));
      if (typeof storage.removeItem === "function") {
        storage.removeItem(LEGACY_STORAGE_KEY);
      }
      return { payload: migrated, fromVersion: 1, migrated: true };
    } catch {
      // fall through
    }
  }

  return { payload: { schemaVersion: SCHEMA_VERSION, library: [] }, fromVersion: 2, migrated: false };
}
