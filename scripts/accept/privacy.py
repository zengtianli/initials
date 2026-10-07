#!/usr/bin/env python3
"""Check isolated CLI persistence and safe simulation; audit privacy-sensitive APIs."""
import ctypes
import hashlib
import json
import plistlib
import re
import subprocess
import time

from _common import ROOT, detail, ensure_build, isolated, run


class TapInfo(ctypes.Structure):  # CGEventTapInformation
    _fields_ = [("eventTapID", ctypes.c_uint32), ("tapPoint", ctypes.c_uint32), ("options", ctypes.c_uint32),
                ("eventsOfInterest", ctypes.c_uint64), ("tappingProcess", ctypes.c_int32),
                ("processBeingTapped", ctypes.c_int32), ("enabled", ctypes.c_bool),
                ("minUsecLatency", ctypes.c_float), ("avgUsecLatency", ctypes.c_float), ("maxUsecLatency", ctypes.c_float)]


def tap_pids():
    """PIDs that own an event tap right now (CGGetEventTapList: read-only, needs no permission)."""
    cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    count = ctypes.c_uint32(0)
    cg.CGGetEventTapList(0, None, ctypes.byref(count))
    taps = (TapInfo * max(count.value, 1))()
    cg.CGGetEventTapList(count.value, taps, ctypes.byref(count))
    return {taps[i].tappingProcess for i in range(count.value)}


def quiet_measure(cli, gui, root, env, dynamic):
    """The measurement lane's entry (--background-measure -lane_quiet YES) on the real built app: it must refuse
    without the lane flag and, with it, own no event tap, open no internet socket and write no support folder."""
    refused = run([gui, "--background-measure"], env=env, expected=2)
    assert "nothing was started" in refused.stderr
    home = root / "home"
    home.mkdir()
    redirected = {k: v for k, v in env.items() if k != "INITIALS_SUPPORT_DIR"} | {"CFFIXED_USER_HOME": str(home)}
    default_support = home / "Library/Application Support/cyou.tianli.initials"
    # Read-only control: without INITIALS_SUPPORT_DIR the default support folder resolves inside this home,
    # so its staying absent below is a statement about the folder the installed app really uses.
    assert run([cli, "path"], env=redirected).stdout.strip() == str(default_support / "config.json")
    assert not default_support.exists()
    process = subprocess.Popen([str(gui), "--background-measure", "-lane_quiet", "YES"], env=redirected,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(2.5)
        assert process.poll() is None, "measurement entry exited early: " + process.stderr.read().decode()
        taps = tap_pids()
        assert process.pid not in taps, "measurement entry owns an event tap"
        resident = subprocess.run(["pgrep", "-f", "^/Applications/Initials.app/Contents/MacOS/Initials"],
                                  capture_output=True, text=True).stdout.split()
        control = ("the detector lists the resident Initials tap" if any(int(p) in taps for p in resident)
                   else "no intercepting resident Initials to show the detector a tap")
        sockets = subprocess.run(["lsof", "-nP", "-a", "-p", str(process.pid), "-i"], capture_output=True, text=True).stdout
        assert not sockets.strip(), "measurement entry holds an internet socket:\n" + sockets
    finally:
        process.terminate()
        process.wait(timeout=10)
    assert not default_support.exists(), "measurement entry created the default support folder"
    created = sorted(str(p.relative_to(home)) for p in home.rglob("*") if p.is_file())
    assert not any("initials" in name.lower() for name in created), f"measurement entry wrote product files: {created}"
    source = (ROOT / "Sources/App/QuietMeasure.swift").read_text()
    reached = re.findall(r"\b(?:AppDelegate|EventTap|AppLifecycleUI|CloudSync\w*|PauseControl|RuntimeStatus|"
                         r"NSStatusBar|NSStatusItem|SMAppService)\b|ConfigStore\.save", source)
    assert not reached, f"measurement entry reaches resident-only parts: {sorted(set(reached))}"
    dynamic.append("The real app's measurement entry refuses without the lane flag; with it, after 2.5 s it owns no event tap "
                   f"({control}), holds no internet socket, and the default support folder of its redirected home stays absent "
                   f"(files created under that home: {created or 'none'})")


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
        assert set(listing) == {"ok", "config", "doubleTapSeconds", "pickerTimeoutSeconds", "right", "left"}
        derived = {"effectiveHold", "effectiveDoubleTap", "editable", "conflicts"}
        for side in ("right", "left"):
            assert set(listing[side]) == side_fields | derived
            shown = {k: {f: b[f] for f in ("name", "bundleID", "path")} for k, b in listing[side]["bindings"].items()}
            assert shown == saved["right"]["bindings"]
            assert all(set(b) == {"name", "bundleID", "path", "found", "resolvedPath"} for b in listing[side]["bindings"].values())
        diagnostic = json.loads(invoke("status", "--json", expected=3).stdout)
        assert set(diagnostic) == {"ok", "running", "pid", "version", "accessibilityTrusted", "tapEnabled", "paused",
                                   "intercepting", "active", "updated", "hammerspoonRcmd", "config", "configError", "error"}
        assert diagnostic["running"] is False and diagnostic["intercepting"] is False and diagnostic["ok"] is False
        assert diagnostic["version"] is None and diagnostic["hammerspoonRcmd"] is False and diagnostic["pid"] is None
        assert diagnostic["config"] == str(config)
        assert invoke("path").stdout.strip() == str(config)
        preview = json.loads(invoke("preview", "q", "--json").stdout)
        assert set(preview) == {"ok", "side", "frontmost", "trigger", "letters"} and preview["letters"][0]["letter"] == "q"
        assert set(json.loads(invoke("login", "--json").stdout)) == {"ok", "openAtLogin", "status"}
        assert files() == before_reads
        dynamic.append("List/status/path/preview/login return only their declared fields; read operations create no files or keyboard log/status artifact")

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

        quiet_measure(cli, gui, root, env, dynamic)

    # This is explicitly a source check, not a claim about observed traffic or
    # a substitute for the real process/persistence checks above.
    network_or_clipboard = re.compile(
        r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|"
        r"CFHTTPMessage|CFReadStreamCreateForHTTPRequest|NSPasteboard|UIPasteboard|"
        r"SentrySDK|TelemetryClient|Analytics)\b|"
        r"\b(?:socket|connect|sendto|recvfrom|curl|wget)\s*\(")
    sources = sorted((ROOT / "Sources").rglob("*.swift"))
    # Only the reviewed, immutable shared implementation may check releases or download an update.
    # AppLifecycleCLI.swift is the command form of the same window (`initials update check|install`): it calls the
    # checker and the installer in the other files and holds no network or clipboard call of its own.
    lifecycle = ROOT / "Sources/Shared/Lifecycle"
    approved = {
        "AppLifecycle.swift": "3033bc6f87a69a2402ff1cda2c8196a4abd677222582c75d21302a65626c2d89",
        "AppConfiguration.swift": "ba4d6aa1f52966159e5b74b1ca2878734c61cad80355ace25e19c0f44626947f",
        "AppLifecycleUI.swift": "fb946d731009b3a797427d706473cf8956c60d0a31a6ada287267f3acbdd7c34",
        "AppLifecycleCLI.swift": "f33393d954dac50331f4fd650066c6ecea573970d53b50b43e8a86cab708241c",
    }
    for name, digest in approved.items():
        assert hashlib.sha256((lifecycle / name).read_bytes()).hexdigest() == digest, f"Unreviewed shared update source: {name}"
    # The shared lane contract is a byte copy of the reviewed original; it logs readiness and nothing else.
    lane_signal = ROOT / "Sources/App/LaneSignal.swift"
    assert hashlib.sha256(lane_signal.read_bytes()).hexdigest() == \
        "e7e68ac41417ddd06e7049a7bd4e01a92d52305bc999cd6ddd323178c64a2ce8", "Unreviewed shared lane source: LaneSignal.swift"
    findings = []
    for source in sources:
        if source.parent == lifecycle and source.name in approved:
            continue
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
    runtime_status = re.search(r"struct RuntimeStatus: Codable[^{]*\{([^}]+)\}", config_source)
    assert runtime_status
    assert set(re.findall(r"\bvar\s+(\w+)\s*:", runtime_status.group(1))) == {
        "pid", "accessibilityTrusted", "tapEnabled", "paused", "version", "updated"
    }
    detail(
        "privacy",
        "PASS: isolated CLI persistence, app simulation, MacKit sentinels, and scoped privacy source checks",
        dynamic_checks=dynamic,
        static_checks=[
            f"{len(sources) - len(approved)} product Swift sources checked for listed network/analytics/clipboard APIs; {len(approved)} shared update sources match approved SHA256",
            "EventTap and KeyEngine contain no listed raw keyboard text extraction or logging APIs",
            "RuntimeStatus source schema contains only PID, permission/interception/pause flags, version and timestamp",
        ],
        boundary="Dynamic coverage is CLI reads/writes, --simulate and the measurement entry with disposable state; "
        "file assertions cover that state tree. Network/clipboard and event logging claims are scoped source checks "
        "plus one socket listing and one event-tap listing of the measurement entry, not a traffic trace. "
        "The resident app's own EventTap is not inspected. No normal GUI, permission prompt, "
        "synthetic input, clipboard access, or Hammerspoon reload was performed.",
    )


if __name__ == "__main__":
    main()
