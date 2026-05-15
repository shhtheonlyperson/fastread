#!/usr/bin/env bun
/**
 * Capture Chrome Web Store submission screenshots against the local
 * HTML fixtures, using the same persistent-context launch the e2e
 * suite uses. Output: chrome-ext/store-assets/screenshots/*.png at
 * 1280x800 (the Web Store's recommended hero size).
 *
 * Coverage:
 *   01-reader-light   — Mullvad article in reader, light theme, serif
 *   02-reader-dark    — same article in dark theme
 *   03-fastread       — fast-read overlay mid-flash with ORP pivot
 *   04-options        — settings page (theme/font/wpm/chunk size/lang)
 *
 * Run: `bun run capture` (alias of `bun run scripts/capture-screenshots.ts`)
 * Requires: dist/ built, fixtures present, Playwright chromium installed.
 */
import { chromium, type BrowserContext, type Page } from '@playwright/test';
import { existsSync, mkdtempSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const EXT_PATH = resolve(ROOT, 'dist');
const FIXTURES = resolve(ROOT, 'test', 'fixtures');
const OUT_DIR = resolve(ROOT, 'store-assets', 'screenshots');
const PORT = Number(process.env.SHOT_PORT ?? 4320);
const BASE = `http://127.0.0.1:${PORT}`;

const VIEWPORT = { width: 1280, height: 800 };

async function main() {
  if (!existsSync(EXT_PATH)) {
    console.error(`No build at ${EXT_PATH}. Run \`bun run build\` first.`);
    process.exit(1);
  }
  await mkdir(OUT_DIR, { recursive: true });

  // Start the fixture server.
  const server = spawn('bun', ['run', resolve(__dirname, '..', 'e2e', 'serve-fixtures.ts'), String(PORT)], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  await waitForServer(BASE);

  const userDataDir = mkdtempSync(`${tmpdir()}/jr-shot-`);
  const ctx = await chromium.launchPersistentContext(userDataDir, {
    channel: 'chromium',
    headless: true,
    viewport: VIEWPORT,
    args: [
      `--disable-extensions-except=${EXT_PATH}`,
      `--load-extension=${EXT_PATH}`,
      '--no-first-run',
      '--no-default-browser-check',
      `--window-size=${VIEWPORT.width},${VIEWPORT.height}`,
    ],
  });
  // MV3 service worker must be alive before content scripts inject.
  if (ctx.serviceWorkers().length === 0) {
    await ctx.waitForEvent('serviceworker', { timeout: 10_000 });
  }

  try {
    await captureReaderShots(ctx);
    await captureOptionsShot(ctx);
    console.log(`\nDone. ${OUT_DIR}`);
  } finally {
    await ctx.close();
    server.kill();
  }
}

async function captureReaderShots(ctx: BrowserContext) {
  const page = await ctx.newPage();
  await page.setViewportSize(VIEWPORT);
  await page.goto(`${BASE}/mullvad.html`);
  await page.locator('body').click();

  // Light theme is the default. Mount reader.
  await page.keyboard.press('KeyF');
  await waitForShadow(page);
  // Let fonts settle.
  await page.waitForTimeout(400);
  await shot(page, '01-reader-light');

  // Switch to dark via the toolbar toggle in the shadow root.
  await page.evaluate(() => {
    const host = document.getElementById('__justread_host__');
    const btn = host?.shadowRoot?.querySelector<HTMLButtonElement>(
      // The theme toggle is the moon/sun icon button; in light mode it
      // shows the moon icon and clicking switches to dark.
      '.jr-toolbar [aria-label="Dark"], .jr-toolbar [aria-label="dark"], .jr-toolbar [aria-label="深色"]',
    );
    btn?.click();
  });
  await page.waitForTimeout(300);
  await shot(page, '02-reader-dark');

  // Switch back to light, then enter fast-read for shot 3.
  await page.evaluate(() => {
    const host = document.getElementById('__justread_host__');
    const btn = host?.shadowRoot?.querySelector<HTMLButtonElement>(
      '.jr-toolbar [aria-label="Light"], .jr-toolbar [aria-label="light"], .jr-toolbar [aria-label="淺色"]',
    );
    btn?.click();
  });
  await page.waitForTimeout(200);
  await page.keyboard.press('Shift+KeyF');
  await page.waitForFunction(() => {
    const host = document.getElementById('__justread_host__');
    const w = host?.shadowRoot?.querySelector('.jr-fr-word');
    return !!w && (w as HTMLElement).innerText.length > 0;
  }, null, { timeout: 5_000 });
  // Advance to a multi-character word so the ORP pivot is visible.
  for (let i = 0; i < 5; i++) {
    await page.keyboard.press('KeyL');
    await page.waitForTimeout(40);
  }
  await page.waitForTimeout(200);
  await shot(page, '03-fastread');
  await page.close();
}

async function captureOptionsShot(ctx: BrowserContext) {
  const [sw] = ctx.serviceWorkers();
  const extId = sw ? new URL(sw.url()).host : null;
  if (!extId) throw new Error('cannot resolve extension id');
  const page = await ctx.newPage();
  await page.setViewportSize(VIEWPORT);
  await page.goto(`chrome-extension://${extId}/src/options/index.html`);
  await page.waitForTimeout(800);
  await shot(page, '04-options');
  await page.close();
}

async function shot(page: Page, name: string) {
  const path = resolve(OUT_DIR, `${name}.png`);
  await page.screenshot({ path, fullPage: false });
  console.log(`  ${name}.png`);
}

async function waitForShadow(page: Page) {
  await page.waitForFunction(
    () => !!document.getElementById('__justread_host__')?.shadowRoot?.querySelector('.jr-article-title'),
    null,
    { timeout: 8_000 },
  );
}

async function waitForServer(url: string) {
  for (let i = 0; i < 30; i++) {
    try {
      const res = await fetch(`${url}/mullvad.html`);
      if (res.ok) return;
    } catch { /* not up yet */ }
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error(`fixture server never responded at ${url}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
