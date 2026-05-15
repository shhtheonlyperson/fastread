#!/usr/bin/env bash
# Verifier for the JustRead Chrome extension at chrome-ext/.
#
# Runs (in order):
#   1. tsgo --noEmit (typecheck)
#   2. vitest run     (lib unit tests + ChunkShaper parity)
#   3. e2e Playwright suite, optional — only when ENABLED=1 and the
#      chromium runtime is already cached, so pre-commit stays fast.
#
# The script SKIPS itself (with a clear log line) if:
#   - chrome-ext/ is not present in this checkout (pre-existing branches
#     or future repo splits),
#   - `bun` is not on PATH (install hint printed).
#
# Skip the whole thing by exporting FASTREAD_SKIP_CHROME_EXT=1.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${FASTREAD_SKIP_CHROME_EXT:-0}" = "1" ]; then
  echo "[verify-chrome-ext] skipped (FASTREAD_SKIP_CHROME_EXT=1)."
  exit 0
fi

if [ ! -d "$ROOT_DIR/chrome-ext" ]; then
  echo "[verify-chrome-ext] no chrome-ext/ directory — skipping."
  exit 0
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "[verify-chrome-ext] bun not on PATH — install with: curl -fsSL https://bun.sh/install | bash" >&2
  echo "[verify-chrome-ext] skipping until bun is installed." >&2
  exit 0
fi

cd "$ROOT_DIR/chrome-ext"

# Reproducible install: lockfile must match. On a fresh checkout bun
# resolves anyway; on subsequent runs this is a no-op when node_modules
# is already in sync.
if [ ! -d node_modules ]; then
  echo "[verify-chrome-ext] installing deps…"
  bun install --frozen-lockfile >/dev/null
fi

echo "[verify-chrome-ext] typecheck"
bun run typecheck

echo "[verify-chrome-ext] vitest"
bun run test

# Optional e2e — guarded so the default pre-push doesn't try to download
# a Chromium binary on first run. Enable explicitly when you want the
# full integration sweep:
#   FASTREAD_E2E_CHROME_EXT=1 .githooks/pre-push
if [ "${FASTREAD_E2E_CHROME_EXT:-0}" = "1" ]; then
  echo "[verify-chrome-ext] e2e (Playwright)"
  bun run e2e
fi

echo "[verify-chrome-ext] ok"
