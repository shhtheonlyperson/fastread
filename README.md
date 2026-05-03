# JustRead

Local RSVP speed reader inspired by the red-focus-letter format in the referenced UltraLinx tweet.

## Use

```bash
npm run serve
```

Open `http://127.0.0.1:4173`, paste text or load a URL, choose WPM, and press play.

## iOS App

```bash
open FastRead.xcodeproj
```

This opens the native SwiftUI app target, `JustRead`. It includes the full library/add/reader/focus/stats/settings flow, bundled Fraunces/Inter/JetBrains Mono fonts, app icon assets, persisted reading settings, and the Swift port of the RSVP engine.

Core RSVP verification is available without Xcode:

```bash
swift test
swift run FastReadCoreVerifier
```

Perf-sensitive iOS paths have a repeatable verifier:

```bash
npm run verify:ios-performance
```

This runs source-level guardrails for bounded READ context and smooth sliders, Swift unit tests, the Swift core verifier, the Swift performance verifier, JS tests, and a Release iOS device build without signing. For slower CI machines, set `FASTREAD_PERF_BUDGET_MULTIPLIER=2`.

GitHub Actions runs those same gates as separate visible steps on pushes to `main` and every pull request. It fails on the old regression patterns too: full-text READ previews, synchronous HTML parsing on paste/load paths, computed token properties on `ReadingArticle`, non-continuous SwiftUI sliders, and unbounded web preview rendering.

## Checks

```bash
npm test
npm run guard:source
swift test
npm run perf:web
npm run verify
```
