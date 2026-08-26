#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/build/DerivedData/Build/Products/Release/CodexTokenLedger.app"
DIST="$ROOT/dist"
APP="$DIST/CodexTokenLedger.app"
ZIP="$DIST/CodexTokenLedger-menu-bar-macOS.zip"

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
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "App: $APP"
echo "Zip: $ZIP"
