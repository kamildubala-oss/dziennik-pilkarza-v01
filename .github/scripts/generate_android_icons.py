#!/usr/bin/env python3
"""Generate Android launcher resources from the approved design/icon.png.

Run before flutter build; keep binary icon artwork in design/ as the source.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
SOURCE = ROOT / "design/icon.png"
ADAPTIVE = ROOT / "design/adaptive-icon.png"
if not SOURCE.is_file() or not ADAPTIVE.is_file():
    raise SystemExit("Missing selected icon artwork in design/")
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
with Image.open(SOURCE) as image:
    icon = image.convert("RGBA")
    for density, size in SIZES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        icon.resize((size, size), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")
with Image.open(ADAPTIVE) as image:
    foreground = image.convert("RGBA")
    for density, size in SIZES.items():
        # Adaptive icon layer is 108dp. Keep the artwork in the central safe area.
        canvas_size = round(size * 108 / 48)
        art_size = round(canvas_size * 0.66)
        artwork = foreground.resize((art_size, art_size), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        canvas.alpha_composite(artwork, ((canvas_size - art_size) // 2, (canvas_size - art_size) // 2))
        canvas.save(RES / f"mipmap-{density}" / "ic_launcher_foreground.png")
print("Launcher icons generated from design/icon.png and design/adaptive-icon.png")
