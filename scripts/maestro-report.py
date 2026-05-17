#!/usr/bin/env python3
"""Stitch Maestro debug artifacts into a self-contained HTML test report.

Run after `scripts/maestro-test.sh` finishes (or after running maestro
test+record manually). Reads the per-flow command JSON in
build/maestro/debug/.maestro/tests/<latest>/, expects the recorded
mp4 + the takeScreenshot PNGs at the repo root, and writes
build/maestro/index.html — a single page with the video, every step
labelled with status/duration, and the screenshots inline.

Open with:
  open build/maestro/index.html
"""

import base64
import datetime as dt
import html
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEBUG_ROOT = REPO_ROOT / "build/maestro/debug/.maestro/tests"
OUT = REPO_ROOT / "build/maestro/index.html"
VIDEO = REPO_ROOT / "build/maestro/user-dictionary.mp4"
SCREENSHOT_FILES = sorted(REPO_ROOT.glob("0[1-9]-*.png"))


def latest_run_dir() -> Path:
    runs = sorted([d for d in DEBUG_ROOT.iterdir() if d.is_dir()])
    if not runs:
        sys.exit(f"❌ no Maestro debug runs under {DEBUG_ROOT}")
    return runs[-1]


def format_command(cmd: dict) -> str:
    name = next(iter(cmd))
    body = cmd[name]
    if name == "tapOnElement":
        sel = body.get("selector", {})
        target = sel.get("idRegex") or sel.get("textRegex") or json.dumps(sel)
        return f"<b>tap</b> {html.escape(str(target))}"
    if name == "assertConditionCommand":
        cond = body.get("condition", {})
        vis = cond.get("visible") or cond.get("notVisible")
        prefix = "assertVisible" if "visible" in cond else "assertNotVisible"
        if isinstance(vis, dict):
            target = vis.get("idRegex") or vis.get("textRegex") or json.dumps(vis)
        else:
            target = str(vis)
        return f"<b>{prefix}</b> {html.escape(target)}"
    if name == "takeScreenshotCommand":
        path = body.get("path", "")
        return f"<b>takeScreenshot</b> {html.escape(path)}"
    if name == "inputTextCommand":
        return f"<b>inputText</b> {html.escape(body.get('text', ''))}"
    if name == "scrollUntilVisibleCommand":
        sel = body.get("selector", {})
        target = sel.get("idRegex") or json.dumps(sel)
        return f"<b>scrollUntilVisible</b> {html.escape(str(target))}"
    if name == "extendedWaitUntilCommand":
        cond = body.get("condition", {})
        vis = cond.get("visible") or {}
        target = vis.get("idRegex") or vis.get("textRegex") or json.dumps(vis)
        text = vis.get("textRegex")
        suffix = f" text={html.escape(text)}" if text else ""
        return f"<b>extendedWaitUntil</b> visible {html.escape(str(target))}{suffix}"
    if name == "applyConfigurationCommand":
        return "<i>apply configuration</i>"
    if name == "defineVariablesCommand":
        return "<i>define variables</i>"
    return f"<b>{html.escape(name)}</b> <code>{html.escape(json.dumps(body)[:120])}</code>"


def steps_html(commands: list[dict]) -> str:
    rows = []
    for i, c in enumerate(commands, 1):
        meta = c.get("metadata", {})
        status = meta.get("status", "?")
        ms = meta.get("duration", 0)
        emoji = "✅" if status == "COMPLETED" else "❌" if status == "FAILED" else "•"
        css = "ok" if status == "COMPLETED" else "fail" if status == "FAILED" else "skip"
        rows.append(
            f"<li class='{css}'>"
            f"<span class='step-num'>{i:02d}</span>"
            f"<span class='step-emoji'>{emoji}</span>"
            f"<span class='step-cmd'>{format_command(c['command'])}</span>"
            f"<span class='step-time'>{ms}ms</span>"
            "</li>"
        )
    return "\n".join(rows)


def screenshots_html() -> str:
    captions = {
        "01": ("Reader · dictionary empty", "1 / 9 tokens — NLTokenizer splits 黃士旗 into 3 single chars."),
        "02": ("Settings · entry added", "Custom words section now lists 黃士旗 with its remove button."),
        "03": ("Reader · dictionary applied", "1 / 7 tokens — 3 single chars merged into one focus chunk 黃士旗."),
        "04": ("Reader · entry removed", "Back to 1 / 9 — cache invalidates the other way too."),
    }
    cards = []
    for path in SCREENSHOT_FILES:
        m = re.match(r"^(\d{2})-", path.name)
        if not m:
            continue
        key = m.group(1)
        title, sub = captions.get(key, (path.stem, ""))
        b64 = base64.b64encode(path.read_bytes()).decode()
        cards.append(
            f"""<figure class='shot'>
  <figcaption><b>{html.escape(title)}</b><br><span class='shot-sub'>{html.escape(sub)}</span></figcaption>
  <img src='data:image/png;base64,{b64}' />
</figure>"""
        )
    return "\n".join(cards)


def video_html() -> str:
    if not VIDEO.exists():
        return "<p><i>No video recording at build/maestro/user-dictionary.mp4 — run <code>maestro record --local</code> first.</i></p>"
    b64 = base64.b64encode(VIDEO.read_bytes()).decode()
    return (
        "<video controls preload='metadata'>"
        f"<source src='data:video/mp4;base64,{b64}' type='video/mp4'>"
        "Your browser does not support the video tag."
        "</video>"
    )


def main() -> None:
    run = latest_run_dir()
    cmd_files = list(run.glob("commands-*.json"))
    if not cmd_files:
        sys.exit(f"❌ no commands-*.json in {run}")
    flow_path = cmd_files[0]
    flow_name = re.search(r"commands-\((.+)\)\.json", flow_path.name).group(1)
    commands = json.loads(flow_path.read_text())

    total_ms = sum(c.get("metadata", {}).get("duration", 0) for c in commands)
    completed = sum(1 for c in commands if c.get("metadata", {}).get("status") == "COMPLETED")
    failed = sum(1 for c in commands if c.get("metadata", {}).get("status") == "FAILED")

    timestamp = dt.datetime.fromtimestamp(
        run.stat().st_mtime, tz=dt.timezone.utc
    ).astimezone().isoformat(timespec="seconds")

    out = OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f"""<!DOCTYPE html>
<html><head><meta charset='utf-8'>
<title>Maestro · {html.escape(flow_name)}</title>
<style>
  body {{ font-family: -apple-system, system-ui, sans-serif; max-width: 1100px;
          margin: 32px auto; padding: 0 24px; color: #141413; background: #faf9f5; }}
  h1 {{ font-family: Georgia, serif; font-weight: 500; letter-spacing: -0.5px; }}
  .summary {{ display: flex; gap: 12px; flex-wrap: wrap; margin: 16px 0 24px; }}
  .pill {{ padding: 6px 12px; border-radius: 4px; background: #f5f0e8; border: 0.5px solid #e6dfd8; font-size: 13px; }}
  .pill.ok {{ background: #cc785c; color: white; }}
  .pill.fail {{ background: #B33; color: white; }}
  video {{ width: 100%; max-width: 640px; border: 0.5px solid #e8e0d2; display: block; margin: 0 auto 32px; background: #181715; }}
  .shots {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin: 24px 0; }}
  .shot {{ margin: 0; }}
  .shot img {{ width: 100%; border: 0.5px solid #e6dfd8; border-radius: 4px; background: white; }}
  .shot figcaption {{ font-size: 12px; margin-bottom: 6px; line-height: 1.45; }}
  .shot-sub {{ color: #3d3d3a; font-weight: normal; }}
  ol.steps {{ list-style: none; padding: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }}
  ol.steps li {{ display: grid; grid-template-columns: 32px 28px 1fr 60px; gap: 12px;
                 padding: 8px 12px; border-bottom: 0.5px solid #e6dfd8; }}
  ol.steps li.ok .step-emoji {{ color: #2A6F47; }}
  ol.steps li.fail {{ background: rgba(179,51,51,.08); }}
  ol.steps li.fail .step-emoji {{ color: #B33; }}
  .step-num {{ color: #6c6a64; }}
  .step-time {{ color: #6c6a64; text-align: right; }}
  .step-cmd code {{ background: #efe9de; padding: 1px 4px; border-radius: 3px; }}
  h2 {{ margin-top: 36px; font-family: Georgia, serif; font-weight: 500; }}
  footer {{ color: #6c6a64; font-size: 12px; margin-top: 32px; padding-top: 16px;
            border-top: 0.5px solid #e6dfd8; }}
</style></head>
<body>
<h1>Maestro · {html.escape(flow_name)}</h1>
<div class='summary'>
  <span class='pill {"ok" if failed == 0 else "fail"}'>{"PASS" if failed == 0 else "FAIL"}</span>
  <span class='pill'>{completed} / {len(commands)} steps</span>
  <span class='pill'>{total_ms / 1000:.1f}s total</span>
  <span class='pill'>{html.escape(timestamp)}</span>
  <span class='pill'>flow: <code>.maestro/{html.escape(flow_name)}.yaml</code></span>
</div>

<h2>Recording</h2>
{video_html()}

<h2>Key states</h2>
<div class='shots'>
{screenshots_html()}
</div>

<h2>Steps ({len(commands)})</h2>
<ol class='steps'>
{steps_html(commands)}
</ol>

<footer>
Generated from <code>build/maestro/debug/.maestro/tests/{html.escape(run.name)}</code>.
Re-run with <code>scripts/maestro-test.sh user-dictionary</code> + <code>maestro record --local …</code> to refresh.
</footer>
</body></html>""")
    print(f"✅ wrote {out}  ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
