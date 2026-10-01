# Initials · one key to any app

[中文](README.md) | **English**

[Website, download and installation guide](https://initials.tianli.cyou/en/)

Hold **⌘** and press a letter to jump to, open or hide that app. **Double-tap ⌘** to show a letter panel, then press a letter. Left and right ⌘ are set up separately and can be used together. Native macOS (Swift + AppKit), lives in the menu bar, with a matching `initials` command-line tool for scripts and agents. See [Resource use](#resource-use) for measurements.

<!-- lightweight:start -->
## Resource use

| Download | Idle memory | Idle CPU | Start to letter-panel offscreen render completed (including PNG export) |
|---|---|---|---|
| **1.6 MB** (installed 2.1 MB) | **16.8 MB** | **0%** | **150 ms** |

Pure AppKit with no third-party dependencies. Keys arrive through a system event-tap callback that only makes a few comparisons, and the switch itself runs outside the callback; config changes arrive via kqueue instead of polling, and a 30-second check only confirms the key tap is still on.

<sub>v1.1.2 (4) · Mac16,12 / Apple M4 / macOS 27.2 · measured 2026-09-29. Measured on the listed device; re-measured for each version. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->

## How it works

Each ⌘ key has two switches; turn on either or both. Default: right ⌘ is held, left ⌘ is double-tapped.

- **Hold ⌘ + letter**:
  - A pinned letter opens its app, switches to it, or hides it when it is already in front (press again to come back).
  - On right ⌘, an unpinned letter cycles through running apps whose name starts with it.
  - Left ⌘ only takes letters pinned in its table, so ⌘C, ⌘V and the rest keep working; Settings and `initials list` warn when a pinned letter shadows a common shortcut.
  - With ⇧⌥⌃ it passes through; with both ⌘ keys held, right ⌘ wins.
- **Double-tap ⌘, then a letter**: that side's letter panel appears without taking focus; Esc or 4 seconds without a key closes it. Another key, a click, a long hold, or one tap on each ⌘ does not count.
- Each side has its own letter table; by default left ⌘ uses the right ⌘ letters.
- **Settings** (menu bar ⌘ icon → Settings): ⌘1/⌘2 switch between right and left ⌘, ⌘N add, ⌫ remove, ↩ change app, ⌘W close. Import an existing Hammerspoon right_command map in one click; with an older MacKit that still has its rcmd module, Settings also offers "Turn off Hammerspoon rcmd".

## Install

macOS 14+, Apple Silicon.

1. Open the DMG, drag Initials to Applications and open it. Signed with Developer ID and notarized by Apple.
2. Click "Open Accessibility Settings…" and switch Initials on under System Settings › Privacy & Security › Accessibility. The top of Settings then reads "✓ Accessibility granted — active"; no restart needed. Initials only looks at ⌘ and the letter that follows; it records nothing.
3. Click "Add…" to pin apps to letters, or "Import from Hammerspoon".

## Command line (for scripts and agents)

The window is for people; `initials` is for scripts and agents. Both run the same `Sources/Shared` code on the same config, with the same rules (for example, left ⌘'s table cannot be edited while it uses the right ⌘ letters), and the running app applies changes at once. The command ships at `Initials.app/Contents/Resources/bin/initials`; `scripts/install.sh` links it to `~/.local/bin/initials`.

- Every command has `initials <command> --help`, which only prints help and never acts.
- Every command takes `--json` and prints one object with `"ok"`; failures have `"ok": false`, an `error` and a non-zero exit code. Help with `--json` is an object too (`{"ok": true, "command", "help"}`).
- Every config edit takes `--dry-run`, which prints the result without saving; an edit that changes nothing does not rewrite the file.
- Unknown options are rejected with exit code 2, never silently ignored.

```bash
# Read (writes nothing)
initials list [--side right|left] [--json]   # triggers, options, shortcut warnings and letters (whether each app is found, and where)
initials preview [letter…] [--side right|left] [--json]  # what each letter would do now (open/activate/hide/nothing), without doing it
initials status [--json]         # running, Accessibility, intercepting, paused, active
initials login [--json]          # does Initials open at login (read only)
initials path [--json]           # config and status file locations
initials version [--json]        # version of the Initials.app it ships in

# Change the config (all take --dry-run and --json)
initials set m Music             # name, bundle id or /path/To.app
initials set w WeChat --side left  # left-only letter (after `initials share off`)
initials unset m
initials move m k                # move M's app to K (replaces K's app and says so)
initials import [--from keymaps.lua]  # Hammerspoon right_command; apps not installed are skipped and listed
initials hold on|off [--side right|left]        # hold that ⌘ + letter
initials tap on|off [--side right|left]         # double-tap that ⌘ for the panel
initials cycle on|off [--side right|left]       # unpinned letters cycle through running apps starting with it
initials hide-front on|off [--side right|left]  # pressing the app already in front hides it
initials share on|off            # left ⌘ uses the right ⌘ letters (its own letters are kept)
initials enable|disable [right|left|all]  # saved; survives restarts

# The running app and an outside module (take --json; they do not edit the Initials config and take no --dry-run)
initials pause | resume          # the menu-bar Pause/Resume; lasts until the app restarts; check `status` first
initials hammerspoon rcmd on|off # only with an older MacKit that still has its rcmd module
```

Typical agent use:

```bash
initials list --json | jq '.right.bindings | map_values(.found)'   # which letters point at missing apps
initials set m Music --dry-run --json                               # look first, then run without --dry-run
initials preview m s --json | jq '.letters[] | {letter, action, target}'
initials pause --json && initials status --json | jq '{paused, intercepting, active}'
```

Exit codes: 0 ok; 1 not found (letter, app, an import file that is missing or has no right_command letters, rcmd module); 2 usage error or cannot read/write (including editing left ⌘ while it uses the right ⌘ letters); 3 Initials not running (status, pause, resume); 4 the running app did not confirm (pause, resume; app versions older than this feature). `status` reads the app's `status.json` and checks that the process really is Initials. The app writes it at launch, when Accessibility is granted and on every pause/resume; a revoked permission or a dead tap is written by the existing 30-second watchdog, only when the state changed and without a timer of its own, so such a change shows up within 30 seconds.

Coverage: every Settings switch, adding, changing, moving, removing and importing letters, the menu-bar Pause/Resume and state, and the letter panel's content (`preview`) all have commands. GUI only: the app chooser and icons, window keys such as ⌘1/⌘2, requesting Accessibility (only the app itself can ask, and you switch it on in System Settings), changing "Open at login" (macOS requires the app to register itself; the CLI only reads it), and quitting. The key switch itself is not a command either: really switching would take focus; use `preview` to see what a letter would do and `open -a` to switch to an app.

Config: `~/Library/Application Support/cyou.tianli.initials/config.json`; the app watches it and applies changes at once. `INITIALS_SUPPORT_DIR=<dir>` points both the app and the CLI at another folder, so tests never touch the real config. With [MacKit](https://github.com/zengtianli/mackit) installed, the current letters are published to `~/.config/mackit/keys.d/initials.json` for `mackit keys` and `mackit doctor`.

## Measured

The [Resource use](#resource-use) section is generated from [perf/lightweight.json](perf/lightweight.json), with download size, idle memory, CPU and startup speed, plus the measured version and conditions. `build.sh` also includes a key-decision benchmark; app switching runs outside the event-tap callback.

## Build

```bash
bash build.sh                   # unit tests first, then app + CLI, signed → build/Initials.app
INITIALS_BUILD_DIR=build/dev CODESIGN_IDENTITY=- bash build.sh  # personal dev build; leaves build/Initials.app alone
bash scripts/install.sh
python3 scripts/release.py
python3 scripts/shots.py        # regenerate site/assets screenshots and scenes from the built app
python3 scripts/build-site.py
```

Offscreen UI checks that never take focus: `Initials --snapshot out.png --settings right|left [--dark]`, `--snapshot out.png --picker [--right]`. `Initials --simulate right:m,left:s` prints what each letter would do right now without doing it. `Initials --help` lists every flag of the app binary; unknown flags exit, and a second copy never starts while one is running for the same config folder (as named by its `status.json`); self-tests in isolated folders and `--snapshot` renders never block the real app. Use `INITIALS_SUPPORT_DIR=<dir>` to isolate tests; `scripts/accept/*.py` check the CLI, the pause channel (`--control-self-test`) and the offscreen UI in isolated folders.

## License

MIT.
