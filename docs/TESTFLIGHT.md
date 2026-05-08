# TestFlight upload runbook

End-to-end steps for taking the current `main` build of JustRead to TestFlight from the command line. Assumes a working iOS Distribution certificate is reachable through Xcode (sign in once via Xcode → Settings → Accounts if you haven't on this machine).

The repo is iOS-only; there is no Expo / EAS pipeline. Distribution goes through `xcodebuild archive` + `xcrun altool`.

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
