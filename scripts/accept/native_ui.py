#!/usr/bin/env python3
"""Exercise real AppKit settings and picker entirely inside a prohibited app process."""
import json
import os
from pathlib import Path
import struct
from _common import ROOT, detail, ensure_build, isolated, run

# Separate left letters: the left settings page then shows one more row ("same letters as right ⌘").
SNAPSHOT_CONFIG = {
    "version": 1,
    "right": {"hold": True, "doubleTap": False, "cycleUnbound": False,
              "bindings": {"f": {"name": "Finder", "bundleID": "com.apple.finder",
                                 "path": "/System/Library/CoreServices/Finder.app"}}},
    "left": {"hold": True, "doubleTap": True, "useRightBindings": False, "cycleUnbound": False,
             "bindings": {"j": {"name": "Finder", "bundleID": "com.apple.finder",
                                "path": "/System/Library/CoreServices/Finder.app"}}},
}


def png_size(path):
    data = Path(path).read_bytes()[:24]
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    return struct.unpack(">II", data[16:24])


def settings_snapshots(gui, out, env):
    """`--snapshot --settings` (docs and site images) renders the whole window, title bar included. The
    app exits non-zero if a control falls outside the content area; the left page must also be taller
    than the right one by its extra row, or the window kept the right page's height."""
    support = Path(env["INITIALS_SUPPORT_DIR"])
    support.mkdir(parents=True, exist_ok=True)
    (support / "config.json").write_text(json.dumps(SNAPSHOT_CONFIG))
    sizes = {}
    for side in ("right", "left"):
        png = out / f"snapshot-settings-{side}.png"
        run([gui, "--snapshot", png, "--settings", side], env=env)
        sizes[side] = png_size(png)
    assert sizes["left"][0] == sizes["right"][0], sizes
    assert sizes["left"][1] - sizes["right"][1] >= 40, f"left settings page did not grow for its extra row: {sizes}"
    return {side: f"{w}x{h}" for side, (w, h) in sizes.items()}


def main():
    _, gui = ensure_build()
    out = Path(os.environ.get("SOP_OUT_DIR", str(ROOT / "perf/acceptance"))).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with isolated() as (_, env):
        run([gui, "--ui-self-test", out], env=env)
        report = json.loads((out / "ui-self-test.json").read_text())
        assert report["passed"] and report["checks"] and all(report["checks"].values())
    with isolated() as (_, env):
        snapshots = settings_snapshots(gui, out, env)
    detail("native_ui", "真实设置窗与字母面板离屏交互、刷新、保存和关闭全部通过；带标题栏的左右设置页快照无控件越界，左页随多出的一行变高；未启动键盘拦截。",
           checks=report["checks"], method=report["method"], settings_snapshots=snapshots,
           screenshots=["settings-shared.png", "settings-right.png", "picker-populated.png", "picker-empty.png",
                        "snapshot-settings-right.png", "snapshot-settings-left.png"],
           limits="不覆盖系统权限弹窗、登录项注册、选 App 对话框、真实按键或装机图标。")


if __name__ == "__main__":
    main()
