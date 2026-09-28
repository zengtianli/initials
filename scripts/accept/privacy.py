#!/usr/bin/env python3
"""Check isolated CLI persistence and safe simulation; audit privacy-sensitive APIs."""
import hashlib
import json
import plistlib
import re

from _common import ROOT, detail, ensure_build, isolated, run


def main():
    cli, gui = ensure_build()
    dynamic = []
    with isolated() as (root, env):
        env = {**env, "XDG_CONFIG_HOME": str(root / "xdg")}
        support = root / "support"
        support.mkdir()
        config = support / "config.json"
        mackit = root / "xdg/mackit"
        (mackit / "keys.d").mkdir(parents=True)
        (mackit / "profile.json").write_text('{"profile":"tianli"}\n')
        (mackit / "hotkey_overrides.json").write_text('{"features":{"rcmd":false},"sentinel":"keep"}\n')
        (mackit / "keys.d/initials.json").write_text('[{"sentinel":"private-shortcut-catalog"}]\n')

        fixture = root / "PrivacyFixture.app"
        (fixture / "Contents").mkdir(parents=True)
        with (fixture / "Contents/Info.plist").open("wb") as out:
            plistlib.dump({"CFBundleName": "PrivacyFixture", "CFBundleIdentifier": "test.initials.privacy.fixture",
                          "CFBundlePackageType": "APPL"}, out)

        def files():
            return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in root.rglob("*") if p.is_file()}

        def invoke(*args, expected=0):
            return run([cli, *args], env=env, expected=expected)

        original = files()
        result = invoke("set", "q", fixture)
        assert result.stdout.strip() == f"right Q → PrivacyFixture ({fixture})"
        assert not result.stderr
        saved = json.loads(config.read_text())
        assert set(saved) == {"version", "right", "left", "doubleTapSeconds", "pickerTimeoutSeconds"}
        side_fields = {"enabled", "hold", "doubleTap", "bindings", "hideIfFrontmost", "cycleUnbound", "useRightBindings"}
        assert set(saved["right"]) == side_fields and set(saved["left"]) == side_fields
        assert saved["right"]["bindings"] == {
            "q": {"name": "PrivacyFixture", "bundleID": "test.initials.privacy.fixture", "path": str(fixture)}
        }
        assert set(files()) == set(original) | {"support/config.json"}
        dynamic.append("A real CLI binding update writes only config.json inside the disposable tree; exact saved schema contains settings and selected app metadata")

        before_reads = files()
        listing = json.loads(invoke("list", "--json").stdout)
        assert set(listing) == {"right", "left"}
        for side in listing.values():
            assert set(side) == side_fields
            assert side["bindings"] == saved["right"]["bindings"]
        diagnostic = json.loads(invoke("status", "--json", expected=3).stdout)
        assert set(diagnostic) == {"running", "accessibilityTrusted", "intercepting", "version", "hammerspoonRcmd", "config"}
        assert diagnostic["running"] is False and diagnostic["intercepting"] is False
        assert diagnostic["version"] is None and diagnostic["hammerspoonRcmd"] is False
        assert diagnostic["config"] == str(config)
        assert invoke("path").stdout.strip() == str(config)
        assert files() == before_reads
        dynamic.append("List/status/path return only their declared fields; read operations create no files or keyboard log/status artifact")

        marker = "private-test-input-never-retained"
        result = run([gui, "--simulate", f"right:q,invalid:{marker}"], env=env)
        assert result.stdout.strip() == "right q: open PrivacyFixture"
        assert marker not in result.stdout + result.stderr
        assert files() == before_reads
        dynamic.append("The real app --simulate entry prints only the requested dry-run action and leaves disposable storage byte-identical")

        invoke("unset", "q")
        assert json.loads(config.read_text())["right"]["bindings"] == {}
        assert set(files()) == set(original) | {"support/config.json"}
        current = files()
        for path, digest in original.items():
            assert current[path] == digest, f"fixture outside config changed: {path}"
        for path in support.rglob("*"):
            if path.is_file():
                assert marker.encode() not in path.read_bytes()
        dynamic.append("Set/unset and simulation preserve MacKit shortcut and rcmd sentinel bytes; isolated execution does not publish bindings or alter the interception switch")

    # This is explicitly a source check, not a claim about observed traffic or
    # a substitute for the real process/persistence checks above.
    network_or_clipboard = re.compile(
        r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|"
        r"CFHTTPMessage|CFReadStreamCreateForHTTPRequest|NSPasteboard|UIPasteboard|"
        r"SentrySDK|TelemetryClient|Analytics)\b|"
        r"\b(?:socket|connect|sendto|recvfrom|curl|wget)\s*\(")
    sources = sorted((ROOT / "Sources").rglob("*.swift"))
    findings = []
    for source in sources:
        for line_number, line in enumerate(source.read_text().splitlines(), 1):
            if network_or_clipboard.search(line):
                findings.append(f"{source.relative_to(ROOT)}:{line_number}")
    assert not findings, "Privacy-sensitive API needs review: " + ", ".join(findings)

    event_sources = [ROOT / "Sources/App/EventTap.swift", ROOT / "Sources/Shared/KeyEngine.swift"]
    raw_text_or_logging = re.compile(
        r"\b(?:keyboardGetUnicodeString|CGEventKeyboardGetUnicodeString|"
        r"NSLog|os_log|Logger|FileHandle|JSONEncoder)\b|\b(?:print|fputs)\s*\(")
    for source in event_sources:
        assert not raw_text_or_logging.search(source.read_text()), f"Event handling logging/text capture needs review: {source.name}"
    config_source = (ROOT / "Sources/Shared/Config.swift").read_text()
    runtime_status = re.search(r"struct RuntimeStatus: Codable\s*\{([^}]+)\}", config_source)
    assert runtime_status
    assert set(re.findall(r"\bvar\s+(\w+)\s*:", runtime_status.group(1))) == {
        "pid", "accessibilityTrusted", "tapEnabled", "version", "updated"
    }
    detail(
        "privacy",
        "PASS: isolated CLI persistence, app simulation, MacKit sentinels, and scoped privacy source checks",
        dynamic_checks=dynamic,
        static_checks=[
            f"{len(sources)} Swift source files checked for listed network/analytics/clipboard APIs",
            "EventTap and KeyEngine contain no listed raw keyboard text extraction or logging APIs",
            "RuntimeStatus source schema contains only PID, permission/interception flags, version and timestamp",
        ],
        boundary="Dynamic coverage is CLI reads/writes and --simulate with disposable state; "
        "file assertions cover that state tree. Network/clipboard and event logging claims are scoped source checks, "
        "not a runtime traffic trace or live EventTap inspection. No normal GUI, permission prompt, "
        "synthetic input, clipboard access, or Hammerspoon reload was performed.",
    )


if __name__ == "__main__":
    main()
