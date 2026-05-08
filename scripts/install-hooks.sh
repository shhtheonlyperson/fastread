#!/usr/bin/env bash
# Wires the tracked .githooks/ scripts into .git/hooks/ for this clone.
# Idempotent — re-run after a fresh clone or after pulling a hook
# update.
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

# Make tracked hooks executable in case the file mode is missing.
chmod +x .githooks/*

# Tell git to use the tracked directory directly. core.hooksPath is a
# relative-path-friendly mechanism that survives across worktrees and
# does not require copying files.
git config core.hooksPath .githooks

echo "Installed hooks from .githooks/:"
ls -1 .githooks
echo "Active hooks path: $(git config --get core.hooksPath)"
