#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT=$(mktemp -d "${TMPDIR:-/tmp/}widget-publisher-tests.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$OUT/cache" -framework CoreGraphics -framework ImageIO -framework CryptoKit -framework UniformTypeIdentifiers \
 "$ROOT/Shared/Models.swift" "$ROOT/Shared/TrainEngine.swift" "$ROOT/Shared/WidgetSnapshot.swift" \
 "$ROOT/Shared/WidgetGeneration.swift" "$ROOT/Shared/WidgetMapRenderer.swift" "$ROOT/Shared/WidgetPublisherCore.swift" \
 "$ROOT/Tests/WidgetPublisherRegression.swift" -o "$OUT/test"
"$OUT/test"
