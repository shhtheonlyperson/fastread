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
swift run FastReadCoreVerifier
```

## Checks

```bash
npm test
```
