"""Shared, isolated acceptance runner. Never starts the normal GUI app."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "accept"
APP = BUILD / "Initials.app"
CLI = APP / "Contents/Resources/bin/initials"
GUI = APP / "Contents/MacOS/Initials"

def run(args, *, env=None, expected=0):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, env=env,
                            text=True, capture_output=True, timeout=180)
    if result.returncode != expected:
        raise AssertionError(f"{Path(str(args[0])).name}: exit {result.returncode}, expected {expected}\n"
                             + result.stdout + result.stderr)
    return result

def ensure_build():
    # Explicit reuse is a real product run, not a new build: Chapter must prove
    # this exact app still matches its receipt and all current source inputs.
    # Keep compilation (including the shared-source check) as the default.
    if os.environ.get("INITIALS_ACCEPT_APP"):
        app = Path(os.environ["INITIALS_ACCEPT_APP"]).expanduser().resolve()
        engine = ROOT.parent / "chapter/engine"
        python = Path.home() / "Dev/.venv/bin/python"
        verification = run([python, "-c", """
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from app_sop import load_apps, verify_build_receipt
root, bundle = map(Path, sys.argv[2:4])
apps = [a for a in load_apps('initials-mac') if a['id'] == 'initials-mac'
        and Path(a['repo']).resolve() == root.resolve()]
if len(apps) != 1:
    raise SystemExit('Current Initials registration could not be verified')
valid, reason = verify_build_receipt(apps[0], bundle)
print(json.dumps({'valid': valid, 'reason': reason}, ensure_ascii=False))
if not valid:
    raise SystemExit(1)
""", engine, ROOT, app])
        proof = json.loads(verification.stdout)
        if proof.get("valid") is not True:
            raise AssertionError("Explicit app reuse lacks a valid build receipt")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
        cli, gui = app / "Contents/Resources/bin/initials", app / "Contents/MacOS/Initials"
        if not cli.is_file() or not gui.is_file():
            raise AssertionError("Verified app is missing the bundled CLI or GUI")
        print("Reused verified app: " + proof["reason"])
        return cli, gui
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        files = sorted(ROOT.glob("Sources/**/*.swift")) + sorted(ROOT.glob("Tests/**/*.swift"))
        files += [ROOT / p for p in ("build.sh", "Info.plist", "Resources/AppIcon.icns")]
        digest = hashlib.sha256(b"".join(str(p.relative_to(ROOT)).encode() + p.read_bytes() for p in files)).hexdigest()
        stamp = BUILD / ".inputs"
        if not GUI.exists() or not CLI.exists() or not stamp.exists() or stamp.read_text() != digest:
            result = run(["bash", "build.sh"], env={**os.environ, "INITIALS_BUILD_DIR": str(BUILD), "CODESIGN_IDENTITY": "-"})
            print("Built isolated app and CLI; bundled unit tests passed.")
            stamp.write_text(digest)
    return CLI, GUI

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
