# JustRead Android — Play Console runbook

End-to-end procedure for taking the local `android-spike/` Gradle project to Google Play Console internal testing. Mirrors the flow proven on `~/proj/osho` and the `shh-mobile-release` skill's `android-local-fallback.md` reference. Path B in the migration plan: minimum viable reader, signed AAB, internal track only.

## Current state of truth

Play Console is the source of truth. Update this section after each release attempt.

- Application ID: `com.shhtheonlyperson.fastread`
- Kotlin namespace: `com.shhtheonlyperson.fastread.spike` (intentional — directory churn deferred to the full KMP port)
- Min SDK: **34** (Android 14, Pixel 8 launch line)
- Target SDK: **35**
- Latest signed AAB: `android-spike/app/build/outputs/bundle/release/app-release.aab`
- Latest live internal-testing release observed in Play Console: `0.2.1` (versionCode 4), released May 4, 2026 at 12:25 PM.
- Current local release candidate: `0.2.1` (versionCode 8), built and `bundletool validate` passed on May 16, 2026.
- Upload keystore: `android-spike/upload-keystore.jks` (gitignored, never commit)
- Keystore properties: `android-spike/keystore.properties` (gitignored)
- Play Console currently expects upload key SHA-1:
  `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`
- Local `android-spike/upload-keystore.jks` currently signs with SHA-1:
  `REPLACEMENT_UPLOAD_KEY_SHA1`
- Local `android-spike/upload-keystore.jks` SHA-256:
  `26:7A:61:85:52:5B:4B:2C:AD:79:7E:89:23:AA:BD:15:66:14:C7:E9:C0:82:0F:A4:D6:D2:B9:A4:BA:79:76:18`
- May 16, 2026 release attempt: Fastlane `verify` produced a valid versionCode 8 AAB, but Android was not uploaded because the repo-local Play service-account JSON was missing and the local upload keystore still signs with SHA-1 `REPLACEMENT_UPLOAD_KEY_SHA1`, while Play expects `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`. Android is not released until the original upload keystore is recovered or Play upload-key reset is completed.

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

The canonical machine-local service-account path is:

```text
~/.config/shh/play-service-accounts/fastread-google-play-service-account.json
```

Fastlane also accepts `FASTREAD_PLAY_SERVICE_ACCOUNT_JSON`, `SUPPLY_JSON_KEY`, `PLAY_STORE_JSON_KEY`, and the legacy gitignored repo-local paths under `android-spike/`.

The preflight expects the service-account email to contain `fastread` so a `shos`/other-app key is not reused by accident. If you intentionally use a shared Play uploader, grant that account access to the FastRead Play app first and run with `FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT=1`.

1. Open [Play Console → Setup → API access](https://play.google.com/console/u/0/developers/api-access).
2. Link or create a Google Cloud project. Naming doesn't matter — `fastread-publisher` is fine.
3. In the linked Cloud project, enable the **Google Play Android Developer API**:
   [https://console.cloud.google.com/apis/api/androidpublisher.googleapis.com](https://console.cloud.google.com/apis/api/androidpublisher.googleapis.com)
4. Back in Play Console → API access, click **Create new service account**.
5. Cloud console opens. Create a service account named `fastread-publisher`. Skip optional roles. Click **Create**.
6. After creation, click the service account → **Keys → Add key → Create new key → JSON**. Browser downloads the JSON.
7. Move the JSON to the canonical machine-local path:

   ```
   ~/.config/shh/play-service-accounts/fastread-google-play-service-account.json
   ```

   Do not commit it. A gitignored repo-local copy at `android-spike/google-service-account.fastread.json` also works, but the canonical path survives clean worktrees and prevents this blocker from recurring.

8. Back in Play Console → API access, find the new service account in the list and click **Manage Play Console permissions**. Grant:

   ```
   View app information
   Release apps to testing tracks
   Manage testing tracks and edit tester lists
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

If `upload-keystore.jks` is destroyed without a backup:

1. Generate a new upload keystore (any password, just something you'll remember).
2. Open Play Console → App → Setup → App signing → **Request upload key reset**.
3. Attach a small certificate-only PEM exported from the new keystore.
4. Wait ~24h for Google to manually verify and swap the upload key.

The Play **app signing key** never leaves Google's HSM, so a lost upload key is not the end of the world — it's only used to re-sign new uploads, not to authenticate the published artefact on devices.

## 7. Common stumbling blocks

| Symptom | Fix |
| --- | --- |
| `Failed to read key justread from store ... Given final block not properly padded` during `bundleRelease` | PKCS12 keystores must use the same password for store and key. `keystore.properties` `keyPassword` should equal `storePassword`. |
| Play Console rejects the AAB with "signed with the wrong key" | Stop and compare SHA-1. On May 15, 2026 Play expected `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`, while local `upload-keystore.jks` signed as `REPLACEMENT_UPLOAD_KEY_SHA1`. Recover the original upload keystore or request an upload-key reset; do not keep uploading the same AAB. |
| `Google Play credential must be a Google Cloud service-account JSON key` | Fastlane is reading a Firebase `google-services.json` or an OAuth client file. Re-download the right file from Play Console → API access. |
| Service account auth fails with `403` | Permission propagation lag. Wait 5 min and retry. If still failing, re-grant in Play Console → API access. |

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
