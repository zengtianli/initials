#!/usr/bin/env python3
"""Regenerate every screenshot and scene image in site/assets from the built app.

1. Offscreen `--snapshot` renders of the real settings window and letter panel,
   driven by a demo config that only pins Apple's own apps (nothing is shown,
   activated or intercepted; the app never touches the keyboard).
2. Scene images for the product pages: the same renders placed in a window
   frame with shadow, over a desktop, next to a keyboard diagram. Scenes are
   HTML pages screenshotted by headless Chrome at 2×.

Usage: bash build.sh && python3 scripts/shots.py
"""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "build/Initials.app/Contents/MacOS/Initials"
ASSETS = ROOT / "site/assets"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VERSION = plistlib.loads((ROOT / "build/Initials.app/Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
TEAL = "#1d7a78"

APPS = {
    "c": ("Calendar", "com.apple.iCal", "/System/Applications/Calendar.app"),
    "f": ("Finder", "com.apple.finder", "/System/Library/CoreServices/Finder.app"),
    "m": ("Music", "com.apple.Music", "/System/Applications/Music.app"),
    "n": ("Notes", "com.apple.Notes", "/System/Applications/Notes.app"),
    "p": ("Preview", "com.apple.Preview", "/System/Applications/Preview.app"),
    "s": ("Safari", "com.apple.Safari", "/Applications/Safari.app"),
    "t": ("Terminal", "com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
}
LEFT_APPS = {
    "j": ("Photos", "com.apple.Photos", "/System/Applications/Photos.app"),
    "k": ("Keynote", "com.apple.iWork.Keynote", "/Applications/Keynote.app"),
    "y": ("Weather", "com.apple.weather", "/System/Applications/Weather.app"),
}


def binding(v):
    return {"name": v[0], "bundleID": v[1], "path": v[2]}


def demo_config(share_left: bool, cycle: bool = True) -> dict:
    # The panel lists running apps for unpinned letters; renders of it turn that off
    # so nothing from this Mac shows up.
    return {
        "version": 1,
        "right": {"hold": True, "doubleTap": False, "cycleUnbound": cycle,
                  "bindings": {k: binding(v) for k, v in APPS.items()}},
        "left": {"hold": True, "doubleTap": True, "useRightBindings": share_left, "cycleUnbound": cycle,
                 "bindings": {k: binding(v) for k, v in LEFT_APPS.items()}},
    }


def snapshot(support: pathlib.Path, out: pathlib.Path, *args: str, lang: str):
    env = dict(os.environ, INITIALS_SUPPORT_DIR=str(support))
    languages = "(zh-Hans)" if lang == "zh" else "(en)"
    subprocess.run([str(APP), "--snapshot", str(out), *args, "-AppleLanguages", languages],
                   env=env, check=True, timeout=60)


def chrome(html: pathlib.Path, out: pathlib.Path, width: int, height: int, tmp: pathlib.Path):
    # Headless Chrome on macOS writes the screenshot but often never exits, so wait
    # for the file and stop it ourselves.
    out.unlink(missing_ok=True)
    proc = subprocess.Popen([CHROME, "--headless=new", "--hide-scrollbars", "--disable-gpu", "--force-device-scale-factor=2",
                             f"--user-data-dir={tmp / 'chrome'}", f"--window-size={width},{height}",
                             "--virtual-time-budget=3000", f"--screenshot={out}", html.as_uri()],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(600):
            if proc.poll() is not None or (out.exists() and out.stat().st_size > 0):
                time.sleep(0.3)
                break
            time.sleep(0.1)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
    if not out.exists():
        raise SystemExit(f"Chrome did not render {out.name}")


def size(png: pathlib.Path) -> tuple[int, int]:
    data = png.read_bytes()
    return int.from_bytes(data[16:20], "big") // 2, int.from_bytes(data[20:24], "big") // 2


BASE_CSS = f"""
*{{box-sizing:border-box;margin:0}}
body{{font-family:-apple-system,"PingFang SC",sans-serif;color:#1f2a2a;-webkit-font-smoothing:antialiased;overflow:hidden}}
.stage{{position:relative;width:100vw;height:100vh;display:flex;align-items:center;justify-content:center;
  background:radial-gradient(120% 90% at 0% 0%,#e3f1ee 0%,rgba(227,241,238,0) 60%),
             radial-gradient(90% 80% at 100% 100%,#f6e7dc 0%,rgba(246,231,220,0) 60%),#f4f6f3}}
.win{{position:relative;border-radius:12px;overflow:hidden;
  box-shadow:0 0 0 .5px rgba(0,0,0,.18),0 22px 60px rgba(20,40,40,.22),0 4px 14px rgba(20,40,40,.10)}}
.win img{{display:block}}
.lights{{position:absolute;left:10px;top:10px;display:flex;gap:10px}}
.lights i{{width:13px;height:13px;border-radius:50%;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.18)}}
.lights i:nth-child(1){{background:#ff5f57}}.lights i:nth-child(2){{background:#febc2e}}.lights i:nth-child(3){{background:#28c840}}
.label{{position:absolute;top:18px;left:24px;right:24px;display:flex;justify-content:space-between;
  font-size:13px;letter-spacing:.08em;color:#557070}}
.note{{position:absolute;bottom:18px;left:0;right:0;text-align:center;font-size:13px;color:#6a7f7d}}
kbd{{display:inline-flex;align-items:center;justify-content:center;min-width:34px;height:34px;padding:0 10px;
  font:600 17px -apple-system,"PingFang SC";color:#1f2a2a;background:#fff;border-radius:8px;
  box-shadow:0 0 0 1px rgba(0,0,0,.12),0 2px 0 rgba(0,0,0,.14)}}
"""


def window_scene(tmp, shot: pathlib.Path, out: pathlib.Path, label: str, note: str):
    w, h = size(shot)
    page = tmp / (out.stem + ".html")
    page.write_text(f"""<!doctype html><meta charset=utf-8><style>{BASE_CSS}
.win img{{width:{w}px;height:{h}px}}</style>
<div class=stage><div class=label><span>{label}</span><span>Initials {VERSION}</span></div>
<div class=win><img src="{shot.as_uri()}"><div class=lights><i></i><i></i><i></i></div></div>
<div class=note>{note}</div></div>""")
    chrome(page, out, w + 140, h + 120, tmp)


def picker_scene(tmp, panel: pathlib.Path, backdrop: pathlib.Path, out: pathlib.Path, dark: bool, keys: str, note: str):
    w, h = size(panel)
    bw, bh = size(backdrop)
    wall = ("linear-gradient(160deg,#16302f 0%,#243b4a 55%,#3a2f3f 100%)" if dark
            else "linear-gradient(160deg,#cfe6e1 0%,#e7eef3 50%,#f3e1d6 100%)")
    page = tmp / (out.stem + ".html")
    page.write_text(f"""<!doctype html><meta charset=utf-8><style>{BASE_CSS}
.desk{{position:absolute;inset:0;background:{wall}}}
.behind{{position:absolute;left:70px;top:70px;width:{bw}px;height:{bh}px;border-radius:12px;overflow:hidden;
  filter:blur(1.5px) saturate(.8);opacity:.75;box-shadow:0 20px 50px rgba(0,0,0,.18)}}
.behind img{{width:100%}}
.panel{{position:relative;border-radius:16px;overflow:hidden;
  box-shadow:0 0 0 .5px rgba(0,0,0,.25),0 30px 80px rgba(0,0,0,.35),0 6px 18px rgba(0,0,0,.18)}}
.panel img{{display:block;width:{w}px;height:{h}px}}
.chip{{position:absolute;top:34px;left:50%;transform:translateX(-50%);display:flex;gap:8px;align-items:center;
  padding:10px 16px;border-radius:14px;background:rgba(255,255,255,.82);backdrop-filter:blur(8px);
  font-size:15px;color:#2d3b3b;box-shadow:0 8px 24px rgba(0,0,0,.12)}}
.note{{color:{'#b8c9c7' if dark else '#50605f'}}}</style>
<div class=stage><div class=desk></div><div class=behind><img src="{backdrop.as_uri()}"></div>
<div class=chip>{keys}</div><div class=panel><img src="{panel.as_uri()}"></div><div class=note>{note}</div></div>""")
    chrome(page, out, 1100, 720, tmp)


def keys_scene(tmp, icons: pathlib.Path, out: pathlib.Path):
    def key(text, wide=1.0, hot=False, sub=""):
        style = f"width:{int(78 * wide)}px"
        cls = "k hot" if hot else "k"
        return f'<div class="{cls}" style="{style}"><b>{text}</b><small>{sub}</small></div>'
    row = "".join([key("fn", sub="🌐"), key("⌃", sub="control"), key("⌥", sub="option"),
                   key("⌘", 1.3, True, "左 command"), key("", 4.6), key("⌘", 1.3, True, "右 command"),
                   key("⌥", sub="option")])

    def combo(tag, keys, icon, text):
        if icon == "panel":  # a 2×2 of pinned apps stands in for the letter panel
            art = "<div class=grid>" + "".join(f'<img src="{(icons / n).as_uri()}">' for n in
                                               ("Calendar.png", "Finder.png", "Music.png", "Safari.png")) + "</div>"
        else:
            art = f'<img class=big src="{(icons / icon).as_uri()}">'
        return (f'<div class=card><div class=tag>{tag}</div><div class=keys>{keys}</div>'
                f'<div class=arrow>→</div>{art}<div class=app>{text}</div></div>')
    cards = "".join([
        combo("按住右 ⌘", "<kbd>右⌘</kbd>+<kbd>M</kbd>", "Music.png", "音乐"),
        combo("按住左 ⌘", "<kbd>左⌘</kbd>+<kbd>K</kbd>", "Keynote.png", "Keynote"),
        combo("双击任一 ⌘", "<kbd>⌘</kbd><kbd>⌘</kbd>", "panel", "字母面板"),
    ])
    page = tmp / "keys.html"
    page.write_text(f"""<!doctype html><meta charset=utf-8><style>{BASE_CSS}
.stage{{flex-direction:column;gap:46px}}
.board{{display:flex;gap:10px;padding:18px;border-radius:22px;background:#e6e9e8;
  box-shadow:inset 0 1px 0 #fff,0 18px 40px rgba(20,40,40,.14)}}
.k{{height:82px;border-radius:12px;background:#fbfbfa;display:flex;flex-direction:column;justify-content:space-between;
  padding:10px 12px;box-shadow:0 0 0 1px rgba(0,0,0,.08),0 3px 0 rgba(0,0,0,.12)}}
.k b{{font-size:24px;font-weight:500;color:#3a4545}} .k small{{font-size:12px;color:#8a9595}}
.k.hot{{background:{TEAL};box-shadow:0 0 0 3px rgba(29,122,120,.25),0 3px 0 #0f4e4c}}
.k.hot b,.k.hot small{{color:#fff}}
.cards{{display:flex;gap:22px}}
.card{{width:300px;padding:20px 22px;border-radius:18px;background:#fff;display:grid;
  grid-template-columns:auto 1fr auto;grid-template-rows:auto auto;align-items:center;gap:10px 12px;
  box-shadow:0 0 0 1px rgba(0,0,0,.06),0 12px 30px rgba(20,40,40,.08)}}
.tag{{grid-column:1/-1;font-size:14px;letter-spacing:.06em;color:{TEAL};font-weight:600}}
.keys{{display:flex;gap:6px;align-items:center;font-size:18px;color:#6a7f7d}}
.arrow{{font-size:22px;color:#9aa9a7;justify-self:center}}
.card .big{{width:52px;height:52px;grid-row:2;grid-column:3}}
.grid{{grid-row:2;grid-column:3;display:grid;grid-template-columns:26px 26px;gap:4px;padding:5px;
  border-radius:10px;background:#f1f3f2;box-shadow:0 0 0 1px rgba(0,0,0,.06)}}
.grid img{{width:26px;height:26px}}
.app{{display:none}}</style>
<div class=stage><div class=board>{row}</div><div class=cards>{cards}</div>
<div class=note>左右两个 ⌘ 各自可设：按住 + 字母、双击弹面板，或两样都开。</div></div>""")
    chrome(page, out, 1100, 560, tmp)


def main():
    assert APP.exists(), "run bash build.sh first"
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="initials-shots-"))
    try:
        for name, config in (("shared", demo_config(True)), ("separate", demo_config(False)),
                             ("panel", demo_config(True, cycle=False))):
            (tmp / name).mkdir()
            (tmp / name / "config.json").write_text(json.dumps(config))
        raw = tmp / "raw"
        raw.mkdir()
        for lang in ("zh", "en"):
            snapshot(tmp / "shared", raw / f"settings-right-{lang}.png", "--settings", "right", lang=lang)
            snapshot(tmp / "separate", raw / f"settings-left-{lang}.png", "--settings", "left", lang=lang)
            snapshot(tmp / "panel", raw / f"picker-{lang}.png", "--picker", "--right", lang=lang)
            snapshot(tmp / "panel", raw / f"picker-dark-{lang}.png", "--picker", "--right", "--dark", lang=lang)
        for png in raw.iterdir():
            shutil.copy2(png, ASSETS / png.name)

        icons = tmp / "icons"
        icons.mkdir()
        subprocess.run(["xcrun", "swift", str(ROOT / "scripts/appicon.swift"), str(icons),
                        *(v[2] for v in (APPS["c"], APPS["f"], APPS["m"], APPS["s"], LEFT_APPS["k"]))],
                       check=True, timeout=300)

        keys_scene(tmp, icons, ASSETS / "scene-keys-zh.png")
        picker_scene(tmp, raw / "picker-zh.png", raw / "settings-right-zh.png", ASSETS / "scene-picker-zh.png", False,
                     "<kbd>⌘</kbd><kbd>⌘</kbd>&nbsp;快速按两下，面板浮在当前窗口上",
                     "面板不抢焦点：按字母切换，Esc 或 4 秒不按键自动关闭")
        picker_scene(tmp, raw / "picker-dark-zh.png", raw / "settings-right-zh.png", ASSETS / "scene-picker-dark-zh.png", True,
                     "<kbd>⌘</kbd><kbd>⌘</kbd>&nbsp;深色模式", "跟随系统深浅色")
        window_scene(tmp, raw / "settings-right-zh.png", ASSETS / "scene-settings-right-zh.png", "真实应用界面 · 右 ⌘",
                     "演示配置只含苹果自带 app")
        window_scene(tmp, raw / "settings-left-zh.png", ASSETS / "scene-settings-left-zh.png", "真实应用界面 · 左 ⌘",
                     "左 ⌘ 单独一张字母表：按住只接管这里指定的字母，⌘C、⌘V 照常")
        for png in sorted(ASSETS.glob("*.png")):
            print(f"{png.relative_to(ROOT)}  {size(png)[0] * 2}×{size(png)[1] * 2}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
