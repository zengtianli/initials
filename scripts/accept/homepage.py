"""Bind Lintel's real offscreen website render to the current published bytes.

The native renderer is shared with the original website publisher. Its captures
may be reused only when every generated file and every capture receipt still
matches; changed pages require a new Lintel render. Live HTML is read again here.
"""
import argparse
import json
import os
from pathlib import Path
import sys

from _common import ROOT, detail

ENGINE = Path.home() / "Apps/lintel/engine"
sys.path.insert(0, str(ENGINE))
from web_control import catalogue_captures, manifest, readback

PAGES = ("index.html", "en/index.html")


def matching_review(site_root, paths):
    current = manifest(site_root)
    errors = []
    for path in paths:
        try:
            plan = json.loads(path.read_text())
            if (plan.get("site") != "initials" or plan.get("ready") is not True
                    or Path(plan["out"]).resolve() != site_root.resolve()
                    or plan["manifest"] != current):
                raise ValueError("计划与当前网站字节不匹配")
            review = plan["acceptance_evidence"]["visual_review"]
            if review.get("verified") is not True:
                raise ValueError("原生渲染未验收")
            evidence = Path(review["evidence_file"])
            if catalogue_captures(evidence, PAGES) != review["captures"]:
                raise ValueError("原生图像或 DOM 回执已变化")
            visual = json.loads(evidence.read_text())
            if visual["manifest"] != current or not visual.get("renderer", "").startswith("native offline WKWebView"):
                raise ValueError("图像未绑定同一份原生渲染产物")
            for row in visual["results"]:
                dom = row["dom"]
                width = {"desktop": 1440, "narrow": 390}[row["mode"]]
                if (dom.get("width") != width or not dom.get("title", "").strip()
                        or dom.get("height", 0) <= 0 or dom.get("unreadableButtons") != []):
                    raise ValueError("页面尺寸、标题或按钮可读性未通过")
            return plan, visual, path
        except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
            errors.append(f"{path.parent.name}: {exc}")
    raise AssertionError("没有与当前字节匹配的 Lintel 原生取证；先运行 lintel site ship --site initials。"
                         + "；".join(errors[:3]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--viewport", choices=("desktop", "mobile"), required=True)
    args = parser.parse_args()
    supplied = os.environ.get("INITIALS_SITE_EVIDENCE_DIR")
    paths = ([Path(supplied).expanduser() / "lintel-plan.json"] if supplied else
             sorted((Path.home() / "Library/Caches/lintel-ship").glob("*/initials*/lintel-plan.json"),
                    key=lambda path: path.stat().st_mtime, reverse=True))
    plan, visual, path = matching_review(ROOT / "build/site", paths)
    origin = os.environ.get("SOP_PROMO_URL", "https://initials.tianli.cyou/").rstrip("/")
    live = readback({"url": origin}, ROOT / "build/site",
                    {page: plan["manifest"][page] for page in PAGES})
    if live.get("ok") is not True:
        raise AssertionError("线上页面与已渲染字节不同：" + json.dumps(live, ensure_ascii=False))
    mode = "narrow" if args.viewport == "mobile" else "desktop"
    rows = [row for row in visual["results"] if row["mode"] == mode and row["page"] in PAGES]
    if {row["page"] for row in rows} != set(PAGES):
        raise AssertionError("中英文页面的视口取证不完整")
    detail("homepage_" + args.viewport,
           f"{args.viewport}：中英文线上页面 HTTP 200 且字节匹配；原生离屏渲染无溢出、坏图或不可读按钮",
           method="ui_automation", renderer=visual["renderer"], plan=str(path),
           manifest_files=len(plan["manifest"]), captures=rows, live_pages=live["files"],
           limits=["复用同一网站字节的原生渲染回执，重新核对所有文件和图像哈希并回读线上 HTML",
                   "响应式视口，不等于真实手机；不代表所有浏览器"])


if __name__ == "__main__":
    main()
