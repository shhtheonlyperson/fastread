# JustRead — Privacy Policy

_Last updated: 2026-05-17_

JustRead is a Chrome extension that turns any web article into a clean
reading view and lets you speed-read it with one-word-at-a-time RSVP.
This page describes what JustRead does and does not do with your data.

## What JustRead does NOT collect

- **No analytics.** JustRead has no telemetry, no usage pings, no error
  reporting service, and no third-party scripts. It never makes an
  outbound network request of its own.
- **No accounts.** There is no sign-in, no user identity, no server.
- **No content uploads.** The pages you read are never sent to a JustRead server.
  Article extraction and tokenization run entirely inside your browser.

## What JustRead stores locally

JustRead uses Chrome's local extension storage (`chrome.storage`) for
two small things:

1. **Your settings** — theme (light / dark), font (serif / sans), font
   size, reading column width, default WPM, chunk size, language, and
   user dictionary entries. Stored in `chrome.storage.sync` so Chrome may
   sync the settings across your signed-in Chrome profile when Chrome Sync
   is enabled. If Chrome Sync is off, the data stays on this machine only.
2. **A short list of your most recently read article titles + URLs**
   (the "Recently read" section in the popup). Stored in
   `chrome.storage.local` on this machine only; capped at the last 6
   items.

You can clear both at any time from `chrome://extensions` → JustRead →
Storage, or by uninstalling the extension.

## What permissions JustRead requests and why

| Permission | Why |
|---|---|
| `storage` | To save your reader/RSVP settings and the recents list described above. |
| `activeTab` | To extract the article from the page you're actively reading. Used only when you invoke JustRead (click the popup, press `Alt+R` / `Alt+Shift+R`, or press `F`). |
| `scripting` | To load JustRead's reader UI into a tab that the extension was just installed into, so you don't have to reload existing tabs after installing. |
| `host_permissions: <all_urls>` | A reader extension is fundamentally a tool that runs on whatever page you want to read. JustRead requires this so the same keyboard shortcut works everywhere. It does **not** use this access to send page contents off-device or to any third party. |

## Contact

Questions, concerns, or removal requests: **shh@theonlyperson.com**
