# Play Console store assets

Drop these into Play Console → JustRead → Store presence → Main store listing during the first-upload flow. Same shape as `~/proj/shos/build/play-assets/`, which is the pattern that worked for the recent shos Android internal release.

## Pre-staged

| File | Where it goes | Required for |
|---|---|---|
| `justread-icon-512.png` (512×512) | App icon (high-res) | All tracks |
| `justread-phone-1-paste.png` (1080×2400) | Phone screenshots — Slot 1 | Production / external testing |
| `justread-phone-2-reader.png` (1080×2400) | Phone screenshots — Slot 2 | Production / external testing |

## Optional (skip for first internal upload)

- **Feature graphic** (1024×500): only required when promoting to closed/open testing or production. Internal testing track does NOT require it. Leave for a v0.2 design pass.
- More phone screenshots (Slots 3-8): Play Store accepts up to 8; we have 2 covering the two main screens, which is enough for v1.

## Title + description

Already in `../fastlane/metadata/android/{en-US,zh-TW}/`. If you do the first upload manually in the browser, copy-paste from those files. Once the service-account JSON is in place, `bundle exec fastlane internal` syncs metadata automatically.
