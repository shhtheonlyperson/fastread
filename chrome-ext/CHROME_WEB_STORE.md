# JustRead Chrome Web Store

Public-safe submission checklist for the Manifest V3 companion extension.
Keep publisher account emails, private dashboard URLs, and reviewer-only notes
out of this file.

## Listing

- Name: `JustRead - Reader View + Speed Reading`
- Category: Productivity / Tools
- Visibility: Public
- Regions: All regions
- Pricing: Free
- Privacy policy: `https://www.theonlyperson.com/fastread/chrome/privacy`
- Terms of Use: `https://www.theonlyperson.com/fastread/chrome/terms`
- Live listing URL after approval: `https://chromewebstore.google.com/detail/jlphjjnghcblidffelhhiooeghjblfed`

## Preflight

```bash
cd chrome-ext
FASTREAD_E2E_CHROME_EXT=1 ../scripts/verify-chrome-ext.sh
bun run icons
bun run capture
bun run zip
```

Verify `dist/manifest.json` has the intended version before uploading the zip.

## Store Listing

Set English (United States) as the default language. Add Chinese
(Traditional) as an additional language.

| Locale | Name |
| --- | --- |
| EN | `JustRead - Reader View + Speed Reading` |
| zh-Hant | `簡讀 - 閱讀模式 + 速讀` |

Paste short and detailed descriptions from:

- `store-assets/listing-en.md`
- `store-assets/listing-zh-hant.md`

Screenshots:

- `store-assets/screenshots/01-reader-light.png`
- `store-assets/screenshots/02-reader-dark.png`
- `store-assets/screenshots/03-fastread.png`
- `store-assets/screenshots/04-options.png`

## Privacy Practices

Single purpose:

> JustRead has one purpose: present web articles in a clean reader view and let
> the user speed-read them. All requested permissions exist solely to support
> that purpose.

Use the permission justifications from `store-assets/listing-en.md`.

Data disclosures should state that JustRead does not collect, sell, transfer,
or transmit user data. Article extraction happens locally in the active tab.

Remote code:

> No, I am not using remote code.

All scripts, styles, and assets must ship in the extension zip and load from
`chrome-extension://`.

## Distribution

- Visibility: Public
- Regions: All regions
- Pricing: Free

## Dashboard Gotchas

- Store icon and screenshots may require a real browser/OS gesture.
- Save each dashboard tab before navigating away.
- Use the review-submission action, not any stale publish-time action.
- If review bounces on the privacy URL, verify the Chrome-specific policy URL
  returns a direct JustRead privacy policy and resubmit.

## After Approval

- Tag the release.
- Add the live listing URL to `chrome-ext/README.md`.
- Record any reusable release lesson in private local notes, not this public
  runbook.
