#!/usr/bin/env bash
# Source-level guardrails for the native iOS app/core. Catches a small
# set of regression patterns that have bitten us before and that are
# cheaper to enforce as a grep than as a full XCTest.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_pattern() {
  local pattern="$1"
  local message="$2"
  shift 2

  if ! grep -ERq "$pattern" "$@"; then
    echo "$message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local message="$2"
  shift 2

  if grep -ERn "$pattern" "$@"; then
    echo "$message" >&2
    exit 1
  fi
}

# Ban surfaces and properties that historically caused render-loop or
# perf regressions on the reader screen.
reject_pattern "ReaderContextPreview|ContextTextPreview|SectionLabel\\(text: \"Context\"\\)|readerContext" \
  "READ context preview must stay removed from the reader." \
  FastReadApp/ReaderView.swift

reject_pattern "FullTextPreview|The full text|fullText|step:" \
  "Found a known perf-regression pattern in reader/settings UI." \
  FastReadApp/ReaderView.swift FastReadApp/SettingsView.swift

reject_pattern "Word typeface|WordTypeface|wordTypeface|wordFont|setWordFont" \
  "Word typeface settings must stay removed from the reader." \
  FastReadApp

# Library rows must keep trailing swipe-to-delete affordance.
require_pattern "\\.swipeActions\\(edge: \\.trailing" \
  "Library rows must support trailing swipe-to-delete." \
  FastReadApp/LibraryView.swift

# Ban synchronous HTML parsing on paste/load paths and computed token
# properties on ReadingArticle (both regressed reader startup latency
# in the past).
reject_pattern "NSAttributedString[[:space:]]*\\(data:" \
  "Do not reintroduce synchronous NSAttributedString HTML parsing on paste/load paths." \
  FastReadApp

# The non-optional `[String]` shape used to be the symptom of a computed
# property that re-tokenized on every access. The current persisted-tokens
# field is `[String]?` — stored, version-gated, and explicitly there to
# avoid that recomputation — so the regex skips the `?` form.
reject_pattern "RSVPEngine\\.tokenize\\(text\\)|var tokens: \\[String\\][^?]|var wordCount: Int \\{ tokens\\.count" \
  "ReadingArticle must not expose computed token/wordCount properties that tokenize on every access." \
  Sources/FastReadCore/ReadingArticle.swift

# The Sources/FastReadCore module is the cross-target shared core and
# must stay UIKit/SwiftUI free so the SwiftPM library remains macOS-
# importable for tests and headless tools.
reject_pattern "import (UIKit|SwiftUI|AppKit)" \
  "Sources/FastReadCore must stay framework-free; UI lives in FastReadApp/." \
  Sources/FastReadCore
