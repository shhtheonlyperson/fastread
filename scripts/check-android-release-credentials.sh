#!/usr/bin/env bash
# Fast fail the Android release before spending time on a build.
#
# Checks only release credentials:
# - a Google Play Developer API service-account JSON exists and has the right shape
# - android-spike/keystore.properties points at an upload keystore whose SHA1
#   matches the Play Console upload-certificate expectation
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android-spike"
PREFERRED_SERVICE_ACCOUNT_PATH="$HOME/.config/shh/play-service-accounts/fastread-google-play-service-account.json"
PREFERRED_SERVICE_ACCOUNT_MANIFEST="${PREFERRED_SERVICE_ACCOUNT_PATH%.json}.manifest"
EXPECTED_UPLOAD_SHA1="${FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1:-FASTREAD_PLAY_EXPECTED_UPLOAD_SHA1}"
FAILED=0

log() {
  printf '[android-release-preflight] %s\n' "$*"
}

fail() {
  printf '[android-release-preflight] ERROR: %s\n' "$*" >&2
  FAILED=1
}

if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
fi
if [ -n "${JAVA_HOME:-}" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

service_account_candidates=()
for env_name in FASTREAD_PLAY_SERVICE_ACCOUNT_JSON SUPPLY_JSON_KEY PLAY_STORE_JSON_KEY; do
  env_value="${!env_name:-}"
  if [ -n "$env_value" ]; then
    service_account_candidates+=("$env_value")
  fi
done
service_account_candidates+=(
  "$PREFERRED_SERVICE_ACCOUNT_PATH"
  "$HOME/.config/shh/play-service-accounts/google-service-account.fastread.json"
  "$HOME/.config/shh/play-service-accounts/google-play-service-account.fastread.json"
  "$ANDROID_DIR/google-service-account.fastread.json"
  "$ANDROID_DIR/google-play-service-account.fastread.json"
)

service_account_path=""
for candidate in "${service_account_candidates[@]}"; do
  if [ -f "$candidate" ]; then
    service_account_path="$candidate"
    break
  fi
done

if [ -z "$service_account_path" ]; then
  fail "Missing fastread Play service-account JSON. Preferred path: ~/.config/shh/play-service-accounts/fastread-google-play-service-account.json"
  log "If you have a downloaded key, install and back it up with:"
  log "scripts/install-android-play-service-account.sh /path/to/downloaded-service-account.json"
else
  if ! service_account_email="$(
    ruby -rjson -e '
      path = ARGV.fetch(0)
      data = JSON.parse(File.read(path))
      missing = %w[type client_email private_key token_uri].select { |key| data[key].to_s.empty? }
      abort("missing required fields: #{missing.join(", ")}") unless missing.empty?
      abort("not a Google service-account JSON") unless data["type"] == "service_account" && data["client_email"].to_s.end_with?(".gserviceaccount.com") && data["private_key"].to_s.include?("BEGIN PRIVATE KEY")
      unless data["client_email"].include?("fastread") || ENV["FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT"] == "1"
        abort("service-account email is not FastRead-specific: #{data["client_email"]}")
      end
      puts data["client_email"]
    ' "$service_account_path"
  )"; then
    fail "Invalid FastRead Play service-account JSON at $service_account_path. Use a fastread-publisher key, or set FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT=1 only after granting a shared account access to the FastRead Play app."
  else
    log "Play service-account JSON found: $service_account_path ($service_account_email)"
    if [ "$service_account_path" = "$PREFERRED_SERVICE_ACCOUNT_PATH" ] && [ ! -f "$PREFERRED_SERVICE_ACCOUNT_MANIFEST" ]; then
      log "Canonical JSON is installed without a manifest. Re-run scripts/install-android-play-service-account.sh on the source JSON to create a local backup + checksum marker."
    elif [ "$service_account_path" != "$PREFERRED_SERVICE_ACCOUNT_PATH" ] && [ -z "${FASTREAD_PLAY_SERVICE_ACCOUNT_JSON:-}${SUPPLY_JSON_KEY:-}${PLAY_STORE_JSON_KEY:-}" ]; then
      log "Using a legacy fallback JSON. Install it to the canonical path with scripts/install-android-play-service-account.sh so clean worktrees do not lose it again."
    fi
  fi
fi

properties_path="$ANDROID_DIR/keystore.properties"
if [ ! -f "$properties_path" ]; then
  fail "Missing $properties_path"
else
  property_value() {
    awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$properties_path"
  }

  store_file="$(property_value storeFile)"
  store_password="$(property_value storePassword)"
  key_alias="$(property_value keyAlias)"

  if [ -z "$store_file" ] || [ -z "$store_password" ]; then
    fail "keystore.properties must define storeFile and storePassword"
  else
    if [ "${store_file#/}" = "$store_file" ]; then
      # Gradle resolves `file(...)` in app/build.gradle.kts relative to the app
      # module directory, so ../upload-keystore.jks means android-spike/upload-keystore.jks.
      store_path="$ANDROID_DIR/app/$store_file"
    else
      store_path="$store_file"
    fi
    store_dir="$(dirname "$store_path")"
    if [ -d "$store_dir" ]; then
      store_path="$(cd "$store_dir" && pwd -P)/$(basename "$store_path")"
    fi

    if [ ! -f "$store_path" ]; then
      fail "Upload keystore not found at $store_path"
    elif ! command -v keytool >/dev/null 2>&1; then
      fail "keytool not on PATH. Install OpenJDK 21 or set JAVA_HOME."
    else
      actual_sha1="$(
        keytool -list -v \
          -keystore "$store_path" \
          -alias "${key_alias:-justread}" \
          -storepass "$store_password" 2>/dev/null |
          awk -F'SHA1: ' '/SHA1:/ { print $2; exit }'
      )"

      if [ -z "$actual_sha1" ]; then
        fail "Could not read SHA1 from upload keystore at $store_path"
      elif [ "$actual_sha1" != "$EXPECTED_UPLOAD_SHA1" ]; then
        fail "Upload keystore SHA1 mismatch. Play expects $EXPECTED_UPLOAD_SHA1; local keystore signs with $actual_sha1."
        log "Use the original upload keystore, or request a Play upload-key reset with:"
        log "keytool -exportcert -rfc -alias ${key_alias:-justread} -keystore $store_path -file /tmp/fastread-upload-certificate.pem"
      else
        log "Upload keystore SHA1 matches Play Console expectation."
      fi
    fi
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

log "Android release credentials are ready."
