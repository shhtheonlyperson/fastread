import { defineConfig } from '@playwright/test';

const FIXTURE_PORT = Number(process.env.FASTREAD_E2E_PORT ?? 4319);
export const FIXTURE_BASE_URL = `http://127.0.0.1:${FIXTURE_PORT}`;

/**
 * Playwright config for extension e2e. The extension itself is loaded
 * per-test via chromium.launchPersistentContext (Manifest V3 doesn't
 * play nicely with the default browser fixture), so this config is
 * mostly conventions: where the specs live and how reports look.
 */
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,             // extension setup is heavy; serial is fine for 1 spec.
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  // Chrome content_scripts don't inject into file:// URLs without
  // explicit per-extension permission. Serve the fixtures over loopback
  // HTTP so the extension matches them under <all_urls>.
  webServer: {
    command: `bun run e2e/serve-fixtures.ts ${FIXTURE_PORT}`,
    url: FIXTURE_BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 10_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
