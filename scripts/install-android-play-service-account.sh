#!/usr/bin/env bash
# Validate and install the FastRead Google Play service-account JSON.
#
# This keeps the secret out of the repo while making the machine-local location
# stable across clean worktrees:
#   ~/.config/shh/play-service-accounts/fastread-google-play-service-account.json
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DEST="$HOME/.config/shh/play-service-accounts/fastread-google-play-service-account.json"
DEST="${FASTREAD_PLAY_SERVICE_ACCOUNT_DEST:-$DEFAULT_DEST}"
BACKUP_DIR="${FASTREAD_PLAY_SERVICE_ACCOUNT_BACKUP_DIR:-$(dirname "$DEST")/backups}"
MANIFEST="${DEST%.json}.manifest"
ONE_PASSWORD_VAULT="${FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_VAULT:-}"
ONE_PASSWORD_TITLE="${FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_TITLE:-FastRead Google Play service-account JSON}"

log() {
  printf '[fastread-play-service-account] %s\n' "$*"
}

usage() {
  cat >&2 <<USAGE
Usage:
  scripts/install-android-play-service-account.sh /path/to/downloaded-service-account.json

Installs to:
  ${DEST}

Environment:
  FASTREAD_PLAY_SERVICE_ACCOUNT_DEST         Override destination path.
  FASTREAD_PLAY_SERVICE_ACCOUNT_BACKUP_DIR   Override local backup directory.
  FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_VAULT
                                           Also archive a document copy to this 1Password vault.
  FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_TITLE
                                           Override the 1Password document title.
  FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT=1
                                           Allow a shared non-fastread service account after Play permissions are granted.
  FASTREAD_ALLOWED_SHARED_PLAY_SERVICE_ACCOUNT_EMAILS
                                           Comma-separated allowlist for shared uploader emails.
USAGE
}

source_path="${1:-}"
if [ -z "$source_path" ] || [ "$source_path" = "-h" ] || [ "$source_path" = "--help" ]; then
  usage
  exit 2
fi

if [ ! -f "$source_path" ]; then
  printf '[fastread-play-service-account] ERROR: source JSON does not exist: %s\n' "$source_path" >&2
  exit 1
fi

source_dir="$(cd "$(dirname "$source_path")" && pwd -P)"
source_abs="$source_dir/$(basename "$source_path")"

metadata="$(
  ruby -rjson -e '
    path = ARGV.fetch(0)
    data = JSON.parse(File.read(path))
    missing = %w[type client_email private_key token_uri].select { |key| data[key].to_s.empty? }
    abort("missing required fields: #{missing.join(", ")}") unless missing.empty?
    unless data["type"] == "service_account" &&
           data["client_email"].to_s.end_with?(".gserviceaccount.com") &&
           data["private_key"].to_s.include?("BEGIN PRIVATE KEY")
      abort("not a Google Cloud service-account JSON key")
    end
    allowed_shared = ENV.fetch("FASTREAD_ALLOWED_SHARED_PLAY_SERVICE_ACCOUNT_EMAILS", "legacy-play-uploader@example.iam.gserviceaccount.com,play-uploader@example.iam.gserviceaccount.com").split(",").map(&:strip)
    unless data["client_email"].include?("fastread") || ENV["FASTREAD_ALLOW_SHARED_PLAY_SERVICE_ACCOUNT"] == "1" || allowed_shared.include?(data["client_email"])
      abort("service-account email is not FastRead-specific: #{data["client_email"]}")
    end
    puts [data["client_email"], data["project_id"].to_s].join("\t")
  ' "$source_abs"
)"

client_email="${metadata%%$'\t'*}"
project_id="${metadata#*$'\t'}"
dest_dir="$(dirname "$DEST")"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$dest_dir" "$BACKUP_DIR"
chmod 700 "$dest_dir" "$BACKUP_DIR"

source_sha256="$(shasum -a 256 "$source_abs" | awk '{print $1}')"

if [ -f "$DEST" ]; then
  existing_sha256="$(shasum -a 256 "$DEST" | awk '{print $1}')"
  if [ "$existing_sha256" != "$source_sha256" ]; then
    previous_backup="$BACKUP_DIR/fastread-google-play-service-account.previous.$timestamp.${existing_sha256:0:12}.json"
    cp "$DEST" "$previous_backup"
    chmod 600 "$previous_backup"
    log "Backed up previous canonical JSON to $previous_backup"
  fi
fi

tmp_dest="$DEST.tmp.$$"
install -m 600 "$source_abs" "$tmp_dest"
mv "$tmp_dest" "$DEST"
chmod 600 "$DEST"

installed_sha256="$(shasum -a 256 "$DEST" | awk '{print $1}')"
backup_path="$BACKUP_DIR/fastread-google-play-service-account.$timestamp.${installed_sha256:0:12}.json"
if ! find "$BACKUP_DIR" -maxdepth 1 -type f -name "fastread-google-play-service-account.*.${installed_sha256:0:12}.json" | grep -q .; then
  cp "$DEST" "$backup_path"
  chmod 600 "$backup_path"
else
  backup_path="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "fastread-google-play-service-account.*.${installed_sha256:0:12}.json" | head -1)"
fi

cat > "$MANIFEST" <<EOF
installed_at_utc=$timestamp
canonical_path=$DEST
backup_path=$backup_path
client_email=$client_email
project_id=$project_id
sha256=$installed_sha256
EOF
chmod 600 "$MANIFEST"

if [ -n "$ONE_PASSWORD_VAULT" ]; then
  if ! command -v op >/dev/null 2>&1; then
    printf '[fastread-play-service-account] ERROR: FASTREAD_PLAY_SERVICE_ACCOUNT_1PASSWORD_VAULT is set, but op is not installed\n' >&2
    exit 1
  fi
  log "Archiving a 1Password document copy in vault: $ONE_PASSWORD_VAULT"
  op document create "$DEST" \
    --vault "$ONE_PASSWORD_VAULT" \
    --title "$ONE_PASSWORD_TITLE" \
    --file-name "fastread-google-play-service-account.json" \
    --tags "fastread,android,google-play,service-account" >/tmp/fastread-play-service-account-1password.json
  chmod 600 /tmp/fastread-play-service-account-1password.json
  printf 'onepassword_vault=%s\n' "$ONE_PASSWORD_VAULT" >> "$MANIFEST"
  printf 'onepassword_title=%s\n' "$ONE_PASSWORD_TITLE" >> "$MANIFEST"
  log "Archived 1Password document metadata: /tmp/fastread-play-service-account-1password.json"
fi

log "Installed canonical JSON: $DEST"
log "Wrote local backup: $backup_path"
log "Wrote non-secret manifest: $MANIFEST"
log "Client email: $client_email"
log "Next check: $ROOT_DIR/scripts/check-android-release-credentials.sh"
