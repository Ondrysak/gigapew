#!/usr/bin/env python3
"""Renders every authored pixel icon to assets/icons/<group>/<id>.png.

    python3 tools/icons/build.py                 # all groups
    python3 tools/icons/build.py --preview /tmp/icons   # also 6x labelled sheets

Art lives in tools/icons/art_*.py. Each module defines
    GROUPS = {"<group>": {"<icon id>": [16 strings of 16 palette chars], ...}}
and may set NO_OUTLINE = {"<icon id>", ...} for icons that draw their own edge.
Icon ids must match the data ids the game looks up (file stems or `id` fields).
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ART_DIR = Path(__file__).resolve().parent
OUT_DIR = ROOT / "assets" / "icons"
PREVIEW_SCALE = 6


def load_art() -> dict[str, dict[str, tuple[list[str], bool]]]:
    groups: dict[str, dict[str, tuple[list[str], bool]]] = {}
    for path in sorted(ART_DIR.glob("art_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        no_outline = set(getattr(module, "NO_OUTLINE", set()))
        for group, icons in module.GROUPS.items():
            target = groups.setdefault(group, {})
            for icon_id, rows in icons.items():
                if icon_id in target:
                    raise ValueError(f"{path.name}: duplicate icon {group}/{icon_id}")
                target[icon_id] = (rows, icon_id not in no_outline)
    return groups


def preview_sheet(group: str, images: dict[str, Image.Image]) -> Image.Image:
    columns = 8
    cell_w, cell_h = pixel.SIZE * PREVIEW_SCALE + 24, pixel.SIZE * PREVIEW_SCALE + 30
    rows = (len(images) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h + 24), (20, 26, 34, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 4), f"{group} ({len(images)})", fill=(255, 220, 120, 255))
    for index, (icon_id, image) in enumerate(sorted(images.items())):
        x = index % columns * cell_w + 12
        y = index // columns * cell_h + 28
        big = image.resize((pixel.SIZE * PREVIEW_SCALE,) * 2, Image.NEAREST)
        sheet.alpha_composite(big, (x, y))
        draw.text((x, y + pixel.SIZE * PREVIEW_SCALE + 2), icon_id[:18], fill=(200, 215, 225, 255))
    return sheet


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", help="directory for labelled per-group preview sheets")
    parser.add_argument("--group", action="append", help="only build these groups")
    args = parser.parse_args()

    groups = load_art()
    for group, icons in sorted(groups.items()):
        if args.group and group not in args.group:
            continue
        images = {icon_id: pixel.render(f"{group}/{icon_id}", rows, outline) for icon_id, (rows, outline) in icons.items()}
        target = OUT_DIR / group
        target.mkdir(parents=True, exist_ok=True)
        for icon_id, image in images.items():
            image.save(target / f"{icon_id}.png")
        print(f"{group}: {len(images)} icons -> {target.relative_to(ROOT)}")
        if args.preview:
            preview = Path(args.preview)
            preview.mkdir(parents=True, exist_ok=True)
            preview_sheet(group, images).save(preview / f"{group}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
