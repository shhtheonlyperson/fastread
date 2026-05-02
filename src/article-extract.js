import { countReadingUnits } from "./reader-core.js";

const VOID_TAGS = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);

const ENTITY_MAP = {
  amp: "&",
  apos: "'",
  gt: ">",
  hellip: "...",
  ldquo: "\"",
  lsquo: "'",
  mdash: "-",
  nbsp: " ",
  ndash: "-",
  quot: "\"",
  rdquo: "\"",
  rsquo: "'",
  lt: "<",
};

export function extractArticle(html, sourceUrl = "") {
  const title = extractTitle(html);
  const jsonLdText = extractJsonLdText(html);
  const candidates = collectCandidates(html);

  if (jsonLdText) {
    candidates.push({
      source: "json-ld",
      priority: 90,
      text: normalizeText(jsonLdText),
    });
  }

  candidates.push({
    source: "body",
    priority: 0,
    text: htmlToText(extractElement(html, /<body\b[^>]*>/i) || html),
  });

  const best = candidates
    .map((candidate) => ({ ...candidate, score: scoreText(candidate.text) + (candidate.priority || 0) * 10000 }))
    .filter((candidate) => candidate.text && candidate.score > 0)
    .sort((a, b) => b.score - a.score)[0];

  return {
    title,
    url: sourceUrl,
    text: best?.text || "",
    wordCount: best ? countReadingUnits(best.text) : 0,
    source: best?.source || "none",
  };
}

export function htmlToText(html) {
  const withoutChrome = removeElementsByClass(
    String(html || ""),
    /\b(sharedaddy|sd-sharing-enabled|robots-nocontent|jp-relatedposts|jp-related-posts|post-navigation-link|wp-block-post-navigation-link)\b/i,
  );

  const cleaned = withoutChrome
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
    .replace(/<svg\b[\s\S]*?<\/svg>/gi, " ")
    .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<template\b[\s\S]*?<\/template>/gi, " ")
    .replace(/<iframe\b[\s\S]*?<\/iframe>/gi, " ")
    .replace(/<(nav|header|footer|aside|form)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<(h[1-6]|p|blockquote|li|figcaption|pre|tr|div|section|article)\b[^>]*>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(h[1-6]|p|blockquote|li|figcaption|pre|tr|div|section|article)>/gi, "\n")
    .replace(/<[^>]+>/g, " ");

  return normalizeText(decodeHtml(cleaned));
}

export function decodeHtml(value) {
  return String(value || "").replace(/&(#x?[0-9a-f]+|[a-z][a-z0-9]+);/gi, (entity, key) => {
    const normalized = key.toLowerCase();
    if (normalized.startsWith("#x")) {
      return fromCodePoint(Number.parseInt(normalized.slice(2), 16), entity);
    }
    if (normalized.startsWith("#")) {
      return fromCodePoint(Number.parseInt(normalized.slice(1), 10), entity);
    }
    return ENTITY_MAP[normalized] ?? entity;
  });
}

export function normalizeText(value) {
  return String(value || "")
    .replace(/\r/g, "\n")
    .replace(/[ \t\f\v]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function collectCandidates(html) {
  const selectors = [
    { source: "entry-content", pattern: /\b(entry-content|wp-block-post-content|post-content|article-content|article__content|article-body|story-body)\b/i },
    { source: "main", pattern: /\b(main-content|content-main|primary-content)\b/i },
  ];

  const candidates = [];

  selectors.forEach(({ source, pattern }) => {
    const block = extractElementByClass(html, pattern);
    if (block) {
      candidates.push({ source, priority: 80, text: htmlToText(block) });
    }
  });

  const article = extractElement(html, /<article\b[^>]*>/i);
  if (article) {
    candidates.push({ source: "article", priority: 60, text: htmlToText(article) });
  }

  const main = extractElement(html, /<main\b[^>]*>/i);
  if (main) {
    candidates.push({ source: "main-element", priority: 30, text: htmlToText(main) });
  }

  return candidates;
}

function extractTitle(html) {
  const metaTitle = matchAttribute(html, /<meta\b[^>]*(property|name)=["'](?:og:title|twitter:title)["'][^>]*>/i, "content");
  if (metaTitle) {
    return normalizeText(decodeHtml(metaTitle));
  }

  const titleMatch = String(html || "").match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  return titleMatch ? normalizeText(decodeHtml(titleMatch[1])) : "";
}

function extractJsonLdText(html) {
  const scripts = String(html || "").match(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) || [];

  for (const script of scripts) {
    const json = script.replace(/^<script\b[^>]*>/i, "").replace(/<\/script>$/i, "").trim();
    try {
      const value = findArticleText(JSON.parse(json));
      if (value && countReadingUnits(value) > 10) {
        return value;
      }
    } catch {
      // Ignore invalid publisher JSON-LD and keep using HTML candidates.
    }
  }

  return "";
}

function findArticleText(value) {
  if (!value) {
    return "";
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const text = findArticleText(item);
      if (text) {
        return text;
      }
    }
    return "";
  }

  if (typeof value === "object") {
    const type = String(value["@type"] || "").toLowerCase();
    if ((type.includes("article") || type.includes("posting")) && typeof value.articleBody === "string") {
      return value.articleBody;
    }

    for (const key of ["@graph", "mainEntity", "mainEntityOfPage", "text", "description"]) {
      if (value[key]) {
        const text = typeof value[key] === "string" ? value[key] : findArticleText(value[key]);
        if (text && countReadingUnits(text) > 10) {
          return text;
        }
      }
    }
  }

  return "";
}

function extractElementByClass(html, classPattern) {
  const tagRe = /<(article|main|section|div)\b[^>]*class=(["'])(.*?)\2[^>]*>/gis;
  let match;

  while ((match = tagRe.exec(String(html || "")))) {
    if (classPattern.test(match[3])) {
      return extractElement(html, new RegExp(escapeRegExp(match[0]), "i"), match.index);
    }
  }

  return "";
}

function removeElementsByClass(html, classPattern) {
  let source = String(html || "");

  for (let pass = 0; pass < 80; pass += 1) {
    const tagRe = /<(article|main|nav|section|aside|div|ul|ol)\b[^>]*class=(["'])(.*?)\2[^>]*>/gis;
    let match;
    let removed = false;

    while ((match = tagRe.exec(source))) {
      if (!classPattern.test(match[3])) {
        continue;
      }

      const block = extractElement(source, new RegExp(escapeRegExp(match[0]), "i"), match.index);
      if (!block) {
        continue;
      }

      source = `${source.slice(0, match.index)} ${source.slice(match.index + block.length)}`;
      removed = true;
      break;
    }

    if (!removed) {
      return source;
    }
  }

  return source;
}

function extractElement(html, startPattern, fromIndex = 0) {
  const source = String(html || "");
  const startRe = cloneRegex(startPattern);
  startRe.lastIndex = fromIndex;
  const start = startRe.exec(source);
  if (!start) {
    return "";
  }

  const startTag = start[0];
  const tagName = (startTag.match(/^<\s*([a-z][\w:-]*)/i) || [])[1]?.toLowerCase();
  if (!tagName || VOID_TAGS.has(tagName)) {
    return startTag;
  }

  let depth = 1;
  const tagRe = /<\/?([a-z][\w:-]*)\b[^>]*>/gi;
  tagRe.lastIndex = start.index + startTag.length;

  let tag;
  while ((tag = tagRe.exec(source))) {
    const name = tag[1].toLowerCase();
    if (name !== tagName) {
      continue;
    }

    const full = tag[0];
    if (full.startsWith("</")) {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start.index, tagRe.lastIndex);
      }
    } else if (!full.endsWith("/>")) {
      depth += 1;
    }
  }

  return source.slice(start.index);
}

function matchAttribute(html, tagPattern, attribute) {
  const tag = String(html || "").match(tagPattern)?.[0];
  if (!tag) {
    return "";
  }

  const attributeRe = new RegExp(`${attribute}=(["'])(.*?)\\1`, "i");
  return tag.match(attributeRe)?.[2] || "";
}

function scoreText(value) {
  const readingUnits = countReadingUnits(value);
  if (readingUnits < 20) {
    return 0;
  }

  const paragraphs = String(value || "").split(/\n{2,}/).filter((paragraph) => countReadingUnits(paragraph) > 8).length;
  return readingUnits + paragraphs * 25;
}

function cloneRegex(pattern) {
  return new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function fromCodePoint(codePoint, fallback) {
  if (!Number.isFinite(codePoint)) {
    return fallback;
  }

  const asciiTypography = {
    0x2018: "'",
    0x2019: "'",
    0x201c: "\"",
    0x201d: "\"",
    0x2013: "-",
    0x2014: "-",
    0x2026: "...",
  };

  if (asciiTypography[codePoint]) {
    return asciiTypography[codePoint];
  }

  try {
    return String.fromCodePoint(codePoint);
  } catch {
    return fallback;
  }
}
