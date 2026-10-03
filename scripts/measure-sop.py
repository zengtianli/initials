#!/usr/bin/env python3
"""Chapter's registered re-measurement for Initials (project.yaml sop.measure.command).

Initials is a resident menu-bar app with no main window, released as a DMG. Sampling only the running instance
records idle numbers and the installed size, so every new version lost its download size and its headline speed
(1.2.0 (6): size and speed missing after Chapter's passive re-measure). This script measures the installed build
that build/release.json names, and writes perf/lightweight.json and perf/raw/:

  idle   the shared app-lightweight batch_measure on the long-running instance (passive, 60 s, helpers included;
         replaced sections go to history, the version and measured_artifact follow the installed bundle)
  size   measure.py size --download <the release DMG> --installed /Applications/Initials.app
  speed  the installed binary's `--snapshot <png> --picker --right` with an isolated INITIALS_SUPPORT_DIR holding a
         copy of the owner's config.json: production picker entries, layout and Retina PNG export; activation policy
         .prohibited, no event tap, nothing shown or activated; 1 warm-up + 7 runs, median

Focus-safe (sop.measure.in_use: true): nothing it starts can be shown or activated. Exits 75 (app_sop's
DEFER_EXIT) when app_sop's gate says the machine is not steady, or the sample was disturbed; nothing is written then.
Outside scripts/accept and Sources on purpose: it is not a build input of the installed-app receipt.
"""
import hashlib
import json
import os
import plistlib
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = Path("/Applications/Initials.app")
EXE = APP / "Contents/MacOS/Initials"
OWNER_CONFIG = Path.home() / "Library/Application Support/cyou.tianli.initials/config.json"
LW = Path.home() / "Apps/.claude/skills/app-lightweight/scripts"
DEFER = 75
RUNS = 7
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
sys.path.insert(0, str(LW))
import app_sop  # noqa: E402
import batch_measure  # noqa: E402

SPEED_KEY = "picker_offscreen_end_to_end"
SPEED_LABEL = "启动到字母面板离屏渲染完成（含 PNG 导出）"
SPEED_LABEL_EN = "Start to letter-panel offscreen render completed (including PNG export)"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    tmp.replace(path)


def picker_runs(workdir):
    """1 warm-up + RUNS offscreen picker renders of the installed binary, isolated from the owner's support folder."""
    support = workdir / "support"
    support.mkdir()
    if OWNER_CONFIG.is_file():
        shutil.copy2(OWNER_CONFIG, support / "config.json")  # the owner's letters, so the panel has real entries
    env = {**os.environ, "INITIALS_SUPPORT_DIR": str(support)}
    samples = []
    for i in range(RUNS + 1):
        png = workdir / f"picker-{i}.png"
        start = time.perf_counter()
        subprocess.run([str(EXE), "--snapshot", str(png), "--picker", "--right"], env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
        elapsed = (time.perf_counter() - start) * 1000
        if png.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            raise RuntimeError("--snapshot --picker 没有写出 PNG")
        if i:
            samples.append(elapsed)
    return samples


def main():
    in_use = os.environ.get(app_sop.SAMPLE_GATE_ENV) == "1"
    steady, why = app_sop.steady()
    if not steady:
        print(f"未测量：{why}")
        return DEFER
    release = json.loads((ROOT / "build/release.json").read_text())
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    short, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    exe_sha = sha256(EXE)
    if (release.get("version"), str(release.get("build"))) != (short, build) or exe_sha != release["artifact"]["sha256"]:
        print(f"装机 {short} ({build}) 不是 build/release.json 记录的发行构建 {release.get('version')} ({release.get('build')})；"
              "先按 scripts/release.py 发行并装机再测")
        return 1
    dmg = ROOT / release["artifact_path"]
    if not dmg.is_file() or sha256(dmg) != release["sha256"]:
        print(f"发行包 {release['artifact_path']} 缺失或与 build/release.json 的 SHA256 不符")
        return 1
    running = [p for p in batch_measure.sh("pgrep", "-f", re.escape(str(EXE))).split() if p]
    if len(running) != 1:
        print(f"常驻实例需要恰好一个，实际 PID={running}；按 scripts/install.sh 恢复常驻后再测")
        return 1

    # 1. Idle and installed size from the long-running instance (shared batch_measure; publishes the file itself).
    spec = {"app": str(APP), "running": str(EXE), "launch": False, "repo": ROOT, "in_use": in_use}
    try:
        batch_measure.run("initials-mac", spec)
    except batch_measure.Deferred as exc:
        print(exc)
        return DEFER

    # 2. Download size of the release DMG and the headline speed; folded into the file batch_measure just wrote.
    out = ROOT / "perf/lightweight.json"
    baseline = out.read_bytes()
    doc = json.loads(baseline)
    version = f"{short} ({build})"
    if doc.get("version") != version:
        raise RuntimeError(f"批量测量写出的版本 {doc.get('version')} 不是装机 {version}")
    size = json.loads(re.search(r"\{.*\}", batch_measure.sh("python3", str(LW / "measure.py"), "size", "--download", str(dmg),
                                                           "--installed", str(APP)), re.S).group(0))["size"]
    with tempfile.TemporaryDirectory(prefix="initials-measure-") as tmp:
        samples = picker_runs(Path(tmp))
    load = batch_measure.load()
    steady, why = app_sop.steady()
    # The measurement's own load is expected afterwards; the owner coming back, unplugging or a build is not.
    if not steady and any(not reason.startswith("负载") for reason in why.split("；")):
        print(f"样本作废，未写入速度与安装包：测量期间{why}")
        return DEFER
    median = round(statistics.median(samples), 1)
    raw_rel = f"perf/raw/picker-operation-{short}-{build}.json"
    (ROOT / "perf/raw").mkdir(parents=True, exist_ok=True)
    write_json(ROOT / raw_rel, {
        "version": version, "samples_ms": samples, "median_ms": median, "runs": RUNS, "binary_sha256": exe_sha,
        "method": "installed release --snapshot <png> --picker --right with isolated INITIALS_SUPPORT_DIR (copy of user config); "
                  "production picker entries/fill/layout and Retina PNG export; 1 warmup + 7 runs; no event tap",
        "load": load, "measured_at": batch_measure.TODAY})
    today = batch_measure.TODAY
    history = doc.setdefault("history", [])
    if doc.get("size", {}).get("download_bytes") not in (None, size["download_bytes"]):
        history.append({"section": "size", "version": version, "replaced_on": today, "reason": "按发行 DMG 重测", "value": doc["size"]})
    doc["size"] = size
    for old in doc.get("speed_gui") or []:
        history.append({"section": "speed_gui", "version": version, "replaced_on": today, "reason": "按登记测量脚本重测", "value": old})
    doc["speed_gui"] = [{
        "key": SPEED_KEY, "label": SPEED_LABEL, "label_en": SPEED_LABEL_EN, "median_ms": median, "runs": RUNS, "headline": True,
        "method": "已安装发行版 --snapshot --picker --right，隔离 INITIALS_SUPPORT_DIR（复制本人配置）；生产 PickerPanel 条目查询、"
                  "布局和 Retina PNG 导出，1 次预热后 7 次中位；不启用按键拦截、不抢焦点。包括进程启动与导出，不代表前台切换应用耗时。",
        "raw": raw_rel, "load": load}]
    reused = doc.get("reused_for") or {}
    if version in reused:  # the "not yet re-measured" note for this version is now answered by this measurement
        history.append({"section": "reused_for", "replaced_on": today, "reason": f"{version} 已实测，不再沿用旧版本数字",
                        "value": doc.pop("reused_for")})
    if out.read_bytes() != baseline:
        print("测量期间证据已被修改，未覆盖 perf/lightweight.json")
        return 1
    write_json(out, doc)
    print(json.dumps({"version": version, "size": size, "picker_median_ms": median, "idle": doc.get("idle", {}).get("footprint_mb")},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
