#!/usr/bin/env python3
"""Offline regression of the release gate; no credentials, build or uploads."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ProvenanceTests(unittest.TestCase):
    def test_metadata_commit_can_follow_build_but_source_and_artifact_cannot_drift(self):
        with tempfile.TemporaryDirectory(prefix="initials-provenance-") as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
            git("init", "-q")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "fixture@invalid.example")
            for name in ("Sources/main.swift", "Resources/icon.icns", "Info.plist", "build.sh"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
            git("add", ".")
            git("commit", "-qm", "compiled inputs")
            source_commit = git("rev-parse", "HEAD")
            release.ROOT = root
            release.APP = root / "candidate.app"
            release.INSTALLED = root / "installed.app"
            for bundle in (release.APP, release.INSTALLED):
                (bundle / "Contents/MacOS").mkdir(parents=True)
                (bundle / "Contents/Resources").mkdir()
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "cyou.tianli.initials", "CFBundleExecutable": "Initials",
                    "CFBundleShortVersionString": "1.4.1", "CFBundleVersion": "14", "CFBundleIconFile": "icon.icns"}))
                (bundle / "Contents/MacOS/Initials").write_bytes(b"verified executable")
                (bundle / "Contents/Resources/icon.icns").write_bytes(b"verified icon")
            files = {name: release.sha(root / name) for name in
                     ("Sources/main.swift", "Resources/icon.icns", "Info.plist", "build.sh")}
            receipt = {"schema_version": 1, "built_at": "fixture", "build_command_sha256": "fixture",
                       "source": {"input_globs": sorted(release.SOURCE_PATTERNS), "dirty": False,
                                  "commit": source_commit, "file_count": len(files),
                                  "sha256": hashlib.sha256(json.dumps(files, sort_keys=True, ensure_ascii=False).encode()).hexdigest()},
                       "artifact": release.artifact_snapshot(release.APP)}
            (root / "perf").mkdir()
            receipt_path = root / "perf/build-receipt.json"
            receipt_path.write_text(json.dumps(receipt))
            (root / "notes.md").write_text("non-compiled handoff")
            git("add", "notes.md")
            git("commit", "-qm", "metadata after build")
            self.assertEqual(release.verify_provenance()["source_commit"], source_commit)
            (root / "Sources/main.swift").write_text("changed source")
            with self.assertRaisesRegex(SystemExit, "Current source inputs differ"):
                release.verify_provenance()
            (root / "Sources/main.swift").write_text("Sources/main.swift")
            (release.INSTALLED / "Contents/MacOS/Initials").write_bytes(b"different installed executable")
            with self.assertRaisesRegex(SystemExit, "Built and installed"):
                release.verify_provenance()
            (release.INSTALLED / "Contents/MacOS/Initials").write_bytes(b"verified executable")
            # A receipt claiming a different historical source must fail even if
            # its current digest and installed app happen to agree.
            (root / "Sources/main.swift").write_text("different historical source")
            git("add", "Sources/main.swift")
            git("commit", "-qm", "other source")
            receipt["source"]["commit"] = git("rev-parse", "HEAD")
            receipt_path.write_text(json.dumps(receipt))
            (root / "Sources/main.swift").write_text("Sources/main.swift")
            with self.assertRaisesRegex(SystemExit, "Recorded Git source differs"):
                release.verify_provenance()


if __name__ == "__main__":
    unittest.main()
