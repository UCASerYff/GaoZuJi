#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$ROOT/build.noindex"
mkdir -p "$OUT/cache"
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path "$OUT/cache" -framework AppKit -framework CoreGraphics -framework ImageIO -framework CryptoKit -framework UniformTypeIdentifiers -lsqlite3 \
 "$ROOT/Shared/Models.swift" "$ROOT/Shared/TrainEngine.swift" "$ROOT/Shared/Repository.swift" "$ROOT/Shared/WidgetSnapshot.swift" \
 "$ROOT/Shared/WidgetGeneration.swift" "$ROOT/Shared/WidgetMapRenderer.swift" "$ROOT/Shared/WidgetPublisherCore.swift" \
 "$ROOT/Tools/PublishWidget.swift" -o "$OUT/publish-widget"
echo "Built headless widget publisher (not launched)"
