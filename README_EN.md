# Initials · one key to any app

[中文](README.md) | **English**

Hold **right ⌘** and press a letter to jump to, open or hide that app. **Double-tap left ⌘** to show a letter panel, then press a letter. Native macOS (Swift + AppKit), lives in the menu bar, about 15 MB of memory, with a matching `initials` command-line tool.

## How it works

- **Right ⌘ + letter**:
  - A pinned letter opens its app, switches to it, or hides it when it is already in front (press again to come back).
  - An unpinned letter cycles through running apps whose name starts with it.
  - Only right ⌘ + a single letter is intercepted. With ⇧⌥⌃ it passes through, and left ⌘ shortcuts (⌘C, ⌘V…) are never touched.
- **Double-tap left ⌘, then a letter**: a letter panel appears without taking focus; Esc or 4 seconds without a key closes it. Another key, a click or a long hold between taps does not count.
- Each side has its own letter table; by default left ⌘ uses the right ⌘ letters.
- **Settings** (menu bar ⌘ icon → Settings): ⌘1/⌘2 switch side, ⌘N add, ⌫ remove, ↩ change app, ⌘W close. Import an existing Hammerspoon rcmd map in one click, and turn Hammerspoon's rcmd off once Initials works.

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
initials enable|disable [right|left|all]
initials status [--json]
initials hammerspoon rcmd on|off
```

Exit codes: 0 ok, 1 not found, 2 usage error, 3 Initials not running (status). Config: `~/Library/Application Support/cyou.tianli.initials/config.json`; the app watches it and applies changes at once. With [MacKit](https://github.com/zengtianli/mackit) installed, the current letters are published to `~/.config/mackit/keys.d/initials.json` for `mackit keys` and `mackit doctor`.

## Measured

- Memory: about 15 MB (`footprint`, idle in the menu bar).
- CPU: about 0.04 s per idle minute; the key decision inside the event tap costs about 4 ns per event (benchmark in `build.sh`); switching runs outside the callback.
- Download: about 1.8 MB.

## Build

```bash
bash build.sh
bash scripts/install.sh
python3 scripts/release.py
python3 scripts/build-site.py
```

Offscreen UI checks that never take focus: `Initials --snapshot out.png --settings right|left [--dark]`, `--snapshot out.png --picker`. `Initials --simulate right:m,left:s` prints what each letter would do right now without doing it. Use `INITIALS_SUPPORT_DIR=<dir>` to isolate tests.

## License

MIT.
