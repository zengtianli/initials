#!/usr/bin/env python3
"""Notarize the installed, verified build and package a signed, notarized DMG.

Order: check the installed app is this build → notarize + staple the app → build
a DMG around the stapled app → sign, notarize + staple the DMG → verify both with
Gatekeeper → write build/release.json. Never rebuilds; run build.sh and
scripts/install.sh first. Credentials come from the existing App Store Connect
team key (same source as other apps); nothing secret is printed.
"""
import glob, hashlib, json, os, pathlib, plistlib, subprocess, sys, tempfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = pathlib.Path(os.environ.get("INITIALS_BUILD_DIR", ROOT / "build")).resolve()
APP = BUILD / "Initials.app"
INSTALLED = pathlib.Path("/Applications/Initials.app")
SOURCE_PATTERNS = {"Sources/**", "Resources/**", "Info.plist", "build.sh"}


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], check=True, capture_output=capture, text=True)


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def artifact_snapshot(bundle):
    """Same executable/version/icon identity recorded by Chapter build-receipt."""
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    executable_name = info["CFBundleExecutable"]
    icon_name = info.get("CFBundleIconFile")
    if pathlib.Path(executable_name).name != executable_name or not icon_name or pathlib.Path(icon_name).name != icon_name:
        raise ValueError("Bundle executable/icon must be resource filenames.")
    if not pathlib.Path(icon_name).suffix:
        icon_name += ".icns"
    executable = "Contents/MacOS/" + executable_name
    icon = "Contents/Resources/" + icon_name
    return {"bundle_id": info["CFBundleIdentifier"], "version": str(info["CFBundleShortVersionString"]),
            "build": str(info["CFBundleVersion"]), "executable": executable, "sha256": sha(bundle / executable),
            "icon": {"path": icon, "sha256": sha(bundle / icon)}}


def verify_provenance():
    """Read-only preflight, deliberately before credentials or notarization upload."""
    receipt_path = ROOT / "perf/build-receipt.json"
    try:
        receipt = json.loads(receipt_path.read_text())
        if receipt.get("schema_version") != 1 or not receipt.get("built_at") or not receipt.get("build_command_sha256"):
            raise ValueError("Build receipt is incomplete; generate it around a fresh build.")
        source = receipt["source"]
        patterns = source["input_globs"]
        if not isinstance(patterns, list) or not SOURCE_PATTERNS.issubset(patterns):
            raise ValueError("Build receipt must cover Sources, Resources, Info.plist and build.sh.")
        if any(not isinstance(p, str) or pathlib.Path(p).is_absolute() or ".." in pathlib.Path(p).parts for p in patterns):
            raise ValueError("Build receipt source globs must stay inside this repository.")
        files = {}
        for pattern in patterns:
            for name in glob.glob(str(ROOT / pattern), recursive=True, include_hidden=True):
                path = pathlib.Path(name)
                relative = path.relative_to(ROOT).as_posix()
                if any(part in {"__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".git"} for part in path.relative_to(ROOT).parts):
                    continue
                if relative in ("perf/build-receipt.json", "perf/runtime-receipt.json"):
                    raise ValueError("Source inputs cannot include their own receipt.")
                if path.is_file():
                    files[relative] = sha(path)
        digest = hashlib.sha256(json.dumps(files, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        if not files or digest != source["sha256"] or len(files) != source["file_count"]:
            raise ValueError("Current source inputs differ from the actual build receipt.")
        def git(*args):
            return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        commit = git("rev-parse", "--verify", "HEAD^{commit}")
        if source.get("commit") != commit or source.get("dirty") is not False:
            raise ValueError("Receipt must name the current committed source; rebuild after committing source changes.")
        if git("status", "--porcelain", "--untracked-files=all", "--", *[f":(glob){p}" for p in patterns]):
            raise ValueError("Build source scope has uncommitted changes; unrelated project metadata is excluded.")
        observed = artifact_snapshot(APP)
        if observed["bundle_id"] != "cyou.tianli.initials" or observed != receipt["artifact"] or artifact_snapshot(INSTALLED) != observed:
            raise ValueError("Built and installed app executable/version/icon must all match the fresh build receipt.")
        return {"source_commit": commit, "source_sha256": digest, "artifact": observed,
                "build_receipt": {"path": "perf/build-receipt.json", "sha256": sha(receipt_path),
                                  "built_at": receipt["built_at"], "build_command_sha256": receipt["build_command_sha256"]}}
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"Release provenance check failed: {exc}") from None


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
    provenance = verify_provenance()
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
    record = {**provenance, "version": version, "build": str(bundle_info["CFBundleVersion"]), "executable_sha256": sha(APP / exe),
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
