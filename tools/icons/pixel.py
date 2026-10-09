"""Shared palette and renderer for the game's pixel-art icons.

Icons are authored as text: one string per pixel row, one palette character per
pixel ('.' is transparent). Every icon is 16x16 and should keep a one-pixel
transparent margin so the automatic dark outline fits. The outline is added to
every transparent pixel that touches an opaque one (4-neighbourhood), so draw
only the fill and shading.
"""

from __future__ import annotations

from PIL import Image

SIZE = 16

# Ramps run dark -> mid -> light. Keep icons to this palette so they match.
PALETTE: dict[str, tuple[int, int, int, int]] = {
    ".": (0, 0, 0, 0),
    "K": (11, 14, 20, 255),  # outline / deepest shadow
    # neutral steel
    "1": (42, 47, 58, 255),
    "2": (74, 82, 99, 255),
    "3": (124, 135, 152, 255),
    "4": (184, 194, 207, 255),
    "5": (238, 243, 248, 255),
    # cyan (scout, tech, energy)
    "c": (13, 77, 92, 255),
    "C": (26, 163, 181, 255),
    "q": (111, 242, 255, 255),
    # orange (fire, driller, cinder)
    "o": (122, 46, 10, 255),
    "O": (224, 102, 26, 255),
    "p": (255, 176, 87, 255),
    # gold / yellow (gold, gunner, power)
    "y": (138, 90, 18, 255),
    "Y": (242, 179, 58, 255),
    "u": (255, 240, 154, 255),
    # red (health, damage, danger)
    "r": (92, 15, 29, 255),
    "R": (212, 40, 63, 255),
    "s": (255, 122, 122, 255),
    # green (engineer, regen, xp)
    "g": (29, 84, 32, 255),
    "G": (79, 201, 58, 255),
    "h": (183, 255, 138, 255),
    # purple (void shard, shock-adjacent, rare)
    "v": (58, 26, 107, 255),
    "V": (145, 80, 240, 255),
    "w": (214, 173, 255, 255),
    # blue (frost, armor)
    "b": (21, 44, 107, 255),
    "B": (58, 109, 240, 255),
    "n": (156, 196, 255, 255),
    # magenta (perks)
    "m": (107, 20, 80, 255),
    "M": (230, 74, 168, 255),
    # brown (wood, rock, leather)
    "d": (74, 44, 26, 255),
    "D": (140, 90, 53, 255),
}

OUTLINE = PALETTE["K"]


def validate(name: str, rows: list[str]) -> None:
    if len(rows) != SIZE:
        raise ValueError(f"{name}: {len(rows)} rows, expected {SIZE}")
    for y, row in enumerate(rows):
        if len(row) != SIZE:
            raise ValueError(f"{name}: row {y} has {len(row)} pixels, expected {SIZE}: {row!r}")
        unknown = sorted(set(row) - PALETTE.keys())
        if unknown:
            raise ValueError(f"{name}: row {y} uses unknown palette characters {unknown}")


def render(name: str, rows: list[str], outline: bool = True) -> Image.Image:
    """Returns the 16x16 RGBA icon for `rows`."""
    validate(name, rows)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            pixels[x, y] = PALETTE[key]
    if outline:
        solid = [[pixels[x, y][3] > 0 for x in range(SIZE)] for y in range(SIZE)]
        for y in range(SIZE):
            for x in range(SIZE):
                if solid[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE and solid[ny][nx]:
                        pixels[x, y] = OUTLINE
                        break
    return image
