"""Shared, isolated acceptance runner. Never starts the normal GUI app."""
from contextlib import contextmanager
import atexit
import fcntl
import json
import os
import plistlib
import shutil
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "accept"
APP = BUILD / "Initials.app"
CLI = APP / "Contents/Resources/bin/initials"
GUI = APP / "Contents/MacOS/Initials"
PRODUCTION_APP = None


def production_cli():
    """Original identity for read-only login status and isolated refusal checks."""
    assert PRODUCTION_APP is not None, "Call ensure_build first"
    return PRODUCTION_APP / "Contents/Resources/bin/initials"

def run(args, *, env=None, expected=0):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, env=env,
                            text=True, capture_output=True, timeout=180)
    if result.returncode != expected:
        raise AssertionError(f"{Path(str(args[0])).name}: exit {result.returncode}, expected {expected}\n"
                             + result.stdout + result.stderr)
    return result

def ensure_build():
    """Verify one production build, then test a disposable identity, never the owner's preferences.

    SDK production happens only from a fixed Chapter acceptance (which owns the
    original queue/global lock). Its receipt binds compiled inputs, not this
    test adapter or an unused signing transport script. Later checks reuse it.
    """
    global PRODUCTION_APP
    engine = ROOT.parent / "chapter/engine"
    python = Path.home() / "Dev/.venv/bin/python"
    def verify(app):
        return subprocess.run([str(python), "-c", """
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from app_sop import load_apps, verify_build_receipt
app=next(a for a in load_apps('initials-mac') if a['id']=='initials-mac' and Path(a['repo']).resolve()==Path(sys.argv[2]).resolve())
valid,reason=verify_build_receipt(app,Path(sys.argv[3]))
print(reason)
raise SystemExit(0 if valid else 1)
""", str(engine), str(ROOT), str(app)], capture_output=True, text=True, timeout=45)
    explicit = os.environ.get("INITIALS_ACCEPT_APP")
    candidates = [Path(explicit).expanduser().resolve()] if explicit else [Path("/Applications/Initials.app"), ROOT / "build/Initials.app"]
    app = next((p for p in candidates if p.is_dir() and verify(p).returncode == 0), None)
    if app is None:
        if explicit:
            raise AssertionError("Explicit app reuse lacks a valid current build receipt: " + verify(candidates[0]).stdout)
        if os.environ.get("SOP_APP_ID") != "initials-mac":
            raise AssertionError("No reusable current build; run this fixed acceptance through Chapter's queue")
        # A direct accept need not own the global SDK lock. Production is only
        # permitted through the original queue's --queue-lock contract.
        descriptor = os.environ.get("SOP_GLOBAL_LOCK_FD")
        assert descriptor and descriptor.isdigit(), "Missing verified build: use chapter sop accept --app initials-mac --check functionality --queue-lock"
        actual = os.fstat(int(descriptor))
        canonical = (Path.home() / "Library/Application Support/app-sop/lock").stat()
        assert (actual.st_dev, actual.st_ino) == (canonical.st_dev, canonical.st_ino), "SDK lock is not the original Chapter lock"
        fcntl.flock(int(descriptor), fcntl.LOCK_EX | fcntl.LOCK_NB)
        BUILD.mkdir(parents=True, exist_ok=True)
        with (BUILD / ".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            app = ROOT / "build/Initials.app"
            if not app.is_dir() or verify(app).returncode != 0:
                command = "CODESIGN_IDENTITY='Developer ID Application: tianli Zeng (B9LJH93LA4)' bash build.sh > build/accept/production-build.log 2>&1"
                args = ["chapter", "sop", "build-receipt", "--app", "initials-mac", "--artifact", str(app), "--build-command", command, "--json"]
                for pattern in ("Sources/**", "Resources/**", "Tests/**", "Info.plist", "build.sh", "LICENSE"):
                    args += ["--source-glob", pattern]
                result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=480)
                (BUILD / "production-build-result.json").write_text(result.stdout + result.stderr)
                if result.returncode:
                    raise AssertionError("Original Chapter producer failed: " + result.stdout + result.stderr)
            proof = verify(app)
            assert proof.returncode == 0, proof.stdout + proof.stderr
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    PRODUCTION_APP = app
    BUILD.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="private-app-", dir=BUILD))
    clone = scratch / "Initials.app"
    run(["ditto", app, clone])
    info = clone / "Contents/Info.plist"
    values = plistlib.loads(info.read_bytes())
    identity = "cyou.tianli.initials.test." + uuid.uuid4().hex
    values["CFBundleIdentifier"] = identity
    info.write_bytes(plistlib.dumps(values))
    run(["codesign", "--force", "--sign", "-", "--identifier", identity, clone])
    def cleanup():
        subprocess.run(["defaults", "delete", identity], capture_output=True)
        shutil.rmtree(scratch, ignore_errors=True)
    atexit.register(cleanup)
    print("Reused verified production app with disposable preferences: " + str(app))
    return clone / "Contents/Resources/bin/initials", clone / "Contents/MacOS/Initials"


@contextmanager
def isolated():
    BUILD.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fixture-", dir=BUILD) as directory:
        root = Path(directory)
        env = {**os.environ, "INITIALS_SUPPORT_DIR": str(root / "support"),
               "XDG_CONFIG_HOME": str(root / "xdg")}
        yield root, env

def detail(name, summary, **facts):
    out = Path(os.environ.get("SOP_OUT_DIR", str(ROOT / "perf/acceptance")))
    out.mkdir(parents=True, exist_ok=True)
    payload = {"summary": summary, **facts}
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    text = text.replace(str(Path.home()), "~").replace(str(ROOT), "<repo>")
    (out / f"{name}.detail.json").write_text(text)
    print(summary)
