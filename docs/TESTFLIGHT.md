# TestFlight Release Runbook

Public-safe procedure for uploading the native iOS app to TestFlight. Keep
App Store Connect key IDs, issuer IDs, private-key paths, certificate IDs,
provisioning-profile UUIDs, and dashboard-only values out of this file.

## Local Secrets

Never commit:

- `.env.local`
- `AuthKey_*.p8`
- `.p12`, `.cer`, `.key`, `.mobileprovision`
- exported `.ipa` files and archives
- generated build directories

`scripts/release-ios-testflight.sh` reads `.env.local` when present. Required
local values:

```bash
FASTREAD_ASC_APP_ID="<App Store Connect app id>"
ASC_KEY_ID="<App Store Connect API key id>"
ASC_ISSUER_ID="<App Store Connect issuer id>"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
FASTREAD_TEAM_ID="<Apple team id>"
FASTREAD_BUILD_KEYCHAIN="$HOME/Library/Keychains/fastread-build.keychain-db"
FASTREAD_CODESIGN="<dedicated build keychain password>"
```

## Before Upload

1. Confirm the App Store Connect app is the JustRead/FastRead record you expect.
2. Confirm the Release bundle identifier matches the ASC record.
3. Bump `CURRENT_PROJECT_VERSION` to a number higher than every accepted build.
4. Confirm `FastReadApp/Info.plist` declares:

   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```

5. Ensure the distribution certificate and provisioning profile are available
   locally through Xcode/keychain.

## Release Script

```bash
scripts/release-ios-testflight.sh
```

The script:

- validates ASC credentials;
- unlocks the dedicated build keychain when present;
- archives the app;
- exports an App Store Connect IPA;
- validates and uploads with `xcrun altool`;
- polls ASC build state.

If a build number is already used, bump `CURRENT_PROJECT_VERSION` and rerun.

## Manual Validation

Do not stop at `processingState=VALID`. Verify the build reaches internal
TestFlight availability. If export compliance appears, confirm the app still
uses no non-exempt encryption and clear the build attribute in App Store
Connect.

## Common Stumbling Blocks

| Symptom | Fix |
| --- | --- |
| Missing ASC key | Set `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` locally. |
| Duplicate build number | Bump `CURRENT_PROJECT_VERSION` and upload again. |
| Wrong bundle identifier | Align the Release build settings with the ASC app record. |
| Code signing asks through macOS UI | Set `FASTREAD_CODESIGN` locally, then let the release script unlock the dedicated keychain and grant `codesign` access. If it still asks, remove stale duplicate signing identities from other keychains. |
| Code signing hangs | Unlock or recreate the dedicated build keychain, then remove stale duplicate signing identities. |
| Missing export compliance | Keep `ITSAppUsesNonExemptEncryption=false` and clear the build state in ASC if needed. |

## After Acceptance

After the build reaches internal TestFlight availability:

```bash
git tag "v<marketing-version>-build<build-number>"
git push origin --tags
```

Commit build-number bumps separately from unrelated product changes.
