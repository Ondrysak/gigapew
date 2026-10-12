#!/usr/bin/env python3
"""Paint the original Prague fixture sign atlas. Run from any directory."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CELL = (256, 128)
# Indices are the PragueKits sign constants. All identities except place names
# and generic public-wayfinding words are invented for this project.
SIGNS = [
    "JIŘÍHO Z PODĚBRAD", "PALMOVKA", "HLAVNÍ NÁDRAŽÍ", "VÝSTUP →",
    "M\n↓", "WC 10 Kč", "WC 20 Kč", "PÁNI  /  DÁMY",
    "MUŽI", "ŽENY", "VOLNO", "OBSAZENO",
    "JÍZDENKY\nPRAHA", "OZNAČTE\nJÍZDENKU", "A   B   C\nMETRO PRAHA", "PIVO",
    "ŽIŽKOVSKÁ\n12°", "MENU\nPIVO 45 Kč\nGULÁŠ 129 Kč", "HERNA\nNONSTOP", "POKLADNA",
    "VEČERKA", "ŠŤASTNÁ ČÍSLA\nLOSY", "CIGARETY", "NONSTOP\nOBČERSTVENÍ",
    "PALMOVKA\nSTAVÍME PRO VÁS", "WC\nTOJ TOJ", "ZÁKAZ VSTUPU\nSTAVENIŠTĚ", "PRAHA\nVEŘEJNÉ WC",
    "UMYJTE SI RUCE", "VÝČEP", "VODA  /  PIVO", "VÝSTUP\n↑",
]

def main():
    atlas = Image.new("RGB", (CELL[0] * 8, CELL[1] * 8), "#171d23")
    font_path = "/usr/share/fonts/TTF/FiraSans-Bold.ttf"
    for index, text in enumerate(SIGNS):
        tile = Image.new("RGB", CELL, "#17262b")
        draw = ImageDraw.Draw(tile)
        background = "#17262b"
        ink = "#eee9cf"
        if index in (0, 1, 2):
            background = ("#117b49", "#c59b16", "#ba3031")[index]
        elif index in (5, 6, 7, 8, 9, 25, 27, 28):
            background, ink = "#e0dfcf", "#173e72"
        elif index in (12, 13):
            background, ink = ("#d36b23" if index == 12 else "#d1ae21"), "#17262b"
        elif index in (15, 18, 23):
            background, ink = "#191323", "#ee6bc6"
        draw.rectangle((0, 0, 255, 127), fill=background)
        draw.rounded_rectangle((5, 5, 250, 122), radius=5, outline=ink, width=2)
        size = 54
        while size > 12:
            font = ImageFont.truetype(font_path, size)
            bounds = draw.multiline_textbbox((0, 0), text, font=font, spacing=3, align="center")
            if bounds[2] - bounds[0] <= 231 and bounds[3] - bounds[1] <= 108:
                break
            size -= 1
        x = (CELL[0] - (bounds[2] - bounds[0])) / 2 - bounds[0]
        y = (CELL[1] - (bounds[3] - bounds[1])) / 2 - bounds[1]
        draw.multiline_text((x, y), text, fill=ink, font=font, spacing=3, align="center")
        if index == 14:
            for n, color in enumerate(("#159450", "#d5af1b", "#d34640")):
                draw.line((22, 104 + n * 5, 232, 104 + n * 5), fill=color, width=3)
        atlas.paste(tile, ((index % 8) * CELL[0], (index // 8) * CELL[1]))
    destination = ROOT / "assets/kits/sign_atlas.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(destination)
    print(destination)

if __name__ == "__main__":
    main()
