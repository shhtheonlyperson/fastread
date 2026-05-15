# JustRead — Chrome Extension

Reader View + RSVP Fast Read for any web article. Sibling to the iOS/Android FastRead apps in this repo.

## Stack

- Manifest V3, Vite + CRXJS, TypeScript, React 18
- `@mozilla/readability` for article extraction
- Shadow DOM overlay (host page CSS does not bleed in)
- Chrome `storage.sync` for settings; `_locales` for i18n (en, zh_TW)

## Develop

```bash
bun install
bun run dev          # Vite + CRXJS HMR
```

Then in Chrome: `chrome://extensions` → enable Developer mode → **Load unpacked** → pick `chrome-ext/dist`.

## Build / package

```bash
bun run build        # typecheck (tsgo) + production build
bun run zip          # zips dist/ → justread-chrome.zip for the Web Store
```

## Keyboard

| Key | Action |
|---|---|
| `Alt+R` | Toggle Reader |
| `Alt+Shift+R` | Toggle Fast Read |
| `Space` | Play/Pause (Fast Read) |
| `←` / `→` | Skip sentence |
| `↑` / `↓` | WPM ±25 |
| `Esc` | Exit current mode |

## Layout

```
src/
  background/        service worker (commands, action click)
  content/           reader + fastread overlay (Shadow DOM)
  popup/             toolbar popup
  options/           settings page
  lib/               readability extract, RSVP engine, storage, messages
  styles/            overlay.css (injected into shadow root)
public/
  _locales/{en,zh_TW}/messages.json
  icons/             128/48/16 png (TODO: ship real icons)
```

## TODO before publishing

- [ ] Add real icons in `public/icons/`
- [ ] Add a site allowlist/blocklist UI in options
- [ ] Persist last-read position per URL
- [ ] Wire `_locales` strings into UI (currently only manifest + popup hard-coded English)
- [ ] Unit tests for `tokenize` / `RsvpEngine`
