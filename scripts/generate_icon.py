#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Design/AppIconMaster.png"
BRAND_MASTER = ROOT / "Design/BrandMarkMaster.png"
ASSETS = ROOT / "Sources/CodexTokenLedger/Resources/Assets.xcassets"
APP_ICON = ASSETS / "AppIcon.appiconset"
PRODUCT_ICON = ASSETS / "TokenPulseAppIcon.imageset"
BRAND_MARK = ASSETS / "TokenPulseBrandMark.imageset"


def save_scaled(image: Image.Image, directory: Path, names_and_sizes: list[tuple[str, int]]) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name, size in names_and_sizes:
        image.resize((size, size), Image.Resampling.LANCZOS).save(directory / name)


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")
    if master.size != (1024, 1024):
        raise ValueError(f"AppIcon master must be 1024x1024, got {master.size}")
    brand_master = Image.open(BRAND_MASTER).convert("RGBA")
    if brand_master.size != (1024, 1024):
        raise ValueError(f"Brand mark master must be 1024x1024, got {brand_master.size}")

    save_scaled(
        master,
        APP_ICON,
        [(f"icon_{size}.png", size) for size in (16, 32, 64, 128, 256, 512, 1024)],
    )
    save_scaled(
        master,
        PRODUCT_ICON,
        [("app-icon.png", 64), ("app-icon@2x.png", 128), ("app-icon@3x.png", 192)],
    )
    save_scaled(
        brand_master,
        BRAND_MARK,
        [("brand-mark.png", 64), ("brand-mark@2x.png", 128), ("brand-mark@3x.png", 192)],
    )


if __name__ == "__main__":
    main()
