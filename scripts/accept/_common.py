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
