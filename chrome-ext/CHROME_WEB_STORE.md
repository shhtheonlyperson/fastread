# JustRead — Chrome Web Store

This doc is the submission checklist plus the live-listing reference.

## Current listing state (as of 2026-05-15)

- **Item ID:** `jlphjjnghcblidffelhhiooeghjblfed`
- **Name:** `JustRead — Reader View + Speed Reading`
- **Publisher account:** `shh@theonlyperson.com` (Web Store Developer fee paid here)
- **Contact email (verified):** `shh@theonlyperson.com`
- **Privacy policy URL:** `https://www.theonlyperson.com/privacy` (source: [`store-assets/PRIVACY.md`](store-assets/PRIVACY.md))
- **Category:** Tools (under Productivity) — visibility public, all regions, free
- **Status URL (bookmark):** [Status tab](https://chrome.google.com/webstore/devconsole/CHROME_DEVELOPER_ID_PLACEHOLDER/jlphjjnghcblidffelhhiooeghjblfed/edit/status)
- **Live URL (post-approval):** `https://chromewebstore.google.com/detail/jlphjjnghcblidffelhhiooeghjblfed`
- **Submitted:** 2026-05-15. Status: **Pending review**. Local tag: `chrome-ext-v1.0.0-submitted`.

## What to watch while in review

| Status tab banner | What it means |
|---|---|
| `This draft is pending review.` | Sitting in Google's queue. |
| `This draft is in review.` | Reviewer is actively looking. |
| `This draft was rejected.` | Reasons appear on the same page; also emailed to the contact address. |
| (Draft empty, Published populated) | Approved + live at the URL above. |

Google emails the contact address (`shh@theonlyperson.com`) on every status change. Sender is typically `noreply-chromewebstore@google.com`.

## If the review bounces

Most likely two reasons; both are addressable without changing the extension code:

1. **Broad host permissions need clearer justification.** Re-paste the `<all_urls>` justification verbatim from [`store-assets/listing-en.md`](store-assets/listing-en.md) into the reviewer reply form.
2. **Single-purpose policy.** Won't happen unless we add features outside reader/RSVP later.

If a code change is needed, bump `chrome-ext/package.json` version (e.g. `1.0.0` → `1.0.1`), `bun run zip`, drag the new zip onto the dashboard's Package tab, fix the flagged setting, and Submit again.

## Resubmission gotchas (learned 2026-05-15 — keep these in mind)

The Chrome Web Store has three quirks that bite automation:

- **Dropzones (icon + screenshots) reject every programmatic upload path.** `setInputFiles`, `DataTransfer` + synthesized `DragEvent('drop')`, CDP-level injection — none take. The page validates `event.isTrusted` and only a real OS-level user gesture passes. Plan to drag the icon and screenshots from Finder yourself.
- **Save Draft is per-tab.** Switching from Privacy → Distribution before saving Privacy wipes the Privacy fields. Pattern: fill a tab → Save → verify by re-snapshotting → only then navigate.
- **"Submit for review" modal action is labeled "Submit For Review" (capital F, R), not "Publish".** A separate "Publish" button publishes a previously-staged build using a stored publish-time that defaults to the Unix epoch; clicking it surfaces a "Publish time has expired" error.
- **Adding the contact email pauses the flow** until you click the verification link Google emails to that address.

> **Account note:** `shh@theonlyperson.com` is the developer account.
> `shh@theonlyperson.com` does NOT have the Developer fee paid (confirmed
> 2026-05-15). Always sign into the dashboard with the gmail account.

---

## 0. Final sanity check before opening the dashboard

```sh
cd chrome-ext

# 1. Tests + e2e green
FASTREAD_E2E_CHROME_EXT=1 ../scripts/verify-chrome-ext.sh

# 2. Bump the version in chrome-ext/package.json from 0.1.0 to 1.0.0
#    (Chrome Web Store rejects 0.x as "still in development" sometimes).
#    Then rebuild.

# 3. Regenerate icons + screenshots from the current build
bun run icons
bun run capture

# 4. Build the upload zip
bun run zip   # → ./justread-chrome.zip
```

Verify `dist/manifest.json` has the new `version` before zipping.

---

## 1. Item → Create new item → upload ZIP

Drag `chrome-ext/justread-chrome.zip` onto the Web Store dashboard.

Once it processes, the form populates the fields below from the
manifest. Fill or replace the rest from this doc.

---

## 2. Store listing tab

### Description language

Set **English (United States)** as the default. Add **Chinese
(Traditional)** as an additional language.

### Name (per language)

| Locale | Value | Source |
|---|---|---|
| EN | `JustRead — Reader View + Speed Reading` | `_locales/en/messages.json:extName` |
| zh-Hant | `簡讀 — 閱讀模式 + 速讀` | `_locales/zh_TW/messages.json:extName` |

### Short description (per language, ≤ 132 chars)

| Locale | Value |
|---|---|
| EN | Paste from `store-assets/listing-en.md` → "Short summary" |
| zh-Hant | Paste from `store-assets/listing-zh-hant.md` → "簡短說明" |

### Detailed description (per language)

| Locale | Source |
|---|---|
| EN | `store-assets/listing-en.md` → "Detailed description" section |
| zh-Hant | `store-assets/listing-zh-hant.md` → "詳細說明" section |

### Category

`Productivity` (primary). No secondary.

### Tags / search terms

`reader`, `reader view`, `read mode`, `RSVP`, `speed reading`,
`distraction free`, `Chinese reader`, `繁體中文`, `Readability`.

### Graphic assets

| Asset | File | Required? |
|---|---|---|
| Store icon (128×128, PNG) | `public/icons/icon-128.png` | yes (auto from manifest) |
| Screenshots (1280×800 PNG, 1–5) | `store-assets/screenshots/01-reader-light.png`<br>`store-assets/screenshots/02-reader-dark.png`<br>`store-assets/screenshots/03-fastread.png`<br>`store-assets/screenshots/04-options.png` | min 1, recommended 4–5 |
| Promotional small tile (440×280) | _not provided — skip_ | optional |
| Marquee (1400×560) | _not provided — skip_ | optional |
| Video | _none_ | optional |

Captions (paste under each screenshot):

1. `Reader View — clean typography, light theme. Press F on any article.`
2. `Dark theme — toggles with one tap or system preference.`
3. `Fast Read (RSVP) — one word at a time, focused at the optimal recognition point.`
4. `Options — theme, font, font size, words-per-minute, chunk size, language.`

---

## 3. Privacy practices tab

### Single purpose

Paste:

> JustRead has one purpose: present web articles in a clean reader view and let the user speed-read them. All requested permissions exist solely to support that purpose.

### Permission justifications

Copy each block from `store-assets/listing-en.md` → "Permission justifications".

### Data usage

Tick **only** these in the data disclosures form:

- [ ] Personally identifiable information — _no_
- [ ] Health information — _no_
- [ ] Financial and payment information — _no_
- [ ] Authentication information — _no_
- [ ] Personal communications — _no_
- [ ] Location — _no_
- [ ] Web history — _no_
- [ ] User activity — _no_
- [ ] Website content — _no_ (we read article text on the active tab to extract it locally; we do not transmit it)

Then tick the three certification statements:

- [x] I do not sell or transfer user data to third parties, outside of the approved use cases.
- [x] I do not use or transfer user data for purposes that are unrelated to my item's single purpose.
- [x] I do not use or transfer user data to determine creditworthiness or for lending purposes.

### Privacy policy URL

`https://www.theonlyperson.com/privacy`

> Ensure that URL is live before submitting. Source markdown to paste at
> the destination lives at `chrome-ext/store-assets/PRIVACY.md`.

### Remote code

`No, I am not using remote code` — JustRead's content script imports
only from chrome-extension:// (its own bundled chunks). All assets ship
in the .zip.

---

## 4. Distribution tab

- Visibility: **Public**
- Regions: **All regions**
- Pricing: **Free**

---

## 5. Submit

Hit **Submit for review**.

Typical review time: 1–3 business days for new Productivity items
without sensitive permissions. JustRead's `<all_urls>` host permission
is the only thing that can trip up review; the justification copy
above is what the reviewer looks for.

---

## 6. After approval

- [ ] Tag the release: `git tag chrome-ext-v1.0.0 && git push --tags`
- [ ] Add the listing URL to `chrome-ext/README.md`.
- [ ] Drop a short note about the launch in the `~/Documents/wiki` `chrome-extensions` index.

---

## Appendix: if the review bounces

The two most common reasons for a JustRead-shaped extension to bounce:

1. **"Broad host permissions need clearer justification."** Re-paste the
   `<all_urls>` justification from this doc verbatim into the reviewer
   reply.
2. **"Single-purpose violation."** Don't add new functionality that
   isn't reader/RSVP; the listing reads as a pure reader extension and
   reviewers expect that.
