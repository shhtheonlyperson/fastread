#!/usr/bin/env bash
# Export the certificate-only PEM Play Console needs for an upload-key reset.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android-spike"
OUTPUT_PATH="${1:-${FASTREAD_UPLOAD_RESET_CERT_PATH:-/tmp/fastread-upload-certificate.pem}}"

log() {
  printf '[fastread-upload-reset-cert] %s\n' "$*"
}

if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
fi
if [ -n "${JAVA_HOME:-}" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

properties_path="$ANDROID_DIR/keystore.properties"
if [ ! -f "$properties_path" ]; then
  printf '[fastread-upload-reset-cert] ERROR: missing %s\n' "$properties_path" >&2
  exit 1
fi

property_value() {
  awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$properties_path"
}

store_file="$(property_value storeFile)"
store_password="$(property_value storePassword)"
key_alias="$(property_value keyAlias)"

if [ -z "$store_file" ] || [ -z "$store_password" ]; then
  printf '[fastread-upload-reset-cert] ERROR: keystore.properties must define storeFile and storePassword\n' >&2
  exit 1
fi

if [ "${store_file#/}" = "$store_file" ]; then
  store_path="$ANDROID_DIR/app/$store_file"
else
  store_path="$store_file"
fi
store_dir="$(dirname "$store_path")"
if [ -d "$store_dir" ]; then
  store_path="$(cd "$store_dir" && pwd -P)/$(basename "$store_path")"
fi

if [ ! -f "$store_path" ]; then
  printf '[fastread-upload-reset-cert] ERROR: upload keystore not found at %s\n' "$store_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
keytool -exportcert -rfc \
  -alias "${key_alias:-justread}" \
  -keystore "$store_path" \
  -storepass "$store_password" \
  -file "$OUTPUT_PATH" >/dev/null
chmod 600 "$OUTPUT_PATH"

log "Wrote upload-key reset certificate: $OUTPUT_PATH"
log "Upload this PEM in Play Console -> JustRead -> App signing -> Request upload key reset."
