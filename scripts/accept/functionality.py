#!/usr/bin/env python3
"""Exercise the shipped CLI and the app's dry-run dispatch with isolated data."""
import json
import plistlib

from _common import detail, ensure_build, isolated, run


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
            "path": str(right_app)}, "set persists resolved app name, identifier and path")
        check(pinned["left"]["bindings"] == pinned["right"]["bindings"], "shared left table reads right bindings")
        unchanged = config_path.read_bytes()
        blocked = command("set", "y", left_app, "--side", "left", expected=2)
        check("share off" in blocked.stderr and config_path.read_bytes() == unchanged,
              "left binding edit while shared is rejected without mutation")
        check(json.loads(command("list", "--side", "right", "--json").stdout).keys() == {"right"},
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
        check(all(not s["enabled"] for s in state().values()), "disable all persists for both sides")
        command("tap", "on", "--side", "right")
        revived = state()
        check(revived["right"]["enabled"] and revived["right"]["doubleTap"] and not revived["right"]["hold"],
              "setting trigger on a disabled side enables only requested trigger")
        command("enable", "all")
        check(all(s["enabled"] for s in state().values()), "enable all persists for both sides")

        command("share", "on")
        check(state()["left"]["bindings"] == state()["right"]["bindings"], "share on restores effective shared table")
        check("y" in json.loads(config_path.read_text())["left"]["bindings"], "sharing preserves independent left bindings on disk")
        command("share", "off")
        check(set(state()["left"]["bindings"]) == {"y"}, "share off restores previous independent left bindings")
        check("Initials Acceptance Right" in command("list").stdout, "human-readable list contains pinned fixture")
        command("unset", "X")
        check(not state()["right"]["bindings"] and "y" in state()["left"]["bindings"], "unset right preserves left")
        command("unset", "y", "--side", "left")
        check(all(not s["bindings"] for s in state().values()), "unset left persists empty tables")
        disk = json.loads(config_path.read_text())
        check(all(not disk[side]["bindings"] for side in ("right", "left")), "final disk state matches fresh CLI reads")

    detail("functionality", f"PASS: {len(checks)} CLI and dry-run assertions using isolated fixture apps.",
           assertions=checks, method="real_product", scope="CLI config and safe app dispatch",
           limitations="No synthetic keys, app activation, hiding, or global event interception; physical hotkeys require user acceptance.")


if __name__ == "__main__":
    main()
