#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}resident-city-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
    -module-cache-path "$TEST_BUILD/cache" -framework CryptoKit -lsqlite3 \
    "$ROOT/Shared/Models.swift" "$ROOT/Shared/TrainEngine.swift" \
    "$ROOT/Shared/Repository.swift" "$ROOT/Tests/ResidentCityRegression.swift" \
    -o "$TEST_BUILD/resident-city-regression"
"$TEST_BUILD/resident-city-regression"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
    -module-cache-path "$TEST_BUILD/cache" -framework AppKit \
    "$ROOT/WidgetExtension/Models.swift" "$ROOT/WidgetExtension/WidgetSnapshot.swift" \
    "$ROOT/WidgetExtension/WidgetData.swift" "$ROOT/Tests/ResidentWidgetRegression.swift" \
    -o "$TEST_BUILD/resident-widget-regression"
"$TEST_BUILD/resident-widget-regression"
