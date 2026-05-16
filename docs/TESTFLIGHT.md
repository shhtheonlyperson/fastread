# TestFlight upload runbook

> **Project-agnostic procedure has moved to the wiki:**
> [`~/Documents/wiki/shh/TestFlight.md`](file:///Users/shh/Documents/wiki/shh/TestFlight.md)
>
> That doc covers both build paths (Expo + EAS local, bare iOS Xcode), the
> shared validate → upload → poll → clear-export-compliance flow, and a
> stumbling-blocks table.
>
> This file kept for fastread-specific values + the dense manual-cert flow
> (RSA CSR, IOS_DISTRIBUTION cert, IOS_APP_STORE profile, keychain import)
> that the wiki references in §3 Path B but doesn't duplicate.

## Current source of truth

Use this section first. It reflects the successful May 16, 2026 upload and supersedes older assumptions in this file.

- App Store Connect app: `JustRead Speed Reader`
- ASC app id: `ASC_APP_ID_PLACEHOLDER`
- Bundle id: `com.shhtheonlyperson.fastread`
- Bundle id resource id: `BUNDLE_RESOURCE_ID_PLACEHOLDER`
- Team id: `QLJ9ZM278S`
- Issuer id: `ASC_ISSUER_ID_PLACEHOLDER`
- Active ASC API key id: `ASC_KEY_ID_PLACEHOLDER`
- Active key path: `~/.appstoreconnect/private_keys/AuthKey_ASC_KEY_ID_PLACEHOLDER.p8`
- Stale/revoked key id to avoid: `REVOKED_ASC_KEY_ID_PLACEHOLDER`
- Current TestFlight version line: `0.2.1`
- Latest successfully uploaded build: `32`
- Latest delivery/build UUID: `6420a091-f44a-4ad1-890e-732b4ef541b1` — build 32 is the 1,500 WPM support release from commit `854e2be`, including iOS, Android, and Chrome parity plus refreshed store/version metadata.
- Active distribution cert id: `DISTRIBUTION_CERT_ID_PLACEHOLDER` (issued 2026-05-09, replaces revoked `5853F89C…`)
- Active provisioning profile UUID: `PROVISIONING_PROFILE_UUID_PLACEHOLDER`
- Builds `26`, `27`, `28`, `29`, `30`, `31`, and `32` all reached `IN_BETA_TESTING` directly because `Info.plist` declares `ITSAppUsesNonExemptEncryption=NO`; no manual export-compliance patch was needed.
- Android counterpart source is now at `0.2.1` versionCode `8`; the signed AAB validates locally at `android-spike/app/build/outputs/bundle/release/app-release.aab`, but Play upload is blocked by upload-key mismatch and missing repo-local service-account JSON (see [`docs/PLAY_CONSOLE_ANDROID.md`](PLAY_CONSOLE_ANDROID.md)).
- If `errSecInternalComponent` shows up during CodeSign, the dedicated `fastread-build.keychain-db` has auto-locked; unlock it (`security unlock-keychain -p fastread …`) and re-grant the partition list. See §"May 9, 2026 — login keychain CDSA hang gotcha" below.
- If `xcrun altool` rejects an upload with `ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE` and `previousBundleVersion: N`, that build number is already registered on ASC even if it never reached your TestFlight UI — bump `CURRENT_PROJECT_VERSION` to `N+1` and re-archive. Build 28 burned this way on 2026-05-11.

Important: do not trust `.env.local` blindly. During the May 8 release, `.env.local` pointed at revoked key `REVOKED_ASC_KEY_ID_PLACEHOLDER`.

The existing App Store Connect record is for `com.shhtheonlyperson.fastread`, not `com.shh.fastread`. If the Xcode project drifts back to `com.shh.fastread` or a different marketing version such as `1.4.0`, align the Release build back to the ASC record before uploading.

The app should declare no non-exempt encryption in `FastReadApp/Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

## May 9, 2026 — login keychain CDSA hang gotcha

If `codesign` hangs indefinitely after "replacing existing signature" on a freshly-imported `.p12` distribution identity, the import landed in the legacy CDSA path of `login.keychain-db` and `securityd` never returns. Symptoms:

- `xcodebuild archive` sits in the CodeSign step for >10 minutes.
- Standalone `codesign --force --sign <hash> --timestamp=none /tmp/test.sh` never completes (sample shows `mach_msg2_trap` blocked in `Security::SecurityServer::ClientSession::generateSignature`).
- The same `codesign` call against an Xcode-managed identity (e.g. `Apple Development: Created via API (ASC_KEY_ID_PLACEHOLDER)`) succeeds in <1s, proving the signer/network are fine.

Workaround that actually shipped build 26:

```bash
KEYCHAIN=~/Library/Keychains/fastread-build.keychain-db
PASS="fastread"
security delete-keychain "$KEYCHAIN" 2>/dev/null
security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASS" "$KEYCHAIN"
# Add to user search list, keep login.keychain-db alongside
security list-keychains -d user -s "$KEYCHAIN" \
  $(security list-keychains -d user | sed 's/[" ]//g')
# Build the .p12 with PBE-SHA1-3DES (security only imports legacy format
# correctly) but import it into the FRESH keychain so the key lives in the
# modern data-protection store, not CDSA.
openssl pkcs12 -export \
  -inkey distribution.key -in distribution.cer \
  -out distribution-legacy.p12 -name "JustRead Distribution" \
  -password pass:"$PASS" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1 -legacy
security import distribution-legacy.p12 -k "$KEYCHAIN" -P "$PASS" \
  -A -T /usr/bin/codesign
security set-key-partition-list \
  -S "apple-tool:,apple:,codesign:" -s -k "$PASS" "$KEYCHAIN"
# IMPORTANT: also remove the broken duplicate from login.keychain-db,
# otherwise xcodebuild may pick the CDSA copy first and hang.
security delete-identity -Z <hash> ~/Library/Keychains/login.keychain-db
```

After this, `codesign` against the new identity returns immediately and `xcodebuild ... archive` finishes in ~3 minutes.

## May 8, 2026 working flow

If a local Apple Distribution identity with private key is missing, create signing material through the ASC API instead of relying on Xcode account state:

1. Generate an RSA 2048 CSR. Apple rejected EC CSRs with `CSR algorithm/size incorrect. Expected: RSA(2048)`.
2. Create an `IOS_DISTRIBUTION` certificate using active API key `ASC_KEY_ID_PLACEHOLDER`.
3. Create an `IOS_APP_STORE` profile for bundle id resource `BUNDLE_RESOURCE_ID_PLACEHOLDER`.
4. Install the `.mobileprovision` under `~/Library/MobileDevice/Provisioning Profiles/`.
5. Import the generated private key and `.cer` into the login keychain.
6. Verify `security find-identity -v -p codesigning` shows `iPhone Distribution: ShihChi Huang (QLJ9ZM278S)`.
7. Archive with manual Release signing scoped only to the app target. Do not pass `PROVISIONING_PROFILE_SPECIFIER` globally to `xcodebuild archive`; it also applies to Swift package targets like `ZIPFoundation` and fails.
8. Export using `method=app-store-connect`, `signingStyle=manual`, team `QLJ9ZM278S`, and `provisioningProfiles` mapping `com.shhtheonlyperson.fastread` to the generated profile UUID.
9. Validate and upload:

```bash
xcrun altool --validate-app \
  -f build/export/JustRead.ipa \
  -t ios \
  --apiKey ASC_KEY_ID_PLACEHOLDER \
  --apiIssuer ASC_ISSUER_ID_PLACEHOLDER

xcrun altool --upload-app \
  -f build/export/JustRead.ipa \
  -t ios \
  --apiKey ASC_KEY_ID_PLACEHOLDER \
  --apiIssuer ASC_ISSUER_ID_PLACEHOLDER
```

After upload, poll ASC builds. Build `24` appeared as `VALID` roughly one minute after upload:

```text
version: 0.2.1
build: 24
processingState: VALID
```

Do not stop at `processingState: VALID`. Also inspect `buildBetaDetail`:

```text
internalBuildState: IN_BETA_TESTING
externalBuildState: READY_FOR_BETA_SUBMISSION
usesNonExemptEncryption: false
```

If the build shows `MISSING_EXPORT_COMPLIANCE`, clear it with:

```http
PATCH /v1/builds/{build_id}
{
  "data": {
    "type": "builds",
    "id": "{build_id}",
    "attributes": {
      "usesNonExemptEncryption": false
    }
  }
}
```

On May 8, 2026, build `24` initially showed `MISSING_EXPORT_COMPLIANCE`. Setting `usesNonExemptEncryption=false` changed it to `IN_BETA_TESTING` internally.

Internal TestFlight groups cannot be assigned through `POST /v1/builds/{id}/relationships/betaGroups`; Apple returns `Builds cannot be assigned to this internal group`. Treat a `VALID` uploaded build as the CLI completion point, then verify group availability in App Store Connect UI if needed.

End-to-end steps for taking the current `main` iOS build of JustRead to TestFlight from the command line. Assumes a working iOS Distribution certificate is reachable through Xcode (sign in once via Xcode → Settings → Accounts if you haven't on this machine).

The iOS distribution path is native Xcode only; there is no Expo / EAS pipeline. The repo also contains Android and Chrome extension targets, but TestFlight distribution goes through `xcodebuild archive` + `xcrun altool`.

---

## 1. Resolve the App Store Connect API key

`xcrun altool` needs a `(key id, issuer id, .p8 file)` triple. The repo expects them in `.env.local` plus a `.p8` somewhere altool searches.

`.env.local` lives at the repo root and is `.gitignore`'d. It must contain:

```sh
ASC_KEY_ID=...
ASC_ISSUER_ID=...
```

The matching `AuthKey_<ASC_KEY_ID>.p8` file must exist in one of:

- `~/.appstoreconnect/private_keys/`
- `~/private_keys/`
- `~/.private_keys/`
- repo root

If `.env.local`'s `ASC_KEY_ID` doesn't match any `.p8` on disk, fix one side or the other. Likely culprit: a stale `.env.local` from a different App Store Connect key. The `.p8` must come from App Store Connect → Users and Access → Keys (download once, can't re-download).

Verify:

```bash
set -a; source .env.local; set +a
xcrun altool --list-providers --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

If providers print without an error, auth is good.

---

## 2. Confirm the App Store Connect record

Two bundle IDs have been used historically:

| When | Bundle ID | Scheme | Notes |
| --- | --- | --- | --- |
| Early 2026 | `com.shhtheonlyperson.fastread` | `JustRead` | Last archive May 6, build 20 |
| Current | `com.shh.fastread` | `FastRead` | What `main` ships today |

Open App Store Connect → My Apps and confirm which record you want to receive this build. If the live record is the older bundle id, flip `PRODUCT_BUNDLE_IDENTIFIER` in `FastRead.xcodeproj/project.pbxproj` back before archiving (and consider renaming the scheme to `JustRead` for archive-name consistency).

---

## 3. Bump the build number

```bash
# Open FastRead.xcodeproj/project.pbxproj and bump CURRENT_PROJECT_VERSION.
# Each upload to a given bundle id must have a strictly higher build number
# than every prior accepted build. altool will reject duplicates with a
# clear message — bump and retry.

sed -i '' 's/CURRENT_PROJECT_VERSION = 1;/CURRENT_PROJECT_VERSION = 21;/' FastRead.xcodeproj/project.pbxproj
git diff FastRead.xcodeproj/project.pbxproj
```

Marketing version (`MARKETING_VERSION`) does not need to change for a TestFlight build; the build number alone differentiates uploads under a given marketing version.

---

## 4. Archive, export, validate, upload

```bash
ARCHIVE=build/JustRead.xcarchive
EXPORT=build/export
mkdir -p build

# 4a. Archive — automatic signing, generic iOS device destination.
xcodebuild \
  -project FastRead.xcodeproj \
  -scheme FastRead \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

# 4b. ExportOptions.plist for the App Store distribution method.
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>QLJ9ZM278S</string>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
PLIST

# 4c. Export the .ipa.
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates

# 4d. Validate before upload — cheap dry run that catches most problems.
set -a; source .env.local; set +a
xcrun altool --validate-app \
  -f "$EXPORT/JustRead.ipa" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

# 4e. Upload.
xcrun altool --upload-app \
  -f "$EXPORT/JustRead.ipa" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

Successful upload prints `No errors uploading 'JustRead.ipa'`.

---

## 5. After upload

- App Store Connect → My Apps → JustRead → TestFlight: build appears in 5–30 minutes (longer for the first build to a new bundle id), status `Processing` → `Ready to Submit`.
- Internal testers: add the build to a test group manually.
- External testers: first build to a new external group needs Beta App Review (~24h).
- Export-compliance prompt: respond once in App Store Connect, or set `ITSAppUsesNonExemptEncryption=NO` in `Info.plist` to skip the prompt for future builds (only valid if the app uses no non-exempt cryptography beyond what the OS provides).

---

## 6. Common stumbling blocks

| Symptom | Fix |
| --- | --- |
| `No accounts with iOS Distribution certificates` | Xcode → Settings → Accounts → Manage Certificates → `+` → Apple Distribution. |
| `Provisioning profile doesn't match bundle id` | Re-archive with `-allowProvisioningUpdates`; Xcode regenerates the profile. |
| `Bundle Version must be higher than the previously approved version` | Bump `CURRENT_PROJECT_VERSION` again, re-archive, re-upload. |
| `Invalid API Key` / `Authentication credentials are missing or invalid` | Mismatched key id ↔ `.p8` file. Re-run §1 verification. |
| Validate succeeds but upload hangs | Network or ASC backend hiccup. Retry once; otherwise check Apple System Status. |

---

## 7. Hygiene after a successful upload

```bash
# Tag the release
git tag "v$(plutil -extract MARKETING_VERSION raw -o - FastReadApp/Info.plist)-build$(plutil -extract CFBundleVersion raw -o - FastReadApp/Info.plist)"
git push origin --tags

# Commit the build bump on its own
git add FastRead.xcodeproj/project.pbxproj
git commit -m "Bump build to NN for TestFlight"
git push origin main
```

Keep build-number bumps and bundle-id changes in separate commits so you can revert one without the other.

---

## 8. Files that must never be committed

`.gitignore` already covers these; double-check before adding any release-related artifact:

- `.env.local` (key id + issuer id)
- `AuthKey_*.p8` (API private key)
- `build/` (archives, ipas)
- `*.zip`

If any of those leak into a commit, rotate the corresponding App Store Connect key in the portal and re-issue.
