# Code quality and test plan

This repo has three active runtime surfaces: native iOS, native Android, and the Chrome extension. Treat a fix as incomplete until the affected surface is covered by the matching verifier.

## Required local checks

```bash
scripts/check-source-guardrails.sh
swift test
scripts/verify-chrome-ext.sh
scripts/verify-android.sh
```

Use `scripts/verify-ios-performance.sh` before pushing iOS reader/performance changes. It also runs simulator/UI flows when the local fixture/tooling is available.

## CI matrix

`.github/workflows/verify.yml` runs:

- iOS/core: source guardrails, `swift test`, core verifier, performance verifier, unsigned Release iOS build
- Chrome extension: Bun install, typecheck, Vitest
- Android: Gradle `:app:testDebugUnitTest` on JDK 21

Known gap: Android tokenizer parity is still ignored on desktop JVM because Android's ICU tokenizer differs from `java.text.BreakIterator`. Move that parity corpus test into `androidTest` before treating Android tokenizer parity as fully gated.

## Current coverage priorities

1. `ReadingStore.swift`: playback timing is now in `PlaybackTiming`; keep adding state-machine tests around stats, selection, persistence, and cache invalidation before deeper store refactors.
2. `UrlIngest.swift`: keep stubbed URLSession tests for redirects, content-type handling, encodings, and size/time failures.
3. `chrome-ext/src/content/*`: `ReaderOverlay` now has a rendered-shell unit smoke test. Keep expanding coverage around `FastReadPanel` playback controls and content-script wiring.
4. Android instrumentation: `MainActivity.kt` has been reduced to routing, but tokenizer parity still needs device/instrumented coverage because JVM `BreakIterator` differs from Android ICU.

## Refactor order

Completed in the current cleanup pass:

1. Extracted `ReadingStore` playback timing into `PlaybackTiming` with direct unit coverage.
2. Split `ReaderView.swift` into stage, pace, contents drawer, and focus-mode files.
3. Split `AddSourceView.swift` into clipboard, EPUB picker, recent-source list, and local EPUB files.
4. Promoted Android reader state, EPUB import, local EPUB discovery, and Compose screens into dedicated modules.

Remaining quality work:

1. Add a clock-injected playback controller if `ReadingStore` needs deterministic timer/stat integration tests beyond `PlaybackTiming`.
2. Move Android tokenizer parity into `androidTest` and run it on an emulator/device.
3. Expand Chrome rendered-shell tests beyond the current `ReaderOverlay` smoke path into `FastReadPanel` playback and content-script injection behavior.

## Tokenizer port decision

Keep the Swift, Kotlin, and TypeScript tokenizer ports manual for now, with stronger parity gates. A generated/shared tokenizer core would reduce drift, but it would also introduce KMP/build-tooling churn before the Android app has full instrumentation and before the Chrome extension path is settled. Revisit a shared/generated core only after Android ICU parity is gated in `androidTest` and content-script tests cover the extension reader shell.
