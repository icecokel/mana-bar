#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"

swiftc -swift-version 6 -target arm64-apple-macosx13.0 -module-cache-path .build/module-cache \
  -framework AppKit -framework Security \
  Sources/UsageModels.swift Sources/PanelTypography.swift Sources/Artwork.swift Sources/CodexUsageClient.swift Sources/ClaudeUsageClient.swift \
  Tests/*.swift -o .build/checks
.build/checks
git diff --check
