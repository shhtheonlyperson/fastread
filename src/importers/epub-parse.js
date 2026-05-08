import { readEpubEntries } from "./epub-zip.js";

const TEXT_DECODER = new TextDecoder("utf-8");

function decodeUtf8(bytes) {
  return TEXT_DECODER.decode(bytes);
}

function decodeXmlEntities(s) {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) =>
      String.fromCodePoint(parseInt(n, 16)),
    )
    .replace(/&amp;/g, "&");
}

function attr(tag, name) {
  // Match attr="value" or attr='value'
  const re = new RegExp(`\\b${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i");
  const m = tag.match(re);
  if (!m) return undefined;
  const v = m[2] !== undefined ? m[2] : m[3];
  return decodeXmlEntities(v);
}

function findFirstTagText(xml, localName) {
  // Match <prefix:localName ...>text</prefix:localName> or <localName ...>text</localName>
  const re = new RegExp(
    `<(?:[a-zA-Z][\\w.-]*:)?${localName}\\b[^>]*>([\\s\\S]*?)</(?:[a-zA-Z][\\w.-]*:)?${localName}>`,
    "i",
  );
  const m = xml.match(re);
  return m ? decodeXmlEntities(m[1].trim()) : undefined;
}

function joinPath(base, rel) {
  if (!rel) return rel;
  if (/^[a-z][a-z0-9+.-]*:/i.test(rel)) return rel; // absolute URL
  // Strip fragment
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

function findContainerOpfPath(entries) {
  const containerBytes = entries.get("META-INF/container.xml");
  if (!containerBytes) {
    throw new Error("EPUB: missing META-INF/container.xml");
  }
  const xml = decodeUtf8(containerBytes);
  const m = xml.match(/<rootfile\b[^>]*>/i);
  if (!m) {
    throw new Error("EPUB: container.xml has no <rootfile>");
  }
  const path = attr(m[0], "full-path");
  if (!path) {
    throw new Error("EPUB: container.xml <rootfile> missing full-path");
  }
  return path;
}

function parseOpf(opfXml) {
  const metadataBlock = (() => {
    const m = opfXml.match(/<metadata\b[^>]*>([\s\S]*?)<\/metadata>/i);
    return m ? m[1] : "";
  })();
  const title = findFirstTagText(metadataBlock, "title");
  const author = findFirstTagText(metadataBlock, "creator");
  const language = findFirstTagText(metadataBlock, "language");

  // Manifest: id -> { href, mediaType, properties }
  const manifest = new Map();
  const manifestBlockMatch = opfXml.match(
    /<manifest\b[^>]*>([\s\S]*?)<\/manifest>/i,
  );
  if (!manifestBlockMatch) {
    throw new Error("EPUB: OPF missing <manifest>");
  }
  const itemRe = /<item\b[^>]*\/?>/gi;
  let im;
  while ((im = itemRe.exec(manifestBlockMatch[1])) !== null) {
    const id = attr(im[0], "id");
    const href = attr(im[0], "href");
    const mediaType = attr(im[0], "media-type");
    const properties = attr(im[0], "properties");
    if (id && href) {
      manifest.set(id, { id, href, mediaType, properties });
    }
  }

  // Spine: ordered list of idrefs
  const spineRefs = [];
  const spineBlockMatch = opfXml.match(/<spine\b[^>]*>([\s\S]*?)<\/spine>/i);
  if (!spineBlockMatch) {
    throw new Error("EPUB: OPF missing <spine>");
  }
  const spineAttrs = opfXml.match(/<spine\b[^>]*>/i)[0];
  const tocId = attr(spineAttrs, "toc");
  const itemrefRe = /<itemref\b[^>]*\/?>/gi;
  let sm;
  while ((sm = itemrefRe.exec(spineBlockMatch[1])) !== null) {
    const idref = attr(sm[0], "idref");
    if (idref) spineRefs.push(idref);
  }

  return {
    metadata: { title, author, language },
    manifest,
    spineRefs,
    tocId,
  };
}

function parseNavXhtml(xml) {
  // Look for <nav epub:type="toc"> ... <a href="...">title</a>
  // Build href -> title map
  const map = new Map();
  const navMatch = xml.match(
    /<nav\b[^>]*epub:type\s*=\s*("toc"|'toc')[^>]*>([\s\S]*?)<\/nav>/i,
  );
  const block = navMatch ? navMatch[2] : xml; // fallback: scan the whole doc
  const aRe = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = aRe.exec(block)) !== null) {
    const href = attr("<a " + m[1] + ">", "href");
    if (!href) continue;
    const text = decodeXmlEntities(m[2].replace(/<[^>]+>/g, "").trim());
    if (text) map.set(href, text);
  }
  return map;
}

function parseTocNcx(xml) {
  // <navMap><navPoint><navLabel><text>Title</text></navLabel><content src="..."/></navPoint>...
  const map = new Map();
  const pointRe = /<navPoint\b[^>]*>([\s\S]*?)<\/navPoint>/gi;
  let pm;
  while ((pm = pointRe.exec(xml)) !== null) {
    const inner = pm[1];
    const labelText = (() => {
      const lm = inner.match(/<navLabel\b[^>]*>([\s\S]*?)<\/navLabel>/i);
      if (!lm) return undefined;
      const tm = lm[1].match(/<text\b[^>]*>([\s\S]*?)<\/text>/i);
      return tm ? decodeXmlEntities(tm[1].trim()) : undefined;
    })();
    const contentMatch = inner.match(/<content\b[^>]*\/?>/i);
    const src = contentMatch ? attr(contentMatch[0], "src") : undefined;
    if (labelText && src) map.set(src, labelText);
  }
  return map;
}

/**
 * Parse an EPUB ArrayBuffer/Uint8Array into metadata + spine.
 * @param {ArrayBuffer | Uint8Array} arrayBuffer
 * @returns {{ metadata: { title?: string, author?: string, language?: string }, spine: Array<{ id: string, href: string, mediaType?: string, navTitle?: string }> }}
 */
export function parseEpub(arrayBuffer) {
  const entries = readEpubEntries(arrayBuffer);
  const opfPath = findContainerOpfPath(entries);
  const opfBytes = entries.get(opfPath);
  if (!opfBytes) {
    throw new Error(`EPUB: OPF not found at ${opfPath}`);
  }
  const opfXml = decodeUtf8(opfBytes);
  const { metadata, manifest, spineRefs, tocId } = parseOpf(opfXml);

  // Resolve nav titles. Prefer EPUB3 nav (manifest item with properties="nav"),
  // fall back to NCX referenced by spine[toc=...].
  const navItem = [...manifest.values()].find(
    (item) => item.properties && /\bnav\b/.test(item.properties),
  );

  let navTitleByHref = new Map();
  if (navItem) {
    const navPath = joinPath(opfPath, navItem.href);
    const navBytes = entries.get(navPath);
    if (navBytes) {
      const navXml = decodeUtf8(navBytes);
      const rel = parseNavXhtml(navXml);
      // Map nav-relative hrefs into OPF-relative hrefs
      for (const [href, title] of rel.entries()) {
        const navAbs = joinPath(navPath, href);
        // Convert back to OPF-relative for matching against manifest hrefs
        const opfDir = opfPath.includes("/")
          ? opfPath.replace(/\/[^/]*$/, "/")
          : "";
        const opfRel = navAbs.startsWith(opfDir)
          ? navAbs.slice(opfDir.length)
          : navAbs;
        navTitleByHref.set(opfRel, title);
      }
    }
  } else if (tocId && manifest.has(tocId)) {
    const ncxItem = manifest.get(tocId);
    const ncxPath = joinPath(opfPath, ncxItem.href);
    const ncxBytes = entries.get(ncxPath);
    if (ncxBytes) {
      const ncxXml = decodeUtf8(ncxBytes);
      const rel = parseTocNcx(ncxXml);
      for (const [href, title] of rel.entries()) {
        const abs = joinPath(ncxPath, href);
        const opfDir = opfPath.includes("/")
          ? opfPath.replace(/\/[^/]*$/, "/")
          : "";
        const opfRel = abs.startsWith(opfDir) ? abs.slice(opfDir.length) : abs;
        navTitleByHref.set(opfRel, title);
      }
    }
  }

  const spine = [];
  for (const idref of spineRefs) {
    const item = manifest.get(idref);
    if (!item) continue;
    // Strip fragment from href when looking up nav titles.
    const hrefNoFrag = item.href.replace(/#.*$/, "");
    const navTitle = navTitleByHref.get(hrefNoFrag);
    spine.push({
      id: item.id,
      href: item.href,
      mediaType: item.mediaType,
      ...(navTitle ? { navTitle } : {}),
    });
  }

  return { metadata, spine };
}
