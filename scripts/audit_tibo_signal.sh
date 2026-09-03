#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="${1:-$ROOT/build/tibo-signal-audit.json}"
DERIVED="$ROOT/build/TiboAuditDerivedData"
APP="$DERIVED/Build/Products/Debug/Codex Lens.app"
TEST_BUNDLE="$APP/Contents/PlugIns/CodexTokenLedgerTests.xctest"

mkdir -p "$ROOT/build"
cd "$ROOT"
xcodegen generate >/dev/null
xcodebuild \
  -project CodexTokenLedger.xcodeproj \
  -scheme CodexTokenLedger \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:CodexTokenLedgerTests/TiboResetSignalTests/testLiveEndpointAuditWhenRequested \
  build-for-testing >/dev/null

TIBO_LIVE_AUDIT_OUTPUT="$OUTPUT" \
DYLD_LIBRARY_PATH="$APP/Contents/MacOS" \
DYLD_FRAMEWORK_PATH="$APP/Contents/Frameworks:$DERIVED/Build/Products/Debug/PackageFrameworks" \
xcrun xctest \
  -XCTest CodexTokenLedgerTests.TiboResetSignalTests/testLiveEndpointAuditWhenRequested \
  "$TEST_BUNDLE"

/usr/bin/python3 - "$OUTPUT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
signal = data.get("latestSignal") or {}
social = (data.get("socialEvidence") or [{}])[0]
assert data.get("sourceStatus") == "healthy"
assert signal.get("postID")
assert signal.get("contentHash") and len(signal["contentHash"]) == 64
assert signal.get("matchedRuleIDs")
assert "text" not in signal and "body" not in signal
assert social.get("postID")
assert social.get("sourceURL", "").startswith("https://x.com/thsottiaux/status/")
assert social.get("signalKind") in {"explicit", "tease", "context"}
print(json.dumps({
    "artifact": str(path),
    "sourceStatus": data["sourceStatus"],
    "postID": signal["postID"],
    "status": signal["status"],
    "ruleVersion": signal["ruleVersion"],
    "socialEvidencePostID": social["postID"],
    "socialEvidenceKind": social["signalKind"],
}, ensure_ascii=False, sort_keys=True))
PY
