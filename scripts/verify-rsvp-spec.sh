#!/usr/bin/env bash
# Drift gate for the shared RSVP/ChunkShaper spec.
#
# Regenerates the per-platform constant modules from Tools/rsvp-spec.json and
# fails if the committed output differs — i.e. someone hand-edited a generated
# file or changed the spec without re-running the generator. This is what keeps
# the Swift / TypeScript / Kotlin copies from silently drifting apart again.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "[verify-rsvp-spec] node not on PATH; cannot run the generator." >&2
  exit 1
fi

GENERATED=(
  "Sources/FastReadCore/RSVPSpec.generated.swift"
  "chrome-ext/src/lib/rsvpSpec.generated.ts"
  "android-spike/app/src/main/java/com/shhtheonlyperson/fastread/spike/core/RsvpSpec.generated.kt"
)

node Tools/gen-rsvp-spec.mjs

if ! git diff --quiet -- "${GENERATED[@]}"; then
  echo "[verify-rsvp-spec] Generated RSVP spec files are out of date." >&2
  echo "[verify-rsvp-spec] Run 'node Tools/gen-rsvp-spec.mjs' and commit the result." >&2
  git --no-pager diff -- "${GENERATED[@]}" >&2 || true
  exit 1
fi

echo "[verify-rsvp-spec] ok — generated files match Tools/rsvp-spec.json"
