# JustRead

Local RSVP speed reader for iOS. Imports EPUBs from Files / share sheet, splits each word at the optimal recognition point, and plays them back at a tunable WPM with optional punctuation pauses.

## Run

```bash
open FastRead.xcodeproj
```

In Xcode, select scheme **FastRead**, target an iPhone simulator or device, and run. The app target is `JustRead`. It bundles Fraunces / Inter / JetBrains Mono, app icons, persisted reader settings, and registers `org.idpf.epub-container` so EPUBs from any other app can be opened directly into the library.

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
```

Default run is fast (~2s, 57 tests). Coverage:

| Suite | What it checks |
| --- | --- |
| `RSVPEngineTests` | tokenize, focus splits, durations, CJK math |
| `DocumentTests` | sections, boundaries, `detectFrontMatter` |
| `ImportersTests` | PlainText + Html adapters via the registry |
| `EpubImporterTests` | OPF / spine / nav.xhtml / NCX parsing |
| `EpubRegistryFlowTests` | registry → Document round trip |
| `HtmlGoldenTests` | 6 frozen HTML/text fixtures, regression-locked |
| `EpubE2ETests` | end-to-end on `~/proj/local-epub/exports/all/local-test-book.epub` |
| `UrlIngestTests` | stubbed `URLProtocol` for fetch errors |
| `StorageMigrationTests` | v1 (text-only) → v2 (Document) round trip |
| `ReadingArticleCodableTests` | persistence shape stable |
| `ParityTests` | parity corpus (kept for fixture stability) |
| `EpubCorpusTests` | gated walker over a real EPUB library |

## Optional gated suites

```bash
# E2E test against a specific EPUB (override path):
FASTREAD_E2E_EPUB=/path/to/book.epub swift test --filter EpubE2ETests

# Walk every *.epub under a directory and assert each one imports:
FASTREAD_RUN_EPUB_CORPUS=1 \
FASTREAD_EPUB_CORPUS_DIR=~/proj/local-epub/exports/all \
swift test --filter EpubCorpusTests
```

## Pre-push gate

```bash
scripts/verify-ios-performance.sh
```

Runs source-level guardrails, the Swift test suite, the headless verifier executables, and a Release simulator build without signing. CI mirrors this on every push to `main` and every pull request.

## Layout

```
FastRead.xcodeproj/        # iOS app
FastReadApp/               # SwiftUI views, store, Info.plist
Sources/FastReadCore/      # importer registry, RSVP engine, Document, EpubImporter, ...
Tests/FastReadCoreTests/   # XCTest
Tests/Fixtures/            # HTML / EPUB / parity fixtures bundled into the test target
Tools/FastReadCoreVerifier/        # headless executable verifier
Tools/FastReadPerformanceVerifier/ # perf budget verifier
Package.swift              # SwiftPM library + executables for headless test runs
```
