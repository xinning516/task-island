#!/usr/bin/env python3
"""Render the REAL dashboard HTML with synthetic tasks (never personal sessions).

Requires Pillow and Playwright with Chromium. Generates an honest interface demo,
not a screen recording or proof of live Codex/ChatGPT status detection.
"""
from __future__ import annotations

from pathlib import Path
import io
import time
import os

from PIL import Image, ImageDraw, ImageFont
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ASSETS.mkdir(exist_ok=True)
OUT_SCREENSHOT = ASSETS / "task-island-screenshot.png"
OUT_GIF = ASSETS / "task-island-demo.gif"

W, H = 1400, 750
BG = (17, 21, 30)
SUBTLE = (143, 155, 178)
WHITE = (236, 243, 255)


def font(size: int, bold=False):
    paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in paths:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def backdrop():
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    draw = ImageDraw.Draw(canvas)
    for y in range(H):
        # restrained gradient that doesn't obstruct real UI render
        draw.line((0, y, W, y), fill=(17 + int(y/H*4), 21 + int(y/H*5), 30 + int(y/H*9), 255))
    draw.rounded_rectangle((20, 18, W-20, H-18), radius=26, outline=(43, 51, 70, 255), width=2)
    draw.text((46, 35), "TASK ISLAND", font=font(23, True), fill=WHITE)
    draw.text((46, 75), "macOS multi-task status overlay", font=font(14), fill=SUBTLE)
    return canvas


def sample_tasks(stage, now):
    state = {
        "expanded": True, "pinned": True, "tiny": False, "muted": False,
        "opacity": 0.95, "hoverEnabled": True, "flash": None,
        "visibleSources": {"codex": True, "vscode": True, "chatgpt": True},
        "tasks": [
            {"id":"sample-codex", "source":"codex", "title":"Codex · Refactor project", "detail":"Processing request", "status":"running", "startedAt":now - 76000, "updatedAt":now},
            {"id":"sample-gpt-a", "source":"chatgpt", "title":"ChatGPT · Research", "detail":"Tab A · Generating response", "status":"running", "startedAt":now - 42000, "updatedAt":now},
            {"id":"sample-gpt-b", "source":"chatgpt", "title":"ChatGPT · Writing", "detail":"Tab B · Chat opened", "status":"idle", "startedAt":now - 120000, "updatedAt":now},
        ]
    }
    if stage >= 2:
        state["tasks"][0]["status"]="done"
        state["tasks"][0]["detail"]="Codex turn completed"
    if stage >= 3:
        state["tasks"][1]["status"]="done"
        state["tasks"][1]["detail"]="Answer finished"
        state["flash"]={"source":"chatgpt", "status":"done"}
    if stage == 4:
        state["expanded"] = False
        state["pinned"] = False
    return state


def ui_shot(browser, state, width, height):
    context = browser.new_context(viewport={"width":width,"height":height}, device_scale_factor=2, reduced_motion="reduce")
    try:
        page = context.new_page()
        page.set_content((ROOT / "hammerspoon/dashboard.html").read_text(encoding="utf-8"), wait_until="load")
        page.evaluate("(s) => window.updateTaskIsland(s)", state)
        page.wait_for_timeout(50)
        return Image.open(io.BytesIO(page.screenshot(omit_background=True))).convert("RGBA")
    finally:
        context.close()


def place(canvas, island, x, y):
    canvas.alpha_composite(island, dest=(x,y))


def label(canvas, x, y, text):
    ImageDraw.Draw(canvas).text((x,y), text, font=font(15,True), fill=(169,186,221))


def create_screenshot(browser, now):
    c = backdrop()
    label(c, 95, 165, "COMPACT  /  STATUS PILL")
    mini_state = sample_tasks(3,now)
    mini_state["expanded"] = False
    place(c, ui_shot(browser,mini_state,210,41), 95,210)
    label(c, 650, 165, "EXPANDED  /  3 SESSIONS")
    place(c, ui_shot(browser,sample_tasks(2,now),344,247), 630,210)
    ImageDraw.Draw(c).text((95,590), "Illustrative preview rendered from the actual dashboard using sample tasks.",
                           font=font(13), fill=SUBTLE)
    c.convert("RGB").save(OUT_SCREENSHOT, optimize=True)


def create_gif(browser, now):
    frames=[]
    durations=[]
    scenes = [
        (0,False,"Two tasks running",1100),
        (1,True,"Hover to expand",1100),
        (2,True,"Codex has finished",1400),
        (3,True,"ChatGPT answer completed",1600),
        (4,False,"Collapse to a compact pill",1400),
    ]
    for stage, expanded, title, duration in scenes:
        c=backdrop()
        draw=ImageDraw.Draw(c)
        draw.text((52,139),title, font=font(22, True),fill=WHITE)
        draw.text((52,178),"Preview only · synthetic task names and statuses",font=font(13),fill=SUBTLE)
        st=sample_tasks(stage, now)
        st["expanded"] = expanded
        w,h=(344,247) if expanded else (210,41)
        p=ui_shot(browser,st,w,h)
        place(c,p,(W-p.width)//2,215)
        frames.append(c.convert("RGB").quantize(colors=96,method=Image.Quantize.MEDIANCUT))
        durations.append(duration)
    frames[0].save(OUT_GIF, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, optimize=True, disposal=2)


def main():
    now=int(time.time()*1000)
    with sync_playwright() as p:
        chrome = os.getenv("TASK_ISLAND_CHROME")
        if not chrome and Path("/usr/bin/chromium").exists():
            chrome = "/usr/bin/chromium"
        browser = p.chromium.launch(headless=True, executable_path=chrome, args=["--no-sandbox"])
        try:
            create_screenshot(browser,now)
            create_gif(browser,now)
        finally:
            browser.close()
    print("Screenshot:", OUT_SCREENSHOT, OUT_SCREENSHOT.stat().st_size)
    print("Demo GIF:  ", OUT_GIF, OUT_GIF.stat().st_size)


if __name__ == "__main__":
    main()
