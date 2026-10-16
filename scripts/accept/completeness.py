#!/usr/bin/env python3
"""Focused real-CLI/offscreen checks, with a disposable bundle ID and support directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    app = out / "lifecycle/Initials.app"
    if app.exists():
        raise SystemExit("Use a fresh output directory")
    subprocess.run(["ditto", str(args.app), str(app)], check=True)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    identity = "cyou.tianli.initials.test." + uuid.uuid4().hex
    info["CFBundleIdentifier"] = identity
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    cli = app / "Contents/Resources/bin/initials"
    executable = app / "Contents/MacOS/Initials"
    env = dict(os.environ, INITIALS_SUPPORT_DIR=str(out / "support"),
               APP_LIFECYCLE_SUPPORT_DIR=str(out / "lifecycle"),
               APP_LIFECYCLE_CLOUD_DIR=str(out / "cloud"), APP_LIFECYCLE_NO_RELAUNCH="1")
    results = []
    control = None

    def production_preferences():
        r = subprocess.run(["defaults", "export", "cyou.tianli.initials", "-"], capture_output=True)
        data = plistlib.dumps(plistlib.loads(r.stdout), sort_keys=True) if r.returncode == 0 else r.stdout
        return (r.returncode, hashlib.sha256(data).hexdigest())

    before_preferences = production_preferences()

    def run(name, words, expected=0, test=None):
        result = subprocess.run([str(cli), *words, "--json"], env=env, capture_output=True, text=True, timeout=20)
        body = json.loads(result.stdout)
        passed = result.returncode == expected and (test(body) if test else True)
        results.append({"case": name, "passed": passed, "exit": result.returncode, "response": body})
        if not passed:
            raise RuntimeError(name + ": " + result.stdout + result.stderr)
        return body

    try:
        run("new_options_default_off", ["update", "options"], test=lambda r: all(not r["options"][k] for k in ("automaticCheck", "automaticDownload", "automaticInstall")))
        run("help_has_no_preference_side_effect", ["update", "options", "--help", "--auto-check", "on"])
        run("help_did_not_save", ["update", "options"], test=lambda r: not r["options"]["automaticCheck"])
        run("options_dry_run", ["update", "options", "--auto-check", "on", "--interval", "12", "--dry-run"], test=lambda r: r["dry_run"])
        run("dry_run_did_not_save", ["update", "options"], test=lambda r: not r["options"]["automaticCheck"])
        run("save_requires_yes", ["update", "options", "--auto-check", "on"], 2, lambda r: r["error"]["code"] == "confirmation_required")
        run("save_options", ["update", "options", "--auto-check", "on", "--interval", "12", "--auto-install", "on", "--yes"])
        run("fresh_process_reads_choices", ["update", "options"], test=lambda r: r["options"]["automaticCheck"] and r["options"]["automaticDownload"] and r["options"]["automaticInstall"] and r["options"]["intervalHours"] == 12)
        run("invalid_interval", ["update", "options", "--interval", "0", "--yes"], 2)
        run("invalid_boolean", ["update", "options", "--auto-check", "maybe", "--yes"], 2)
        run("unknown_option", ["update", "options", "--bogus", "--yes"], 2)
        run("extra_positionals", ["update", "options", "extra"], 2)
        run("turn_off_preserves_other_choices", ["update", "options", "--auto-check", "off", "--yes"], test=lambda r: not r["options"]["automaticCheck"] and r["options"]["automaticInstall"])
        run("skip_and_remind", ["update", "options", "--skip", "1.4.2/15", "--remind", "24", "--yes"], test=lambda r: r["options"]["skippedBuild"] == "1.4.2/15" and r["options"]["remindAfter"] > time.time())
        run("clear_skip_and_reminder", ["update", "options", "--skip", "clear", "--remind", "0", "--yes"])
        feed = out / "cloud/TianliApps/Updates" / identity / "test"
        feed.mkdir(parents=True)
        (feed / "release.json").write_text(json.dumps({"bundle_id": identity, "channel": "test", "version": "1.4.2", "build": "15", "sha256": "0" * 64, "size_bytes": 1, "filename": "never-download.zip", "installation": "bundle"}))
        run("local_feed_read", ["update", "check"], test=lambda r: r["update_available"])
        run("local_install_dry_run", ["update", "install", "--dry-run"], test=lambda r: r["dry_run"])
        run("private_config_roundtrip", ["export", str(out / "valid.json")])
        config = json.loads((out / "valid.json").read_text())
        (out / "invalid.json").write_text(json.dumps(dict(config, pickerTimeoutSeconds=None)))
        run("null_import_rejected", ["import", str(out / "invalid.json")], 2)
        run("original_config_not_erased", ["list"], test=lambda r: r["pickerTimeoutSeconds"] == config["pickerTimeoutSeconds"])
        control = subprocess.Popen([str(executable), "--control-self-test", "30"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        status = out / "support/status.json"
        deadline = time.monotonic() + 5
        while not status.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        state = json.loads(status.read_text())
        state["updateBusy"] = True
        status.write_text(json.dumps(state))
        run("busy_install_refused_before_any_download", ["update", "install", "--yes"], 1, lambda r: r["error"]["code"] == "busy")
        run("pause_private_instance", ["pause"], test=lambda r: r["paused"])
        run("resume_private_instance", ["resume"], test=lambda r: not r["paused"])
        run("quit_private_instance", ["quit"])
        control.wait(timeout=5)
        control = None
        ui = subprocess.run([str(executable), "--ui-self-test", str(out / "ui")], env=env, capture_output=True, text=True, timeout=30)
        (out / "ui.log").write_text(ui.stdout + ui.stderr)
        report = json.loads((out / "ui/ui-self-test.json").read_text())
        results.append({"case": "real_appkit_offscreen", "passed": ui.returncode == 0 and report["passed"], "checks": report["checks"]})
        blocked = subprocess.run([str(args.app / "Contents/Resources/bin/initials"), "update", "options", "--auto-check", "on", "--yes", "--json"], env=env, capture_output=True, text=True, timeout=10)
        results.append({"case": "production_identity_cannot_write_preferences_in_isolated_mode", "passed": blocked.returncode == 1 and json.loads(blocked.stdout)["error"]["code"] == "isolated_preferences"})
        results.append({"case": "production_preferences_unchanged", "passed": production_preferences() == before_preferences})
        results.append({"case": "no_installer_downloaded", "passed": not (feed / "never-download.zip").exists()})
    finally:
        if control is not None:
            control.terminate()
            control.wait(timeout=5)
        subprocess.run(["defaults", "delete", identity], capture_output=True)
        (out / "result.json").write_text(json.dumps({"passed": all(r["passed"] for r in results), "bundle_id": identity, "cases": results}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": all(r["passed"] for r in results), "cases": len(results), "out": str(out)}, ensure_ascii=False))
    return 0 if all(r["passed"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
