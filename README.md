# JustRead

Local RSVP speed reader across three shipped surfaces:

- Native iOS app in `FastReadApp/` plus shared Swift core in `Sources/FastReadCore/`
- Native Android project in `android-spike/`
- Chrome extension companion in `chrome-ext/`

The core reader imports EPUBs, plain text, and fetched HTML, splits each word/chunk at the optimal recognition point, and plays them back at a tunable WPM with optional punctuation pauses.

## Run iOS

```bash
open FastRead.xcodeproj
```

In Xcode, select scheme **FastRead**, target an iPhone simulator or device, and run. The app target is `JustRead`. It bundles Fraunces / Inter / JetBrains Mono, app icons, persisted reader settings, and registers `org.idpf.epub-container` so EPUBs from any other app can be opened directly into the library.

## Run Android

```bash
scripts/verify-android.sh
cd android-spike
./gradlew :app:assembleDebug
```

The Android app is a native Compose project. It is still intentionally named `android-spike/` because the package/source layout has not yet been promoted into a shared KMP module. Treat it as a first-class release surface, but do not assume feature parity unless the relevant Android verifier or Maestro flow has run.

## Run Chrome Extension

```bash
cd chrome-ext
bun install --frozen-lockfile
bun run build
```

For local development, use `bun run dev`. For Web Store packaging, use `bun run zip` and follow `chrome-ext/CHROME_WEB_STORE.md`.

## Reader pipeline

```
EPUB / .txt / fetched HTML
         │
         ▼
ImporterRegistry  ──►  Document { sections[] }
         │
         ▼
Document.flattenText  ──►  RSVPEngine.tokenize  ──►  RSVP loop (Timer + SwiftUI)
```

The shared core lives in `Sources/FastReadCore/` (a SwiftPM library) and is compiled into both the iOS app target and the test target.

## Tests

```bash
swift test
scripts/verify-chrome-ext.sh
scripts/verify-android.sh
```

Current fast local coverage:

- SwiftPM core: 100 tests, with the external EPUB corpus gated behind env vars
- Chrome extension: typecheck plus 103 Vitest tests
- Android: Gradle JVM unit-test task; current JVM coverage exercises reader playback state and EPUB text extraction, while tokenizer parity remains ignored until it moves to Android instrumentation

SwiftPM suite coverage:

| Suite | What it checks |
| --- | --- |
| `RSVPEngineTests` | tokenize, focus splits, durations, CJK math |
| `DocumentTests` | sections, boundaries, `detectFrontMatter` |
| `ImportersTests` | PlainText + Html adapters via the registry |
| `EpubImporterTests` | OPF / spine / nav.xhtml / NCX parsing |
| `EpubErrorPathsTests` | non-zip / no-container / no-OPF / empty-spine refusals |
| `EpubRegistryFlowTests` | registry → Document round trip |
| `HtmlGoldenTests` | 6 frozen HTML/text fixtures, regression-locked |
| `ReadingStoreTests` | library lifecycle, jump/scrub/play/pause, settings + article persistence |
| `EpubE2ETests` | gated end-to-end run against a local EPUB provided through `FASTREAD_E2E_EPUB` or `test.epub` |
| `UrlIngestTests` | stubbed `URLProtocol` for fetch errors |
| `StorageMigrationTests` | v1 (text-only) → v2 (Document) round trip |
| `ReadingArticleCodableTests` | persistence shape stable |
| `ParityTests` | parity corpus (kept for fixture stability) |
| `EpubCorpusTests` | gated walker over a real EPUB library |

A separate XCUITest target lives outside the SwiftPM package and runs against the simulator:

| Target | Scheme | What it checks |
| --- | --- | --- |
| `FastReadUITests` | `FastReadUITests` (or the bundled `FastRead` test action) | Single happy-path XCUITest: launches the app reset, picks `test.epub` from the system Files picker, asserts the reader opens, taps `SKIP ->`, opens `CONTENTS`, jumps to a chapter, and confirms the playhead moves. |

Run the UI test directly:

```bash
xcodebuild test \
  -scheme FastReadUITests \
  -destination "platform=iOS Simulator,id=0CC71FC3-7C33-4707-A627-554BCB569549" \
  CODE_SIGNING_ALLOWED=NO
```

The test seeds `test.epub` (from `FASTREAD_E2E_EPUB` or the repo-root copy) into the simulator's app sandbox at launch via the debug-only `-FASTREAD_RESET_LIBRARY` / `-FASTREAD_SEED_EPUB` launch arguments handled in `FastReadApp.swift`. It is automatically skipped by `scripts/verify-ios-performance.sh` when no fixture is available.

## Optional gated suites

`EpubE2ETests` resolves its EPUB in this order: `FASTREAD_E2E_EPUB` env var -> `<repoRoot>/test.epub` (gitignored convenience copy). It skips when neither exists.

`EpubCorpusTests` defaults to `~/Library/Mobile Documents/com~apple~CloudDocs/books/`, override with `FASTREAD_EPUB_CORPUS_DIR`.

iCloud Drive paths require the test runner's process to have **Files-and-Folders access for iCloud Drive** (System Settings → Privacy & Security → Files and Folders). Without it, suites skip with a hint instead of failing.

```bash
# Quick path: drop any EPUB at the repo root as test.epub
cp ~/some-book.epub test.epub
swift test --filter EpubE2ETests   # 6 tests run

# Walk every *.epub under a directory:
FASTREAD_RUN_EPUB_CORPUS=1 swift test --filter EpubCorpusTests
FASTREAD_RUN_EPUB_CORPUS=1 FASTREAD_EPUB_CORPUS_DIR=~/EPUBs swift test --filter EpubCorpusTests
```

## Hooks

```bash
scripts/install-hooks.sh
```

Wires `core.hooksPath = .githooks` so the tracked `pre-commit` and `pre-push` hooks fire automatically. Re-run after a fresh clone.

- `pre-commit`: source guardrails, `swift test`, Chrome typecheck/Vitest
- `pre-push`: iOS verifier, Chrome verifier, Android JVM unit tests

See `docs/CODE_QUALITY.md` for the current verification matrix, known gaps, and refactor backlog.

## Pre-push gate (manual)

```bash
scripts/verify-ios-performance.sh
```

Runs source-level guardrails, the Swift test suite, the headless verifier executables, a Release iOS build without signing, and simulator/UI flows when local fixtures/tools are available. CI mirrors the headless iOS, Chrome, and Android unit-test portions on every push to `main` and every pull request.

## Layout

```
FastRead.xcodeproj/        # iOS app
FastReadApp/               # SwiftUI views, store, Info.plist
Sources/FastReadCore/      # importer registry, RSVP engine, Document, EpubImporter, ...
Tests/FastReadCoreTests/   # XCTest
Tests/Fixtures/            # HTML / EPUB / parity fixtures bundled into the test target
Tools/FastReadCoreVerifier/        # headless executable verifier
Tools/FastReadPerformanceVerifier/ # perf budget verifier
android-spike/             # Native Android Compose app and Play release lane
chrome-ext/                # Manifest V3 extension, unit tests, e2e, store assets
docs/                      # Release and tokenizer runbooks
Package.swift              # SwiftPM library + executables for headless test runs
```
