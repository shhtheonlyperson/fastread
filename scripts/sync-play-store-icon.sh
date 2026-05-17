#!/usr/bin/env bash
# Verify or update the Google Play store-listing icon for JustRead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---check}"
PLAY_JSON="${FASTREAD_PLAY_SERVICE_ACCOUNT_JSON:-$HOME/.config/shh/play-service-accounts/fastread-google-play-service-account.json}"
PLAY_PACKAGE="${FASTREAD_PLAY_PACKAGE:-com.shhtheonlyperson.fastread}"
PLAY_LANGUAGE="${FASTREAD_PLAY_LISTING_LANGUAGE:-en-US}"
ICON_PATH="${FASTREAD_PLAY_ICON:-$ROOT_DIR/android-spike/play-assets/justread-icon-512.png}"

log() {
  printf '[fastread-play-icon] %s\n' "$*"
}

fail() {
  printf '[fastread-play-icon] ERROR: %s\n' "$*" >&2
  exit 1
}

case "$MODE" in
  --check | --apply) ;;
  *) fail "usage: $0 [--check|--apply]" ;;
esac

[[ -f "$PLAY_JSON" ]] || fail "missing Play service-account JSON at $PLAY_JSON"
[[ -f "$ICON_PATH" ]] || fail "missing Play icon at $ICON_PATH"

node - "$MODE" "$PLAY_JSON" "$PLAY_PACKAGE" "$PLAY_LANGUAGE" "$ICON_PATH" <<'NODE'
const fs = require("fs");
const crypto = require("crypto");

const [mode, jsonPath, packageName, language, iconPath] = process.argv.slice(2);
const service = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
const iconBytes = fs.readFileSync(iconPath);
const desiredSha1 = crypto.createHash("sha1").update(iconBytes).digest("hex");
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`;
const uploadBase = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}`;

const b64u = (input) =>
  Buffer.from(input)
    .toString("base64")
    .replace(/=+$/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64u(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64u(
    JSON.stringify({
      iss: service.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: service.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;
  const signature = crypto.createSign("RSA-SHA256").update(unsigned).sign(service.private_key);
  const jwt = `${unsigned}.${b64u(signature)}`;
  const res = await fetch(service.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`token ${res.status}: ${text}`);
  return JSON.parse(text).access_token;
}

async function api(token, method, url, opts = {}) {
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...(opts.headers || {}) },
    body: opts.body,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`${method} ${url} -> ${res.status}: ${text}`);
    err.status = res.status;
    err.body = text;
    throw err;
  }
  return text ? JSON.parse(text) : null;
}

function permissionHint() {
  return [
    `Grant ${service.client_email} Play Console permission CAN_MANAGE_PUBLIC_LISTING`,
    "(UI label: Edit store listing information / Manage store presence), then rerun this script.",
  ].join(" ");
}

(async () => {
  const token = await accessToken();
  const edit = await api(token, "POST", `${base}/edits`);
  const lang = encodeURIComponent(language);

  try {
    const images = await api(token, "GET", `${base}/edits/${edit.id}/listings/${lang}/icon`);
    const current = images.images || [];
    const currentSha1s = current.map((image) => image.sha1).filter(Boolean);

    if (current.length === 1 && currentSha1s[0] === desiredSha1) {
      console.log(`OK ${packageName} ${language} icon sha1=${desiredSha1}`);
      await api(token, "DELETE", `${base}/edits/${edit.id}`);
      return;
    }

    if (mode === "--check") {
      throw new Error(
        `Play icon mismatch for ${packageName} ${language}. ` +
          `expected sha1=${desiredSha1}; current=${currentSha1s.join(",") || "none"}. ` +
          `Run scripts/sync-play-store-icon.sh --apply.`,
      );
    }

    await api(token, "DELETE", `${base}/edits/${edit.id}/listings/${lang}/icon`);
    const upload = await api(
      token,
      "POST",
      `${uploadBase}/edits/${edit.id}/listings/${lang}/icon?uploadType=media`,
      {
        headers: {
          "Content-Type": "image/png",
          "Content-Length": String(iconBytes.length),
        },
        body: iconBytes,
      },
    );
    const uploadedSha1 = upload.image && upload.image.sha1;
    if (uploadedSha1 !== desiredSha1) {
      throw new Error(`uploaded icon sha1=${uploadedSha1 || "none"} did not match desired sha1=${desiredSha1}`);
    }

    try {
      await api(token, "POST", `${base}/edits/${edit.id}:commit`);
    } catch (err) {
      if (err.status === 403) {
        throw new Error(`Play icon upload was prepared but commit was denied. ${permissionHint()}`);
      }
      throw err;
    }
    console.log(`Updated ${packageName} ${language} icon sha1=${desiredSha1}`);
  } catch (err) {
    try {
      await api(token, "DELETE", `${base}/edits/${edit.id}`);
    } catch {}
    throw err;
  }
})().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
NODE
