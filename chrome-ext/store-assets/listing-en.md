# JustRead — Web Store listing (English)

## Name (max 75 chars)

`JustRead — Reader View + Speed Reading`

## Short summary (max 132 chars)

`Strip the clutter from any web article and speed-read it with RSVP. Light/dark, serif/sans, h/j/k/l keyboard.`

## Detailed description (max 16,000 chars)

JustRead turns any web article into a clean, distraction-free reading view — and then lets you speed-read it one word at a time.

**Two modes, one keyboard:**

• **Reader View** — Strip ads, sidebars, banners, comments, and every other piece of chrome. Just the article, in a quiet typographic column. Light, dark themes. Serif and sans typefaces. Adjustable font size, line height, and column width.

• **Fast Read (RSVP)** — Rapid Serial Visual Presentation. One word flashes at a time, centered on the optimal recognition point so your eyes don't have to dart. Read at your own pace from 150 to 1200 words per minute. Skip by sentence, pause, scrub. The whole flow is keyboard-driven (vim-style h/j/k/l, plus arrow keys and Space).

**Why JustRead is different:**

• Built by someone who reads in two languages. The tokenizer handles English and Traditional Chinese natively, with rhythm-aware chunking for Han-character text — so 黃士旗 stays as one chunk, 我去吃飯 flashes as a sensible cadence, and Latin words don't get awkwardly split mid-syllable.

• Works on the SPA-rendered web. Most reader extensions choke on Substack notes, Medium drafts, and other JavaScript-mounted content. JustRead has a fallback extractor for those — if Readability bails out, the densest text block (ProseMirror, article-shaped containers) gets picked up.

• No accounts, no servers, no analytics. Everything runs in your browser. The source is public.

**Keyboard shortcuts (Fast Read):**

• `Space` — play / pause
• `h` or `←` — previous sentence
• `l` or `→` — next sentence
• `j` or `↓` — slower (−25 WPM)
• `k` or `↑` — faster (+25 WPM)
• `Esc` — back to reader; second `Esc` to exit

**Open Reader / Fast Read from anywhere:**

• `Alt+R` — toggle Reader View
• `Alt+Shift+R` — toggle Fast Read
• Or click the toolbar icon.

**Privacy:** Zero network requests, zero telemetry, zero third-party scripts. JustRead stores your settings in `chrome.storage` and never sends page contents anywhere. Full policy at https://www.theonlyperson.com/privacy

## Category

`Productivity` (primary)

## Language

English, Traditional Chinese

## Single-purpose description (required by Web Store reviewers)

JustRead has one purpose: present web articles in a clean reader view and let the user speed-read them. All requested permissions exist solely to support that purpose.

## Permission justifications

These are the exact strings Web Store reviewers want for each permission.

**`activeTab`**
> JustRead needs to read the current page's HTML to extract the article body and present it in the reader view. `activeTab` is invoked only when the user explicitly opens the reader (click the toolbar button or press the keyboard shortcut).

**`scripting`**
> When the user installs JustRead, any tabs that were already open won't yet have the content script loaded. `scripting.executeScript` injects the content script on demand so the user doesn't have to manually reload every existing tab.

**`storage`**
> JustRead saves the user's display preferences (theme, font, size, words-per-minute, language) and a short "recently read" list. Stored locally via `chrome.storage`; never transmitted.

**Host permission `<all_urls>`**
> A reader-mode tool must work on whichever article the user wants to read. JustRead reads page content on demand for extraction; it does not transmit any page content off the device and does not run on pages where the user has not explicitly invoked the reader.
