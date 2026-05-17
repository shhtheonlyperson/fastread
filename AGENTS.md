# FastRead Assistant Notes

Be direct, concise, and practical. Lead with the recommendation or answer,
then explain the tradeoffs and risks that matter.

## Public Repo Hygiene

Treat this repository as public-source by default.

- Do not commit store credentials, API private keys, service-account JSON,
  upload keystores, `.env.local`, generated archives, private book files, or
  machine-local account details.
- Do not add release-account emails, private dashboard URLs, API key IDs,
  issuer IDs, provisioning-profile UUIDs, upload-certificate fingerprints, or
  private local corpus paths to tracked docs.
- Keep release-specific values in ignored local files or environment variables.
- If a public runbook needs a sensitive value, name the environment variable
  and explain where to find it in the relevant store console.

## Platform Parity

When making an app fix, check Android too. Treat an iOS-only fix as incomplete
unless the user explicitly scopes the task to iOS only or Android is not
applicable. If Android cannot be verified locally, say exactly why.

## Release Shorthand

If the user says `bump release`, treat it as mobile release work:

- sync to the latest `origin/main` / `main`;
- bump the store build number/version code as needed;
- release from the latest main state;
- prioritize iOS/TestFlight, then Android internal testing if Play credentials
  are available;
- verify store acceptance, not just local build success.

Do not ask whether this means web, desktop, docs, or package publishing.

## Android Play Release

Before an Android internal-testing release, read
`docs/PLAY_CONSOLE_ANDROID.md` and verify live Play Console state.

The public repo intentionally does not track the active upload-key fingerprint
or service-account identity. Local release automation expects:

- `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`
- a service-account JSON via `FASTREAD_PLAY_SERVICE_ACCOUNT_JSON` or the
  canonical ignored machine-local path
- optionally `FASTREAD_ALLOWED_SHARED_PLAY_SERVICE_ACCOUNT_EMAILS` or
  `FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT=1` for a shared uploader

If Play rejects an AAB as signed with the wrong key, stop and recover the
active upload key or request a Play upload-key reset. Do not keep uploading.

## iOS TestFlight Release

Before an iOS/TestFlight release, read `docs/TESTFLIGHT.md`.

The public repo intentionally does not track active App Store Connect key IDs,
issuer IDs, provisioning-profile UUIDs, or private-key paths. Local release
automation expects these from `.env.local` or the shell:

- `FASTREAD_ASC_APP_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_PATH`

Do not stop at `processingState=VALID`; verify the build reaches internal
TestFlight availability.

## Chrome Web Store Release

The browser companion lives at `chrome-ext/`. Before Web Store work, read
`chrome-ext/CHROME_WEB_STORE.md` and listing assets in
`chrome-ext/store-assets/`.

Current legal URLs:

- Privacy: `https://www.theonlyperson.com/fastread/chrome/privacy`
- Terms: `https://www.theonlyperson.com/fastread/chrome/terms`

Keep the extension free of remote code and third-party telemetry. Web Store
asset uploads may require a real browser gesture; automate only the parts the
dashboard accepts reliably.
