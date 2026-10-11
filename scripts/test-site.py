#!/usr/bin/env python3
"""Small regressions for the site's measured/public-build disclosure."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("initials_site", ROOT / "scripts/build-site.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)
sys.path.insert(0, str(ROOT.parent / "lintel/engine"))
from site_contract import check_homepage


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
