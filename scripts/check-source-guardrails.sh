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

reject_pattern "ReaderContextPreview|ContextTextPreview|SectionLabel\\(text: \"Context\"\\)|<SectionLabel>Context</SectionLabel>|readerContext" \
  "READ context previews must stay removed from native and Expo reader surfaces." \
  FastReadApp/ReaderView.swift components/fast-read-screen.jsx

reject_pattern "FullTextPreview|The full text|fullText|step:" \
  "Found a known perf-regression pattern in reader/settings UI." \
  FastReadApp/ReaderView.swift FastReadApp/SettingsView.swift components/fast-read-screen.jsx

reject_pattern "Word typeface|WordTypeface|wordTypeface|wordFont|setWordFont" \
  "Word typeface settings must stay removed from native and Expo reader surfaces." \
  FastReadApp components/fast-read-screen.jsx

reject_pattern "TextInput|smartInput|Paste or type" \
  "Expo Add screen must stay clipboard-only for the shipped TestFlight surface." \
  components/fast-read-screen.jsx

require_pattern "PanResponder\\.create" \
  "Expo range controls must track finger movement continuously instead of only applying on press release." \
  components/fast-read-screen.jsx

require_pattern "scrollEnabled=\\{!isRangeScrubbing\\}" \
  "Expo range controls must lock the vertical ScrollView while the user is scrubbing horizontally." \
  components/fast-read-screen.jsx

require_pattern "onStartShouldSetPanResponderCapture: \\(\\) => true" \
  "Expo range controls must capture scrubber touches before the parent ScrollView can steal the gesture." \
  components/fast-read-screen.jsx

require_pattern "gestureState\\?\\.moveX\\) && gestureState\\.moveX > 0" \
  "Expo scrubbers must ignore invalid initial PanResponder moveX=0 values so sliders do not snap while dragging." \
  components/fast-read-screen.jsx

require_pattern "GestureHandlerRootView" \
  "Expo root layout must wrap the app with GestureHandlerRootView so swipe actions work reliably." \
  app/_layout.jsx

require_pattern "<Swipeable" \
  "Expo Library rows must support trailing swipe-to-delete." \
  components/fast-read-screen.jsx

require_pattern "\\.swipeActions\\(edge: \\.trailing" \
  "Native SwiftUI Library rows must support trailing swipe-to-delete." \
  FastReadApp/LibraryView.swift

require_pattern "clipboardBeamActive" \
  "Expo paste button must keep a visibly stronger active beam while reading/fetching clipboard content." \
  components/fast-read-screen.jsx

require_pattern "duration: isBeamActive \\? 850 : 2500" \
  "Expo paste beam must speed up during active paste/fetch work." \
  components/fast-read-screen.jsx

require_pattern "rangeValueFromLocation" \
  "Range input coordinate mapping must stay covered by shared reader-core tests." \
  components/fast-read-screen.jsx src/reader-core.js test/reader-core.test.mjs

require_pattern "rangeValueFromPageX" \
  "Range inputs must use absolute page coordinates so nested thumb/fill touches do not snap values." \
  components/fast-read-screen.jsx src/reader-core.js test/reader-core.test.mjs

require_pattern "measureInWindow" \
  "Range inputs must measure the track bounds before mapping absolute touch coordinates." \
  components/fast-read-screen.jsx

require_pattern "ui\\.tabs\\?\\.\\[tab\\.id\\]" \
  "Tab labels must derive from the active locale so language changes update UI immediately." \
  components/fast-read-screen.jsx

require_pattern "pageHeadingCjk" \
  "Page titles must define CJK-specific metrics so Chinese ADD/Settings titles do not clip." \
  components/fast-read-screen.jsx

require_pattern "heroLineCjk" \
  "Library masthead must define CJK-specific metrics so Chinese headings do not clip." \
  components/fast-read-screen.jsx

require_pattern "nextArticleProgressState" \
  "Expo reader progress sync must stay idempotent so playback timers are not starved by render loops." \
  components/fast-read-screen.jsx src/reader-core.js

require_pattern "return didChange \\? nextItems : items" \
  "Expo reader progress sync must avoid library state writes when article progress is unchanged." \
  components/fast-read-screen.jsx

reject_pattern "\\[article, progress" \
  "Expo reader effects must not depend on the full article object; use stable article ids instead." \
  components/fast-read-screen.jsx

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
