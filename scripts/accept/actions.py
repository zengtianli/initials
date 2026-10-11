"""Real CLI action bindings, portable config and side-effect-free dispatch."""
import json
import os
from _common import run


def exercise(cli, gui, root, env, check):
    downloads = root / "downloads"
    downloads.mkdir()
    old = downloads / "z-old.txt"
    old.write_text("old")
    newest = downloads / "a-new.txt"
    newest.write_text("new")
    (downloads / "incomplete.crdownload").write_text("partial")
    os.utime(old, (2000000000, 2000000000))
    screenshots = root / "screenshots"
    screenshots.mkdir()
    capture = screenshots / "Screenshot fixture.png"
    capture.write_bytes(b"fixture")
    env = {**env, "INITIALS_ACTION_DOWNLOADS_DIR": str(downloads), "INITIALS_ACTION_SCREENSHOTS_DIR": str(screenshots)}
    def command(*args, expected=0):
        return run([cli, *args], env=env, expected=expected)

    path = root / "support/config.json"
    before = path.read_bytes()
    catalog = json.loads(command("actions", "--json").stdout)
    ids = {a["id"] for a in catalog["actions"]}
    check(len(ids) == 8 and "open-last-download" in ids, "action catalog lists eight built-in commands")
    command("bind", "g", "show-downloads", "--dry-run")
    check(path.read_bytes() == before, "action dry-run does not save")
    command("bind", "g", "show-downloads")
    command("bind", "o", "open-last-download")
    command("bind", "r", "reveal-last-download")
    command("bind", "p", "open-last-screenshot")
    dynamic = {e["letter"]: e for e in json.loads(command("preview", "g", "o", "r", "p", "--json").stdout)["letters"]}
    check(dynamic["o"]["resolvedTarget"] == str(newest) and dynamic["r"]["resolvedAction"] == "reveal", "latest download ignores modified old file and incomplete newest file")
    check(dynamic["p"]["resolvedTarget"] == str(capture) and dynamic["g"]["resolvedTarget"] == str(downloads), "dynamic actions use screenshot and Downloads directories")
    document = root / "report.txt"
    document.write_text("fixture")
    for letter, kind, target in [("j", "open-folder", str(root)), ("k", "open-file", str(document)),
                                 ("u", "open-url", "https://example.com"), ("q", "run-shortcut", "Fixture Shortcut")]:
        out = json.loads(command("bind", letter, kind, target, "--json").stdout)
        check(out["binding"]["action"] == {"kind": kind, "target": target}, f"bind persists {kind}")
    saved = path.read_bytes()
    out = json.loads(command("preview", "j", "k", "u", "q", "--json").stdout)
    targets = {entry["letter"]: entry for entry in out["letters"]}
    check(targets["k"]["resolvedTarget"] == str(document) and targets["j"]["resolvedTarget"] == str(root), "preview resolves real local file and directory")
    check(targets["q"]["resolvedAction"] == "run-shortcut" and targets["q"]["resolvedTarget"] == "Fixture Shortcut", "shortcut preview does not execute")
    simulated = run([gui, "--simulate", "right:g,right:o,right:r,right:p,right:j,right:k,right:u,right:q"], env=env).stdout
    check("show-downloads" in simulated and "open-last-download" in simulated and "run-shortcut" in simulated, "app dispatch recognizes all configured actions without execution")
    check(path.read_bytes() == saved and not (root / "support/status.json").exists(), "action preview and simulation leave lifecycle and configuration untouched")
    for args in [("bind", "a", "unknown"), ("bind", "a", "show-downloads", "extra"),
                 ("bind", "a", "open-url", "bad URL"), ("bind", "a", "open-file"),
                 ("bind", "a", "open-folder", "relative"), ("actions", "--dry-run"),
                 ("bind", "a", "show-downloads", "--bogus")]:
        command(*args, expected=2)
        check(path.read_bytes() == saved, f"invalid action arguments do not mutate: {args}")
    command("bind", "a", "open-folder", str(document), expected=1)
    check(path.read_bytes() == saved, "folder action rejects a file")
    exported = root / "action-export.json"
    command("export", str(exported))
    command("unset", "g")
    command("import", str(exported))
    imported = json.loads(command("list", "--json").stdout)
    check(imported["right"]["bindings"]["g"]["action"]["kind"] == "show-downloads", "export and import preserve action bindings")
    command("move", "g", "h")
    moved = json.loads(command("list", "--json").stdout)["right"]["bindings"]
    check("g" not in moved and moved["h"]["action"]["kind"] == "show-downloads", "moving an action preserves its type")
