#!/usr/bin/env python3
"""Generates the invented Prague street-face atlas used by the human enemies.

Every face is painted from the parameters below: nothing is traced or sampled
from a photograph and no real person is depicted. 16 cells in a 4 x 4 atlas,
each a 64 x 64 pixel painting upscaled 4x with nearest filtering:

    cells 0-11   homeless / drunk / junkie faces (Bezdomovec, Feťák, Alkoholik)
    cells 12-15  harder faces (Vekslák, Vyhazovač, Pan Herna)

A cell covers the whole front of the model head (forehead to chin), planar
mapped by tools/vat/bake_vat.py. Its outer ring is blended into BASE_SRGB so the
face meets the untextured skin on the head sides and neck without a seam.

    python3 tools/vat/faces/build_faces.py            # writes atlas.png + preview
    python3 tools/vat/faces/build_faces.py --preview /tmp/faces_preview.png
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
CELL = 64
GRID = 4
SCALE = 4
# Neutral dirty skin. monsters.json derives the untextured Skin colour from this.
BASE_SRGB = (170, 128, 104)

# Row 0-2 homeless, row 3 hard. Positions are pixels in the 64 grid, y down.
EYE_Y = 31
EYE_X = (18, 46)
FACES = [
    # 0 long grey beard, bloodshot, shaggy hair
    dict(tone=-6, hair=("shaggy", (128, 124, 118)), beard=("long", (140, 136, 128)), brow=(110, 106, 100), eyes="bloodshot",
         iris=(70, 80, 90), bags=0.7, teeth="gaps", nose="red", wrinkles=3, grime=0.5, snot=False),
    # 1 drunk red nose, slack drooling mouth
    dict(tone=10, hair=("patchy", (70, 56, 44)), beard=("stubble", (60, 50, 44)), brow=(70, 56, 44), eyes="halflid",
         iris=(96, 70, 40), bags=0.8, teeth="yellow", nose="red", wrinkles=2, grime=0.35, drool=True, flush=0.6),
    # 2 junkie: gaunt, pinned pupils, sores
    dict(tone=-14, hair=("fringe", (36, 30, 26)), beard=("stubble", (70, 60, 54)), brow=(40, 34, 30), eyes="pinned",
         iris=(88, 100, 96), bags=1.0, teeth="rotten", nose="plain", wrinkles=1, grime=0.55, sores=9, gaunt=True),
    # 3 black eye and split lip
    dict(tone=0, hair=("short", (58, 46, 36)), beard=("stubble", (56, 46, 40)), brow=(56, 46, 36), eyes="plain",
         iris=(70, 96, 120), bags=0.5, teeth="gaps", nose="plain", wrinkles=1, grime=0.4, bruise="left", splitlip=True),
    # 4 vomit down the chin, glazed
    dict(tone=-4, hair=("long", (62, 48, 34)), beard=("scruff", (82, 66, 48)), brow=(62, 48, 34), eyes="glazed",
         iris=(100, 110, 80), bags=0.9, teeth="open", nose="plain", wrinkles=2, grime=0.5, vomit=True),
    # 5 toothless in a knit cap
    dict(tone=-8, hair=("cap", (60, 44, 74)), beard=("mustache", (150, 146, 138)), brow=(150, 146, 138), eyes="plain",
         iris=(96, 76, 52), bags=0.6, teeth="none", nose="plain", wrinkles=4, grime=0.45),
    # 6 scabs, lazy eye, crooked mouth
    dict(tone=6, hair=("mullet", (88, 62, 38)), beard=("stubble", (88, 66, 46)), brow=(88, 62, 38), eyes="lazy",
         iris=(70, 100, 70), bags=0.8, teeth="rotten", nose="plain", wrinkles=1, grime=0.5, sores=14, crooked=True),
    # 7 bald, filthy, nicotine moustache, snot
    dict(tone=-2, hair=("bald", (0, 0, 0)), beard=("mustache", (150, 118, 62)), brow=(90, 76, 60), eyes="plain",
         iris=(80, 84, 90), bags=0.7, teeth="yellow", nose="red", wrinkles=3, grime=0.7, snot=True),
    # 8 tattooed tear, scarred brow
    dict(tone=-4, hair=("shaved", (50, 44, 40)), beard=("stubble", (46, 40, 36)), brow=(34, 30, 28), eyes="plain",
         iris=(60, 56, 48), bags=0.5, teeth="closed", nose="plain", wrinkles=1, grime=0.35, tattoo=True, scar=True),
    # 9 stringy hair, screaming, wide wild eyes
    dict(tone=-10, hair=("stringy", (40, 36, 32)), beard=("stubble", (60, 54, 48)), brow=(40, 36, 32), eyes="wild",
         iris=(78, 86, 96), bags=1.0, teeth="scream", nose="plain", wrinkles=2, grime=0.55),
    # 10 cross-eyed, flushed, long drool thread
    dict(tone=12, hair=("fringe", (110, 90, 66)), beard=("none", (0, 0, 0)), brow=(110, 90, 66), eyes="cross",
         iris=(84, 112, 128), bags=0.5, teeth="open", nose="red", wrinkles=1, grime=0.4, drool=True, flush=0.9),
    # 11 black bear beard with crumbs
    dict(tone=-6, hair=("shaggy", (30, 26, 24)), beard=("bear", (28, 24, 22)), brow=(26, 22, 20), eyes="bloodshot",
         iris=(60, 44, 30), bags=0.8, teeth="hidden", nose="plain", wrinkles=2, grime=0.6, crumbs=True),
    # 12 gold tooth grin
    dict(tone=4, hair=("slick", (28, 24, 22)), beard=("stubble", (36, 32, 30)), brow=(26, 22, 20), eyes="plain",
         iris=(52, 40, 30), bags=0.3, teeth="gold", nose="plain", wrinkles=1, grime=0.15, scar_cheek=True),
    # 13 shaved head, long scar
    dict(tone=-2, hair=("shaved", (62, 56, 52)), beard=("stubble", (52, 46, 42)), brow=(40, 36, 32), eyes="plain",
         iris=(88, 96, 100), bags=0.3, teeth="closed", nose="plain", wrinkles=2, grime=0.2, scar=True),
    # 14 broken nose, cauliflower brow
    dict(tone=-6, hair=("short", (72, 60, 48)), beard=("none", (0, 0, 0)), brow=(66, 54, 42), eyes="plain",
         iris=(70, 92, 112), bags=0.4, teeth="closed", nose="broken", wrinkles=1, grime=0.2, bruise="right"),
    # 15 slicked hair, tinted glasses, thin moustache
    dict(tone=6, hair=("slick", (22, 18, 18)), beard=("mustache", (24, 20, 20)), brow=(22, 18, 18), eyes="plain",
         iris=(40, 32, 28), bags=0.2, teeth="closed", nose="plain", wrinkles=1, grime=0.1, shades=True),
]


def srgb(c, k=1.0):
    return np.array([min(255, max(0, v * k)) for v in c], dtype=np.float32)


class Canvas:
    def __init__(self, rng: random.Random):
        self.rng = rng
        self.px = np.zeros((CELL, CELL, 3), dtype=np.float32)

    def blend(self, x, y, color, alpha=1.0):
        if 0 <= x < CELL and 0 <= y < CELL:
            self.px[y, x] = self.px[y, x] * (1.0 - alpha) + np.array(color, dtype=np.float32) * alpha

    def rect(self, x0, y0, x1, y1, color, alpha=1.0):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.blend(x, y, color, alpha)

    def ellipse(self, cx, cy, rx, ry, color, alpha=1.0, ragged=0.0):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                d = ((x - cx) / max(rx, 0.5)) ** 2 + ((y - cy) / max(ry, 0.5)) ** 2
                if ragged:
                    d += self.rng.uniform(-ragged, ragged)
                if d <= 1.0:
                    self.blend(x, y, color, alpha)

    def line(self, x0, y0, x1, y1, color, alpha=1.0, width=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps + 1):
            t = i / max(steps, 1)
            x = round(x0 + (x1 - x0) * t)
            y = round(y0 + (y1 - y0) * t)
            for w in range(width):
                self.blend(x, y + w, color, alpha)

    def speckle(self, x0, y0, x1, y1, color, density, alpha=1.0):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                if self.rng.random() < density:
                    self.blend(x, y, color, alpha)


def paint(index: int, t: dict) -> Image.Image:
    rng = random.Random(7000 + index * 131)
    c = Canvas(rng)
    base = srgb(BASE_SRGB)
    tone = t.get("tone", 0)
    c.px[:, :] = base + tone
    # Low-frequency blotches: uneven, unwashed skin.
    blot = np.zeros((CELL, CELL), dtype=np.float32)
    for _ in range(6):
        bx, by = rng.uniform(10, 54), rng.uniform(16, 60)
        br = rng.uniform(5, 12)
        yy, xx = np.mgrid[0:CELL, 0:CELL]
        blot += np.exp(-(((xx - bx) ** 2 + (yy - by) ** 2) / (2 * br * br))) * rng.uniform(-9, 9)
    c.px += blot[:, :, None]
    if t.get("flush"):
        c.ellipse(15, 44, 8, 6, (214, 110, 96), 0.45 * t["flush"], 0.3)
        c.ellipse(49, 44, 8, 6, (214, 110, 96), 0.45 * t["flush"], 0.3)
    if t.get("gaunt"):
        c.ellipse(13, 44, 7, 9, (86, 64, 60), 0.5)
        c.ellipse(51, 44, 7, 9, (86, 64, 60), 0.5)

    # Hair on the forehead (bald models rely on this; haired models cover it).
    hair_kind, hair_col = t["hair"]
    # The models bring their own hair meshes (or are bald), so only a faint
    # shaved-scalp shadow is painted; anything else would clash with the mesh.
    if hair_kind != "shaved":
        hair_kind = "bald"
    hair_col = srgb(hair_col)
    heights = dict(shaggy=15, fringe=13, short=9, cap=17, mullet=10, stringy=12, long=14, slick=10, patchy=11, shaved=7, bald=0)
    top = heights.get(hair_kind, 8)
    if hair_kind == "cap":
        c.rect(0, 0, 63, top, hair_col * 0.9)
        for x in range(0, 64, 4):
            c.rect(x, 0, x + 1, top, hair_col * 1.25, 0.5)
        c.rect(0, top - 1, 63, top + 1, hair_col * 0.7)
    elif top:
        alpha = 0.55 if hair_kind in ("shaved",) else 1.0
        for x in range(CELL):
            edge = top + (rng.randint(-3, 4) if hair_kind not in ("slick", "shaved") else rng.randint(-1, 2))
            if hair_kind == "patchy" and 14 < x < 50:
                edge -= rng.randint(2, 8)
            if hair_kind == "stringy" and x % 6 in (0, 1):
                edge += 9
            c.rect(x, 0, x, max(edge, 0), hair_col * rng.uniform(0.85, 1.15), alpha)
        if hair_kind in ("long", "stringy", "shaggy", "mullet"):
            for side, x0 in (("l", 0), ("r", 55)):
                for x in range(x0, x0 + 9):
                    c.rect(x, 0, x, rng.randint(36, 52), hair_col * rng.uniform(0.7, 1.1), 0.9)
    # Forehead wrinkles.
    for i in range(t.get("wrinkles", 1)):
        y = 19 + i * 3
        c.line(14 + rng.randint(0, 4), y, 50 - rng.randint(0, 4), y + rng.choice((-1, 0, 1)), (110, 78, 62), 0.45)

    # Eye sockets and bags.
    bag = (112, 82, 92) if t.get("gaunt") else (122, 88, 78)
    for ex in EYE_X:
        c.ellipse(ex, EYE_Y + 3, 9, 5, bag, 0.55 * t.get("bags", 0.5), 0.2)
        c.ellipse(ex, EYE_Y + 6, 8, 2.2, (90, 66, 70), 0.35 * t.get("bags", 0.5))
    if t.get("bruise") in ("left", "right"):
        ex = EYE_X[0 if t["bruise"] == "left" else 1]
        c.ellipse(ex, EYE_Y, 12, 10, (92, 54, 110), 0.75, 0.35)
        c.ellipse(ex + 2, EYE_Y + 4, 8, 6, (150, 130, 60), 0.4, 0.35)
    # Brows.
    brow = srgb(t["brow"])
    tilt = rng.choice((-1, 1)) * rng.uniform(0.5, 1.5)
    for k, ex in enumerate(EYE_X):
        sgn = -1 if k == 0 else 1
        c.line(ex - 8, EYE_Y - 8 + int(sgn * tilt * -2), ex + 8, EYE_Y - 8 + int(sgn * tilt * 2), brow, 0.95, 3)

    # Eyes.
    kind = t.get("eyes", "plain")
    iris = srgb(t.get("iris", (80, 80, 80)))
    for k, ex in enumerate(EYE_X):
        ey = EYE_Y
        w, h = 7, 3.6
        white = np.array([232, 224, 206], dtype=np.float32)
        if kind in ("bloodshot", "glazed", "wild"):
            white = np.array([226, 190, 176], dtype=np.float32)
        if kind == "wild":
            h = 5.2
        if kind == "halflid":
            h = 2.6
        if kind == "lazy" and k == 1:
            ey += 2
            h = 2.8
        c.ellipse(ex, ey, w, h, (60, 40, 36), 1.0)
        c.ellipse(ex, ey, w - 1, h - 1, white, 1.0)
        if kind in ("bloodshot", "wild", "glazed"):
            for _ in range(7):
                a = rng.uniform(0, math.tau)
                c.line(ex + math.cos(a) * 5.5, ey + math.sin(a) * 2.3, ex + math.cos(a) * 2.5, ey + math.sin(a) * 1.0, (170, 40, 40), 0.9)
        px = ex
        if kind == "cross":
            px = ex + (3 if k == 0 else -3)
        if kind == "lazy" and k == 1:
            px = ex + 3
        if kind == "glazed":
            px = ex + rng.randint(-1, 1)
        pr = 1.6 if kind == "pinned" else (3.2 if kind == "wild" else 2.6)
        c.ellipse(px, ey, pr + 1.2, min(pr + 1.2, h - 0.6), iris, 1.0)
        c.ellipse(px, ey, pr * 0.6, min(pr * 0.6, h - 1.2), (14, 12, 12), 1.0)
        c.blend(int(px - 1), int(ey - 1), (255, 255, 255), 0.8)
        if kind == "halflid":
            c.rect(ex - w, ey - int(h) - 1, ex + w, ey - 1, base + tone - 12, 0.95)
            c.line(ex - w, ey - 1, ex + w, ey - 1, (70, 48, 44), 0.9)
    if t.get("shades"):
        for ex in EYE_X:
            c.ellipse(ex, EYE_Y, 10.5, 7, (14, 14, 18), 0.97)
            c.blend(ex - 4, EYE_Y - 3, (160, 160, 180), 0.55)
        c.line(28, EYE_Y - 1, 36, EYE_Y - 1, (20, 20, 20), 1.0, 2)
    if t.get("tattoo"):
        c.line(EYE_X[1] + 2, EYE_Y + 6, EYE_X[1] + 2, EYE_Y + 11, (36, 52, 84), 0.9, 2)
        c.ellipse(EYE_X[1] + 2, EYE_Y + 12, 1.5, 2, (36, 52, 84), 0.9)

    # Nose.
    nose = t.get("nose", "plain")
    nx = 32 + (3 if nose == "broken" else 0)
    c.line(30, 34, 29, 43, (118, 82, 66), 0.5)
    c.line(34, 34, 35, 43, (118, 82, 66), 0.5)
    if nose == "red":
        c.ellipse(32, 43, 7, 5, (200, 82, 78), 0.7, 0.3)
    if nose == "broken":
        c.line(32, 30, nx, 43, (96, 66, 54), 0.7, 2)
    c.ellipse(nx - 3, 44, 2, 1.3, (50, 30, 28), 0.95)
    c.ellipse(nx + 3, 44, 2, 1.3, (50, 30, 28), 0.95)
    c.line(nx - 5, 46, nx + 5, 46, (110, 76, 62), 0.55)
    if t.get("snot"):
        c.line(nx - 3, 45, nx - 3, 50, (214, 220, 160), 0.9, 2)
        c.ellipse(nx - 3, 51, 1.6, 1.6, (214, 220, 160), 0.9)

    # Mouth and teeth.
    teeth = t.get("teeth", "closed")
    my = 53
    lip = (126, 72, 68)
    cx = 32 + (3 if t.get("crooked") else 0)
    dark = (30, 14, 16)
    if teeth in ("closed", "hidden"):
        c.line(cx - 8, my, cx + 8, my + (2 if t.get("crooked") else 0), dark, 1.0, 2)
        c.line(cx - 7, my + 2, cx + 7, my + 2, lip, 0.7)
    elif teeth == "none":
        c.ellipse(cx, my + 1, 7, 2.6, dark, 1.0)
        c.line(cx - 8, my + 3, cx + 8, my + 3, (118, 84, 72), 0.6)
    else:
        mh = {"open": 7.5, "scream": 10.0}.get(teeth, 4.6)
        c.ellipse(cx, my + 1, 11, mh, dark, 1.0)
        tooth_col = {"yellow": (206, 190, 120), "rotten": (150, 128, 70), "gaps": (200, 184, 130), "open": (200, 184, 130),
                     "scream": (190, 170, 100), "gold": (218, 176, 50)}.get(teeth, (200, 184, 130))
        for i, tx in enumerate(range(cx - 7, cx + 8, 3)):
            if teeth in ("gaps", "rotten") and rng.random() < 0.42:
                continue
            col = (214, 176, 40) if (teeth == "gold" and i == 4) else tuple(int(v * rng.uniform(0.82, 1.05)) for v in tooth_col)
            c.rect(tx, my - 1, tx + 1, my + 1, col, 1.0)
            if teeth in ("open", "scream"):
                c.rect(tx, my + 3, tx + 1, my + 4, col, 0.9)
        if teeth in ("scream",):
            c.ellipse(cx, my + 5, 4, 2, (150, 40, 50), 0.9)
        c.line(cx - 9, my - 3, cx + 9, my - 3, lip, 0.65)
    if t.get("splitlip"):
        c.line(cx + 2, my + 3, cx + 3, my + 8, (160, 24, 24), 1.0, 2)
        c.speckle(cx, my + 4, cx + 6, my + 10, (190, 30, 30), 0.35)
    if t.get("drool"):
        c.line(cx + 4, my + 4, cx + 4, my + 12, (206, 214, 214), 0.85, 2)
        c.ellipse(cx + 4, my + 13, 1.8, 2.2, (214, 222, 222), 0.85)

    # Beard / stubble over the lower face.
    kind, col = t.get("beard", ("none", (0, 0, 0)))
    col = srgb(col)
    if kind == "stubble":
        c.speckle(10, 44, 54, 63, col, 0.45, 0.75)
        c.speckle(14, 36, 50, 46, col, 0.18, 0.6)
    elif kind in ("long", "scruff", "bear"):
        top_y = {"long": 46, "scruff": 47, "bear": 38}[kind]
        for x in range(8, 57):
            edge = top_y + rng.randint(-2, 2) + (0 if kind == "bear" else int(abs(x - 32) * 0.12))
            c.rect(x, edge, x, 63, col * rng.uniform(0.85, 1.12), 0.96)
        if kind == "long":
            for x in range(12, 53, 5):
                c.line(x, 56, x + rng.randint(-1, 1), 63, col * 1.2, 0.8)
        # keep the mouth visible through the beard
        if teeth not in ("hidden", "closed"):
            c.ellipse(cx, my + 1, 8, 3.8, dark, 0.95)
        elif kind == "bear":
            c.line(cx - 6, my + 1, cx + 6, my + 1, (50, 20, 20), 0.9)
    elif kind == "mustache":
        for dx in range(-11, 12):
            sag = int(abs(dx) * 0.25)
            c.rect(cx + dx, 46 + sag, cx + dx, 50 + sag, col, 0.95)
    if t.get("crumbs"):
        c.speckle(14, 52, 50, 63, (220, 190, 120), 0.04, 0.9)
        c.speckle(18, 54, 46, 63, (180, 70, 50), 0.025, 0.9)
    if t.get("vomit"):
        for x in range(24, 41):
            ln = rng.randint(7, 15) if abs(x - 32) < 6 else rng.randint(2, 7)
            c.rect(x, 54, x, 54 + ln, (150, 150, 62), 0.9)
        c.speckle(24, 54, 41, 63, (214, 190, 110), 0.18, 0.95)
        c.speckle(24, 54, 41, 63, (110, 50, 40), 0.06, 0.95)

    # Scars, sores, grime.
    if t.get("scar"):
        c.line(EYE_X[0] - 4, EYE_Y - 12, EYE_X[0] + 14, EYE_Y + 22, (200, 140, 130), 0.95)
        c.line(EYE_X[0] - 3, EYE_Y - 12, EYE_X[0] + 15, EYE_Y + 22, (96, 54, 50), 0.6)
    if t.get("scar_cheek"):
        c.line(48, 40, 56, 54, (210, 150, 140), 0.9)
        c.line(49, 40, 57, 54, (96, 54, 50), 0.55)
    for _ in range(t.get("sores", 0)):
        sx, sy = rng.randint(10, 54), rng.randint(34, 60)
        c.ellipse(sx, sy, rng.uniform(1, 2.2), rng.uniform(1, 2.0), rng.choice(((120, 40, 40), (84, 36, 30), (176, 90, 84))), 0.95)
    grime = t.get("grime", 0.3)
    for _ in range(int(7 + grime * 20)):
        gx, gy = rng.uniform(4, 60), rng.uniform(8, 62)
        c.ellipse(gx, gy, rng.uniform(2, 7), rng.uniform(1.5, 5), (62, 48, 36), rng.uniform(0.15, 0.4) * (0.5 + grime), 0.5)
    for _ in range(int(3 + grime * 8)):
        sx = rng.randint(8, 56)
        c.line(sx, rng.randint(24, 40), sx + rng.randint(-3, 3), rng.randint(46, 62), (60, 46, 34), 0.3 * grime + 0.1)
    # Greasy highlight on forehead and nose bridge.
    c.ellipse(26, 17, 6, 2, (240, 214, 190), 0.22)
    c.blend(32, 38, (240, 214, 190), 0.4)

    # Blend the outer ring into the neutral skin so the cell meets the head sides.
    arr = c.px
    yy, xx = np.mgrid[0:CELL, 0:CELL]
    edge = np.minimum.reduce([xx, CELL - 1 - xx, yy * 0 + 63, CELL - 1 - yy]) / 7.0
    fade = np.clip(edge, 0.0, 1.0)[:, :, None]
    # Hairlines on the top edge intentionally keep their colour.
    top_keep = np.clip(1.0 - yy[:, :1] / 4.0, 0.0, 1.0)[:, :, None]
    fade = np.maximum(fade, top_keep * (1.0 - np.clip(np.minimum(xx, CELL - 1 - xx) / 3.0, 0, 1))[:, :, None] * 0 + top_keep)
    arr = base * (1.0 - fade) + arr * fade
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def build() -> Image.Image:
    atlas = Image.new("RGB", (CELL * GRID, CELL * GRID), BASE_SRGB)
    for index, traits in enumerate(FACES):
        atlas.paste(paint(index, traits), ((index % GRID) * CELL, (index // GRID) * CELL))
    return atlas.resize((atlas.width * SCALE, atlas.height * SCALE), Image.NEAREST)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", help="optional extra copy of the atlas for visual review")
    args = parser.parse_args()
    atlas = build()
    atlas.save(HERE / "atlas.png")
    print("wrote", HERE / "atlas.png", atlas.size)
    if args.preview:
        atlas.save(args.preview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
