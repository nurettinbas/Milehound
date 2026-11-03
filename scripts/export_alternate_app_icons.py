#!/usr/bin/env python3
"""Build Home Screen alternate icons from Symbol.png + ShellPalette fills.

Keep RGB tuples in sync with MilehoundShared/ShellPalette.swift.
Sky stays the primary Liquid Glass icon; this writes the other 19 palettes
as Icon Composer .icon bundles. Do not emit alternate .appiconset folders —
Xcode 26 treats those as having an unassigned Dark [1d] child.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow required: pip install pillow", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parents[1]
SYMBOL = ROOT / "Milehound" / "Milehound.icon" / "Assets" / "Symbol.png"
ASSETS = ROOT / "Milehound" / "Assets.xcassets"
PRIMARY_SET = ASSETS / "Milehound.appiconset"
ICON_DIR = ROOT / "Milehound" / "AppIcons"

# light.tint / dark.mid — same numbers as ShellPalette recipes.
# Sky light uses the Icon Composer fill so the raster fallback matches glass.
PALETTES: dict[str, dict[str, tuple[float, float, float]]] = {
    "sky": {"light": (0.28235, 0.59608, 0.84706), "dark": (0.07, 0.13, 0.24)},
    "ocean": {"light": (0.12, 0.52, 0.72), "dark": (0.05, 0.16, 0.24)},
    "teal": {"light": (0.10, 0.52, 0.54), "dark": (0.05, 0.18, 0.20)},
    "mint": {"light": (0.16, 0.58, 0.46), "dark": (0.06, 0.20, 0.16)},
    "forest": {"light": (0.16, 0.48, 0.24), "dark": (0.07, 0.16, 0.08)},
    "lime": {"light": (0.48, 0.62, 0.10), "dark": (0.14, 0.20, 0.05)},
    "gold": {"light": (0.82, 0.56, 0.08), "dark": (0.20, 0.14, 0.04)},
    "sunset": {"light": (0.86, 0.36, 0.18), "dark": (0.22, 0.10, 0.07)},
    "orange": {"light": (0.90, 0.42, 0.10), "dark": (0.24, 0.12, 0.04)},
    "coral": {"light": (0.84, 0.30, 0.26), "dark": (0.22, 0.08, 0.08)},
    "rose": {"light": (0.78, 0.24, 0.40), "dark": (0.22, 0.08, 0.12)},
    "pink": {"light": (0.80, 0.30, 0.52), "dark": (0.22, 0.08, 0.16)},
    "magenta": {"light": (0.70, 0.20, 0.64), "dark": (0.20, 0.06, 0.18)},
    "purple": {"light": (0.52, 0.26, 0.74), "dark": (0.14, 0.07, 0.22)},
    "violet": {"light": (0.42, 0.28, 0.78), "dark": (0.12, 0.07, 0.24)},
    "indigo": {"light": (0.30, 0.32, 0.76), "dark": (0.10, 0.10, 0.26)},
    "slate": {"light": (0.32, 0.42, 0.54), "dark": (0.12, 0.14, 0.18)},
    "graphite": {"light": (0.32, 0.34, 0.40), "dark": (0.12, 0.12, 0.14)},
    "sand": {"light": (0.72, 0.52, 0.28), "dark": (0.20, 0.15, 0.08)},
    "ember": {"light": (0.68, 0.18, 0.22), "dark": (0.20, 0.06, 0.08)},
}

PRIMARY_PALETTE = "sky"


def rgb(triplet: tuple[float, float, float]) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(c * 255))) for c in triplet)


def icon_set_name(palette: str) -> str:
    return f"AppIcon{palette[:1].upper()}{palette[1:]}"


def compose(symbol: Image.Image, fill: tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", symbol.size, fill + (255,))
    canvas.alpha_composite(symbol)
    return canvas.convert("RGB")


def ios18_icon_contents(light: str, dark: str, tinted: str) -> str:
    """Xcode 26 app-icon JSON. Tinted must be luminosity=tinted, not appearance=tinted."""
    payload = {
        "images": [
            {
                "filename": light,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": dark,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [{"appearance": "luminosity", "value": "tinted"}],
                "filename": tinted,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }
    return json.dumps(payload, indent=2, separators=(",", " : ")) + "\n"


def srgb(triplet: tuple[float, float, float]) -> str:
    return f"srgb:{triplet[0]:.5f},{triplet[1]:.5f},{triplet[2]:.5f},1.00000"


def icon_composer_json(
    light: tuple[float, float, float], dark: tuple[float, float, float]
) -> str:
    return (
        "{\n"
        '  "fill-specializations" : [\n'
        "    {\n"
        '      "value" : {\n'
        f'        "solid" : "{srgb(light)}"\n'
        "      }\n"
        "    },\n"
        "    {\n"
        '      "appearance" : "dark",\n'
        '      "value" : {\n'
        f'        "solid" : "{srgb(dark)}"\n'
        "      }\n"
        "    }\n"
        "  ],\n"
        '  "groups" : [\n'
        "    {\n"
        '      "layers" : [\n'
        "        {\n"
        '          "image-name" : "Symbol.png",\n'
        '          "is-glass" : true,\n'
        '          "opacity" : 1\n'
        "        }\n"
        "      ]\n"
        "    }\n"
        "  ]\n"
        "}\n"
    )


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path, "PNG", optimize=True)


def write_composer_icon(
    directory: Path,
    light: tuple[float, float, float],
    dark: tuple[float, float, float],
) -> None:
    assets = directory / "Assets"
    if directory.exists():
        shutil.rmtree(directory)
    assets.mkdir(parents=True)
    shutil.copy2(SYMBOL, assets / "Symbol.png")
    (directory / "icon.json").write_text(
        icon_composer_json(light, dark), encoding="utf-8"
    )


def main() -> None:
    symbol = Image.open(SYMBOL).convert("RGBA")
    tinted = compose(symbol, (0, 0, 0))
    written: list[str] = []
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    for name, fills in PALETTES.items():
        if name == PRIMARY_PALETTE:
            dark = compose(symbol, rgb(fills["dark"]))
            save_png(dark, PRIMARY_SET / "AppIcon-Dark.png")
            save_png(tinted, PRIMARY_SET / "AppIcon-Tinted.png")
            (PRIMARY_SET / "Contents.json").write_text(
                ios18_icon_contents(
                    "AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"
                ),
                encoding="utf-8",
            )
            continue

        set_name = icon_set_name(name)
        write_composer_icon(ICON_DIR / f"{set_name}.icon", fills["light"], fills["dark"])
        written.append(set_name)

    print("primary dark/tinted updated")
    print("alternate icon names:")
    print(" ".join(written))


if __name__ == "__main__":
    main()
