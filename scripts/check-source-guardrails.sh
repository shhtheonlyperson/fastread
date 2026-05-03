#!/usr/bin/env bash
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

require_pattern "RSVPEngine\\.contextWindow" \
  "ReaderView must use RSVPEngine.contextWindow so READ context stays bounded." \
  FastReadApp/ReaderView.swift

reject_pattern "FullTextPreview|The full text|step:" \
  "Found a known perf-regression pattern in reader/settings UI." \
  FastReadApp/ReaderView.swift FastReadApp/SettingsView.swift

reject_pattern "NSAttributedString[[:space:]]*\\(data:" \
  "Do not reintroduce synchronous NSAttributedString HTML parsing on paste/load paths." \
  FastReadApp

reject_pattern "RSVPEngine\\.tokenize\\(text\\)|var tokens: \\[String\\]|var wordCount: Int \\{ tokens\\.count" \
  "ReadingArticle must not expose computed token/wordCount properties that tokenize on every access." \
  FastReadApp/Models.swift

require_pattern "contextWindow\\(tokens\\.length, index\\)" \
  "Web renderPreview must use contextWindow so previews stay bounded." \
  src/app.js

if ! perl -0ne 'exit(/function renderPreview\(\) \{[\s\S]*?tokens\.slice\(window\.lowerBound, window\.upperBound\)/ ? 0 : 1)' src/app.js; then
  echo "Web renderPreview must slice the bounded context window instead of iterating every token." >&2
  exit 1
fi
