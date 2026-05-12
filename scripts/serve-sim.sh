#!/usr/bin/env bash
set -euo pipefail

PORT="${SERVE_SIM_PORT:-3200}"
PACKAGE="${SERVE_SIM_PACKAGE:-serve-sim@0.1.23}"

usage() {
  cat <<'EOF'
Usage: scripts/serve-sim.sh [serve-sim args...]

Starts Evan Bacon's serve-sim preview for a booted Apple Simulator.

Defaults:
  SERVE_SIM_PORT=3200
  SERVE_SIM_PACKAGE=serve-sim@0.1.23

Examples:
  scripts/serve-sim.sh
  SERVE_SIM_PORT=3300 scripts/serve-sim.sh "iPhone 17 Pro"
  scripts/serve-sim.sh --detach --quiet
  scripts/serve-sim.sh --kill
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required. Install Xcode or Xcode Command Line Tools first." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js 18+ is required for serve-sim." >&2
  exit 1
fi

if [[ "${1:-}" != "--kill" && "${1:-}" != "--list" ]]; then
  if ! xcrun simctl list devices booted | grep -q "(Booted)"; then
    echo "No booted Apple Simulator found. Boot one in Xcode/Simulator, then rerun this action." >&2
    echo "Available runtimes:" >&2
    xcrun simctl list devices available | sed -n '1,80p' >&2
    exit 1
  fi
fi

exec npx --yes "$PACKAGE" -p "$PORT" "$@"
