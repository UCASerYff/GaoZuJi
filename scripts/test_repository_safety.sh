#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp/}repository-safety-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
    -module-cache-path "$TEST_BUILD/cache" -framework CryptoKit -lsqlite3 \
    "$ROOT/Shared/Models.swift" "$ROOT/Shared/TrainEngine.swift" \
    "$ROOT/Shared/Repository.swift" "$ROOT/Tests/RepositorySafetyRegression.swift" \
    -o "$TEST_BUILD/repository-safety-regression"
"$TEST_BUILD/repository-safety-regression"
