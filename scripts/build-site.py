#!/usr/bin/env python3
"""Assemble build/site from site/ and the notarized release (build/release.json).

Version, size and checksum come from the release record, never typed by hand.
"""
import hashlib, json, pathlib, shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
release = json.loads((ROOT / "build/release.json").read_text())
dmg = ROOT / release["artifact_path"]
if hashlib.sha256(dmg.read_bytes()).hexdigest() != release["sha256"]:
    raise SystemExit("DMG does not match build/release.json; rerun scripts/release.py")
out = ROOT / "build/site"
if out.exists():
    shutil.rmtree(out)
shutil.copytree(ROOT / "site", out)
(out / "downloads").mkdir()
shutil.copy2(dmg, out / "downloads" / dmg.name)
(out / "downloads/SHA256SUMS.txt").write_text(f"{release['sha256']}  {dmg.name}\n")
page = (out / "index.html").read_text()
page = (page.replace("{{VERSION}}", release["version"])
            .replace("{{SIZE}}", f"{release['size_bytes'] / 1_000_000:.1f}")
            .replace("{{SHA256}}", release["sha256"]))
if "{{" in page:
    raise SystemExit("Unfilled placeholder in index.html")
(out / "index.html").write_text(page)
print(f"Built {out} (v{release['version']}, {dmg.name})")
