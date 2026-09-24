#!/usr/bin/env python3
"""Create an explicitly labelled guide from Initials' real offscreen views.

Only the existing --snapshot branch is invoked. It exits before startTap().
No normal app launch, keyboard events, clipboard access or app switching occurs.
Usage: python3 scripts/render-guide.py
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
from datetime import datetime, timezone

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/guide"
OUT = ROOT / "site/media"
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
SIZE = (1440, 1080)
NOTICE = "真实界面离屏导览 · 示例配置 · 非连续实机录屏"
CLIPS = [
    ("right", "01 · 右 Command 的字母表", [
        ("settings-right.png", None, 6, "先看「右 Command」设置", "这是只含 Apple 应用的示例字母表。"),
        ("settings-right.png", (30, 375, 1210, 810), 6, "一个字母，对应一个 app", "示例中 M 对应 Music，F 对应 Finder；映射可自行修改。"),
        ("settings-right.png", (30, 165, 1210, 375), 6, "按住与双击，分别开关", "这里展示开关与映射；没有触发真实按键或切换应用。"),
    ]),
    ("panel", "02 · 看懂字母面板", [
        ("picker.png", None, 7, "看字母，也看应用名称", "这是原生面板的离屏快照，不是按键后弹出的实录。"),
        ("picker-dark.png", None, 7, "浅色和深色，同一张字母表", "面板提示按字母选择、Esc 关闭；本段只说明界面。"),
    ]),
    ("left", "03 · 给左 Command 单独设一张表", [
        ("settings-left.png", None, 6, "选择「左 Command」设置", "示例关闭共用字母表，使用 J、K、Y 三个字母。"),
        ("settings-left.png", (30, 155, 1210, 445), 6, "先看开关，再看共用选项", "按住和双击可分别配置；共用选项决定是否沿用右侧映射。"),
        ("settings-left.png", (30, 445, 1210, 690), 6, "只给需要的字母分配应用", "本例未占用 C、V；实际使用仍需本人完成授权并验证按键。"),
    ]),
]
CLIPS_EN = [
    ("right", "01 · The right Command letter table", [
        ("settings-right.png", None, 6, "Start with Right Command settings", "This example only pins Apple apps."),
        ("settings-right.png", (30, 375, 1210, 810), 6, "One letter, one app", "M is Music and F is Finder. You can change these mappings."),
        ("settings-right.png", (30, 165, 1210, 375), 6, "Hold and double-tap have separate switches", "This guide shows settings; it does not press keys or switch apps."),
    ]),
    ("panel", "02 · Read the letter panel", [
        ("picker.png", None, 7, "Find the letter beside the app name", "An offscreen render of the native panel, not a live keyboard recording."),
        ("picker-dark.png", None, 7, "The same letter table in light and dark", "The hints show letter selection and Esc. This clip explains the UI only."),
    ]),
    ("left", "03 · A separate table for left Command", [
        ("settings-left.png", None, 6, "Open Left Command settings", "This example turns sharing off and assigns J, K and Y."),
        ("settings-left.png", (30, 155, 1210, 445), 6, "Check the triggers and the sharing option", "Choose hold, double-tap, and whether to reuse the right-hand table."),
        ("settings-left.png", (30, 445, 1210, 690), 6, "Pin only the letters you need", "C and V are free here. Grant access and test your own shortcuts after installing."),
    ]),
]
LANG = "zh"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args):
    subprocess.run(list(map(str, args)), check=True, cwd=ROOT)


def stamp(seconds):
    ms = round(seconds * 1000)
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02}.{ms % 1000:03}"


def capture():
    spec = importlib.util.spec_from_file_location("initials_shots", ROOT / "scripts/shots.py")
    shots = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shots)
    release = json.loads((ROOT / "build/release.json").read_text())
    if digest(shots.APP) != release["executable_sha256"]:
        raise SystemExit("Guide must use the recorded release executable")
    info = plistlib.loads((shots.APP.parent.parent / "Info.plist").read_bytes())
    source = WORK / "source"
    source.mkdir(parents=True, exist_ok=True)
    configs = {}
    for name, side in (("right", "right"), ("left", "left"), ("panel", None)):
        config = shots.demo_config(name == "panel", cycle=False)
        # These paths are already used by the verified right-hand fixture.
        config["left"]["bindings"] = {
            k: shots.binding(shots.APPS[app]) for k, app in (("j", "c"), ("k", "m"), ("y", "p"))
        }
        support = source / name
        support.mkdir(exist_ok=True)
        config_path = support / "config.json"
        config_path.write_text(json.dumps(config))
        before = digest(config_path)
        if side:
            shots.snapshot(support, source / f"settings-{side}.png", "--settings", side, lang=LANG)
        else:
            shots.snapshot(support, source / "picker.png", "--picker", "--right", lang=LANG)
            shots.snapshot(support, source / "picker-dark.png", "--picker", "--right", "--dark", lang=LANG)
        assert before == digest(config_path), "Offscreen capture changed its fixture"
        configs[name] = {side: {letter: value["name"] for letter, value in config[side]["bindings"].items()}
                         for side in ("right", "left")}
    return source, release, info, configs


def font(size):
    return ImageFont.truetype(FONT, size)


def centered(draw, text, y, size, fill):
    face = font(size)
    bounds = draw.textbbox((0, 0), text, font=face)
    width = bounds[2] - bounds[0]
    if width > SIZE[0] - 88:
        raise ValueError(f"Caption is too wide: {text}")
    draw.text(((SIZE[0] - width) / 2, y), text, font=face, fill=fill)


def frame(source, crop, title, line1, line2, part, version, destination):
    canvas = Image.new("RGB", SIZE, "#f7faf9")
    draw = ImageDraw.Draw(canvas)
    centered(draw, title, 28, 34, "#22303a")
    centered(draw, NOTICE, 80, 22, "#526c6b")
    image = Image.open(source).convert("RGBA")
    if crop:
        x0, y0, x1, y1 = crop
        assert 0 <= x0 < x1 <= image.width and 0 <= y0 < y1 <= image.height
        image = image.crop(crop)
    image = ImageOps.contain(image, (1260, 735), Image.Resampling.LANCZOS)
    x, y = (SIZE[0] - image.width) // 2, 145 + (735 - image.height) // 2
    draw.rounded_rectangle((x - 9, y - 9, x + image.width + 9, y + image.height + 9), 20,
                           fill="#ffffff", outline="#d9e5e3", width=2)
    canvas.paste(image, (x, y), image)
    draw.rectangle((0, 914, 1440, 1080), fill="#e7f1ef")
    centered(draw, line1, 932, 31, "#1d6967")
    centered(draw, line2, 983, 23, "#3f565b")
    footer = (f"Initials {version} · Offscreen view {part} · {'Detail crop' if crop else 'Full view'} · No audio"
              if LANG == "en" else f"Initials {version} · 离屏快照 {part} · {'局部放大' if crop else '完整界面'} · 无音频")
    centered(draw, footer, 1034, 18, "#607578")
    canvas.save(destination)


def concat(parts, output, listing):
    listing.write_text("".join(f"file '{path}'\n" for path in parts))
    run("ffmpeg", "-v", "error", "-f", "concat", "-safe", "0", "-i", listing,
        "-c", "copy", "-movflags", "+faststart", "-y", output)


def main():
    global LANG, WORK, OUT, NOTICE, CLIPS
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lang", choices=("zh", "en"), default="zh")
    LANG = parser.parse_args().lang
    if LANG == "en":
        WORK = WORK / "en"
        OUT = OUT / "en"
        NOTICE = "Real UI · Offscreen guide · Example settings · Not a live recording"
        CLIPS = CLIPS_EN
    OUT.mkdir(parents=True, exist_ok=True)
    source, release, info, configs = capture()
    all_clips, all_cues, chapters, timeline = [], ["WEBVTT\n"], [], 0
    for name, title, pieces in CLIPS:
        parts, cues, elapsed = [], ["WEBVTT\n"], 0
        for i, (raw, crop, duration, line1, line2) in enumerate(pieces):
            png, mp4 = WORK / f"{name}-{i}.png", WORK / f"{name}-{i}.mp4"
            frame(source / raw, crop, title, line1, line2, f"{i+1}/{len(pieces)}", release["version"], png)
            if i == 0:
                Image.open(png).save(OUT / f"{name}.jpg", quality=90)
            run("ffmpeg", "-v", "error", "-loop", "1", "-framerate", "24", "-i", png,
                "-t", duration, "-an", "-c:v", "libx264", "-tune", "stillimage", "-preset", "fast",
                "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-y", mp4)
            text = f"{NOTICE}\n{line1}\n{line2}"
            cues.append(f"{stamp(elapsed)} --> {stamp(elapsed + duration)}\n{text}\n")
            all_cues.append(f"{stamp(timeline + elapsed)} --> {stamp(timeline + elapsed + duration)}\n{text}\n")
            elapsed += duration
            parts.append(mp4)
        video = OUT / f"{name}.mp4"
        concat(parts, video, WORK / f"{name}-concat.txt")
        (OUT / f"{name}.vtt").write_text("\n".join(cues))
        chapters.append({"name": name, "title": title, "start": timeline, "duration": elapsed,
                         "frames": [{"source": p[0], "crop": p[1], "duration": p[2],
                                     "title": p[3], "caption": p[4]} for p in pieces]})
        timeline += elapsed
        all_clips.append(video)
    concat(all_clips, OUT / "tutorial.mp4", WORK / "tutorial-concat.txt")
    (OUT / "tutorial.vtt").write_text("\n".join(all_cues))
    manifest = {"schema": 1, "product": "Initials", "language": LANG, "version": release["version"],
                "build": info["CFBundleVersion"], "executable_sha256": release["executable_sha256"],
                "created_at": datetime.now(timezone.utc).isoformat(),
                "method": NOTICE, "audio": False, "duration": timeline,
                "scope": ("Real native views rendered offscreen, with labelled detail crops and fixed Apple-app examples."
                          if LANG == "en" else "真实原生视图的离屏快照与局部放大；只含 Apple 应用的固定示例配置。"),
                "not_demonstrated": (["Real key presses", "Global app switching or hiding", "Accessibility authorization"]
                                     if LANG == "en" else ["真实按键", "全局切换或隐藏应用", "辅助功能授权流程"]),
                "safety": ("Only --snapshot, which exits before startTap; no keyboard simulation, clipboard use or app switching."
                           if LANG == "en" else "仅调用 --snapshot 并在 startTap 前退出；没有模拟键盘、剪贴板或应用切换。"),
                "example_tables": configs, "chapters": chapters,
                "sources": [{"file": p.name, "sha256": digest(p)} for p in sorted(source.glob("*.png"))],
                "files": [{"file": p.name, "sha256": digest(p), "bytes": p.stat().st_size}
                          for p in sorted(OUT.iterdir()) if p.suffix in (".mp4", ".vtt", ".jpg")]}
    (OUT / "guide.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Offscreen guide: 3 chapters, {timeline}s, {OUT}")


if __name__ == "__main__":
    main()
