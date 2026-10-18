#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}widget-generation-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
    -module-cache-path "$TEST_BUILD/cache" -framework CryptoKit -framework ImageIO -framework CoreGraphics \
    "$ROOT/Shared/Models.swift" "$ROOT/Shared/TrainEngine.swift" \
    "$ROOT/Shared/WidgetSnapshot.swift" "$ROOT/Shared/WidgetGeneration.swift" \
    "$ROOT/Tests/WidgetGenerationRegression.swift" -o "$TEST_BUILD/widget-generation-regression"
"$TEST_BUILD/widget-generation-regression"
