#!/usr/bin/python3
"""Package and validate the image-generated Pulse Atelier PNG icon family.

The glyph artwork lives in generated-ui-icon-sheet-v2.png and was produced by
Codex's built-in image generation tool. This script deliberately does not draw
or synthesize icons; the Swift slicer only crops and scales that raster source.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
SPEC = json.loads((ROOT / "icon-system.json").read_text())
SOURCE = ROOT / "generated-ui-icon-sheet-v2.png"
SLICER = ROOT / "slice_generated_ui_icons.swift"
ASSETS = PROJECT / "Sources/CodexTokenLedger/Resources/Assets.xcassets"


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing image-generated raster source: {SOURCE}")
    subprocess.run([str(SLICER)], cwd=PROJECT, check=True)

    files = []
    errors = []
    for name in SPEC["icons"]:
        for scale, size in ((1, 24), (2, 48), (3, 72)):
            filename = name + ("" if scale == 1 else f"@{scale}x") + ".png"
            path = ASSETS / f"PulseIcon-{name}.imageset" / filename
            try:
                with Image.open(path) as image:
                    if image.format != "PNG" or image.size != (size, size) or image.mode != "RGBA":
                        errors.append(f"{filename}: expected RGBA PNG {size}x{size}, got {image.mode} {image.size}")
                files.append({
                    "file": filename,
                    "pixels": [size, size],
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                })
            except Exception as error:
                errors.append(f"{filename}: {error}")

    report = {
        "status": "pass" if not errors else "fail",
        "source": SOURCE.name,
        "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "generation": "built-in imagegen raster sheet; Swift crop/scale packaging only",
        "format": "transparent PNG Image Assets",
        "iconCount": len(SPEC["icons"]),
        "scales": ["1x", "2x", "3x"],
        "errors": errors,
        "files": files,
    }
    report_path = ROOT / "reports/raster-validator.json"
    report_path.parent.mkdir(exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: packaged {len(SPEC['icons'])} image-generated PNG icons")


if __name__ == "__main__":
    main()
