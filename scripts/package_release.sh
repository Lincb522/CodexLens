#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/build/DerivedData/Build/Products/Release/Codex Lens.app"
DIST="$ROOT/dist"
APP="$DIST/Codex Lens.app"
ZIP="$DIST/Codex-Lens-macOS.zip"
IDENTITY="${CODESIGN_IDENTITY:-}"

if [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
    echo "CODESIGN_IDENTITY must name a Developer ID Application certificate." >&2
    exit 2
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/build_app.sh"
fi

mkdir -p "$DIST"
/usr/bin/python3 - "$APP" "$ZIP" <<'PY'
import pathlib
import shutil
import sys

for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()
PY

/usr/bin/ditto "$SOURCE_APP" "$APP"
/usr/bin/install -m 0644 "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
/usr/bin/codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "App: $APP"
echo "Zip: $ZIP"
