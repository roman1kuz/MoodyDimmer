#!/bin/zsh
# Builds and signs "Moody Dimmer.app" and packs it into build/MoodyDimmer-<version>.dmg.
#
#   ./scripts/build-app.sh            build the DMG only
#   ./scripts/build-app.sh --install  build the DMG, copy the app to /Applications and relaunch
#
# The .app itself is assembled in a temporary *.noindex folder (Spotlight skips those) and removed
# afterwards, so macOS sees a single Moody Dimmer: the one in /Applications.
#
# Signing: if the keychain has the "Moody Dimmer Local Signing" certificate (or SIGN_IDENTITY
# is set), it is used, so the signature stays the same between builds and macOS keeps the
# Accessibility permission. Otherwise the app is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-Moody Dimmer Local Signing}"
NAME="Moody Dimmer"        # app bundle and volume name
EXE="MoodyDimmer"          # executable, matches CFBundleExecutable

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXE"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/$EXE-$VERSION.dmg"
STAGE="build/stage.noindex"
APP="$STAGE/$NAME.app"
INSTALLED="/Applications/$NAME.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# App icon: with Xcode, compile the Icon Composer icon; otherwise use the .icns fallback.
DEV_DIR="$(xcode-select -p 2>/dev/null)"
[[ "$DEV_DIR" == *CommandLineTools* && -d /Applications/Xcode.app ]] && DEV_DIR=/Applications/Xcode.app/Contents/Developer
# actool resolves relative paths against its own working directory, so pass absolute ones.
if DEVELOPER_DIR="$DEV_DIR" xcrun actool --compile "$PWD/$APP/Contents/Resources" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$PWD/$STAGE/icon.plist" \
        --errors --warnings "$PWD/Resources/AppIcon.icon" >"$STAGE/actool.log" 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
    echo "App icon: Icon Composer icon"
else
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    echo "App icon: .icns fallback (actool failed, see below)"
    grep -E "description|error" -A1 "$STAGE/actool.log" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/  \1/' || head -3 "$STAGE/actool.log"
fi
cp -R Resources/*.lproj "$APP/Contents/Resources/"
strip -x "$APP/Contents/MacOS/$EXE"

SIGNED_WITH_CERT=false
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
    SIGNED_WITH_CERT=true
    echo "Signed with certificate: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Certificate not found: signed ad hoc (the Accessibility permission will reset after each rebuild)"
fi
# Building registers the staged app with LaunchServices; unregister it right away.
"$LSREGISTER" -u "$APP" 2>/dev/null || true

# DMG: the app plus an Applications shortcut for drag-to-install.
rm -f "$STAGE/actool.log" "$STAGE/icon.plist"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
$SIGNED_WITH_CERT && codesign --force --sign "$IDENTITY" "$DMG"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$EXE" 2>/dev/null && sleep 0.5 || true
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    open "$INSTALLED"
    echo "Installed and launched: $INSTALLED"
fi
rm -rf "$STAGE"
echo "DMG: $PWD/$DMG"
