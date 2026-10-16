#!/usr/bin/env python3
"""Compare existing site screenshots with real, isolated native snapshots.

Does not record videos, launch the normal application, or modify user settings.
The report records any changed screenshot; review it before reusing the guide.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
from datetime import datetime, timezone
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/Initials.app"))
    parser.add_argument("--out", type=Path, default=ROOT / "build/media-review")
    parser.add_argument("--baseline-app", type=Path, help="Previously released app, verified against build/release.json")
    parser.add_argument("--record", action="store_true", help="Refresh changed native screenshots and record a proven unchanged guide scope")
    args = parser.parse_args()
    app = args.app.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    receipt = json.loads((ROOT / "perf/build-receipt.json").read_text())
    executable = app / receipt["artifact"]["executable"]
    assert digest(executable) == receipt["artifact"]["sha256"], "App is not the recorded build"
    # Verify every compiled application source/resource against the real receipt.
    # The unrelated old signing transport is not used by a snapshot process.
    for name, checksum in receipt["source"]["files"].items():
        if name.startswith(("Sources/", "Resources/")) or name == "Info.plist":
            assert digest(ROOT / name) == checksum, name
    spec = importlib.util.spec_from_file_location("shots", ROOT / "scripts/shots.py")
    shots = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shots)
    shots.APP = executable
    baseline_executable = None
    if args.baseline_app:
        baseline_executable = args.baseline_app.resolve() / "Contents/MacOS/Initials"
        released = json.loads((ROOT / "build/release.json").read_text())
        assert digest(baseline_executable) == released["executable_sha256"], "Baseline is not the recorded release"
    checks = {}
    for lang in ("zh", "en"):
        for name, config in (("shared", shots.demo_config(True)), ("separate", shots.demo_config(False)),
                             ("panel", shots.demo_config(True, cycle=False))):
            support = out / lang / name
            support.mkdir(parents=True, exist_ok=True)
            path = support / "config.json"
            path.write_text(json.dumps(config))
            before = digest(path)
            names = (["settings-right"] if name == "shared" else ["settings-left"] if name == "separate"
                     else ["picker", "picker-dark"])
            for view in names:
                filename = f"{view}-{lang}.png"
                target = out / filename
                flags = ["--settings", view.removeprefix("settings-")] if view.startswith("settings-") else ["--picker", "--right"] + (["--dark"] if "dark" in view else [])
                shots.snapshot(support, target, *flags, lang=lang)
                previous = ROOT / "site/assets" / filename
                old, new = Image.open(previous).convert("RGBA"), Image.open(target).convert("RGBA")
                same = old.size == new.size and ImageChops.difference(old, new).convert("RGB").getbbox() is None
                checks[filename] = {"unchanged_pixels": same, "previous_sha256": digest(previous),
                                    "current_sha256": digest(target), "previous_size": old.size, "current_size": new.size}
                if baseline_executable:
                    baseline = out / "baseline" / filename
                    baseline.parent.mkdir(exist_ok=True)
                    shots.APP = baseline_executable
                    shots.snapshot(support, baseline, *flags, lang=lang)
                    shots.APP = executable
                    before_image = Image.open(baseline).convert("RGBA")
                    checks[filename].update(baseline_sha256=digest(baseline),
                        release_ui_unchanged=before_image.size == new.size and ImageChops.difference(before_image, new).convert("RGB").getbbox() is None)
            assert digest(path) == before, "Snapshot changed fixture settings"
    sys.path.insert(0, str(ROOT.parent / "chapter/engine"))
    from app_sop import app_source_snapshot, load_apps
    product = load_apps("initials-mac")[0]
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    report = {"checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "tool": "python3 scripts/review-media.py", "version": info["CFBundleShortVersionString"],
              "build": str(info["CFBundleVersion"]), "executable_sha256": digest(executable),
              "ui_source_sha256": app_source_snapshot(product, product["sop"]["ui"])["sha256"],
              "unchanged": all(row.get("release_ui_unchanged", row["unchanged_pixels"]) for row in checks.values()), "screenshots": checks,
              "baseline_executable_sha256": digest(baseline_executable) if baseline_executable else None,
              "method": "Real --snapshot, isolated fixture; no event tap, synthetic input or focus changes"}
    (out / "review.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.record:
        assert baseline_executable and report["unchanged"], "Changed UI needs a new scope review, not an unchanged declaration"
        import shutil
        for filename, row in checks.items():
            if not row["unchanged_pixels"]:
                shutil.copy2(out / filename, ROOT / "site/assets" / filename)
        key = f"{report['version']} ({report['build']})"
        for meta in (ROOT / "site/media/guide.json", ROOT / "site/media/en/guide.json"):
            guide = json.loads(meta.read_text())
            # Verify all historical media bytes; recording dates and hashes stay intact.
            for row in guide["files"]:
                assert digest(meta.parent / row["file"]) == row["sha256"], row["file"]
            guide.setdefault("reused_for", {})[key] = {
                "reviewed_at": report["checked_at"],
                "reason": "保留标明 1.1.0 的历史离屏字母表导览，未重录视频。1.4.1 与公开 1.4.0 的八张中英设置及面板在同一环境逐像素一致；静态截图刷新日历图标和登录项状态。新增自动更新选项不在旧片段中，由当前原生离屏验收覆盖；旧片不代表新版全部界面或真实按键实录。",
                "reason_en": "Retain the explicitly labelled 1.1.0 historical offscreen letter-table guide, without re-recording. Eight bilingual Settings/picker views from 1.4.1 and public 1.4.0 are pixel-identical in the same environment. Static screenshots refresh calendar icons and login status. New optional update controls are covered by current native offscreen acceptance, not the historical clips; the clips are not a full current-UI or live-key recording.",
                "verification": "scripts/review-media.py --baseline-app build/Initials.app; frozen build/media-review/review.json"}
            guide.setdefault("ui_reviews", []).append(report)
            meta.write_text(json.dumps(guide, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
