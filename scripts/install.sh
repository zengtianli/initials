#!/bin/bash
# Installs build/Initials.app to /Applications (old copy kept in build/installed-backup)
# and links the `initials` CLI into ~/.local/bin.
#
# Initials is a resident app. Without options the install refuses while it runs.
# `--restart` quits the running copy (SIGTERM, the same path as Quit), installs, and
# relaunches it in the background with `open -g -j … --background`: no focus change,
# no Settings window, no synthetic input. If copying or verifying the new app fails,
# the previous app is put back and relaunched.
set -euo pipefail
usage() { echo "usage: scripts/install.sh [--restart]" >&2; exit 2; }
RESTART=0
[ $# -le 1 ] || usage
case "${1:-}" in
  '') ;;
  --restart) RESTART=1 ;;
  *) usage ;;
esac
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${INITIALS_BUILD_DIR:-$DIR/build}/Initials.app"
DEST="/Applications/Initials.app"
BACKUP="$DIR/build/installed-backup/Initials.app"
RUNNING='^/Applications/Initials.app/Contents/MacOS/Initials([[:space:]]|$)'
test -d "$SRC" || { echo "Build first: bash build.sh" >&2; exit 1; }
# Check the new copy before the running one is stopped.
codesign --verify --deep --strict "$SRC"

WAS_RUNNING=0
if pgrep -fq "$RUNNING"; then
  if [ "$RESTART" != 1 ]; then
    echo "Installed Initials is running. Quit it first, or pass --restart to quit, install and relaunch it in the background." >&2
    exit 1
  fi
  WAS_RUNNING=1
  pkill -TERM -f "$RUNNING" || true
  for _ in $(seq 50); do pgrep -fq "$RUNNING" || break; sleep 0.1; done
  if pgrep -fq "$RUNNING"; then
    echo "Installed Initials did not quit within 5 s; nothing was replaced." >&2
    exit 1
  fi
fi

relaunch() {
  [ "$WAS_RUNNING" = 1 ] || return 0
  open -g -j -a "$DEST" --args --background
  for _ in $(seq 100); do
    if pgrep -fq "$RUNNING"; then
      echo "Relaunched in the background: pid $(pgrep -f "$RUNNING" | head -1)"
      return 0
    fi
    sleep 0.1
  done
  echo "Initials did not come back within 10 s; start it from /Applications." >&2
  return 1
}
restore() {
  echo "Install failed; putting the previous app back." >&2
  rm -rf "$DEST"
  if [ -d "$BACKUP" ]; then mv "$BACKUP" "$DEST"; fi
  relaunch || true
}

if [ -d "$DEST" ]; then
  mkdir -p "$(dirname "$BACKUP")"
  rm -rf "$BACKUP"
  mv "$DEST" "$BACKUP"
fi
trap restore ERR
ditto "$SRC" "$DEST"
codesign --verify --deep --strict "$DEST"
trap - ERR
mkdir -p "$HOME/.local/bin"
ln -sfn "$DEST/Contents/Resources/bin/initials" "$HOME/.local/bin/initials"
echo "Installed: $DEST"
echo "CLI: $HOME/.local/bin/initials -> $DEST/Contents/Resources/bin/initials"
relaunch
