# FastRead Assistant Notes

## Platform Parity

When making an app fix, check and update Android too. Treat an iOS-only fix as incomplete unless the user explicitly scopes the task to iOS only or Android is technically not applicable. If Android cannot be verified locally, say exactly why and what remains unverified.

## Release Shorthand

If the user says `bump release`, treat it as:

- sync to the latest `origin/main` / `main` state first;
- bump the store build number/version code as needed for the next release;
- release the mobile app from that latest main state;
- prioritize iOS/TestFlight, then Android internal testing if the Play service-account JSON is available;
- verify store acceptance, not just local build success.

Do not ask whether this means web, desktop, docs, or package publishing. In this repo, `bump release` means mobile release.

## Android Play Release

Before attempting an Android internal-testing release, read `docs/PLAY_CONSOLE_ANDROID.md` and verify live Play Console state.

Current Play Console app:

- App: `JustRead`
- Package: `com.shhtheonlyperson.fastread`
- Current internal release observed: `0.2.1 (4)`

Key pitfalls:

- Do not trust `docs/PLAY_CONSOLE_ANDROID.md` or local Gradle metadata blindly; Play Console is the source of truth for package name and signing key.
- Before upload, inspect the built AAB manifest and confirm package/version: `bundletool dump manifest --bundle=android-spike/app/build/outputs/bundle/release/app-release.aab`.
- Before upload, compare the local upload keystore SHA1/SHA256 to the Play Console expected upload certificate.
- Before any Android release build/upload, run `scripts/check-android-release-credentials.sh`. The canonical machine-local Play service-account JSON path is `~/.config/shh/play-service-accounts/fastread-google-play-service-account.json`; repo-local JSON copies are only a fallback.
- When creating or re-downloading the FastRead Play service-account JSON, immediately run `scripts/install-android-play-service-account.sh ~/Downloads/<downloaded-key>.json`. This validates the key, installs it to the canonical machine-local path, writes a local backup, and creates a checksum manifest so clean worktrees do not lose it again. For off-machine backup, run the installer with `FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_VAULT=<vault>` and approve the 1Password prompt.
- If Play rejects the AAB with "signed with the wrong key", stop. Do not keep uploading, generate another keystore, or call the release done. Find the original upload keystore or request an upload-key reset.
- On 2026-05-14, Play expected SHA1 `FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1`; the local `android-spike/upload-keystore.jks` signed with SHA1 `REPLACEMENT_UPLOAD_KEY_SHA1`, so Android upload was blocked pending original-key recovery or Play upload-key reset.
- If requesting an upload-key reset, export the replacement cert with `keytool -exportcert -rfc -alias justread -keystore android-spike/upload-keystore.jks -file /tmp/fastread-upload-certificate.pem`.

## iOS TestFlight Release

Before attempting any iOS/TestFlight release, read `docs/TESTFLIGHT.md`.

Current release target:

- App Store Connect app: `JustRead Speed Reader`
- ASC app id: `ASC_APP_ID_PLACEHOLDER`
- Bundle id: `com.shhtheonlyperson.fastread`
- Team id: `QLJ9ZM278S`
- Active ASC API key id: `ASC_KEY_ID_PLACEHOLDER`
- Avoid revoked key id: `REVOKED_ASC_KEY_ID_PLACEHOLDER`

Key pitfalls:

- Do not trust `.env.local` blindly; it previously pointed at revoked key `REVOKED_ASC_KEY_ID_PLACEHOLDER`.
- The App Store Connect record is `com.shhtheonlyperson.fastread`; do not upload `com.shh.fastread`.
- If a distribution private key is missing locally, create an RSA 2048 CSR, then create a new `IOS_DISTRIBUTION` cert and `IOS_APP_STORE` profile through the ASC API.
- Do not pass `PROVISIONING_PROFILE_SPECIFIER` globally to `xcodebuild archive`; scope manual signing to the app target only.
- Do not stop at `processingState=VALID`; verify `buildBetaDetail.internalBuildState=IN_BETA_TESTING`.
- If a build shows `MISSING_EXPORT_COMPLIANCE`, set `usesNonExemptEncryption=false` on the build and keep `ITSAppUsesNonExemptEncryption=false` in `FastReadApp/Info.plist`.
- Internal TestFlight groups cannot be attached with the ASC `builds/{id}/relationships/betaGroups` API.

## Chrome Web Store Release

The browser companion lives at `chrome-ext/` (sibling to the iOS/Android targets). Before working on a Web Store release, read `chrome-ext/CHROME_WEB_STORE.md` and the listing assets at `chrome-ext/store-assets/`.

Current Web Store listing:

- Item ID: `jlphjjnghcblidffelhhiooeghjblfed`
- Item name: `JustRead — Reader View + Speed Reading`
- Publisher account: `shh@theonlyperson.com` (Developer fee paid here)
- Contact email (verified): `shh@theonlyperson.com`
- Privacy policy URL: `https://www.theonlyperson.com/privacy` (source `chrome-ext/store-assets/PRIVACY.md`)
- Category: Tools (under Productivity); Visibility: Public, all regions, free
- Status URL: `https://chrome.google.com/webstore/devconsole/CHROME_DEVELOPER_ID_PLACEHOLDER/jlphjjnghcblidffelhhiooeghjblfed/edit/status`
- Live URL (post-approval): `https://chromewebstore.google.com/detail/jlphjjnghcblidffelhhiooeghjblfed`
- Submitted: 2026-05-15 (tag `chrome-ext-v1.0.0-submitted`)

Key pitfalls:

- The Web Store dropzones for the store icon (128×128) and screenshots (1280×800) reject every programmatic upload path: `setInputFiles`, synthesized `DragEvent('drop', { dataTransfer })`, CDP-level drops. They require a real user gesture (drag from Finder, or click + native file picker). Plan to hand off these uploads to the user; automate the rest.
- Save Draft saves only the currently visible tab. Filling Privacy fields then navigating to Distribution **wipes** the unsaved Privacy values. Pattern: fill page → Save → verify with snapshot → only then navigate.
- The submit-confirm modal's action button is "Submit For Review" (capital F, R). There is a *different* "Publish" button that uses a stored publish-time which defaults to the Unix epoch and surfaces a "Publish time has expired" error. Click "Submit For Review" only.
- The contact email change triggers an emailed verification link that the user has to click before the submit gate lifts. Plan for the inbox round-trip.
- When driving the dashboard via `agent-browser --auto-connect`, the user must launch Chrome with `--remote-debugging-port=9222` first; tab focus changes break the attached CDP target. Use `agent-browser tab list` + `agent-browser tab t<n>` to recover.
