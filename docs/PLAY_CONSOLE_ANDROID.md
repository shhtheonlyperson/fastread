# JustRead Android Play Release Runbook

Public-safe procedure for taking `android-spike/` to Google Play internal
testing. Keep account IDs, service-account emails, upload-key fingerprints, and
dashboard-only values out of this file.

## Source Of Truth

Play Console is the source of truth for:

- package name
- current internal-testing version
- upload-certificate fingerprint
- service-account permissions
- store-listing icon state

The Android package is `com.shhtheonlyperson.fastread`.

## Local Secrets

Never commit these:

- `android-spike/upload-keystore.jks`
- `android-spike/keystore.properties`
- `android-spike/google-service-account*.json`
- `android-spike/google-play-service-account*.json`
- generated AABs, APKs, and build directories

The release preflight expects local/private values from environment variables
or ignored machine-local paths:

```bash
export FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1="<Play Console upload cert SHA-1>"
export FASTREAD_PLAY_SERVICE_ACCOUNT_JSON="$HOME/.config/shh/play-service-accounts/fastread-google-play-service-account.json"
```

If using a shared uploader intentionally, either set:

```bash
export FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT=1
```

or set a comma-separated allowlist:

```bash
export FASTREAD_ALLOWED_SHARED_PLAY_SERVICE_ACCOUNT_EMAILS="uploader@example.iam.gserviceaccount.com"
```

## Preflight

Run this before any release build/upload:

```bash
scripts/check-android-release-credentials.sh
```

It checks:

- service-account JSON exists and has the expected Google service-account
  shape;
- service-account identity is FastRead-specific, explicitly allowlisted, or
  explicitly allowed as shared;
- Play Developer API edit access works unless
  `FASTREAD_SKIP_PLAY_API_CHECK=1`;
- Play store listing icon matches unless `FASTREAD_SKIP_PLAY_ICON_CHECK=1`;
- `android-spike/keystore.properties` points at an upload keystore whose SHA-1
  matches `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`.

## Install A Play Service Account

After downloading a Play service-account JSON, install it outside the repo:

```bash
scripts/install-android-play-service-account.sh ~/Downloads/<downloaded-key>.json
```

The installer validates the JSON shape, copies it to the canonical local path,
sets restrictive permissions, writes a local backup, and records a checksum
manifest. Do not leave the JSON in Downloads or inside a checkout.

## Build And Upload

```bash
scripts/check-android-release-credentials.sh
cd android-spike

# Bump versionCode and versionName in app/build.gradle.kts first.
bundle exec fastlane internal
```

The `internal` lane builds a signed AAB and uploads it to the internal testing
track. Use `bundle exec fastlane verify` when you only need a signed local AAB
plus validation.

## First Upload

The first Play upload may require browser-only setup:

1. Create or open the Play Console app.
2. Confirm Play App Signing setup.
3. Fill required App content forms.
4. Upload the signed AAB to internal testing.
5. Add testers and verify the opt-in URL works.

Subsequent uploads can use Fastlane once API access and signing are proven.

## Wrong-Key Rejection

If Play rejects the AAB as signed with the wrong key, stop. Do not generate
another random keystore and keep uploading.

Correct paths:

- recover the active upload keystore;
- or request a Play upload-key reset and wait for Play to accept the replacement
  certificate.

The helper for exporting a replacement certificate is:

```bash
scripts/export-android-upload-reset-certificate.sh
```

## Store Listing Icon

The icon is part of the release gate:

```bash
scripts/sync-play-store-icon.sh --check
scripts/sync-play-store-icon.sh --apply
```

If the commit step is denied, grant the service account store-listing edit
permission in Play Console, then rerun the command.
