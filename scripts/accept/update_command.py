"""`initials update check|install` through the real bundled CLI.

Everything happens on app copies inside the disposable tree: the release record is a test channel under
APP_LIFECYCLE_CLOUD_DIR, the only copy that may be replaced sits inside APP_LIFECYCLE_SUPPORT_DIR, and the
replaced copy goes to that folder's own trash. Nothing here goes online, reads iCloud Drive, or touches
/Applications, the owner's Trash or a running Initials.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
from _common import run


def exercise(cli, root, env, check):
    built = Path(cli).parents[3]               # build/accept/Initials.app: outside the lifecycle test folder
    lifecycle, cloud = root / "lifecycle", root / "cloud"
    inside = lifecycle / "apps/Initials.app"   # the only copy an isolated run may replace
    inside.parent.mkdir(parents=True)
    run(["ditto", built, inside])
    inner = inside / "Contents/Resources/bin/initials"
    feed = cloud / "TianliApps/Updates/cyou.tianli.initials/test"
    feed.mkdir(parents=True)
    target = {**env, "APP_LIFECYCLE_SUPPORT_DIR": str(lifecycle), "APP_LIFECYCLE_CLOUD_DIR": str(cloud)}
    info = plistlib.loads((built / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    newer = str(int(build) + 1)
    here, there = {"version": version, "build": build}, {"version": version, "build": newer}
    owner_trash = Path.home() / ".Trash"
    owner_backups = Path.home() / "Library/Application Support/TianliApps/UpgradeBackups/cyou.tianli.initials"

    def command(*args, tool=inner, using=target, expected=0):
        return json.loads(run([tool, *args, "--json"], env=using, expected=expected).stdout)

    def fingerprint(app):
        return [hashlib.sha256((app / part).read_bytes()).hexdigest()
                for part in ("Contents/Info.plist", "Contents/MacOS/Initials", "Contents/Resources/bin/initials")]

    def owner_state():
        retired = sorted(p.name for p in owner_trash.glob("app-upgrade-*")) if owner_trash.is_dir() else []
        return retired, owner_backups.exists()

    def publish(number, sha256=None):
        """A release of the current version with build `number`, packaged from the built app."""
        stage = root / "release-stage"
        shutil.rmtree(stage, ignore_errors=True)
        app = stage / "Initials.app"
        run(["ditto", built, app])
        plist = app / "Contents/Info.plist"
        plist.write_bytes(plistlib.dumps({**plistlib.loads(plist.read_bytes()), "CFBundleVersion": number}))
        run(["codesign", "--force", "--sign", "-", "--identifier", "cyou.tianli.initials.cli", app / "Contents/Resources/bin/initials"])
        run(["codesign", "--force", "--sign", "-", "--identifier", "cyou.tianli.initials", app])
        archive = feed / "Initials.zip"
        archive.unlink(missing_ok=True)
        run(["ditto", "-c", "-k", "--keepParent", app, archive])
        (feed / "release.json").write_text(json.dumps({
            "bundle_id": "cyou.tianli.initials", "channel": "test", "version": version, "build": number,
            "filename": archive.name, "sha256": sha256 or hashlib.sha256(archive.read_bytes()).hexdigest(),
            "size_bytes": archive.stat().st_size}))

    owner_before = owner_state()
    original, outside = fingerprint(inside), fingerprint(built)

    # Usage is judged before anything is read.
    for args in (["update"], ["update", "bogus"], ["update", "check", "extra"], ["update", "install", "--no-such"]):
        out = command(*args, expected=2)
        check(out["ok"] is False and out["error"]["code"] == "usage", f"`{' '.join(args)}` is a usage error (exit 2, error.code usage)")

    # No release record: an isolated run says so; it never falls back to the website or to iCloud Drive.
    out = command("update", "check", expected=1)
    check(out["error"]["code"] == "check_incomplete" and out["source"] == {"kind": "private_cloud", "channel": "test"}
          and out["command"] == "update check", "update check without a test feed is exit 1 check_incomplete, read from the test channel")
    out = command("update", "check", using=env, expected=1)
    check(out["error"]["code"] == "check_incomplete" and out["source"]["kind"] == "private_cloud",
          "an isolated run without the lifecycle test variables still reads no website and no iCloud Drive")
    check(command("update", "install", "--yes", expected=1)["error"]["code"] == "check_incomplete",
          "update install --yes without a release record is exit 1 and replaces nothing")

    # A release at the installed build: nothing to do is success.
    publish(build)
    out = command("update", "check")
    check(out["state"] == "up_to_date" and out["update_available"] is False and out["current"] == here
          and out["upgrade"]["command"] is None, "update check reports up_to_date and offers no command")
    out = command("update", "install", "--yes")
    check(out["installed"] is False and out["state"] == "up_to_date" and out["app_running"] is False
          and {"current", "latest", "source"} <= set(out), "update install --yes with no newer release is exit 0, installed false")
    check(fingerprint(inside) == original, "with no newer release the app copy is untouched")

    # One build ahead: check names the command, the dry run and the missing --yes change nothing.
    publish(newer)
    out = command("update", "check")
    check(out["state"] == "update_available" and out["update_available"] and out["latest"]["build"] == newer
          and out["upgrade"]["in_app"] is True and out["upgrade"]["command"] == "initials update install --yes",
          "update check reports the newer release and names `initials update install --yes`")
    out = command("update", "install", "--dry-run")
    check(out["dry_run"] is True and out["installed"] is False and out["would_install"] == {"from": here, "to": there}
          and out["installation"] == "bundle" and out["will_quit_app"] is False and out["will_relaunch"] is False,
          "update install --dry-run says what it would install and that no app would be quit")
    check(command("update", "install", "--yes", "--dry-run")["dry_run"] is True, "--dry-run wins over --yes")
    out = command("update", "install", expected=2)
    check(out["error"]["code"] == "confirmation_required" and out["command"] == "update install",
          "update install without --yes is exit 2 confirmation_required")
    plain = run([inner, "update", "install"], env=target, expected=2)
    check(plain.stdout == "" and "--yes" in plain.stderr, "without --json the refusal goes to stderr")
    check(fingerprint(inside) == original, "the dry runs and the refused install left the app copy untouched")

    # An isolated run replaces only a copy inside its own test folder.
    out = command("update", "install", "--yes", tool=cli, expected=1)
    check(out["error"]["code"] == "isolated_run" and out["command"] == "update install" and fingerprint(built) == outside,
          "an isolated run refuses to replace an app outside its test folder (exit 1 isolated_run)")
    check(command("update", "install", "--dry-run", tool=cli)["dry_run"] is True, "the dry run still answers for that copy")

    # A package that does not match its record is refused before anything is replaced.
    publish(newer, sha256="0" * 64)
    out = command("update", "install", "--yes", expected=1)
    check(out["error"]["code"] == "upgrade_failed" and fingerprint(inside) == original,
          "a package with the wrong SHA256 is exit 1 upgrade_failed and the app copy is untouched")

    # The replacement itself, read back from disk by new processes.
    publish(newer)
    out = command("update", "install", "--yes")
    check(out["installed"] is True and out["state"] == "installed" and out["previous"] == here and out["current"] == there
          and out["backup"] is None and out["old_app_cleanup"] == "trashed" and out["relaunched"] is False
          and out["app_running"] is False, "update install --yes replaces the copy and reports previous, current and the retired old copy")
    on_disk = plistlib.loads((inside / "Contents/Info.plist").read_bytes())["CFBundleVersion"]
    run(["codesign", "--verify", "--deep", "--strict", inside])
    check(on_disk == newer, "on disk the app copy is the new build and its signature verifies")
    retired = list((lifecycle / "trash").glob("*/Initials.app"))
    check(len(retired) == 1 and plistlib.loads((retired[0] / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == build
          and not (lifecycle / "backups/Initials.app").exists(),
          "the replaced copy is in the test folder's own trash and no backup is left behind")
    check(command("update", "check")["state"] == "up_to_date" and command("version")["build"] == newer,
          "update check and version read the new build back")
    out = command("update", "install", "--yes")
    check(out["installed"] is False and out["state"] == "up_to_date", "installing again finds nothing newer (exit 0)")

    check(fingerprint(built) == outside, "the built app the tests run from was never replaced")
    check(owner_state() == owner_before, "the owner's Trash and upgrade-backup folder received nothing")
