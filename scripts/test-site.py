#!/usr/bin/env python3
"""Site regressions: measured/public-build disclosure and GitHub-only downloads."""
import importlib.util
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("initials_site", ROOT / "scripts/build-site.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)
sys.path.insert(0, str(ROOT.parent / "lintel/engine"))
from site_contract import check_homepage


class Links(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.anchors = []
        self.feed(page)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.anchors.append(dict(attrs))


class ReleaseDownloads(unittest.TestCase):
    def setUp(self):
        self.release = json.loads((ROOT / "build/release.json").read_text())
        self.out = ROOT / "build/site"
        self.links = site.release_links(self.release)

    def test_release_links_follow_original_version(self):
        other = dict(self.release, version="9.8.7", filename="Initials-9.8.7-arm64.dmg")
        self.assertEqual(site.release_links(other)["release_url"],
                         "https://github.com/zengtianli/initials/releases/tag/v9.8.7")
        with self.assertRaises(SystemExit):
            site.release_links(dict(other, filename=self.release["filename"]))

    def test_both_pages_link_install_buttons_to_release(self):
        for filename in ("index.html", "en/index.html"):
            anchors = Links((self.out / filename).read_text()).anchors
            buttons = [a for a in anchors if a.get("href") == self.links["release_url"]
                       and "button" in a.get("class", "").split()]
            self.assertEqual(len(buttons), 3, filename)
            self.assertTrue(all("download" not in a for a in buttons))
            self.assertFalse(any("/downloads/" in a.get("href", "")
                                 or a.get("href", "").endswith(".dmg") for a in anchors))
            self.assertTrue(any(a.get("href", "").endswith("tutorial.mp4") for a in anchors))

    def test_package_free_bundle_preserves_release_integrity(self):
        site.assert_package_free(self.out)
        self.assertFalse((self.out / "downloads").exists())
        record = json.loads((self.out / "release.json").read_text())
        self.assertEqual(record["sha256"], self.release["sha256"])
        self.assertEqual(record["bytes"], self.release["size_bytes"])
        self.assertEqual(record["download"], self.links["download_url"])
        updates = json.loads((self.out / "updates.json").read_text())
        self.assertEqual(updates["channel"], "public")
        self.assertEqual(updates["bundle_id"], "cyou.tianli.initials")
        self.assertEqual(updates["sha256"], record["sha256"])
        self.assertEqual(updates["download_url"], record["download"])
        manifest = json.loads((self.out / "site-manifest.json").read_text())
        self.assertEqual({f["path"] for f in manifest["files"]},
                         {p.relative_to(self.out).as_posix() for p in self.out.rglob("*")
                          if p.is_file() and p.name != "site-manifest.json"})

    def test_unlinked_installer_is_rejected_but_tutorial_archive_is_allowed(self):
        evidence = ROOT / "build/github-downloads-20261011"
        evidence.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=evidence) as temp:
            out = Path(temp)
            (out / "tutorial-example.zip").touch()
            site.assert_package_free(out)
            (out / self.release["filename"]).touch()
            with self.assertRaises(SystemExit):
                site.assert_package_free(out)


class MeasurementScope(unittest.TestCase):
    def setUp(self):
        self.raw = json.loads((ROOT / "perf/lightweight.json").read_text())
        self.release = json.loads((ROOT / "build/release.json").read_text())

    def scope_check(self, block):
        result = check_homepage("<main>" + block + "</main>", product={
            "performance_evidence": str(ROOT / "perf/lightweight.json"),
            "release_evidence": str(ROOT / "build/release.json"),
            "strict_metadata": True,
        })
        return next(c for c in result["checks"] if c["id"] == "resources.release_version")

    def test_current_measurement_has_explicit_public_scope(self):
        block = site.lightweight_section(self.raw, self.release, None, "zh")
        self.assertEqual(self.scope_check(block)["status"], "passed")
        for value in (self.raw["version"], self.raw["device"], self.raw["measured_at"]):
            self.assertIn(value, block)

    def test_english_measurement_has_explicit_public_scope(self):
        block = site.lightweight_section(self.raw, self.release, None, "en")
        self.assertEqual(self.scope_check(block)["status"], "passed")

    def test_unscoped_different_build_is_rejected(self):
        public = f"{self.release['version']} ({self.release['build']})"
        if self.raw["version"] == public:
            self.skipTest("Current measurements and public build match")
        block = site.standalone_section(ROOT / "perf/lightweight.json", self.raw["version"].split()[0])
        self.assertEqual(self.scope_check(block)["status"], "failed")


if __name__ == "__main__":
    unittest.main()
