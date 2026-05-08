import { lookup } from "node:dns/promises";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { extractArticle } from "./src/article-extract.js";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 4173);
const MAX_HTML_BYTES = 6 * 1024 * 1024;

const MIME = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

const server = createServer(async (req, res) => {
  try {
    const requestUrl = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);

    if (requestUrl.pathname === "/api/extract") {
      await handleExtract(requestUrl, res);
      return;
    }

    if (requestUrl.pathname === "/api/raw") {
      await handleRaw(requestUrl, res);
      return;
    }

    await serveStatic(requestUrl.pathname, res);
  } catch (error) {
    sendJson(res, 500, { error: error.message || "Unexpected server error" });
  }
});

server.listen(PORT, () => {
  console.log(`FastRead running at http://127.0.0.1:${PORT}`);
});

async function handleExtract(requestUrl, res) {
  const target = requestUrl.searchParams.get("url") || "";
  const validated = await validateFetchUrl(target);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch(validated.href, {
      headers: {
        accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2",
        "user-agent": "Mozilla/5.0 FastRead local reader",
      },
      redirect: "follow",
      signal: controller.signal,
    });

    if (!response.ok) {
      sendJson(res, 502, { error: `Fetch failed with HTTP ${response.status}` });
      return;
    }

    const length = Number(response.headers.get("content-length") || 0);
    if (length > MAX_HTML_BYTES) {
      sendJson(res, 413, { error: "Page is too large to extract" });
      return;
    }

    const contentType = response.headers.get("content-type") || "";
    if (!/text\/html|application\/xhtml\+xml|text\/plain/i.test(contentType)) {
      sendJson(res, 415, { error: `Unsupported content type: ${contentType || "unknown"}` });
      return;
    }

    const html = await response.text();
    if (Buffer.byteLength(html, "utf8") > MAX_HTML_BYTES) {
      sendJson(res, 413, { error: "Page is too large to extract" });
      return;
    }

    const article = extractArticle(html, response.url || validated.href);
    if (!article.text || article.wordCount < 20) {
      sendJson(res, 422, { error: "Could not find enough readable text on that page" });
      return;
    }

    sendJson(res, 200, article);
  } catch (error) {
    sendJson(res, 502, { error: error.name === "AbortError" ? "Fetch timed out" : error.message });
  } finally {
    clearTimeout(timeout);
  }
}

async function handleRaw(requestUrl, res) {
  const target = requestUrl.searchParams.get("url") || "";
  const validated = await validateFetchUrl(target);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch(validated.href, {
      headers: {
        accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2",
        "user-agent": "Mozilla/5.0 FastRead local reader",
      },
      redirect: "follow",
      signal: controller.signal,
    });

    if (!response.ok) {
      sendJson(res, 502, { error: `Fetch failed with HTTP ${response.status}` });
      return;
    }

    const contentType = response.headers.get("content-type") || "text/html; charset=utf-8";
    const length = Number(response.headers.get("content-length") || 0);
    if (length > MAX_HTML_BYTES) {
      sendJson(res, 413, { error: "Page is too large to extract" });
      return;
    }
    if (!/text\/html|application\/xhtml\+xml|text\/plain/i.test(contentType)) {
      sendJson(res, 415, { error: `Unsupported content type: ${contentType}` });
      return;
    }

    const html = await response.text();
    if (Buffer.byteLength(html, "utf8") > MAX_HTML_BYTES) {
      sendJson(res, 413, { error: "Page is too large to extract" });
      return;
    }

    const body = Buffer.from(html, "utf8");
    res.writeHead(200, {
      "content-type": contentType,
      "content-length": body.byteLength,
      "x-final-url": response.url || validated.href,
    });
    res.end(body);
  } catch (error) {
    sendJson(res, 502, { error: error.name === "AbortError" ? "Fetch timed out" : error.message });
  } finally {
    clearTimeout(timeout);
  }
}

async function validateFetchUrl(value) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error("Enter a valid URL");
  }

  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error("Only http and https URLs are supported");
  }

  if (isBlockedHost(parsed.hostname)) {
    throw new Error("Local and private network URLs are blocked");
  }

  const records = await lookup(parsed.hostname, { all: true, verbatim: true });
  if (!records.length || records.some((record) => isPrivateAddress(record.address))) {
    throw new Error("Local and private network URLs are blocked");
  }

  return parsed;
}

function isBlockedHost(hostname) {
  const host = hostname.toLowerCase().replace(/\.$/, "");
  return host === "localhost" || host.endsWith(".localhost") || isPrivateAddress(host);
}

function isPrivateAddress(address) {
  const ipVersion = net.isIP(address);
  if (!ipVersion) {
    return false;
  }

  if (ipVersion === 4) {
    const [a, b] = address.split(".").map(Number);
    return (
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      a >= 224
    );
  }

  const normalized = address.toLowerCase();
  return normalized === "::1" || normalized.startsWith("fc") || normalized.startsWith("fd") || normalized.startsWith("fe80:");
}

async function serveStatic(requestPath, res) {
  const cleanPath = decodeURIComponent(requestPath.split("?")[0] || "/");
  const filePath = path.normalize(path.join(ROOT, cleanPath === "/" ? "index.html" : cleanPath));

  if (!filePath.startsWith(ROOT)) {
    sendText(res, 403, "Forbidden");
    return;
  }

  try {
    const info = await stat(filePath);
    if (!info.isFile()) {
      sendText(res, 404, "Not found");
      return;
    }

    res.writeHead(200, {
      "content-type": MIME[path.extname(filePath)] || "application/octet-stream",
      "content-length": info.size,
    });
    createReadStream(filePath).pipe(res);
  } catch {
    sendText(res, 404, "Not found");
  }
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function sendText(res, status, body) {
  res.writeHead(status, {
    "content-type": "text/plain; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}
