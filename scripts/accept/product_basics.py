#!/usr/bin/env python3
"""Chapter basic acceptance: installed product, private settings/cloud/feed, offscreen AppKit."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    spec = json.loads(os.environ["SOP_PRODUCT_BASICS_SPEC"])
    out = Path(os.environ["SOP_OUT_DIR"]).resolve()
    run = out / ("product-basics-" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    app = Path("/Applications/Initials.app")
    receipt = json.loads((ROOT / "perf/build-receipt.json").read_text())
    artifact = receipt["artifact"]
    installed_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    checks = {"settings.installed_identity": installed_info["CFBundleIdentifier"] == artifact["bundle_id"],
              "settings.installed_build": str(installed_info["CFBundleVersion"]) == str(artifact["build"]),
              "settings.installed_executable_sha": sha(app / artifact["executable"]) == artifact["sha256"],
              "shortcuts.current_source_matches_installed": all(sha(ROOT / p) == h for p, h in receipt["source"]["files"].items())}
    cases = []
    env = dict(os.environ, INITIALS_BUILD_DIR=str(run / "logic-build"))
    logic = subprocess.run(["bash", "build.sh", "--test-only"], cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    (run / "key-engine.log").write_text(logic.stdout + logic.stderr)
    checks["shortcuts.key_engine_actions_and_conflicts"] = logic.returncode == 0 and "tests: all passed" in logic.stdout
    complete = subprocess.run([sys.executable, str(ROOT / "scripts/accept/completeness.py"), "--app", str(app), "--out", str(run / "checks")],
                              cwd=ROOT, capture_output=True, text=True, timeout=120)
    (run / "completeness.log").write_text(complete.stdout + complete.stderr)
    old = json.loads((run / "checks/result.json").read_text())
    cases.extend(old["cases"])
    checks["settings.isolated_cli_and_offscreen_suite"] = complete.returncode == 0 and old["passed"] is True
    ui = json.loads((run / "checks/ui/ui-self-test.json").read_text())["checks"]
    for key in ("settings_import_complete", "settings_import_backup", "settings_import_rejects_unrelated_json",
                "settings_remove_saved", "settings_close_without_focus", "settings_right_controls_in_bounds", "settings_shared_controls_in_bounds"):
        checks["settings." + key] = ui.get(key) is True
    for key in ("action_dispatch_open-url", "action_dispatch_run-shortcut", "picker_never_accepts_focus"):
        checks["shortcuts." + key] = ui.get(key) is True
    for key in ("icloud_background_initial_sync", "icloud_remote_notification_applies_without_polling", "icloud_disable_keeps_files", "icloud_disable_preserves_cloud"):
        checks["icloud." + key] = ui.get(key) is True
    mapping = {c["case"]: c["passed"] for c in cases}
    for key in ("local_feed_read", "local_install_dry_run", "fresh_process_reads_choices", "invalid_interval", "skip_and_remind", "busy_install_refused_before_any_download", "production_preferences_unchanged"):
        checks["updates." + key] = mapping.get(key) is True
    checks["updates.settings_check_action"] = ui.get("settings_check_updates_action") is True

    clone = run / "checks/lifecycle/Initials.app"
    identity = plistlib.loads((clone / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    cli = clone / "Contents/Resources/bin/initials"
    env = dict(os.environ, INITIALS_SUPPORT_DIR=str(run / "checks/support"), INITIALS_ICLOUD_DIR=str(run / "cloud"),
               APP_LIFECYCLE_SUPPORT_DIR=str(run / "checks/lifecycle"), APP_LIFECYCLE_CLOUD_DIR=str(run / "checks/cloud"), APP_LIFECYCLE_NO_RELAUNCH="1")

    def call(key, words, predicate, code=0):
        result = subprocess.run([str(cli), *words, "--json"], env=env, capture_output=True, text=True, timeout=20)
        body = json.loads(result.stdout)
        checks[key] = result.returncode == code and bool(predicate(body))
        cases.append({"case": key, "passed": checks[key], "exit": result.returncode, "response": body})
        return body

    try:
        call("shortcuts.disable_trigger", ["hold", "off", "--side", "right"], lambda b: True)
        call("shortcuts.disabled_readback", ["list"], lambda b: b["right"]["hold"] is False)
        call("shortcuts.enable_trigger", ["hold", "on", "--side", "right"], lambda b: True)
        call("shortcuts.enabled_readback", ["list"], lambda b: b["right"]["hold"] is True)
        call("icloud.enable", ["sync", "on"], lambda b: b["enabled"] is True)
        call("icloud.push", ["sync", "now"], lambda b: b["available"] is True)
        cloud = run / "cloud/config.json"
        checks["icloud.created_cloud_configuration"] = cloud.is_file()
        before = sha(run / "checks/support/config.json")
        saved_directory = env.pop("INITIALS_ICLOUD_DIR")
        call("icloud.unavailable_state", ["sync", "now"], lambda b: b["available"] is False and b["enabled"] is True)
        call("icloud.local_usable_without_cloud", ["list"], lambda b: b["right"]["hold"] is True)
        checks["icloud.unavailable_keeps_local"] = sha(run / "checks/support/config.json") == before
        env["INITIALS_ICLOUD_DIR"] = saved_directory
        cloud.write_text("{broken")
        call("icloud.corrupt_cloud_refused", ["sync", "now"], lambda b: True, 2)
        checks["icloud.corrupt_cloud_preserves_local"] = sha(run / "checks/support/config.json") == before
        call("icloud.disable", ["sync", "off"], lambda b: b["enabled"] is False)
        checks["icloud.disable_preserves_both_files"] = cloud.is_file() and (run / "checks/support/config.json").is_file()
        feed = run / "checks/cloud/TianliApps/Updates" / identity / "test/release.json"
        feed.write_text("{broken")
        call("updates.corrupt_feed_readable_error", ["update", "check"], lambda b: b.get("ok") is False, 1)
        checks["settings.no_foreign_preferences"] = mapping.get("production_preferences_unchanged") is True
    finally:
        subprocess.run(["defaults", "delete", identity], capture_output=True)
    # Fixed semantic obligations come from Chapter policy; these aggregate actual product checks above.
    checks.update({
        "settings.interaction": ui.get("settings_remove_saved") is True and ui.get("settings_close_without_focus") is True,
        "settings.persisted_readback": checks["shortcuts.enabled_readback"] and ui.get("settings_import_complete") is True,
        "settings.error_preserves_data": mapping.get("original_config_not_erased") is True and ui.get("settings_import_rejects_unrelated_json") is True,
        "shortcuts.action_path": checks["shortcuts.key_engine_actions_and_conflicts"] and ui.get("action_dispatch_open-url") is True,
        "shortcuts.disable_restore": checks["shortcuts.disabled_readback"] and checks["shortcuts.enabled_readback"],
        "shortcuts.conflict_or_reserved_keys": checks["shortcuts.key_engine_actions_and_conflicts"],
        "icloud.push_pull": checks["icloud.created_cloud_configuration"] and ui.get("icloud_remote_notification_applies_without_polling") is True,
        "icloud.unavailable_local_fallback": checks["icloud.unavailable_state"] and checks["icloud.local_usable_without_cloud"] and checks["icloud.unavailable_keeps_local"],
        "icloud.conflict_or_corrupt_recovery": checks["icloud.corrupt_cloud_refused"] and checks["icloud.corrupt_cloud_preserves_local"],
        "icloud.disable_preserves_data": checks["icloud.disable"] and checks["icloud.disable_preserves_both_files"] and ui.get("icloud_disable_preserves_cloud") is True,
        "updates.check_result": mapping.get("local_feed_read") is True and ui.get("settings_check_updates_action") is True,
        "updates.failure_recovery": checks["updates.corrupt_feed_readable_error"],
        "updates.options_or_store_entry": mapping.get("fresh_process_reads_choices") is True,
        "updates.data_preservation": mapping.get("production_preferences_unchanged") is True and mapping.get("no_installer_downloaded") is True,
    })
    raw = {"schema_version": 1, "app_id": os.environ["SOP_APP_ID"], "spec_digest": spec["digest"], "checks": checks,
           "checked_at": time.time(), "scope": "Installed 1.4.1 binary; disposable identity; real offscreen views, current KeyEngine; cloud folder/feed fixtures. Apple server transfer between two devices is outside this isolated check.",
           "installed": {"version": installed_info["CFBundleShortVersionString"], "build": installed_info["CFBundleVersion"], "sha256": sha(app / artifact["executable"])},
           "cases": cases, "upstream": {"ui": {"path": str((run / "checks/ui/ui-self-test.json").relative_to(ROOT)), "sha256": sha(run / "checks/ui/ui-self-test.json")},
                                      "key_engine_log": {"path": str((run / "key-engine.log").relative_to(ROOT)), "sha256": sha(run / "key-engine.log")}}}
    raw_path = run / "raw.json"
    raw_path.write_text(json.dumps(raw, ensure_ascii=False, indent=2) + "\n")
    features = {key: {"result": "passed" if all(v for k, v in checks.items() if k.startswith(key + ".")) else "failed",
                      "method": "ui_automation" if key == "settings" else "real_product", "evidence": str(raw_path.relative_to(ROOT)),
                      "evidence_sha256": sha(raw_path), "checks": [k for k in checks if k.startswith(key + ".")]}
                for key in ("settings", "shortcuts", "icloud", "updates")}
    passed = all(checks.values())
    detail = {"schema_version": 1, "app_id": os.environ["SOP_APP_ID"], "spec_digest": spec["digest"], "features": features,
              "summary": f"基础功能 {'通过' if passed else '失败'}；{len(checks)} 项实测检查；iCloud 为隔离目录同步链路", "scope": raw["scope"]}
    (out / "product_basics.detail.json").write_text(json.dumps(detail, ensure_ascii=False, indent=2) + "\n")
    print(detail["summary"], flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
