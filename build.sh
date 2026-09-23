#!/bin/bash
# Builds build/Initials.app (app + bundled `initials` CLI) after the unit tests pass.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
# Optional helper that pins a specific Xcode; plain `xcrun` is used without it.
XCODE_ENV_SH="${XCODE_ENV_SH:-$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh}"
if [ -f "$XCODE_ENV_SH" ]; then source "$XCODE_ENV_SH"; xcode_env_use macosx; fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC=(xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macos14.0 -sdk "$SDK")
list() { find "$@" -type f -name '*.swift' | LC_ALL=C sort; }
SHARED=(); while IFS= read -r f; do SHARED+=("$f"); done < <(list Sources/Shared)
APPSRC=(); while IFS= read -r f; do APPSRC+=("$f"); done < <(list Sources/App)
CLISRC=(); while IFS= read -r f; do CLISRC+=("$f"); done < <(list Sources/CLI)
TESTSRC=(); while IFS= read -r f; do TESTSRC+=("$f"); done < <(list Tests)

mkdir -p build
STAGE="$(mktemp -d "$DIR/build/compile.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

"${SWIFTC[@]}" "${SHARED[@]}" "${TESTSRC[@]}" -o "$STAGE/tests"
"$STAGE/tests"

APP="$STAGE/Initials.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
"${SWIFTC[@]}" -Xlinker -dead_strip -framework Carbon "${SHARED[@]}" "${APPSRC[@]}" -o "$APP/Contents/MacOS/Initials"
"${SWIFTC[@]}" -Xlinker -dead_strip "${SHARED[@]}" "${CLISRC[@]}" -o "$APP/Contents/Resources/bin/initials"

# Maintainer's Developer ID by default; CODESIGN_IDENTITY=- builds an ad-hoc copy for yourself.
IDENTITY="${CODESIGN_IDENTITY:-A0F5AE165F8F84EDC1787ACCE21E2F7551B7830A}"
if [ "$IDENTITY" != '-' ] && ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "Signing identity not found; building ad-hoc (set CODESIGN_IDENTITY to your own)." >&2
  IDENTITY='-'
fi
if [ "$IDENTITY" = '-' ]; then
  codesign --force --sign - --identifier cyou.tianli.initials.cli "$APP/Contents/Resources/bin/initials"
  codesign --force --sign - --identifier cyou.tianli.initials "$APP"
else
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier cyou.tianli.initials.cli "$APP/Contents/Resources/bin/initials"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/Initials")" = arm64
"$APP/Contents/MacOS/Initials" --version
"$APP/Contents/Resources/bin/initials" --version

if [ -e build/Initials.app ]; then
  rm -rf build/Initials.previous.app
  mv build/Initials.app build/Initials.previous.app
fi
mv "$APP" build/Initials.app
echo "Built: $DIR/build/Initials.app"
