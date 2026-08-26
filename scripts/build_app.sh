#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"

cd "$ROOT"
xcodegen generate
xcodebuild \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/CodexTokenLedger.app"
echo "Built: $APP"
