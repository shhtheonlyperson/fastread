/**
 * End-to-end test for the JustRead Chrome extension. Loads the built
 * extension at chrome-ext/dist into a real Chromium via a persistent
 * context (Manifest V3 only loads via --load-extension; the default
 * browser fixture won't do), navigates to local HTML fixtures, drives
 * the actual user flows, and asserts the Shadow-DOM overlay, RSVP
 * rendering, and keyboard shortcuts behave end-to-end.
 *
 * Why this exists: unit tests cover lib/ thoroughly but never exercise
 * the manifest, content-script injection, popup → background → content
 * messaging, or the runtime interactions between scripts. Every bug
 * earlier in this branch's history (Page-not-ready, Inject-failed,
 * Substack-content-not-found, stale-manifest hashes) would slip past
 * the unit suite. This spec catches those.
 *
 * Run: `bun run e2e` (or `pnpm exec playwright test` / direct CLI).
 * Skipped automatically by scripts/verify-chrome-ext.sh unless
 * FASTREAD_E2E_CHROME_EXT=1, since it needs the Chromium binary cache.
 */
import { test, expect, chromium, type BrowserContext, type Page } from '@playwright/test';
import { existsSync, mkdtempSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { FIXTURE_BASE_URL } from '../playwright.config';

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXT_PATH = resolve(__dirname, '..', 'dist');

function fixtureUrl(name: string): string {
  return `${FIXTURE_BASE_URL}/${name}`;
}

async function launchWithExtension(): Promise<BrowserContext> {
  if (!existsSync(EXT_PATH)) {
    throw new Error(`Built extension not found at ${EXT_PATH}. Run \`bun run build\` first.`);
  }
  const userDataDir = mkdtempSync(`${tmpdir()}/jr-e2e-`);
  const ctx = await chromium.launchPersistentContext(userDataDir, {
    // `headless: 'chrome'` uses the new headless mode that actually loads
    // MV3 extensions. The default `headless: true` is the older headless
    // shell that silently skips --load-extension on some Chromium builds.
    channel: 'chromium',
    headless: true,
    args: [
      `--disable-extensions-except=${EXT_PATH}`,
      `--load-extension=${EXT_PATH}`,
      '--no-first-run',
      '--no-default-browser-check',
    ],
  });

  // Wait for the MV3 service worker so the content_script registration
  // is live before we try to navigate. Otherwise the first page.goto can
  // beat the worker boot and the content script never injects.
  let workers = ctx.serviceWorkers();
  if (workers.length === 0) {
    workers = [await ctx.waitForEvent('serviceworker', { timeout: 10_000 })];
  }
  // Sanity: the worker URL points into our extension.
  if (!workers.some(w => w.url().startsWith('chrome-extension://'))) {
    throw new Error(`extension service worker did not register (saw: ${workers.map(w => w.url()).join(', ')})`);
  }
  return ctx;
}

/** Wait until the JustRead Shadow-DOM host element appears on the page. */
async function expectOverlayMounted(page: Page) {
  await page.waitForFunction(
    () => document.getElementById('__justread_host__') !== null,
    null,
    { timeout: 8_000 },
  );
}

/** Read text out of the shadow root (Playwright's `getByText` can't
 *  cross shadow boundaries by selector alone — go through evaluate). */
async function shadowText(page: Page, selector: string): Promise<string> {
  return page.evaluate((sel) => {
    const host = document.getElementById('__justread_host__');
    if (!host?.shadowRoot) return '';
    const el = host.shadowRoot.querySelector(sel);
    return (el as HTMLElement | null)?.innerText ?? '';
  }, selector);
}

async function shadowExists(page: Page, selector: string): Promise<boolean> {
  return page.evaluate((sel) => {
    const host = document.getElementById('__justread_host__');
    return !!host?.shadowRoot?.querySelector(sel);
  }, selector);
}

test.describe('JustRead extension @ Mullvad (long technical article)', () => {
  let ctx: BrowserContext;
  let page: Page;

  test.beforeAll(async () => {
    ctx = await launchWithExtension();
    page = await ctx.newPage();
    await page.goto(fixtureUrl('mullvad.html'));
    // The content script registers an onMessage listener AND a global
    // keydown handler. Press 'f' to open the reader — the page itself
    // has no focused input so the handler fires.
    await page.locator('body').click();
  });

  test.afterAll(async () => {
    await ctx?.close();
  });

  test('press F → reader overlay mounts in Shadow DOM with the article title', async () => {
    await page.keyboard.press('KeyF');
    await expectOverlayMounted(page);
    const title = await shadowText(page, '.jr-article-title');
    expect(title.toLowerCase()).toContain('mullvad');
    // Reader article body picked up something meaningful.
    const body = await shadowText(page, '.jr-content');
    expect(body.length).toBeGreaterThan(200);
  });

  test('Shift+F → Fast Read mode renders an ORP-pivoted word', async () => {
    // Reader is still open from previous test (beforeAll context).
    await page.keyboard.press('Shift+KeyF');
    await page.waitForFunction(() => {
      const host = document.getElementById('__justread_host__');
      const w = host?.shadowRoot?.querySelector('.jr-fr-word');
      return !!w && (w as HTMLElement).innerText.length > 0;
    }, null, { timeout: 5_000 });
    const word = await shadowText(page, '.jr-fr-word');
    expect(word.trim().length).toBeGreaterThan(0);
    const pivotPresent = await shadowExists(page, '.jr-fr-pivot');
    expect(pivotPresent).toBe(true);
  });

  test('keyboard: j slows the cadence, k speeds it back up', async () => {
    // chrome.storage.* is only available to extension contexts. The
    // service worker is the cheapest one to evaluate against.
    const [sw] = ctx.serviceWorkers();
    if (!sw) throw new Error('no extension service worker available');
    const readWpm = () => sw.evaluate(() => new Promise<number>((res) => {
      chrome.storage.sync.get({ wpm: 900 }, (v) => res(v.wpm as number));
    }));
    const waitForWpm = async (target: number) => {
      for (let i = 0; i < 30; i++) {
        if (await readWpm() === target) return;
        await new Promise(r => setTimeout(r, 80));
      }
      throw new Error(`wpm never reached ${target} (current: ${await readWpm()})`);
    };

    const startWpm = await readWpm();
    // Press j → wait → press j again. Pressing twice back-to-back loses
    // the second event because the keydown effect re-installs on each
    // state change and a fast second press can land in the gap.
    await page.keyboard.press('KeyJ');
    await waitForWpm(startWpm - 25);
    await page.keyboard.press('KeyJ');
    await waitForWpm(startWpm - 50);
    await page.keyboard.press('KeyK');
    await waitForWpm(startWpm - 25);
  });

  test('Esc returns from fastread to reader, second Esc unmounts', async () => {
    // Currently in fastread.
    await page.keyboard.press('Escape');
    // Back to reader; the article title should be visible again.
    await page.waitForFunction(() => {
      const host = document.getElementById('__justread_host__');
      return !!host?.shadowRoot?.querySelector('.jr-article-title');
    }, null, { timeout: 5_000 });

    await page.keyboard.press('Escape');
    await page.waitForFunction(() => document.getElementById('__justread_host__') === null, null, { timeout: 5_000 });
    const stillMounted = await page.evaluate(() => !!document.getElementById('__justread_host__'));
    expect(stillMounted).toBe(false);
  });
});

test.describe('JustRead extension @ Substack-style note (short / SPA-shaped)', () => {
  let ctx: BrowserContext;

  test.beforeAll(async () => { ctx = await launchWithExtension(); });
  test.afterAll(async () => { await ctx?.close(); });

  test('fallback ProseMirror extractor picks up the note body', async () => {
    const page = await ctx.newPage();
    await page.goto(fixtureUrl('substack-note.html'));
    await page.locator('body').click();
    await page.keyboard.press('KeyF');
    await expectOverlayMounted(page);
    const body = await shadowText(page, '.jr-content');
    // The fixture's note copy starts with "Recently, I've started"; make
    // sure that prose ended up in the reader (i.e. the fallback path
    // selected ProseMirror, not the nav).
    expect(body).toContain('Recently');
    expect(body).not.toContain('Subscriptions'); // nav shouldn't bleed in
  });
});
