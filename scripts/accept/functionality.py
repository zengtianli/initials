#!/usr/bin/env python3
"""Exercise the shipped CLI and the app's dry-run dispatch with isolated data."""
import hashlib
import json
import os
import plistlib
import subprocess
import time

from _common import detail, ensure_build, isolated, run
from config_sync import exercise as exercise_config_sync


def main():
    cli, gui = ensure_build()
    checks = []
    with isolated() as (root, env):
        config_path = root / "support/config.json"

        def command(*args, expected=0):
            return run([cli, *args], env=env, expected=expected)

        def state():
            # Every read starts a new CLI process and therefore tests persistence.
            return json.loads(command("list", "--json").stdout)

        def check(condition, label):
            if not condition:
                raise AssertionError(label)
            checks.append(label)

        def fixture(name, bundle_id):
            app = root / (name + ".app")
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleName": name,
                "CFBundleDisplayName": name,
                "CFBundleIdentifier": bundle_id,
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
            }))
            return app

        right_app = fixture("Initials Acceptance Right", "test.initials.acceptance.right")
        left_app = fixture("Initials Acceptance Left", "test.initials.acceptance.left")
        check(command("path").stdout.strip() == str(config_path), "CLI uses isolated support directory")
        initial = state()
        check(not config_path.exists(), "reading defaults does not create configuration")
        check(initial["right"]["hold"] and not initial["right"]["doubleTap"], "right default is hold")
        check(not initial["left"]["hold"] and initial["left"]["doubleTap"], "left default is double tap")
        check(initial["left"]["useRightBindings"], "left shares right bindings by default")

        check("right X" in command("set", "X", right_app).stdout, "set accepts and normalizes uppercase letter")
        pinned = state()
        check(pinned["right"]["bindings"]["x"] == {
            "name": "Initials Acceptance Right", "bundleID": "test.initials.acceptance.right",
            "path": str(right_app), "found": True, "resolvedPath": str(right_app)},
              "set persists resolved app name, identifier and path; list reports where it is found")
        check(pinned["left"]["bindings"] == pinned["right"]["bindings"], "shared left table reads right bindings")
        unchanged = config_path.read_bytes()
        blocked = command("set", "y", left_app, "--side", "left", expected=2)
        check("share off" in blocked.stderr and config_path.read_bytes() == unchanged,
              "left binding edit while shared is rejected without mutation")
        only_right = json.loads(command("list", "--side", "right", "--json").stdout)
        check("right" in only_right and "left" not in only_right and only_right["ok"] is True,
              "side-filtered list returns only requested side")

        simulation = run([gui, "--simulate", "right:x,left:x"], env=env).stdout.strip().splitlines()
        check(simulation == ["right x: open Initials Acceptance Right", "left x: open Initials Acceptance Right"],
              "dry-run dispatcher uses right binding and shared left binding")
        check(config_path.read_bytes() == unchanged, "dry-run dispatcher leaves configuration unchanged")
        check(not (root / "support/status.json").exists(), "dry-run exits before starting normal app lifecycle")

        command("share", "off")
        check(not state()["left"]["useRightBindings"], "share off persists")
        command("set", "Y", left_app, "--side", "left")
        separate = state()
        check(set(separate["left"]["bindings"]) == {"y"} and set(separate["right"]["bindings"]) == {"x"},
              "independent left binding leaves right table intact")
        simulation = run([gui, "--simulate", "right:x,left:y"], env=env).stdout.strip().splitlines()
        check(simulation == ["right x: open Initials Acceptance Right", "left y: open Initials Acceptance Left"],
              "dry-run dispatcher uses independent side bindings")

        command("hold", "on", "--side", "left")
        check(state()["left"]["hold"], "left hold on persists")
        command("hold", "off", "--side", "left")
        check(not state()["left"]["hold"], "left hold off persists")
        command("tap", "on", "--side", "right")
        check(state()["right"]["doubleTap"], "right tap on persists")
        command("tap", "off", "--side", "right")
        check(not state()["right"]["doubleTap"], "right tap off persists")
        command("disable", "right")
        disabled = state()
        check(not disabled["right"]["enabled"] and disabled["left"]["enabled"], "disable right affects only right")
        command("enable", "right")
        check(state()["right"]["enabled"], "enable right persists")
        command("disable", "all")
        check(all(not s["enabled"] for s in (lambda d: (d["right"], d["left"]))(state())), "disable all persists for both sides")
        command("tap", "on", "--side", "right")
        revived = state()
        check(revived["right"]["enabled"] and revived["right"]["doubleTap"] and not revived["right"]["hold"],
              "setting trigger on a disabled side enables only requested trigger")
        command("enable", "all")
        check(all(s["enabled"] for s in (lambda d: (d["right"], d["left"]))(state())), "enable all persists for both sides")

        command("share", "on")
        check(state()["left"]["bindings"] == state()["right"]["bindings"], "share on restores effective shared table")
        check("y" in json.loads(config_path.read_text())["left"]["bindings"], "sharing preserves independent left bindings on disk")
        command("share", "off")
        check(set(state()["left"]["bindings"]) == {"y"}, "share off restores previous independent left bindings")
        check("Initials Acceptance Right" in command("list").stdout, "human-readable list contains pinned fixture")
        command("unset", "X")
        check(not state()["right"]["bindings"] and "y" in state()["left"]["bindings"], "unset right preserves left")
        command("unset", "y", "--side", "left")
        check(all(not s["bindings"] for s in (lambda d: (d["right"], d["left"]))(state())), "unset left persists empty tables")
        disk = json.loads(config_path.read_text())
        check(all(not disk[side]["bindings"] for side in ("right", "left")), "final disk state matches fresh CLI reads")

        # --- Agent contract: help never acts, unknown options never act, --json everywhere ---
        def digest():
            return hashlib.sha256(config_path.read_bytes()).hexdigest() if config_path.exists() else None

        def as_json(*args, expected=0):
            out = json.loads(command(*args, "--json", expected=expected).stdout)
            check(out["ok"] is (expected == 0), f"{' '.join(map(str, args))} --json reports ok={expected == 0}")
            return out

        command("share", "on")
        command("set", "x", right_app)
        before = digest()
        help_forms = [["--help"], ["-h"], ["help"], ["help", "import"]] + [[name, "--help"] for name in (
            "list", "preview", "status", "login", "path", "version", "set", "unset", "move", "import", "enable",
            "disable", "hold", "tap", "cycle", "hide-front", "share", "pause", "resume", "hammerspoon", "export", "sync")]
        help_forms += [["import", "-h"], ["hold", "on", "--help"], ["unset", "x", "--help"], ["enable", "right", "--help"],
                       ["set", "q", str(right_app), "--help"], ["import", "--bogus", "--help"]]
        for args in help_forms:
            text = command(*args).stdout
            check("initials" in text and digest() == before, f"`{' '.join(args)}` prints help and changes nothing")
        for args in (["import", "--bogus"], ["hold", "on", "--bogus"], ["share", "on", "--side", "left"],
                     ["list", "--from", "x"], ["path", "--dry-run"], ["login", "on"], ["bogus"], ["preview", "1"],
                     ["--bogus"], ["pause", "--dry-run"], ["resume", "--dry-run"], ["hammerspoon", "rcmd", "off", "--dry-run"]):
            command(*args, expected=2)
            check(digest() == before, f"`{' '.join(args)}` is rejected (exit 2) without writing")
        for args, which in ((["--json"], None), (["help", "import", "--json"], "import"), (["list", "--help", "--json"], "list"),
                            (["pause", "-h", "--json"], "pause")):
            out = json.loads(command(*args).stdout)
            check(out["ok"] is True and out["command"] == which and "initials" in out["help"] and digest() == before,
                  f"`{' '.join(args)}` answers help as one JSON object and changes nothing")

        listing = as_json("list")
        right, left = listing["right"], listing["left"]
        check({"config", "doubleTapSeconds", "pickerTimeoutSeconds"} <= set(listing), "list JSON has config path and timings")
        check(all(x["effectiveHold"] == (x["enabled"] and x["hold"]) and x["effectiveDoubleTap"] == (x["enabled"] and x["doubleTap"])
                  for x in (right, left)) and right["editable"] and not left["editable"],
              "list JSON has effective triggers (enabled and trigger) and editability")

        # Shared left refuses every edit of its hidden table, like the greyed-out Settings controls.
        for args in (["unset", "x", "--side", "left"], ["move", "x", "y", "--side", "left"],
                     ["import", "--side", "left", "--from", str(root / "none.lua")]):
            out = as_json(*args, expected=2)
            check("share off" in out["error"] and digest() == before, f"`{' '.join(args)}` refused while left shares letters")

        out = as_json("import", "--from", root / "none.lua", expected=1)
        check("not found" in out["error"] and digest() == before, "import from a missing file is exit 1 (not found)")

        # Dry runs report the change and save nothing.
        out = as_json("set", "q", left_app, "--dry-run")
        check(out["dryRun"] and out["changed"] and "q" in out["state"]["right"]["bindings"] and digest() == before,
              "set --dry-run reports the new table without saving")
        out = as_json("move", "x", "k", "--dry-run")
        check(out["changed"] and set(out["state"]["right"]["bindings"]) == {"k"} and digest() == before, "move --dry-run saves nothing")

        out = as_json("set", "x", right_app)
        check(out["changed"] is False and digest() == before, "repeating a set is idempotent and does not rewrite the file")
        out = as_json("set", "w", left_app)
        check(out["changed"] and out["letter"] == "w" and out["binding"]["found"], "set --json echoes the binding")
        out = as_json("move", "w", "x")
        check(out["replaced"]["name"] == "Initials Acceptance Right" and set(state()["right"]["bindings"]) == {"x"}
              and state()["right"]["bindings"]["x"]["bundleID"] == "test.initials.acceptance.left",
              "move replaces the target letter and clears the old one, persisted")
        out = as_json("unset", "q", expected=1)
        check(out["exitCode"] == 1, "unset of a missing letter is exit 1 with ok false")

        for side in ("right", "left"):
            for verb, field in (("cycle", "cycleUnbound"), ("hide-front", "hideIfFrontmost")):
                as_json(verb, "off", "--side", side)
                check(state()[side][field] is False, f"{verb} off --side {side} persists")
                as_json(verb, "on", "--side", side)
                check(state()[side][field] is True, f"{verb} on --side {side} persists")

        check(state()["left"]["conflicts"] == [], "no shortcut warning while left ⌘ is not held")
        command("hold", "on", "--side", "left")
        command("set", "c", right_app)
        check(state()["left"]["conflicts"] == [{"letter": "c", "shortcut": "copy"}, {"letter": "x", "shortcut": "cut"}],
              "left-hold conflicts use stable, locale-independent ids")
        command("unset", "c")
        command("hold", "off", "--side", "left")

        lua = root / "keymaps.lua"
        lua.write_text('M.right_command = {\n  x = "%s",\n  z = "NoSuchApp12345",\n}\n' % right_app)
        before = digest()
        out = as_json("import", "--from", lua, "--dry-run")
        check(out["dryRun"] and set(out["imported"]) == {"x"} and out["unresolved"] == [{"letter": "z", "app": "NoSuchApp12345"}]
              and out["replaced"] == ["x"] and digest() == before, "import --dry-run previews letters, misses and replacements")
        as_json("import", "--from", lua)
        check(state()["right"]["bindings"]["x"]["bundleID"] == "test.initials.acceptance.right", "import saves resolved letters")

        preview = as_json("preview", "x", "q")
        rows = {row["letter"]: row for row in preview["letters"]}
        now = state()["right"]
        check(rows["x"]["pinned"] and rows["x"]["action"] == "open" and rows["x"]["target"] == "Initials Acceptance Right"
              and rows["x"]["hold"] == now["effectiveHold"] and rows["x"]["panel"] == now["effectiveDoubleTap"],
              "preview reports the pinned letter's action and how it is reached, without doing it")
        check(not rows["q"]["pinned"] and rows["q"]["action"] in {"nothing", "activate", "hide"}, "preview covers unpinned letters")
        check(any(r["letter"] == "x" for r in as_json("preview", "--side", "left")["letters"]), "left preview shows shared letters")

        info = plistlib.loads((cli.parents[2] / "Info.plist").read_bytes())
        version = as_json("version")
        check(version["version"] == info["CFBundleShortVersionString"] and version["build"] == info["CFBundleVersion"],
              "version is read from the host app's Info.plist")
        login = as_json("login")
        check(isinstance(login["openAtLogin"], bool) and login["status"] in
              {"enabled", "notRegistered", "requiresApproval", "notFound"}, "login reports the login-item status read only")
        exercise_config_sync(cli, root, env, check)

        # Runtime control through the real PauseControl in an isolated, never-active app process.
        status_path = root / "support/status.json"
        out = as_json("status", expected=3)
        check(out["running"] is False and out["error"], "status without the app is exit 3, ok false")
        as_json("pause", expected=3)
        control = subprocess.Popen([str(gui), "--control-self-test", "30"], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if status_path.exists():
                    break
                time.sleep(0.05)
            live = as_json("status")
            check(live["running"] and live["pid"] == control.pid and live["paused"] is False, "status sees the running app")
            out = as_json("pause")
            check(out["paused"] and out["changed"], "pause is confirmed by the app")
            live = as_json("status")
            check(live["paused"] is True and live["intercepting"] is False and live["active"] is False,
                  "status reports paused and not intercepting")
            check(as_json("pause")["changed"] is False, "pausing again is idempotent")
            out = as_json("resume")
            check(out["paused"] is False and out["changed"] and as_json("status")["paused"] is False, "resume is confirmed")

            # One copy per support folder: a second copy on this folder exits, one on another folder starts.
            second = subprocess.run([str(gui), "--control-self-test", "5"], env=env, text=True,
                                    capture_output=True, timeout=10)
            check(second.returncode == 1 and "already running" in second.stderr and as_json("status")["pid"] == control.pid,
                  "a second copy on the same support folder exits 1 and leaves the running one alone")
            other_env = {**env, "INITIALS_SUPPORT_DIR": str(root / "other-support")}
            other = subprocess.Popen([str(gui), "--control-self-test", "10"], env=other_env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                for _ in range(100):
                    if (root / "other-support/status.json").exists():
                        break
                    time.sleep(0.05)
                other_status = json.loads(run([cli, "status", "--json"], env=other_env).stdout)
                check(other_status["running"] and other_status["pid"] == other.pid and as_json("status")["pid"] == control.pid,
                      "a copy on another support folder starts while this one runs (self-tests never block the real app)")
            finally:
                other.terminate()
                other.wait(timeout=10)
        finally:
            control.terminate()
            control.wait(timeout=10)
        check(not status_path.exists(), "the app removes only its own status file on quit")
        status_path.write_text(json.dumps({"pid": os.getpid(), "accessibilityTrusted": True, "tapEnabled": True,
                                           "paused": False, "version": "x", "updated": "2026-09-30T00:00:00Z"}))
        check(as_json("status", expected=3)["running"] is False, "a live pid that is not Initials does not count as running")
        status_path.unlink()

    detail("functionality", f"PASS: {len(checks)} CLI and dry-run assertions using isolated fixture apps.",
           assertions=checks, method="real_product",
           scope="CLI config, help/option contract, JSON output, preview, login status read, pause/resume via the "
                 "isolated control self-test, the one-copy-per-support-folder guard, and safe app dispatch",
           limitations="No synthetic keys, app activation, hiding, or global event interception; physical hotkeys require user acceptance.")


if __name__ == "__main__":
    main()
