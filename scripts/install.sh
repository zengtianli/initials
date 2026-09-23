#!/bin/bash
# Installs build/Initials.app to /Applications (old copy kept in build/installed-backup)
# and links the `initials` CLI into ~/.local/bin.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$DIR/build/Initials.app"
DEST="/Applications/Initials.app"
test -d "$SRC" || { echo "Build first: bash build.sh" >&2; exit 1; }
if pgrep -xq Initials; then echo "Initials is running. Quit it (menu bar ⌘ icon → Quit) before replacing the installed app." >&2; exit 1; fi
if [ -d "$DEST" ]; then
  mkdir -p "$DIR/build/installed-backup"
  rm -rf "$DIR/build/installed-backup/Initials.app"
  mv "$DEST" "$DIR/build/installed-backup/Initials.app"
fi
ditto "$SRC" "$DEST"
codesign --verify --deep --strict "$DEST"
mkdir -p "$HOME/.local/bin"
ln -sfn "$DEST/Contents/Resources/bin/initials" "$HOME/.local/bin/initials"
echo "Installed: $DEST"
echo "CLI: $HOME/.local/bin/initials -> $DEST/Contents/Resources/bin/initials"
