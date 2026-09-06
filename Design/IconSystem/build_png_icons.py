#!/usr/bin/python3
"""Package and validate individual image-generated raster glyphs."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
SPEC = json.loads((ROOT / "icon-system.json").read_text())
SOURCES = ROOT / "Generated"
PACKAGER = ROOT / "package_generated_icons.swift"
ASSETS = PROJECT / "Sources/CodexTokenLedger/Resources/Assets.xcassets"


def main() -> None:
    subprocess.run(["/usr/bin/swift", str(PACKAGER)], cwd=PROJECT, check=True)

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
                    alpha = image.getchannel("A")
                    bounds = alpha.point(lambda a: 255 if a > 18 else 0).getbbox()
                    if not bounds or min(bounds[0], bounds[1], size - bounds[2], size - bounds[3]) < size * 0.06:
                        errors.append(f"{filename}: empty or insufficient transparent padding")
                    elif max(abs((bounds[0] + bounds[2]) / 2 - size / 2), abs((bounds[1] + bounds[3]) / 2 - size / 2)) > 0.5:
                        errors.append(f"{filename}: off-center alpha bounds {bounds}")
                    if alpha.getextrema()[0] != 0 or alpha.getextrema()[1] < 240:
                        errors.append(f"{filename}: missing transparency or solid ink")
                    if path.read_bytes() != (ROOT / "png" / filename).read_bytes():
                        errors.append(f"{filename}: design and app assets differ")
                files.append({
                    "file": filename,
                    "pixels": [size, size],
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                })
            except Exception as error:
                errors.append(f"{filename}: {error}")

    report = {
        "status": "pass" if not errors else "fail",
        "sources": [{"file": "Generated/" + name + ".png", "sha256": hashlib.sha256((SOURCES / (name + ".png")).read_bytes()).hexdigest()} for name in SPEC["icons"]],
        "generation": "built-in imagegen individual rasters; matte extraction and centered PNG packaging",
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
