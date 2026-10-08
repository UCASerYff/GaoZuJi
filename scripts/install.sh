#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
SOURCE="$ROOT/build.noindex/搞足迹.app"
if [[ ! -d "$SOURCE" ]]; then
    SOURCE="$ROOT/.install.noindex/搞足迹.app"
    mkdir -p "$ROOT/.install.noindex"
    VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")
    (cd "$ROOT/dist";shasum -a 256 -c "搞足迹-$VERSION.zip.sha256")
    ditto -x -k "$ROOT/dist/搞足迹-$VERSION.zip" "$ROOT/.install.noindex"
fi
TARGET="/Applications/搞足迹.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
codesign --verify --deep --strict "$SOURCE"
for key in CFBundleShortVersionString CFBundleVersion; do
    EXPECTED=$(/usr/libexec/PlistBuddy -c "Print :$key" "$ROOT/Info.plist")
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$SOURCE/Contents/Info.plist")" == "$EXPECTED" ]] || { echo '应用版本与源码不一致';exit 1;}
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$SOURCE/Contents/PlugIns/GaoZuJiWidgets.appex/Contents/Info.plist")" == "$EXPECTED" ]] || { echo '小组件版本与源码不一致';exit 1;}
done
[[ "$(codesign -dv "$SOURCE" 2>&1 | sed -n 's/^TeamIdentifier=//p')" == "5G96498KGJ" ]] || { echo '需要团队签名';exit 1;}
if pgrep -f '^/Applications/搞足迹.app/Contents/MacOS/GaoZuJi' >/dev/null; then echo '请先退出当前应用';exit 1;fi
STAMP=$(date +%Y%m%d-%H%M%S)
SAFETY="$ROOT/rollback/搞足迹-$STAMP.app"
mkdir -p "$ROOT/rollback"
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$SAFETY";fi
if ! ditto "$SOURCE" "$TARGET" || ! codesign --verify --deep --strict "$TARGET" || ! "$LSREGISTER" -f -R "$TARGET" || ! pluginkit -a "$TARGET/Contents/PlugIns/GaoZuJiWidgets.appex"; then
    rm -rf "$TARGET"
    if [[ -d "$SAFETY" ]];then mv "$SAFETY" "$TARGET";"$LSREGISTER" -f -R "$TARGET";pluginkit -a "$TARGET/Contents/PlugIns/GaoZuJiWidgets.appex";fi
    exit 1
fi
killall -TERM GaoZuJiWidgets 2>/dev/null || true
rm -rf "$ROOT/.install.noindex"
echo "Installed $TARGET"
