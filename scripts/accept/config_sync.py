"""Portable config and two-device sync through the real bundled CLI."""
import json
from _common import run


def exercise(cli, root, env, check):
    config = root / "support/config.json"
    original = config.read_bytes()
    exported = root / "Initials-config.json"

    def command(*args, target=env, expected=0):
        return json.loads(run([cli, *args, "--json"], env=target, expected=expected).stdout)

    command("export", exported, "--dry-run")
    check(not exported.exists() and config.read_bytes() == original, "export dry-run writes neither file nor config")
    command("export", exported)
    payload = json.loads(exported.read_bytes())
    check(payload == json.loads(original), "export contains both full tables and every stored option")
    payload["right"]["bindings"] = {
        "m": {"name": "Music", "bundleID": "com.apple.Music", "path": "/Users/old/Applications/Music.app"},
        "z": {"name": "Missing fixture", "bundleID": "test.initials.never-installed", "path": "/old/Missing.app"},
    }
    payload["left"]["useRightBindings"] = True
    payload["left"]["bindings"] = {"k": payload["right"]["bindings"]["z"]}
    payload["doubleTapSeconds"] = .45
    payload["pickerTimeoutSeconds"] = 8
    exported.write_text(json.dumps(payload))
    preview = command("import", exported, "--dry-run")
    check(preview["dryRun"] and config.read_bytes() == original
          and not (config.parent / "config-before-import.json").exists(), "JSON import dry-run keeps current file and creates no backup")
    command("import", exported, "--side", "left", expected=2)
    restored = command("import", exported)
    disk = json.loads(config.read_bytes())
    check(disk["right"]["bindings"]["m"]["path"] != "/Users/old/Applications/Music.app"
          and disk["left"]["bindings"] == payload["left"]["bindings"]
          and disk["pickerTimeoutSeconds"] == 8 and disk["doubleTapSeconds"] == .45,
          "JSON restore relocates installed apps, keeps hidden left table and restores timing options")
    check(len(restored["missing"]) == 2 and disk["right"]["bindings"]["z"] == payload["right"]["bindings"]["z"],
          "JSON restore preserves missing apps on both tables")
    check((config.parent / "config-before-import.json").read_bytes() == original, "JSON import saves exact prior configuration")
    before = config.read_bytes()
    again = command("import", "--from", exported)
    check(not again["changed"] and config.read_bytes() == before, "--from JSON is supported and repeated imports are idempotent")
    command("import", exported, "--from", exported, expected=2)
    unrelated = root / "unrelated.json"
    unrelated.write_text("{}")
    command("import", unrelated, expected=2)
    check(config.read_bytes() == before, "unrelated JSON and conflicting source arguments never erase config")
    command("export", config, expected=2)
    check(config.read_bytes() == before, "export refuses to overwrite active config")

    cloud = root / "fake-icloud/Initials"
    cloud.mkdir(parents=True)
    a = {**env, "INITIALS_ICLOUD_DIR": str(cloud)}
    b = {**a, "INITIALS_SUPPORT_DIR": str(root / "mini-support")}
    cloud_file = cloud / "config.json"
    check(not command("sync", "status", target=b)["enabled"], "new installation lets the user choose iCloud sync")
    command("sync", "now", target=b)
    check(not cloud_file.exists(), "default-off does not touch iCloud")
    command("sync", "on", target=a)
    command("sync", "on", target=b)
    command("sync", "now", target=b)
    check(not cloud_file.exists() and not (root / "mini-support/config.json").exists(), "new empty Mac never uploads defaults while waiting for cloud")
    command("sync", "now", target=a)
    cloud_original = cloud_file.read_bytes()
    command("sync", "now", target=b)
    check(json.loads((root / "mini-support/config.json").read_bytes()) == disk
          and cloud_file.read_bytes() == cloud_original, "second Mac pulls full settings without rewriting cloud")
    command("set", "f", "Finder", target=b)
    command("sync", "now", target=b)
    command("set", "n", "Notes", target=a)
    command("sync", "now", target=a)
    command("sync", "now", target=b)
    letters = json.loads((root / "mini-support/config.json").read_bytes())["right"]["bindings"]
    check(set(letters) == {"m", "z", "f", "n"}, "independent offline additions from two Macs merge without losing letters")
    command("unset", "n", target=a)
    command("disable", "left", target=b)
    command("sync", "now", target=b)
    command("sync", "now", target=a)
    command("sync", "now", target=b)
    merged = json.loads((root / "mini-support/config.json").read_bytes())
    check("n" not in merged["right"]["bindings"] and not merged["left"]["enabled"], "offline deletion and option edit both survive reconciliation")
    frozen = cloud_file.read_bytes()
    command("sync", "off", "--dry-run", target=a)
    check(command("sync", "status", target=a)["enabled"], "sync off dry-run leaves preference unchanged")
    command("sync", "off", target=a)
    command("set", "p", "Preview", target=a)
    command("sync", "now", target=a)
    check(cloud_file.read_bytes() == frozen and config.exists(), "disabled sync retains both files and keeps changes local")
    command("sync", "on", target=a)
    command("sync", "now", target=a)
    check("p" in json.loads(cloud_file.read_bytes())["right"]["bindings"], "re-enabled sync publishes pending local edit")
    valid_cloud = cloud_file.read_bytes()
    valid_local = config.read_bytes()
    cloud_file.write_text("{}")
    command("sync", "now", target=a, expected=2)
    check(config.read_bytes() == valid_local and cloud_file.read_text() == "{}", "malformed cloud copy cannot replace local settings or be silently overwritten")
    cloud_file.write_bytes(valid_cloud)
    command("sync", "now", target=a)
    check(config.read_bytes() == valid_local, "sync resumes after cloud file recovery")
    update_feed = root / "update-feed.json"
    update_feed.write_text(json.dumps({"bundle_id": "cyou.tianli.initials", "version": "9.0.0", "build": "99",
                                      "channel": "test", "filename": "Fixture.zip", "sha256": "0" * 64}))
    update_env = {**env, "INITIALS_UPDATE_FEED": str(update_feed)}
    result = command("updates", target=update_env)
    check(result["updateAvailable"] and config.read_bytes() == valid_local, "real CLI checks newer release without modifying settings")
    update_feed.write_text("{}")
    result = command("updates", target=update_env, expected=2)
    check(not result["ok"] and config.read_bytes() == valid_local, "invalid update feed is a failure, never reported as latest")
    # All test state is disposable; restore the original fixture for the rest of acceptance.
    config.write_bytes(original)
