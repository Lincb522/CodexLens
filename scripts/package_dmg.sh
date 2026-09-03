#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${SOURCE_APP:-$ROOT/dist/Codex Lens.app}"
DIST="${DIST_DIR:-$ROOT/dist}"
DMG="$DIST/Codex-Lens-macOS.dmg"
IDENTITY="${CODESIGN_IDENTITY:-}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/CodexTokenLedger.dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 2
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$DIST"
/usr/bin/ditto "$APP" "$STAGING/Codex Lens.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
/usr/bin/hdiutil create \
  -volname "Codex Lens" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG"

if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
  /usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  /usr/bin/codesign --verify --verbose=2 "$DMG"
elif [[ "${REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
  echo "CODESIGN_IDENTITY must name a Developer ID Application certificate." >&2
  exit 2
fi

/usr/bin/hdiutil verify "$DMG"
echo "DMG: $DMG"
