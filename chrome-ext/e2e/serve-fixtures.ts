#!/usr/bin/env bun
/**
 * Tiny static file server for the e2e suite. Only used by Playwright's
 * webServer hook to expose chrome-ext/test/fixtures/ over loopback HTTP
 * (Chrome content_scripts don't inject into file:// URLs unless the
 * user explicitly grants the extension file-URL access, which we can't
 * automate in a clean profile).
 */
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, '..', 'test', 'fixtures');

const port = Number(process.argv[2] ?? 4319);

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
  // Strip leading slash + any query/hash, prevent path traversal.
  const rel = url.pathname.replace(/^\/+/, '').replace(/\.\.+/g, '');
  const path = resolve(FIXTURES, rel || 'mullvad.html');
  if (!path.startsWith(FIXTURES)) { res.writeHead(403).end(); return; }
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'content-type': MIME[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`fixtures @ http://127.0.0.1:${port}`);
});
