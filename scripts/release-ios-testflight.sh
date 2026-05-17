#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

SCHEME="${FASTREAD_IOS_SCHEME:-FastRead}"
PROJECT="${FASTREAD_IOS_PROJECT:-FastRead.xcodeproj}"
CONFIGURATION="${FASTREAD_IOS_CONFIGURATION:-Release}"
ASC_APP_ID="${FASTREAD_ASC_APP_ID:-ASC_APP_ID_PLACEHOLDER}"
ASC_KEY_ID="${ASC_KEY_ID:-ASC_KEY_ID_PLACEHOLDER}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-ASC_ISSUER_ID_PLACEHOLDER}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
TEAM_ID="${FASTREAD_TEAM_ID:-QLJ9ZM278S}"
BUILD_KEYCHAIN="${FASTREAD_BUILD_KEYCHAIN:-$HOME/Library/Keychains/fastread-build.keychain-db}"
BUILD_KEYCHAIN_PASSWORD="${FASTREAD_BUILD_KEYCHAIN_PASSWORD:-fastread}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="${FASTREAD_ARCHIVE_PATH:-$ROOT_DIR/build/JustRead-$STAMP.xcarchive}"
EXPORT_DIR="${FASTREAD_EXPORT_DIR:-$ROOT_DIR/build/export-$STAMP}"
EXPORT_OPTIONS="$ROOT_DIR/build/ExportOptions-$STAMP.plist"

log() {
  printf '[fastread-ios-release] %s\n' "$*"
}

fail() {
  printf '[fastread-ios-release] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_clean() {
  if [[ "${FASTREAD_ALLOW_DIRTY:-0}" == "1" ]]; then
    return
  fi
  local status
  status="$(git status --porcelain)"
  [[ -z "$status" ]] || fail "worktree is dirty. Commit/stash first, or set FASTREAD_ALLOW_DIRTY=1."
}

ensure_auth() {
  [[ -f "$ASC_KEY_PATH" ]] || fail "missing ASC API key at $ASC_KEY_PATH"
}

unlock_keychain() {
  if [[ -f "$BUILD_KEYCHAIN" ]]; then
    security unlock-keychain -p "$BUILD_KEYCHAIN_PASSWORD" "$BUILD_KEYCHAIN" || true
    security set-key-partition-list \
      -S "apple-tool:,apple:,codesign:" \
      -s \
      -k "$BUILD_KEYCHAIN_PASSWORD" \
      "$BUILD_KEYCHAIN" >/dev/null 2>&1 || true
  fi
}

project_setting() {
  local key="$1"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F'= ' -v k="$key" '{lhs=$1; gsub(/^[ \t]+|[ \t]+$/, "", lhs); if (lhs == k) {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}}'
}

asc_latest_build_number() {
  node - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" "$ASC_APP_ID" <<'NODE'
const fs = require("fs");
const crypto = require("crypto");
const [keyId, issuerId, keyPath, appId] = process.argv.slice(2);
const key = fs.readFileSync(keyPath, "utf8");
const b64u = (input) => Buffer.from(input).toString("base64").replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const now = Math.floor(Date.now() / 1000);
const header = b64u(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
const payload = b64u(JSON.stringify({ iss: issuerId, exp: now + 600, aud: "appstoreconnect-v1" }));
const signingInput = `${header}.${payload}`;
const signer = crypto.createSign("SHA256");
signer.update(signingInput);
const signature = signer.sign({ key, dsaEncoding: "ieee-p1363" }).toString("base64").replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const token = `${signingInput}.${signature}`;
const url = new URL("https://api.appstoreconnect.apple.com/v1/builds");
url.searchParams.set("filter[app]", appId);
url.searchParams.set("sort", "-uploadedDate");
url.searchParams.set("limit", "50");
(async () => {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const text = await res.text();
  if (!res.ok) {
    console.error(text);
    process.exit(1);
  }
  const data = JSON.parse(text);
  const numbers = (data.data || [])
    .map((b) => Number.parseInt(b.attributes && b.attributes.version, 10))
    .filter(Number.isFinite);
  console.log(numbers.length ? Math.max(...numbers) : 0);
})().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
NODE
}

set_build_number() {
  local next="$1"
  perl -0pi -e "s/CURRENT_PROJECT_VERSION = \\d+;/CURRENT_PROJECT_VERSION = $next;/g" "$PROJECT/project.pbxproj"
}

write_export_options() {
  local bundle_id profile_specifier
  bundle_id="$(project_setting PRODUCT_BUNDLE_IDENTIFIER)"
  profile_specifier="$(project_setting PROVISIONING_PROFILE_SPECIFIER)"
  [[ -n "$bundle_id" ]] || fail "missing PRODUCT_BUNDLE_IDENTIFIER"
  [[ -n "$profile_specifier" ]] || fail "missing PROVISIONING_PROFILE_SPECIFIER"
  mkdir -p "$ROOT_DIR/build"
  cat >"$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
  <key>provisioningProfiles</key>
  <dict>
    <key>$bundle_id</key><string>$profile_specifier</string>
  </dict>
</dict>
</plist>
PLIST
}

ipa_plist_value() {
  local ipa="$1"
  local key="$2"
  local tmp plist
  tmp="$(mktemp -d)"
  unzip -q "$ipa" "Payload/*.app/Info.plist" -d "$tmp"
  plist="$(find "$tmp/Payload" -name Info.plist -path '*.app/Info.plist' | head -n 1)"
  [[ -n "$plist" ]] || fail "cannot find Info.plist in $ipa"
  plutil -extract "$key" raw -o - "$plist"
  rm -rf "$tmp"
}

archive_export_upload() {
  local build_number="$1"
  write_export_options
  rm -rf "$ARCHIVE" "$EXPORT_DIR"
  mkdir -p "$ROOT_DIR/build" "$EXPORT_DIR"

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive

  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

  local ipa
  ipa="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -n 1)"
  [[ -f "$ipa" ]] || fail "no IPA exported under $EXPORT_DIR"

  local short_version actual_build
  short_version="$(ipa_plist_value "$ipa" CFBundleShortVersionString)"
  actual_build="$(ipa_plist_value "$ipa" CFBundleVersion)"
  [[ "$actual_build" == "$build_number" ]] || fail "archive build number $actual_build did not match expected $build_number"

  xcrun altool --validate-app "$ipa" \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH" \
    --output-format json

  xcrun altool --upload-package "$ipa" \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH" \
    --wait \
    --show-progress \
    --output-format json

  xcrun altool --build-status \
    --apple-id "$ASC_APP_ID" \
    --bundle-version "$actual_build" \
    --bundle-short-version-string "$short_version" \
    --platform ios \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH" \
    --wait \
    --output-format json

  log "Uploaded TestFlight build $short_version ($actual_build): $ipa"
}

ensure_clean
ensure_auth
unlock_keychain

local_build="$(project_setting CURRENT_PROJECT_VERSION)"
remote_build="$(asc_latest_build_number)"
next_build=$(( local_build > remote_build ? local_build : remote_build + 1 ))

log "Current local build: $local_build; latest ASC build: $remote_build; next: $next_build"
set_build_number "$next_build"
archive_export_upload "$next_build"

log "Build number bump is staged in $PROJECT/project.pbxproj. Commit it after verifying the upload."
