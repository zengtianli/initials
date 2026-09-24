# Initials · one key to any app

[中文](README.md) | **English**

[Website, download and installation guide](https://initials.tianli.cyou/en/)

Hold **⌘** and press a letter to jump to, open or hide that app. **Double-tap ⌘** to show a letter panel, then press a letter. Left and right ⌘ are set up separately and can be used together. Native macOS (Swift + AppKit), lives in the menu bar, about 15 MB of memory, with a matching `initials` command-line tool.

## How it works

Each ⌘ key has two switches; turn on either or both. Default: right ⌘ is held, left ⌘ is double-tapped.

- **Hold ⌘ + letter**:
  - A pinned letter opens its app, switches to it, or hides it when it is already in front (press again to come back).
  - On right ⌘, an unpinned letter cycles through running apps whose name starts with it.
  - Left ⌘ only takes letters pinned in its table, so ⌘C, ⌘V and the rest keep working; Settings and `initials list` warn when a pinned letter shadows a common shortcut.
  - With ⇧⌥⌃ it passes through; with both ⌘ keys held, right ⌘ wins.
- **Double-tap ⌘, then a letter**: that side's letter panel appears without taking focus; Esc or 4 seconds without a key closes it. Another key, a click, a long hold, or one tap on each ⌘ does not count.
- Each side has its own letter table; by default left ⌘ uses the right ⌘ letters.
- **Settings** (menu bar ⌘ icon → Settings): ⌘1/⌘2 switch between right and left ⌘, ⌘N add, ⌫ remove, ↩ change app, ⌘W close. Import an existing Hammerspoon rcmd map in one click, and turn Hammerspoon's rcmd off once Initials works.

## Install

macOS 14+, Apple Silicon.

1. Open the DMG, drag Initials to Applications and open it. Signed with Developer ID and notarized by Apple.
2. Click "Open Accessibility Settings…" and switch Initials on under System Settings › Privacy & Security › Accessibility. The top of Settings then reads "✓ Accessibility granted — active"; no restart needed. Initials only looks at ⌘ and the letter that follows; it records nothing.
3. Click "Add…" to pin apps to letters, or "Import from Hammerspoon".

## Command line

```bash
initials list
initials set m Music               # name, bundle id or /path/To.app
initials set w WeChat --side left  # left-only letter (after `initials share off`)
initials unset m
initials import [--from keymaps.lua]
initials hold on|off [--side right|left]  # hold that ⌘ + letter
initials tap on|off [--side right|left]   # double-tap that ⌘ for the panel
initials enable|disable [right|left|all]
initials status [--json]
initials hammerspoon rcmd on|off
```

Exit codes: 0 ok, 1 not found, 2 usage error, 3 Initials not running (status). Config: `~/Library/Application Support/cyou.tianli.initials/config.json`; the app watches it and applies changes at once. With [MacKit](https://github.com/zengtianli/mackit) installed, the current letters are published to `~/.config/mackit/keys.d/initials.json` for `mackit keys` and `mackit doctor`.

## Measured

- Memory: about 15 MB (`footprint`, idle in the menu bar).
- CPU: about 0.04 s per idle minute; the key decision inside the event tap costs about 6 ns per event (benchmark in `build.sh`); switching runs outside the callback.
- Download: about 1.8 MB.

## Build

```bash
bash build.sh
bash scripts/install.sh
python3 scripts/release.py
python3 scripts/shots.py        # regenerate site/assets screenshots and scenes from the built app
python3 scripts/build-site.py
```

Offscreen UI checks that never take focus: `Initials --snapshot out.png --settings right|left [--dark]`, `--snapshot out.png --picker [--right]`. `Initials --simulate right:m,left:s` prints what each letter would do right now without doing it. Use `INITIALS_SUPPORT_DIR=<dir>` to isolate tests.

## License

MIT.
