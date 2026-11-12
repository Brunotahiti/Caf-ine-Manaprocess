#!/bin/bash
# Produit Caféine.dmg, signé avec un certificat Developer ID et notarisé par
# Apple. Préparatifs (certificat, profil de notarisation) : voir le README.
#
# Variables facultatives :
#   SIGN_IDENTITY   nom du certificat, s'il y en a plusieurs dans le trousseau
#   NOTARY_PROFILE  nom du profil de notarisation (défaut : cafeine-notary)
set -euo pipefail
cd "$(dirname "$0")"

APP="Caféine.app"
DMG="Caféine.dmg"
PROFILE="${NOTARY_PROFILE:-cafeine-notary}"
IDENTITY="${SIGN_IDENTITY:-}"

fail() {
    echo "Erreur : $1" >&2
    exit 1
}

if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -n 1)"
fi
[ -n "$IDENTITY" ] || fail "aucun certificat « Developer ID Application » dans le trousseau (voir le README)."
echo "Certificat : $IDENTITY"

echo "== Compilation =="
./build.sh

echo "== Signature de l'application =="
# Le « hardened runtime » et l'horodatage sont exigés par la notarisation.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "== Création de l'image disque =="
STAGING="$(mktemp -d)"
LOG="$(mktemp)"
trap 'rm -rf "$STAGING" "$LOG"' EXIT
ditto "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Caféine" -srcfolder "$STAGING" -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "== Notarisation (quelques minutes) =="
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$LOG" \
    || fail "l'envoi à Apple a échoué. Le profil « $PROFILE » existe-t-il ? (voir le README)"
# notarytool peut se terminer sans erreur alors qu'Apple a refusé l'app.
if ! grep -q "status: Accepted" "$LOG"; then
    ID="$(sed -n 's/^ *id: *//p' "$LOG" | head -n 1)"
    echo "Pour le détail du refus :" >&2
    echo "  xcrun notarytool log $ID --keychain-profile $PROFILE" >&2
    fail "Apple n'a pas accepté l'application."
fi

echo "== Agrafage et vérification =="
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "Image disque prête à partager : $(pwd)/$DMG"
