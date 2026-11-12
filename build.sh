#!/bin/bash
# Compile Caféine et assemble Caféine.app à la racine du dépôt.
set -euo pipefail
cd "$(dirname "$0")"

APP="Caféine.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Cafeine"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Cafeine"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Le numéro de version vient du fichier VERSION, seule source de vérité.
VERSION="$(tr -d '[:space:]' < VERSION)"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $VERSION" \
    "$APP/Contents/Info.plist"

# Signature locale (ad hoc) : suffisante pour lancer l'app sur ce Mac.
codesign --force --sign - "$APP"

echo "Application créée : $(pwd)/$APP"
