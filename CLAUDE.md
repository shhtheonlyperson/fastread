# FastRead Assistant Notes

This file mirrors `AGENTS.md`. Keep it public-safe: no credentials, private
account emails, dashboard URLs, certificate fingerprints, ASC key IDs, issuer
IDs, provisioning-profile UUIDs, or private corpus paths.

## Default Style

Be direct, concise, and practical. Lead with the recommendation or answer, then
explain material tradeoffs and risks.

## Release Meaning

In this repo, `bump release` means mobile release work from the latest main
state. Prioritize iOS/TestFlight, then Android internal testing if the required
local credentials are available. Verify store acceptance, not only local build
success.

## Public Repo Rules

- Keep secrets and release identities in `.env.local`, the shell, keychain, or
  ignored machine-local paths.
- Do not commit generated archives, private EPUBs, service-account JSON,
  upload keystores, API private keys, or local release notes.
- Public docs should name required environment variables rather than storing
  sensitive values.

## Release Docs

- Android: `docs/PLAY_CONSOLE_ANDROID.md`
- iOS/TestFlight: `docs/TESTFLIGHT.md`
- Chrome Web Store: `chrome-ext/CHROME_WEB_STORE.md`

Current Chrome legal URLs:

- `https://www.theonlyperson.com/fastread/chrome/privacy`
- `https://www.theonlyperson.com/fastread/chrome/terms`
