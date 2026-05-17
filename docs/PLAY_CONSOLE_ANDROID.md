# JustRead Android — Play Console runbook

End-to-end procedure for taking the local `android-spike/` Gradle project to Google Play Console internal testing. Mirrors the flow proven on `~/proj/osho` and the `shh-mobile-release` skill's `android-local-fallback.md` reference. Path B in the migration plan: minimum viable reader, signed AAB, internal track only.

## Current state of truth

Play Console is the source of truth. Update this section after each release attempt.

- Application ID: `com.shhtheonlyperson.fastread`
- Kotlin namespace: `com.shhtheonlyperson.fastread.spike` (intentional — directory churn deferred to the full KMP port)
- Min SDK: **34** (Android 14, Pixel 8 launch line)
- Target SDK: **35**
- Latest signed AAB: `android-spike/app/build/outputs/bundle/release/app-release.aab`
- Latest live internal-testing release observed through the Play Developer API: `0.2.2` (versionCode 9), `completed`, uploaded May 16, 2026.
- Current local release candidate: `0.2.2` (versionCode 9), built and uploaded to Play internal testing on May 16, 2026.
- Upload keystore: `android-spike/upload-keystore.jks` (gitignored, never commit)
- Keystore properties: `android-spike/keystore.properties` (gitignored)
- Play Console currently expects upload key SHA-1:
  `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`
- Local `android-spike/upload-keystore.jks` currently signs with SHA-1:
  `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`
- Local `android-spike/upload-keystore.jks` SHA-256:
  `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA256`
- May 16, 2026 release attempt: the original upload keystore was recovered from the old EAS project `30524a6b-d9f1-40a1-b75a-43e289b49812` (`huang47` / `fastread` / production build credentials). Its SHA-1 matches Play's current upload key, so the pending upload-key reset was canceled in Play Console. Fastlane then built and uploaded versionCode 8 to the internal track with `release_status: completed`.
- May 16, 2026 parity release: Android `0.2.2` / versionCode 9 was built from commit `88dea9e` and uploaded through `fastlane internal`; live Play track readback returned internal release `0.2.2`, versionCode `9`, status `completed`.
- Play store listing icon is guarded by `scripts/sync-play-store-icon.sh --check`; the current `en-US` icon matches `android-spike/play-assets/justread-icon-512.png`.

## 1. Create the app in Play Console (one time)

[https://play.google.com/console](https://play.google.com/console) → **Create app**

```
App name:        JustRead Speed Reader
Package name:    com.shhtheonlyperson.fastread
App or game:     App
Free or paid:    Free
Default language: Chinese (Traditional, Taiwan), or fall back to English (United States) if zh-TW isn't selectable
```

Accept the developer programme policy and US export laws. Play Console locks the package name when the first AAB is uploaded, not at create time, so you can still change it after this step if you typo.

## 2. Set up Play App Signing (one time)

When creating the release in step 4, Play Console asks how you want to sign the app.

- Choose **"Use Play App Signing"** (the default).
- Choose **"Export and upload a key from Java keystore"**.
- Run this locally to extract a `pepk`-encrypted upload key for Google to ingest:

  ```bash
  cd android-spike
  java -jar pepk.jar --keystore=upload-keystore.jks --alias=justread \
    --output=play-encrypted-upload-key.pem \
    --include-cert \
    --rsa-aes-encryption \
    --encryption-key-path=encryption-public-key.pem
  ```

  `pepk.jar` and `encryption-public-key.pem` are downloadable from the Play Console signing page itself. The output `.pem` is what you upload back to Play Console.

- Or simpler — at app creation, choose **"Let Play App Signing generate the app signing key for me"** AND let Google manage everything. In that case you upload AABs signed with `upload-keystore.jks` and Play re-signs them with the app signing key it generated. This is what we do.

After Play Console accepts the upload key, verify the SHA-1 it shows matches the current Play Console expectation above. If you are intentionally resetting the upload key, verify it changes to the replacement certificate's SHA-1 before uploading again.

If it doesn't match, you uploaded the wrong keystore — double-check `keystore.properties` points at the file you're looking at.

## 3. Set up the service account for fastlane (one time)

This unlocks `fastlane android internal` for every subsequent release. Without it you'd be dragging the AAB into the browser each time. This is separate from the upload keystore: a valid service-account JSON lets Fastlane call Play APIs, but Play will still reject an AAB signed by the wrong upload key.

Run this before any Android release build:

```bash
scripts/check-android-release-credentials.sh
# or
cd android-spike && PATH=/opt/homebrew/opt/ruby/bin:$PATH bundle exec fastlane release_preflight
```

The preflight checks both gates before a long build:

- Play service-account JSON exists and is a real Google Cloud service-account key.
- `android-spike/keystore.properties` points at an upload keystore whose SHA-1 matches Play Console.
- Play store listing icon matches `android-spike/play-assets/justread-icon-512.png`.

The canonical machine-local service-account path is:

```text
~/.config/shh/play-service-accounts/fastread-google-play-service-account.json
```

On this machine, that path may be a symlink to the shared uploader:

```text
~/.config/shh/play-service-accounts/shos-google-play-service-account.json
```

Shared uploader accounts are intentionally allowlisted in the scripts and must have Play Console access to JustRead. The canonical shared uploader is `play-uploader@example.iam.gserviceaccount.com`; the legacy fallback is `legacy-play-uploader@example.iam.gserviceaccount.com`. The preflight does a live Android Publisher API edit insert/delete against `com.shhtheonlyperson.fastread`, so missing Play permissions fail before any build or upload.

The store listing icon has a separate permission gate. Run this after granting **Edit store listing information** / `CAN_MANAGE_PUBLIC_LISTING`:

```bash
scripts/sync-play-store-icon.sh --apply
scripts/sync-play-store-icon.sh --check
```

Do not leave the downloaded JSON in `~/Downloads` or inside a repo checkout. Install it immediately with:

```bash
scripts/install-android-play-service-account.sh ~/Downloads/<downloaded-key>.json
```

That script validates the key shape, copies it to the canonical path, sets `0600` permissions, writes a local backup under `~/.config/shh/play-service-accounts/backups/`, and records a non-secret checksum manifest next to the canonical JSON. This is the durable path; clean worktrees and repo resets should not affect it.

For an off-machine backup, add a 1Password vault name and approve the 1Password prompt:

```bash
FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_VAULT="Private" \
  scripts/install-android-play-service-account.sh ~/Downloads/<downloaded-key>.json
```

This stores the JSON as a 1Password document named `FastRead Google Play service-account JSON`.

Fastlane also accepts `FASTREAD_PLAY_SERVICE_ACCOUNT_JSON`, `SUPPLY_JSON_KEY`, `PLAY_STORE_JSON_KEY`, the shared `shos` machine-local fallback, and the legacy gitignored repo-local paths under `android-spike/`.

The preflight expects the service-account email to contain `fastread` or match `FASTREAD_ALLOWED_SHARED_PLAY_SERVICE_ACCOUNT_EMAILS` (default: `play-uploader@example.iam.gserviceaccount.com` plus the legacy `legacy-play-uploader@example.iam.gserviceaccount.com`). If you intentionally use another shared Play uploader, grant that account access to the FastRead Play app first and set the allowlist explicitly.

1. Open [Play Console → Setup → API access](https://play.google.com/console/u/0/developers/api-access).
2. Link or create a Google Cloud project. Naming doesn't matter — `fastread-publisher` is fine.
3. In the linked Cloud project, enable the **Google Play Android Developer API**:
   [https://console.cloud.google.com/apis/api/androidpublisher.googleapis.com](https://console.cloud.google.com/apis/api/androidpublisher.googleapis.com)
4. Back in Play Console → API access, click **Create new service account**.
5. Cloud console opens. Create a service account named `fastread-publisher`. Skip optional roles. Click **Create**.
6. After creation, click the service account → **Keys → Add key → Create new key → JSON**. Browser downloads the JSON.
7. Install the JSON into the canonical machine-local path:

   ```bash
   scripts/install-android-play-service-account.sh ~/Downloads/<downloaded-key>.json
   scripts/check-android-release-credentials.sh
   ```

   Do not commit it. A gitignored repo-local copy at `android-spike/google-service-account.fastread.json` is only a fallback; the installer-managed canonical path survives clean worktrees and prevents this blocker from recurring.

8. Back in Play Console → API access, find the new service account in the list and click **Manage Play Console permissions**. Grant:

   ```
   View app information
   Release apps to testing tracks
   Manage testing tracks and edit tester lists
   Edit store listing information
   ```

   Don't grant production permissions until you actually want to ship to production.

## 4. First upload (manual, browser-only)

The very first AAB has to go through the browser because Play Console requires several review forms answered before any release. Subsequent uploads can use fastlane.

1. **Build the AAB locally:**

   ```bash
   cd android-spike
   bundle install              # one-time, picks up Gemfile
   bundle exec fastlane verify  # builds + bundletool validate
   ```

2. **Open Play Console → All apps → JustRead Speed Reader → Internal testing → Create new release.**
3. Drop `android-spike/app/build/outputs/bundle/release/app-release.aab` into the upload area.
4. Fill the release notes; for the first internal beta a one-line "First internal build — paste-text RSVP, Trad-Chinese tokeniser, custom dictionary." is fine.
5. Save → Review release → Start rollout to internal testing.
6. Add yourself as an internal tester:
   - Internal testing → Testers tab → Create email list
   - Add your Google email → Save
   - Copy the **Join the test** URL Play Console generates and open it on the Pixel 10 Pro to opt in.
7. The Play Store app on the device will offer the build within a few minutes.

While you're in the browser, fill the **App content** forms — these one-time questions block the release going past internal-testing if left empty:

```
Privacy policy:        Required eventually; for internal testing you can leave blank.
                       Add before opening external testing or production.
Ads:                   No
App access:            All functionality is available without login.
Content rating:        Run the IARC questionnaire — JustRead is "Reference / News" with no
                       sensitive content. Expected rating: PEGI 3 / ESRB Everyone.
Target audience:       Adults / general audience, NOT directed at children.
News app:              No
Data safety:           No data collected or shared. All persistence is local SharedPreferences.
                       Tick "We comply with Play Families policy" only if you ever target kids.
Government app:        No
Financial features:    No
Health features:       No
Permissions:           No runtime permissions requested.
Data deletion URL:     Not applicable, no developer-collected data.
```

## 5. Subsequent releases (fastlane)

```bash
scripts/check-android-release-credentials.sh
cd android-spike

# bump versionCode + versionName in app/build.gradle.kts.
# Each upload to a given track must have a strictly higher versionCode
# than every prior accepted build.

bundle exec fastlane internal
```

The `internal` lane:

1. Builds + signs `app-release.aab` with the upload key from `keystore.properties`.
2. Uploads to the **internal** track via the Google Play Developer API using the canonical service-account JSON or explicit env var.
3. Promotes the release to `release_status: completed` so internal testers see it within a few minutes.

If you want to upload but not auto-promote, use `bundle exec fastlane draft` — it leaves the release in draft so you can finish editing in Play Console before pressing Rollout.

## 6. Recovering from a lost upload key

If `upload-keystore.jks` is missing, first search EAS before requesting or waiting for a reset:

```bash
cd /tmp/fastread-eas-old
npx --yes eas-cli@latest credentials -p android
# choose production -> credentials.json -> Download credentials from EAS
```

The recovered production EAS keystore should have alias `UPLOAD_KEY_ALIAS_PLACEHOLDER`, SHA-1 `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`, and SHA-256 `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA256`.

Keep local keystore backups under:

```text
~/.config/shh/android-keystores/
```

If the original upload key really is destroyed and no EAS credential exists:

1. Generate a new upload keystore (any password, just something you'll remember).
2. Open Play Console → App → Setup → App signing → **Request upload key reset**.
3. Attach a small certificate-only PEM exported from the new keystore.
   The helper reads `android-spike/keystore.properties` and avoids printing passwords:

   ```bash
   scripts/export-android-upload-reset-certificate.sh
   ```

4. Wait ~24h for Google to manually verify and swap the upload key.

The Play **app signing key** never leaves Google's HSM, so a lost upload key is not the end of the world — it's only used to re-sign new uploads, not to authenticate the published artefact on devices.

## 7. Common stumbling blocks

| Symptom | Fix |
| --- | --- |
| `Failed to read key justread from store ... Given final block not properly padded` during `bundleRelease` | PKCS12 keystores must use the same password for store and key. `keystore.properties` `keyPassword` should equal `storePassword`. |
| Play Console rejects the AAB with "signed with the wrong key" | Stop and compare SHA-1. Play currently expects `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`. The recovered EAS keystore matches that. If local `upload-keystore.jks` signs as `REPLACEMENT_UPLOAD_KEY_SHA1`, it is the canceled reset replacement key, not the active Play upload key. |
| `Google Play credential must be a Google Cloud service-account JSON key` | Fastlane is reading a Firebase `google-services.json` or an OAuth client file. Re-download the right file from Play Console → API access. |
| Service account auth fails with `403` | Permission propagation lag or missing app permission. Wait 5 min and retry. If still failing, re-grant `View app information`, `Release apps to testing tracks`, and `Manage testing tracks and edit tester lists` in Play Console → Users and permissions for `com.shhtheonlyperson.fastread`. |
| `Play icon upload was prepared but commit was denied` | Grant the service account **Edit store listing information** / `CAN_MANAGE_PUBLIC_LISTING`, then rerun `scripts/sync-play-store-icon.sh --apply`. After the release, remove unrelated temporary account-level permissions and keep only app-level release/store-presence permissions. |

## 8. Files that must never be committed

`.gitignore` already covers these; double-check before adding any release artefact:

- `android-spike/upload-keystore.jks`
- `android-spike/keystore.properties`
- `android-spike/google-service-account.fastread.json`
- `android-spike/build/`
- `android-spike/app/build/`

If any of these leak into a commit, rotate the corresponding credential immediately:
- Upload key → Play Console upload key reset (§6).
- Service account → Cloud console → IAM → revoke key → create new one → download fresh JSON.
