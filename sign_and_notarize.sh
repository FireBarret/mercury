#!/bin/bash
# Builds Mercury, signs it with a Developer ID Application cert (hardened runtime),
# notarizes it with Apple, staples the ticket, and packages it as a DMG.
#
# One-time setup:
#   1. Install a "Developer ID Application" cert (Xcode > Settings > Accounts >
#      Manage Certificates > + > Developer ID Application).
#   2. Store notarization credentials in the keychain:
#        xcrun notarytool store-credentials mercury-notary \
#          --apple-id shaban.dariush@gmail.com --team-id 6FX577RXQP
#      (it prompts for an app-specific password from appleid.apple.com)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Mercury"
APP_DIR="build/${APP_NAME}.app"
ZIP="build/${APP_NAME}-notarize.zip"
PROFILE="${NOTARY_PROFILE:-mercury-notary}"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"

if [ -z "${IDENTITY}" ]; then
    echo "No 'Developer ID Application' identity found in the keychain." >&2
    exit 1
fi

./build_app.sh

echo "Signing with: ${IDENTITY}"
# Sign Sparkle's nested code inside-out, then the app (no --deep).
SPARKLE="${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B"
for xpc in "${SPARKLE}"/XPCServices/*.xpc; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "${IDENTITY}" "${xpc}"
done
codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${SPARKLE}/Autoupdate"
codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${SPARKLE}/Updater.app"
codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "Notarizing…"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP}"
xcrun notarytool submit "${ZIP}" --keychain-profile "${PROFILE}" --wait

echo "Stapling…"
xcrun stapler staple "${APP_DIR}"
spctl --assess --type execute --verbose "${APP_DIR}"

rm -f "${ZIP}"

echo "Building DMG…"
DMG="build/${APP_NAME}.dmg"
STAGE="$(mktemp -d)"
cp -R "${APP_DIR}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait
xcrun stapler staple "${DMG}"
spctl --assess --type open --context context:primary-signature --verbose "${DMG}"

echo "Writing appcast…"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
SIG=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "${DMG}")   # prints sparkle:edSignature="…" length="…"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mercury</title>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/FireBarret/mercury/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/FireBarret/mercury/releases/download/v${VERSION}/Mercury.dmg" type="application/octet-stream" ${SIG}/>
    </item>
  </channel>
</rss>
XML
echo "Done: ${DMG} and build/appcast.xml (attach both to the GitHub release)"
