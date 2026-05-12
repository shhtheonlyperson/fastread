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
