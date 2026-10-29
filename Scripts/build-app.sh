#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "CrystalDiskInfo Mac is arm64-only; current host is $(uname -m)." >&2
    exit 1
fi

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="build/CrystalDiskInfoMac.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/CrystalDiskInfoMac" "$APP/Contents/MacOS/CrystalDiskInfoMac"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: Resources/AppIcon.icns is missing; run 'swift Scripts/make-icon.swift' to generate it." >&2
fi

ARCHS="$(lipo -archs "$APP/Contents/MacOS/CrystalDiskInfoMac")"
if [[ "$ARCHS" != "arm64" ]]; then
    echo "Expected an arm64-only binary, got: $ARCHS" >&2
    exit 1
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "$APP"
