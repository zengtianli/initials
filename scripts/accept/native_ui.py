#!/usr/bin/env python3
"""Exercise real AppKit settings and picker entirely inside a prohibited app process."""
import json
import os
from pathlib import Path
from _common import ROOT, detail, ensure_build, isolated, run


def main():
    _, gui = ensure_build()
    out = Path(os.environ.get("SOP_OUT_DIR", str(ROOT / "perf/acceptance"))).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with isolated() as (_, env):
        run([gui, "--ui-self-test", out], env=env)
        report = json.loads((out / "ui-self-test.json").read_text())
        assert report["passed"] and report["checks"] and all(report["checks"].values())
        detail("native_ui", "真实设置窗与字母面板离屏交互、刷新、保存和关闭全部通过；未启动键盘拦截。",
               checks=report["checks"], method=report["method"],
               screenshots=["settings-shared.png", "settings-right.png", "picker-populated.png", "picker-empty.png"],
               limits="不覆盖系统权限弹窗、登录项注册、选 App 对话框、真实按键或装机图标。")


if __name__ == "__main__":
    main()
