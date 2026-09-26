#!/usr/bin/env python3
"""Notarize the installed, verified build and package a signed, notarized DMG.

Order: check the installed app is this build → notarize + staple the app → build
a DMG around the stapled app → sign, notarize + staple the DMG → verify both with
Gatekeeper → write build/release.json. Never rebuilds; run build.sh and
scripts/install.sh first. Credentials come from the existing App Store Connect
team key (same source as other apps); nothing secret is printed.
"""
import hashlib, json, os, pathlib, plistlib, subprocess, sys, tempfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = pathlib.Path(os.environ.get("INITIALS_BUILD_DIR", ROOT / "build")).resolve()
APP = BUILD / "Initials.app"
INSTALLED = pathlib.Path("/Applications/Initials.app")


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], check=True, capture_output=capture, text=True)


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def auth():
    """notarytool credentials: NOTARY_KEYCHAIN_PROFILE, or ASC_KEY_ID + ASC_ISSUER_ID
    (key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8), or the maintainer's helper."""
    import os
    if os.environ.get("NOTARY_KEYCHAIN_PROFILE"):
        return ["--keychain-profile", os.environ["NOTARY_KEYCHAIN_PROFILE"]]
    kid, issuer = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID")
    if not (kid and issuer):
        helper = pathlib.Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"
        if not (helper / "asc.py").exists():
            raise SystemExit("Set NOTARY_KEYCHAIN_PROFILE, or ASC_KEY_ID and ASC_ISSUER_ID.")
        sys.path.insert(0, str(helper))
        import asc
        kid, issuer = asc._personal_env("ASC_KEY_ID"), asc._personal_env("ASC_ISSUER_ID")
    key = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{kid}.p8"
    return ["--key", str(key), "--key-id", kid, "--issuer", issuer]


def notarize(payload):
    out = run("xcrun", "notarytool", "submit", payload, *auth(), "--wait", "--output-format", "json", capture=True).stdout
    result = json.loads(out)
    print(f"notarization {result.get('id')}: {result.get('status')}")
    if result.get("status") != "Accepted":
        log = run("xcrun", "notarytool", "log", result["id"], *auth(), capture=True).stdout
        raise SystemExit("Notarization failed:\n" + log)
    return result["id"]


def main():
    exe = "Contents/MacOS/Initials"
    if not (INSTALLED / exe).exists() or sha(INSTALLED / exe) != sha(APP / exe):
        raise SystemExit("Installed Initials differs from build/Initials.app; run scripts/install.sh and verify first.")
    info = run("codesign", "-dv", "--verbose=4", APP, capture=True).stderr
    if "Authority=Developer ID Application:" not in info or "runtime" not in info:
        raise SystemExit("Developer ID signature with hardened runtime required.")
    authority = next(l.removeprefix("Authority=") for l in info.splitlines() if l.startswith("Authority=Developer ID Application:"))
    bundle_info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    version = bundle_info["CFBundleShortVersionString"]
    dmg = BUILD / f"Initials-{version}-arm64.dmg"
    record = {"version": version, "build": str(bundle_info["CFBundleVersion"]), "executable_sha256": sha(APP / exe),
              "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}

    with tempfile.TemporaryDirectory(prefix="initials-release-") as temp:
        temp = pathlib.Path(temp)
        payload = temp / "Initials.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, payload)
        record["app_notarization_id"] = notarize(payload)
        run("xcrun", "stapler", "staple", APP)
        run("xcrun", "stapler", "validate", APP)
        run("spctl", "--assess", "--type", "execute", "--verbose=2", APP)

        stage = temp / "stage"
        stage.mkdir()
        run("ditto", APP, stage / "Initials.app")
        (stage / "Applications").symlink_to("/Applications")
        if dmg.exists():
            dmg.unlink()
        run("hdiutil", "create", "-quiet", "-volname", f"Initials {version}", "-srcfolder", stage, "-format", "UDZO", dmg)
        run("codesign", "--force", "--sign", authority, "--timestamp", dmg)
        record["dmg_notarization_id"] = notarize(dmg)
        run("xcrun", "stapler", "staple", dmg)
        run("xcrun", "stapler", "validate", dmg)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg)

        mount = temp / "mount"
        mount.mkdir()
        run("hdiutil", "attach", "-quiet", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            run("codesign", "--verify", "--deep", "--strict", mount / "Initials.app")
            run("xcrun", "stapler", "validate", mount / "Initials.app")
            if sha(mount / "Initials.app" / exe) != record["executable_sha256"]:
                raise SystemExit("DMG contains a different executable.")
        finally:
            run("hdiutil", "detach", "-quiet", mount)

    record.update(filename=dmg.name, sha256=sha(dmg), size_bytes=dmg.stat().st_size,
                  artifact_path=str(dmg.relative_to(ROOT)))
    (BUILD / "release.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
