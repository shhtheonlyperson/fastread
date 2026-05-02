import {
  DEFAULT_TEXT,
  clamp,
  durationForToken,
  estimateMinutes,
  getProgress,
  splitForFocus,
  tokenize,
} from "./reader-core.js";

const STORAGE_KEY = "fastread-state-v1";

const els = {
  textInput: document.querySelector("#text-input"),
  urlForm: document.querySelector("#url-form"),
  urlInput: document.querySelector("#url-input"),
  urlStatus: document.querySelector("#url-status"),
  loadUrl: document.querySelector("#load-url"),
  wordLeft: document.querySelector("#word-left"),
  wordFocus: document.querySelector("#word-focus"),
  wordRight: document.querySelector("#word-right"),
  playPause: document.querySelector("#play-pause"),
  previous: document.querySelector("#previous-word"),
  next: document.querySelector("#next-word"),
  reset: document.querySelector("#reset-reader"),
  wpm: document.querySelector("#wpm"),
  wpmValue: document.querySelector("#wpm-value"),
  punctuationPause: document.querySelector("#punctuation-pause"),
  progress: document.querySelector("#progress"),
  progressText: document.querySelector("#progress-text"),
  stats: document.querySelector("#stats"),
  focusPreview: document.querySelector("#focus-preview"),
  copyHtml: document.querySelector("#copy-html"),
  copyText: document.querySelector("#copy-text"),
  clearText: document.querySelector("#clear-text"),
  focusMode: document.querySelector("#focus-mode"),
};

let tokens = [];
let index = 0;
let isPlaying = false;
let timer = null;

const icons = {
  play: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>`,
  pause: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h4v14H7zM13 5h4v14h-4z"/></svg>`,
  expand: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 9H3V3h6v2H5zM21 9h-2V5h-4V3h6zM9 21H3v-6h2v4h4zM21 21h-6v-2h4v-4h2z"/></svg>`,
  collapse: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3v6H3V7h4V3zM21 9h-6V3h2v4h4zM9 15v6H7v-4H3v-2zM17 17v4h-2v-6h6v2z"/></svg>`,
};

function restoreState() {
  try {
    const state = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    els.textInput.value = state.text || DEFAULT_TEXT;
    els.urlInput.value = state.url || "";
    els.wpm.value = state.wpm || 650;
    els.punctuationPause.checked = state.punctuationPause ?? true;
  } catch {
    els.textInput.value = DEFAULT_TEXT;
  }
}

function saveState() {
  const state = {
    text: els.textInput.value,
    url: els.urlInput.value,
    wpm: Number(els.wpm.value),
    punctuationPause: els.punctuationPause.checked,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function refreshTokens(resetIndex = false) {
  tokens = tokenize(els.textInput.value);
  if (resetIndex) {
    index = 0;
  }
  index = clamp(index, 0, Math.max(tokens.length - 1, 0));
  render();
  saveState();
}

function renderWord(token) {
  const parts = splitForFocus(token);
  els.wordLeft.textContent = parts.before;
  els.wordFocus.textContent = parts.focus;
  els.wordRight.textContent = parts.after;
}

function renderPreview() {
  const fragment = document.createDocumentFragment();

  tokens.forEach((token) => {
    const parts = splitForFocus(token);
    const word = document.createElement("span");
    word.className = "focus-word";

    const before = document.createTextNode(parts.before);
    const focus = document.createElement("span");
    focus.className = "focus-mark";
    focus.textContent = parts.focus;
    const after = document.createTextNode(parts.after);

    word.append(before, focus, after);
    fragment.append(word, " ");
  });

  els.focusPreview.replaceChildren(fragment);
}

function render() {
  const token = tokens[index] || "";
  renderWord(token);
  renderPreview();

  const wpm = Number(els.wpm.value);
  const progress = tokens.length ? getProgress(index, tokens.length) : 0;
  const minutes = estimateMinutes(tokens.length, wpm);
  const eta = minutes < 1 ? `${Math.ceil(minutes * 60)}s` : `${minutes.toFixed(1)}m`;

  els.wpmValue.textContent = String(wpm);
  els.progress.value = tokens.length ? index : 0;
  els.progress.max = Math.max(tokens.length - 1, 0);
  els.progressText.textContent = tokens.length ? `${index + 1} / ${tokens.length}` : "0 / 0";
  els.stats.textContent = `${tokens.length} words · ${eta} at ${wpm} WPM · ${progress}%`;
  els.playPause.innerHTML = isPlaying ? icons.pause : icons.play;
  els.playPause.setAttribute("aria-label", isPlaying ? "Pause" : "Play");
  els.focusMode.innerHTML = document.body.classList.contains("is-focus-mode") ? icons.collapse : icons.expand;
  els.focusMode.setAttribute("aria-label", document.body.classList.contains("is-focus-mode") ? "Exit focus mode" : "Focus mode");
  els.focusMode.setAttribute("title", document.body.classList.contains("is-focus-mode") ? "Exit focus mode" : "Focus mode");
  els.previous.disabled = !tokens.length || index === 0;
  els.next.disabled = !tokens.length || index >= tokens.length - 1;
  els.playPause.disabled = !tokens.length;
}

async function loadUrl(event) {
  event.preventDefault();
  const url = els.urlInput.value.trim();

  if (!url) {
    setUrlStatus("Enter a URL first.", true);
    return;
  }

  stop();
  els.loadUrl.disabled = true;
  setUrlStatus("Loading...");

  try {
    const response = await fetch(`/api/extract?url=${encodeURIComponent(url)}`);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(payload.error || `Request failed with HTTP ${response.status}`);
    }

    els.textInput.value = payload.text;
    refreshTokens(true);
    const title = payload.title ? `${payload.title} | ` : "";
    setUrlStatus(`${title}${payload.wordCount} words loaded.`);
  } catch (error) {
    setUrlStatus(error.message || "Could not load that URL.", true);
  } finally {
    els.loadUrl.disabled = false;
    saveState();
  }
}

function setUrlStatus(message, isError = false) {
  els.urlStatus.textContent = message;
  els.urlStatus.dataset.state = isError ? "error" : message ? "ok" : "";
}

async function toggleFocusMode() {
  const entering = !document.body.classList.contains("is-focus-mode");
  document.body.classList.toggle("is-focus-mode", entering);

  if (entering && document.documentElement.requestFullscreen && !document.fullscreenElement) {
    try {
      await document.documentElement.requestFullscreen();
    } catch {
      // CSS focus mode still gives a full-page reader when browser fullscreen is unavailable.
    }
  } else if (!entering && document.exitFullscreen && document.fullscreenElement) {
    try {
      await document.exitFullscreen();
    } catch {
      // The CSS state has already been cleared.
    }
  }

  render();
}

function stop() {
  isPlaying = false;
  clearTimeout(timer);
  timer = null;
  render();
}

function scheduleNext() {
  clearTimeout(timer);
  if (!isPlaying || !tokens.length) {
    return;
  }

  const token = tokens[index];
  const delay = durationForToken(token, Number(els.wpm.value), els.punctuationPause.checked);
  timer = window.setTimeout(() => {
    if (index >= tokens.length - 1) {
      stop();
      return;
    }
    index += 1;
    render();
    scheduleNext();
  }, delay);
}

function togglePlayback() {
  if (!tokens.length) {
    return;
  }

  isPlaying = !isPlaying;
  render();
  if (isPlaying) {
    scheduleNext();
  } else {
    clearTimeout(timer);
  }
}

function move(delta) {
  stop();
  index = clamp(index + delta, 0, Math.max(tokens.length - 1, 0));
  render();
}

function getFocusHtml() {
  return tokens
    .map((token) => {
      const parts = splitForFocus(token);
      return `<span class="fastread-word">${escapeHtml(parts.before)}<span class="fastread-focus">${escapeHtml(parts.focus)}</span>${escapeHtml(parts.after)}</span>`;
    })
    .join(" ");
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (char) => {
    const entities = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    };
    return entities[char];
  });
}

async function copy(value, button, doneLabel) {
  await navigator.clipboard.writeText(value);
  const previous = button.textContent;
  button.textContent = doneLabel;
  window.setTimeout(() => {
    button.textContent = previous;
  }, 1200);
}

els.urlForm.addEventListener("submit", loadUrl);
els.urlInput.addEventListener("input", saveState);
els.textInput.addEventListener("input", () => refreshTokens(true));
els.wpm.addEventListener("input", () => {
  render();
  saveState();
  if (isPlaying) {
    scheduleNext();
  }
});
els.punctuationPause.addEventListener("change", () => {
  saveState();
  if (isPlaying) {
    scheduleNext();
  }
});
els.playPause.addEventListener("click", togglePlayback);
els.previous.addEventListener("click", () => move(-1));
els.next.addEventListener("click", () => move(1));
els.reset.addEventListener("click", () => {
  stop();
  index = 0;
  render();
});
els.progress.addEventListener("input", () => {
  stop();
  index = Number(els.progress.value);
  render();
});
els.copyHtml.addEventListener("click", () => copy(getFocusHtml(), els.copyHtml, "Copied"));
els.copyText.addEventListener("click", () => copy(els.focusPreview.textContent.trim(), els.copyText, "Copied"));
els.clearText.addEventListener("click", () => {
  stop();
  els.textInput.value = "";
  setUrlStatus("");
  refreshTokens(true);
  els.textInput.focus();
});
els.focusMode.addEventListener("click", toggleFocusMode);

document.addEventListener("fullscreenchange", () => {
  if (!document.fullscreenElement && document.body.classList.contains("is-focus-mode")) {
    document.body.classList.remove("is-focus-mode");
    render();
  }
});

document.addEventListener("keydown", (event) => {
  const editing = event.target instanceof HTMLTextAreaElement || event.target instanceof HTMLInputElement;
  if (editing) {
    return;
  }

  if (event.code === "Space") {
    event.preventDefault();
    togglePlayback();
  } else if (event.key.toLowerCase() === "f") {
    toggleFocusMode();
  } else if (event.key === "Escape" && document.body.classList.contains("is-focus-mode")) {
    toggleFocusMode();
  } else if (event.key === "ArrowLeft") {
    move(-1);
  } else if (event.key === "ArrowRight") {
    move(1);
  }
});

restoreState();
refreshTokens(true);
