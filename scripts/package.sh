#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
APP=${GAO_PACKAGE_APP:-"$ROOT/build.noindex/搞足迹.app"}
STAGE="$ROOT/.release.noindex"
RELEASE_APP="$STAGE/搞足迹.app"
SIGNING_IDENTITY=${GAO_SIGNING_IDENTITY:-A15B2B2D22B018CBC842063C9A8A589946647524}
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")" ]] || { echo '构建版本与源码版本不一致';exit 1;}
NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist")
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$NUMBER" ]] || { echo '构建号不一致';exit 1;}
for component in "$APP/Contents/PlugIns/GaoZuJiWidgets.appex/Contents/Info.plist" "$APP/Contents/Frameworks/Footprints.framework/Resources/Info.plist"; do
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$component")" == "$VERSION" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$component")" == "$NUMBER" ]] || { echo '组件版本不一致';exit 1;}
done
rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$RELEASE_APP"
python3 "$ROOT/scripts/sanitize_bundle.py" "$RELEASE_APP"
for helper in "$RELEASE_APP"/Contents/Frameworks/Footprints.framework/Versions/A/Resources/UsageEngine/tokscale(N); do
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$helper"
done
codesign --force --sign "$SIGNING_IDENTITY" "$RELEASE_APP/Contents/Frameworks/Footprints.framework"
codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/Widget.entitlements" "$RELEASE_APP/Contents/PlugIns/GaoZuJiWidgets.appex"
codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/App.entitlements" "$RELEASE_APP"
codesign --verify --deep --strict "$RELEASE_APP"
ditto -c -k --keepParent --norsrc --noextattr "$RELEASE_APP" "$ROOT/dist/GaoZuJi-$VERSION.zip"
(cd "$ROOT/dist"; shasum -a 256 "GaoZuJi-$VERSION.zip" > "GaoZuJi-$VERSION.zip.sha256")
echo "Packaged $ROOT/dist/GaoZuJi-$VERSION.zip"
