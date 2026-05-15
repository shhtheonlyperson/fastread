#!/usr/bin/env bun
/**
 * Render the JustRead icon SVG to PNG at the Chrome MV3 sizes
 * (16 / 48 / 128) using a headless Chromium. Geometric design only —
 * no text, so it renders identically across systems regardless of
 * which fonts Chromium has cached locally.
 *
 * Run: `bun run scripts/build-icons.ts`
 * Output: public/icons/icon-{16,48,128}.png
 */
import { chromium } from '@playwright/test';
import { writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const OUT_DIR = resolve(ROOT, 'public', 'icons');

const SIZES = [16, 48, 128];

/** Design: a serif "JR" wordmark with the second letter recoloured to
 *  the RSVP-pivot terracotta. Wordmark > pictogram at 16px because the
 *  letters stay readable while a book/dot icon turns into mush. Cream
 *  rounded backdrop matches the reader's light-theme paper tone.
 *
 *  Smaller sizes drop the inner letter inset and use a fuller weight
 *  so the strokes don't dissolve. We render each size from its own
 *  SVG variant rather than scaling one master, since downsampling at
 *  16/48 always loses the pivot color contrast. */
function svgForSize(size: number): string {
  // Layout constants chosen empirically for clarity at each size.
  // - small (16, 32): single 'J' centered, full-bleed glyph
  // - medium (48): same 'J' with a small terracotta dot
  // - large (128): JR wordmark with terracotta R
  if (size <= 32) {
    return `<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
      <rect width="128" height="128" rx="22" fill="#f7f3e7"/>
      <path d="M 78 28
               L 78 86
               Q 78 104 60 104
               Q 42 104 38 86
               L 50 84
               Q 52 92 60 92
               Q 66 92 66 84
               L 66 28 Z"
            fill="#1a1a1a"/>
      <circle cx="92" cy="40" r="10" fill="#b4513a"/>
    </svg>`;
  }
  if (size <= 64) {
    return `<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
      <rect width="128" height="128" rx="26" fill="#f7f3e7"/>
      <path d="M 76 22
               L 76 84
               Q 76 104 56 104
               Q 36 104 30 84
               L 44 81
               Q 47 92 56 92
               Q 64 92 64 82
               L 64 22 Z"
            fill="#1a1a1a"/>
      <circle cx="96" cy="34" r="11" fill="#b4513a"/>
    </svg>`;
  }
  // 128 — full wordmark
  return `<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
    <rect width="128" height="128" rx="28" fill="#f7f3e7"/>
    <g font-family="Charter, 'Iowan Old Style', Georgia, 'Times New Roman', serif"
       font-weight="600" text-anchor="middle">
      <text x="44" y="92" font-size="84" fill="#1a1a1a">J</text>
      <text x="86" y="92" font-size="84" fill="#b4513a">R</text>
    </g>
  </svg>`;
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true });
  const browser = await chromium.launch();
  try {
    for (const size of SIZES) {
      const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
      const html = `<!doctype html><html><head><style>
        html, body { margin: 0; padding: 0; background: transparent; }
        svg { display: block; width: ${size}px; height: ${size}px; }
      </style></head><body>${svgForSize(size)}</body></html>`;
      await page.setContent(html);
      const buf = await page.screenshot({ omitBackground: true, type: 'png' });
      const out = resolve(OUT_DIR, `icon-${size}.png`);
      await writeFile(out, buf);
      console.log(`wrote ${out} (${buf.byteLength} bytes)`);
      await page.close();
    }
  } finally {
    await browser.close();
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
