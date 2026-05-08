# FastRead Assistant Notes

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
