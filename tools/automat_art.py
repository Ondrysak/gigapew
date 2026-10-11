#!/usr/bin/env python3
"""Deterministic art for the fruit-machine deposits (gold "SUPER DROBNÉ", shard "JACKPOT 777").

Writes to assets/automat/:
  reel_strip.png         256x2048  16 reel stops, 256x128 cells, symbol STRIP[i] in cell i (top down)
  glass_<theme>.png      1024x2048 atlas: top glass (v 0-0.5), lower glass (v 0.5-0.75), misc (v 0.75-1)
  glass_<theme>_mask.png 512x1024  same UV layout; R = lamp group*16+8, G = ordinal*16+8, B = lamp coverage

Glass alpha is 0 where reels, LEDs and the coin window show through from behind.
The layout constants below are mirrored in scripts/mining/slot_bank_geometry.gd and
the lamp groups in shaders/slot_machine.gdshaderinc. Text uses Fira Sans (SIL OFL 1.1).
Run: python3 tools/automat_art.py
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "automat"
FONTS = Path("/usr/share/fonts/TTF")
HEAVY = str(FONTS / "FiraSans-Heavy.ttf")
HEAVY_ITALIC = str(FONTS / "FiraSans-HeavyItalic.ttf")
CONDENSED = str(FONTS / "FiraSansCondensed-ExtraBold.ttf")
BOLD = str(FONTS / "FiraSans-Bold.ttf")

# Symbols, in shader order (slot_machine.gdshaderinc).
SEVEN, BAR, BELL, MELON, GRAPES, PLUM, ORANGE, LEMON, CHERRY = range(9)
STRIP = [SEVEN, CHERRY, LEMON, PLUM, BELL, ORANGE, CHERRY, GRAPES, LEMON, BAR, ORANGE, MELON, CHERRY, PLUM, LEMON, GRAPES]
PAY = [750, 400, 300, 200, 100, 50, 50, 25, 25]

# Lamp groups encoded in the mask's red channel (slot_machine.gdshaderinc LAMP_*).
LOGO, STARS, PAYROW, WINLINE, LADDER, HOUSE, RISK, RISKBAR, LOWLINE, INFO, INDICATOR, LABEL, RAYS = range(1, 14)

# Layouts in normalized panel coordinates (u right, v down). Mirrored in slot_bank_geometry.gd.
TOP_ASPECT = 1.15
TOP_REELS = [(0.245, 0.485, 0.115, 0.22), (0.375, 0.485, 0.115, 0.22), (0.505, 0.485, 0.115, 0.22)]  # centre u, top v, w, h
TOP_CREDIT = (0.30, 0.835, 0.66, 0.955)
TOP_BET = (0.045, 0.86, 0.215, 0.94)
TOP_BONUS = (0.745, 0.86, 0.945, 0.94)
TOP_COIN = (0.80, 0.035, 0.955, 0.10)
LOW_ASPECT = 3.6
LOW_REELS = [(0.19, 0.24, 0.075, 0.46), (0.275, 0.24, 0.075, 0.46), (0.36, 0.24, 0.075, 0.46)]

SS = 2  # supersampling of every canvas


# ----------------------------------------------------------------------------- numpy helpers

def box_blur(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Three box passes approximate a Gaussian; works on (H, W) or (H, W, C)."""
    if sigma <= 0.3:
        return a.astype(np.float32)
    r = max(1, int(round(math.sqrt(12.0 * sigma * sigma / 3.0 + 1.0) / 2.0)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = box_blur(out, r, 0)
        out = box_blur(out, r, 1)
    return out


def _bounds(mask: np.ndarray, pad: float):
    """Slices around the nonzero part of a mask (None when empty)."""
    rows = np.nonzero(mask.max(1) > 0.001)[0]
    if len(rows) == 0:
        return None
    cols = np.nonzero(mask.max(0) > 0.001)[0]
    p = int(pad) + 2
    return (slice(max(0, rows[0] - p), min(mask.shape[0], rows[-1] + p + 1)),
            slice(max(0, cols[0] - p), min(mask.shape[1], cols[-1] + p + 1)))


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    if r <= 0:
        return mask
    out = np.zeros_like(mask, dtype=np.float32)
    box = _bounds(mask, r * 3)
    if box is not None:
        out[box] = np.clip(blur((mask[box] > 0.5).astype(np.float32), r * 0.6) * 4.0, 0.0, 1.0)
    return out


def smooth(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def noise(h: int, w: int, scale: float, seed: int) -> np.ndarray:
    """Smooth value noise in 0..1, deterministic."""
    rng = np.random.default_rng(seed)
    gh, gw = int(h / scale) + 3, int(w / scale) + 3
    g = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((int(gw * scale), int(gh * scale)), Image.BICUBIC)
    return np.asarray(img, np.float32)[:h, :w] / 255.0


def mask_image(size: tuple[int, int], draw_fn) -> np.ndarray:
    img = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(img))
    return np.asarray(img, np.float32) / 255.0


class Canvas:
    """Premultiplied-free float RGBA canvas with straight alpha 'over' compositing."""

    def __init__(self, w: int, h: int, color=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.float32)
        self.a[...] = color

    def over(self, rgb, alpha: np.ndarray, x: int = 0, y: int = 0) -> None:
        """Composite colour (array HxWx3 or tuple) with coverage `alpha` at (x, y)."""
        ah, aw = alpha.shape
        x0, y0, x1, y1 = max(0, x), max(0, y), min(self.w, x + aw), min(self.h, y + ah)
        if x0 >= x1 or y0 >= y1:
            return
        al = alpha[y0 - y:y1 - y, x0 - x:x1 - x][..., None]
        if isinstance(rgb, np.ndarray):
            col = rgb[y0 - y:y1 - y, x0 - x:x1 - x]
        else:
            col = np.array(rgb[:3], np.float32)
        dst = self.a[y0:y1, x0:x1]
        out_a = al + dst[..., 3:4] * (1.0 - al)
        safe = np.maximum(out_a, 1e-6)
        dst[..., :3] = (col * al + dst[..., :3] * dst[..., 3:4] * (1.0 - al)) / safe
        dst[..., 3:4] = out_a

    def layer(self, other: "Canvas", x: int = 0, y: int = 0) -> None:
        self.over(other.a[..., :3], other.a[..., 3], x, y)

    def add(self, rgb: np.ndarray, amount: np.ndarray) -> None:
        """Additive glow (keeps alpha)."""
        self.a[..., :3] += rgb * amount[..., None]

    def image(self, size: tuple[int, int] | None = None) -> Image.Image:
        arr = np.clip(self.a, 0.0, 1.0)
        img = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")
        return img.resize(size, Image.LANCZOS) if size else img


def shade(mask: np.ndarray, color, *, soft: float, light=(-0.55, -0.65, 0.55), ambient=0.38,
          spec=0.55, shine=24.0, bump: np.ndarray | None = None, rim=0.35, bulge=2.2) -> np.ndarray:
    """Illustrated volume shading from a silhouette: height = blurred mask, Blinn-Phong lit."""
    out = np.zeros(mask.shape + (3,), np.float32)
    box = _bounds(mask, soft * 3)
    if box is None:
        return out
    if bump is not None:
        bump = bump[box]
    out[box] = _shade(mask[box], color, soft, light, ambient, spec, shine, bump, rim, bulge)
    return out


def _shade(mask, color, soft, light, ambient, spec, shine, bump, rim, bulge) -> np.ndarray:
    h = blur(mask, soft)
    h = np.sqrt(np.clip(h, 0.0, 1.0))
    if bump is not None:
        h = h + bump
    gy, gx = np.gradient(h)
    k = bulge * soft
    n = np.stack([-gx * k, -gy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    L = np.array(light, np.float32)
    L /= np.linalg.norm(L)
    diff = np.clip((n * L).sum(-1), 0.0, 1.0)
    half = L + np.array([0.0, 0.0, 1.0], np.float32)
    half /= np.linalg.norm(half)
    sp = np.clip((n * half).sum(-1), 0.0, 1.0) ** shine * spec
    edge = 1.0 - rim * (1.0 - smooth(0.0, 0.55, h))
    base = np.array(color, np.float32)
    rgb = base * (ambient + (1.0 - ambient) * diff)[..., None] * edge[..., None] + sp[..., None]
    return np.clip(rgb, 0.0, 1.0)


def gradient_v(h: int, w: int, stops) -> np.ndarray:
    """Vertical colour ramp; stops = [(t, (r,g,b)), ...]."""
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)
    out = np.zeros((h, 3), np.float32)
    for c in range(3):
        out[:, c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
    return np.repeat(out[:, None, :], w, axis=1)


def font(path: str, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, max(4, int(size)))


def text_mask(size: tuple[int, int], text: str, fnt, xy, anchor="mm", stroke=0) -> np.ndarray:
    return mask_image(size, lambda d: d.text(xy, text, font=fnt, fill=255, anchor=anchor, stroke_width=stroke, stroke_fill=255))


# ----------------------------------------------------------------------------- symbols

def _symbol_seven(S: int) -> Canvas:
    c = Canvas(S, S)
    f = font(HEAVY_ITALIC, S * 1.02)
    centre = (S * 0.52, S * 0.47)
    outer = text_mask((S, S), "7", f, centre, stroke=int(S * 0.05))
    gold = text_mask((S, S), "7", f, centre, stroke=int(S * 0.028))
    body = text_mask((S, S), "7", f, centre)
    c.over((0.07, 0.02, 0.02), outer)
    gold_rgb = shade(gold, (1.0, 0.78, 0.2), soft=S * 0.012, spec=0.8, shine=18, ambient=0.5)
    c.over(gold_rgb, gold)
    ramp = gradient_v(S, S, [(0.0, (1.0, 0.32, 0.2)), (0.45, (0.93, 0.05, 0.05)), (1.0, (0.5, 0.0, 0.02))])
    lit = shade(body, (1.0, 1.0, 1.0), soft=S * 0.03, spec=0.0, ambient=0.55, rim=0.25)
    c.over(ramp * lit, body)
    # Glossy highlight streak along the top bar.
    rows = np.arange(S, dtype=np.float32)[:, None]
    streak = body * np.exp(-((rows - S * 0.19) / (S * 0.035)) ** 2)
    c.add(np.array([1.0, 0.85, 0.8], np.float32), streak * 0.5)
    return c


def _symbol_bar(S: int) -> Canvas:
    c = Canvas(S, S)
    box = (S * 0.08, S * 0.3, S * 0.92, S * 0.7)
    outer = mask_image((S, S), lambda d: d.rounded_rectangle(box, radius=S * 0.07, fill=255))
    inner = mask_image((S, S), lambda d: d.rounded_rectangle((box[0] + S * 0.035, box[1] + S * 0.035, box[2] - S * 0.035, box[3] - S * 0.035), radius=S * 0.045, fill=255))
    c.over(shade(outer, (1.0, 0.76, 0.18), soft=S * 0.012, spec=0.85, shine=16, ambient=0.5), outer)
    c.over(shade(inner, (0.06, 0.06, 0.08), soft=S * 0.03, spec=0.35, shine=30), inner)
    f = font(HEAVY, S * 0.3)
    word = text_mask((S, S), "BAR", f, (S * 0.5, S * 0.505))
    c.over(gradient_v(S, S, [(0.0, (1, 1, 1)), (0.5, (0.86, 0.88, 0.92)), (0.52, (0.6, 0.62, 0.7)), (1.0, (0.95, 0.96, 1))]), word)
    return c


def _bell_mask(S: int) -> np.ndarray:
    prof = [(0.0, 0.17), (0.07, 0.175), (0.12, 0.2), (0.15, 0.26), (0.165, 0.35), (0.18, 0.47), (0.22, 0.58), (0.29, 0.66), (0.34, 0.7), (0.345, 0.74), (0.3, 0.765), (0.0, 0.78)]
    pts = [(S * (0.5 + x), S * y) for x, y in prof] + [(S * (0.5 - x), S * y) for x, y in reversed(prof)]
    return mask_image((S, S), lambda d: d.polygon(pts, fill=255))


def _symbol_bell(S: int) -> Canvas:
    c = Canvas(S, S)
    body = _bell_mask(S)
    clapper = mask_image((S, S), lambda d: d.ellipse((S * 0.43, S * 0.73, S * 0.57, S * 0.87), fill=255))
    ring = mask_image((S, S), lambda d: d.ellipse((S * 0.44, S * 0.07, S * 0.56, S * 0.2), outline=255, width=int(S * 0.035)))
    sil = np.maximum(np.maximum(body, clapper), ring)
    c.over((0.12, 0.06, 0.0), np.clip(dilate(sil, int(S * 0.022)), 0, 1))
    gold = (1.0, 0.74, 0.12)
    c.over(shade(ring, gold, soft=S * 0.01, spec=0.7), ring)
    c.over(shade(clapper, (0.9, 0.62, 0.1), soft=S * 0.03, spec=0.8), clapper)
    c.over(shade(body, gold, soft=S * 0.06, spec=0.9, shine=14, ambient=0.32, bulge=2.6), body)
    lip = mask_image((S, S), lambda d: d.rounded_rectangle((S * 0.17, S * 0.67, S * 0.83, S * 0.77), radius=S * 0.05, fill=255)) * body
    c.over(shade(lip, (0.86, 0.55, 0.06), soft=S * 0.015, spec=0.6), lip * 0.9)
    return c


def _symbol_melon(S: int) -> Canvas:
    c = Canvas(S, S)
    body = mask_image((S, S), lambda d: d.ellipse((S * 0.08, S * 0.2, S * 0.92, S * 0.84), fill=255))
    c.over((0.02, 0.1, 0.02), dilate(body, int(S * 0.02)))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    # Curved dark stripes follow the melon's longitude lines, with ragged edges.
    u = (xx - 0.5) / 0.42
    lon = np.arcsin(np.clip(u, -0.999, 0.999)) / (math.pi / 2)
    wobble = (noise(S, S, S * 0.03, 11) - 0.5) * 0.08
    stripes = smooth(0.25, 0.45, np.abs(np.sin((lon + wobble) * math.pi * 3.5)))
    base = np.array([0.07, 0.36, 0.06]) * (1.0 - stripes[..., None]) + np.array([0.38, 0.72, 0.18]) * stripes[..., None]
    lit = shade(body, (1, 1, 1), soft=S * 0.08, spec=0.0, ambient=0.3, bulge=2.4)
    spec = shade(body, (0, 0, 0), soft=S * 0.08, spec=0.6, shine=20, bulge=2.4)
    c.over(np.clip(base * lit + spec, 0, 1), body)
    stem = mask_image((S, S), lambda d: d.line([(S * 0.5, S * 0.21), (S * 0.53, S * 0.13)], fill=255, width=int(S * 0.035)))
    c.over((0.35, 0.25, 0.08), stem)
    return c


def _leaf(S: int, cx: float, cy: float, length: float, width: float, angle: float) -> tuple[np.ndarray, np.ndarray]:
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for i in range(41):
        t = i / 40.0
        x = (t - 0.5) * length
        y = math.sin(math.pi * t) ** 0.8 * width * 0.5
        pts.append((x, y))
    pts += [(x, -y) for x, y in reversed(pts)]
    poly = [(S * (cx + x * ca - y * sa), S * (cy + x * sa + y * ca)) for x, y in pts]
    leaf = mask_image((S, S), lambda d: d.polygon(poly, fill=255))
    rib = mask_image((S, S), lambda d: d.line([(S * (cx - 0.5 * length * ca), S * (cy - 0.5 * length * sa)), (S * (cx + 0.45 * length * ca), S * (cy + 0.45 * length * sa))], fill=255, width=max(2, int(S * 0.012))))
    return leaf, rib * leaf


def _draw_leaf(c: Canvas, S: int, *args) -> None:
    leaf, rib = _leaf(S, *args)
    c.over((0.03, 0.12, 0.02), dilate(leaf, int(S * 0.015)))
    c.over(shade(leaf, (0.22, 0.62, 0.12), soft=S * 0.025, spec=0.35, ambient=0.4), leaf)
    c.over((0.1, 0.35, 0.05), rib * 0.8)


def _ball(c: Canvas, S: int, cx: float, cy: float, rx: float, ry: float, color, outline=(0.1, 0.0, 0.02), bump=None, spec=0.85, shine=30.0) -> None:
    m = mask_image((S, S), lambda d: d.ellipse((S * (cx - rx), S * (cy - ry), S * (cx + rx), S * (cy + ry)), fill=255))
    c.over(outline, dilate(m, int(S * 0.018)))
    c.over(shade(m, color, soft=S * min(rx, ry) * 0.55, spec=spec, shine=shine, ambient=0.3, bump=bump, bulge=2.6), m)

def _symbol_cherry(S: int) -> Canvas:
    c = Canvas(S, S)
    stems = mask_image((S, S), lambda d: (
        d.line([(S * 0.37, S * 0.6), (S * 0.42, S * 0.4), (S * 0.53, S * 0.22), (S * 0.62, S * 0.14)], fill=255, width=int(S * 0.035), joint="curve"),
        d.line([(S * 0.68, S * 0.63), (S * 0.68, S * 0.42), (S * 0.65, S * 0.24), (S * 0.62, S * 0.14)], fill=255, width=int(S * 0.035), joint="curve")))
    c.over((0.12, 0.08, 0.0), dilate(stems, int(S * 0.012)))
    c.over(shade(stems, (0.45, 0.42, 0.1), soft=S * 0.01, spec=0.2), stems)
    _draw_leaf(c, S, 0.74, 0.14, 0.3, 0.13, -0.35)
    _ball(c, S, 0.36, 0.7, 0.19, 0.18, (0.86, 0.04, 0.08))
    _ball(c, S, 0.67, 0.72, 0.18, 0.17, (0.78, 0.02, 0.07))
    return c


def _symbol_lemon(S: int) -> Canvas:
    c = Canvas(S, S)
    angle = -0.32
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for i in range(120):
        t = i / 120.0 * 2 * math.pi
        x, y = math.cos(t), math.sin(t)
        # Pointed nibs at both ends of the lemon.
        r = 1.0 + 0.16 * max(0.0, abs(x)) ** 12
        px, py = x * 0.4 * r, y * 0.27
        pts.append((S * (0.5 + px * ca - py * sa), S * (0.52 + px * sa + py * ca)))
    body = mask_image((S, S), lambda d: d.polygon(pts, fill=255))
    c.over((0.25, 0.16, 0.0), dilate(body, int(S * 0.02)))
    pores = (noise(S, S, S * 0.008, 7) - 0.5) * 0.008
    c.over(shade(body, (1.0, 0.86, 0.1), soft=S * 0.07, spec=0.7, shine=22, ambient=0.35, bump=pores, bulge=2.5), body)
    _draw_leaf(c, S, 0.27, 0.26, 0.22, 0.1, -2.2)
    return c


def _symbol_orange(S: int) -> Canvas:
    c = Canvas(S, S)
    pores = (noise(S, S, S * 0.007, 3) - 0.5) * 0.01
    _ball(c, S, 0.5, 0.55, 0.36, 0.35, (1.0, 0.52, 0.04), outline=(0.25, 0.08, 0.0), bump=pores, spec=0.55, shine=18)
    navel = mask_image((S, S), lambda d: d.ellipse((S * 0.47, S * 0.2, S * 0.53, S * 0.24), fill=255))
    c.over((0.45, 0.25, 0.02), navel)
    _draw_leaf(c, S, 0.63, 0.16, 0.26, 0.12, -0.45)
    return c


def _symbol_plum(S: int) -> Canvas:
    c = Canvas(S, S)
    _ball(c, S, 0.5, 0.55, 0.33, 0.37, (0.42, 0.1, 0.5), outline=(0.08, 0.0, 0.1), spec=0.4, shine=12)
    groove = mask_image((S, S), lambda d: d.arc((S * 0.3, S * 0.19, S * 0.7, S * 0.95), 200, 280, fill=255, width=int(S * 0.02)))
    c.over((0.22, 0.03, 0.28), groove * 0.7)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    bloom = np.exp(-(((xx - 0.38) / 0.12) ** 2 + ((yy - 0.4) / 0.16) ** 2))
    body = mask_image((S, S), lambda d: d.ellipse((S * 0.17, S * 0.18, S * 0.83, S * 0.92), fill=255))
    c.add(np.array([0.35, 0.38, 0.6], np.float32), bloom * body * 0.45)
    stem = mask_image((S, S), lambda d: d.line([(S * 0.5, S * 0.2), (S * 0.47, S * 0.08)], fill=255, width=int(S * 0.03)))
    c.over((0.3, 0.2, 0.05), stem)
    _draw_leaf(c, S, 0.62, 0.12, 0.24, 0.1, -0.3)
    return c


def _symbol_grapes(S: int) -> Canvas:
    c = Canvas(S, S)
    stem = mask_image((S, S), lambda d: d.line([(S * 0.5, S * 0.26), (S * 0.52, S * 0.08)], fill=255, width=int(S * 0.03)))
    c.over((0.3, 0.22, 0.05), stem)
    _draw_leaf(c, S, 0.66, 0.16, 0.3, 0.15, -0.25)
    rows = [(0.29, [0.32, 0.44, 0.56, 0.68]), (0.42, [0.26, 0.38, 0.5, 0.62, 0.74]), (0.55, [0.32, 0.44, 0.56, 0.68]), (0.68, [0.38, 0.5, 0.62]), (0.8, [0.44, 0.56])]
    for y, xs in rows:
        for i, x in enumerate(xs):
            tint = 0.92 + 0.08 * ((i * 7 + int(y * 100)) % 3)
            _ball(c, S, x, y, 0.072, 0.075, (0.4 * tint, 0.12, 0.55 * tint), outline=(0.08, 0.0, 0.12), spec=0.75, shine=26)
    return c


SYMBOLS = {SEVEN: _symbol_seven, BAR: _symbol_bar, BELL: _symbol_bell, MELON: _symbol_melon,
           GRAPES: _symbol_grapes, PLUM: _symbol_plum, ORANGE: _symbol_orange, LEMON: _symbol_lemon, CHERRY: _symbol_cherry}
_symbol_cache: dict[int, Canvas] = {}


def symbol(sym: int) -> Canvas:
    """512px master of a reel symbol (transparent background)."""
    if sym not in _symbol_cache:
        _symbol_cache[sym] = SYMBOLS[sym](512)
    return _symbol_cache[sym]


def symbol_image(sym: int, size: int) -> tuple[np.ndarray, np.ndarray]:
    img = symbol(sym).image((size, size))
    arr = np.asarray(img, np.float32) / 255.0
    return arr[..., :3], arr[..., 3]


def put_symbol(c: Canvas, sym: int, cx: float, cy: float, size: int, shadow=0.0) -> None:
    rgb, alpha = symbol_image(sym, size)
    x, y = int(cx - size / 2), int(cy - size / 2)
    if shadow > 0:
        c.over((0.0, 0.0, 0.0), blur(alpha, size * 0.03) * shadow, x + int(size * 0.025), y + int(size * 0.04))
    c.over(rgb, alpha, x, y)


# ----------------------------------------------------------------------------- reel strip

def reel_strip() -> Image.Image:
    W, CELL = 256 * SS, 128 * SS
    H = CELL * len(STRIP)
    paper = np.ones((H, W, 3), np.float32) * np.array([0.96, 0.93, 0.84], np.float32)
    fibre = noise(H, W, 6, 21) * 0.04 + noise(H, W, 40, 22) * 0.04
    paper -= fibre[..., None]
    c = Canvas(W, H, (0, 0, 0, 1))
    c.a[..., :3] = paper
    for i, sym in enumerate(STRIP):
        put_symbol(c, sym, W / 2, CELL * i + CELL / 2, int(CELL * 0.9), shadow=0.35)
    return c.image((256, 256 * 8))


# ----------------------------------------------------------------------------- glass panels

THEMES = {
    "gold": {
        "logo": "SUPER DROBNÉ", "banner": "750", "name": "DROBNÉ",
        "bg": (0.03, 0.0, 0.0), "glow": (0.95, 0.22, 0.02), "ray": (0.62, 0.08, 0.02),
        "panel": (0.1, 0.008, 0.0), "accent": (0.9, 0.1, 0.03), "outline": (0.85, 0.06, 0.02),
    },
    "shard": {
        "logo": "JACKPOT 777", "banner": "MEGA", "name": "KEŠULKY",
        "bg": (0.025, 0.0, 0.04), "glow": (0.85, 0.05, 0.72), "ray": (0.5, 0.03, 0.58),
        "panel": (0.08, 0.0, 0.11), "accent": (0.8, 0.05, 0.7), "outline": (0.8, 0.03, 0.62),
    },
}
GOLD = (1.0, 0.76, 0.26)
YELLOW = (1.0, 0.9, 0.22)
CHROME = [(0.0, (0.98, 0.98, 1.0)), (0.4, (0.74, 0.76, 0.84)), (0.5, (0.26, 0.26, 0.34)), (0.6, (0.55, 0.56, 0.7)), (1.0, (0.96, 0.96, 1.0))]
GOLD_RAMP = [(0.0, (1.0, 0.95, 0.6)), (0.45, (1.0, 0.75, 0.2)), (0.55, (0.6, 0.35, 0.05)), (1.0, (1.0, 0.82, 0.35))]
LINE_COLORS = [(1.0, 0.85, 0.15), (0.3, 0.95, 0.3), (1.0, 0.15, 0.1), (0.25, 0.55, 1.0), (1.0, 0.95, 0.85)]


class LampMask:
    """Lamp group/ordinal ids (dilated past each lamp so filtering never mixes ids) and coverage."""

    MARGIN = 14

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.core = np.zeros((h, w, 2), np.int16)
        self.halo = np.zeros((h, w, 2), np.int16)
        self.cov = np.zeros((h, w), np.float32)

    def add(self, group: int, ordinal: int, cov: np.ndarray, strength: float = 1.0) -> None:
        ys, xs = np.nonzero(cov > 0.02)
        if len(ys) == 0:
            return
        m = self.MARGIN
        y0, y1 = max(0, ys.min() - m), min(self.h, ys.max() + m + 1)
        x0, x1 = max(0, xs.min() - m), min(self.w, xs.max() + m + 1)
        local = cov[y0:y1, x0:x1]
        core = self.core[y0:y1, x0:x1]
        core[local > 0.25] = (group, ordinal)
        halo = self.halo[y0:y1, x0:x1]
        grown = (blur((local > 0.02).astype(np.float32), m * 0.5) > 0.01) & (halo[..., 0] == 0)
        halo[grown] = (group, ordinal)
        region = self.cov[y0:y1, x0:x1]
        np.maximum(region, local * strength, out=region)

    def clear(self, cov: np.ndarray) -> None:
        """An opaque printed panel hides whatever lamp was under it."""
        self.cov *= 1.0 - cov
        hide = cov > 0.5
        self.core[hide] = 0
        self.halo[hide] = 0

    def image(self, size: tuple[int, int]) -> Image.Image:
        ids = np.where(self.core[..., :1] > 0, self.core, self.halo)
        lit = ids[..., 0] > 0
        r = np.where(lit, ids[..., 0] * 16 + 8, 0).astype(np.uint8)
        g = np.where(lit, ids[..., 1] * 16 + 8, 0).astype(np.uint8)
        rg = Image.fromarray(np.stack([r, g, np.zeros_like(r)], -1), "RGB").resize(size, Image.NEAREST)
        b = Image.fromarray((np.clip(self.cov, 0, 1) * 255 + 0.5).astype(np.uint8), "L").resize(size, Image.BOX)
        out = np.asarray(rg).copy()
        out[..., 2] = np.asarray(b)
        return Image.fromarray(out, "RGB")


class Panel:
    def __init__(self, w: int, h: int, theme: dict):
        self.w, self.h, self.t = w, h, theme
        self.c = Canvas(w, h, (0.0, 0.0, 0.0, 1.0))
        self.m = LampMask(w, h)

    def box(self, u0, v0, u1, v1):
        return (u0 * self.w, v0 * self.h, u1 * self.w, v1 * self.h)

    def pt(self, u, v):
        return (u * self.w, v * self.h)

    def mask(self, fn) -> np.ndarray:
        return mask_image((self.w, self.h), fn)

    def rect(self, box, radius) -> np.ndarray:
        return self.mask(lambda d: d.rounded_rectangle(box, radius=radius, fill=255))

    def hole(self, box, radius=0.0) -> None:
        cov = self.rect(box, radius)
        self.c.a[..., 3] *= 1.0 - cov
        self.m.clear(cov)

    def fill(self, box, radius, color, lamps_hidden=True) -> np.ndarray:
        cov = self.rect(box, radius)
        self.c.over(color, cov)
        if lamps_hidden:
            self.m.clear(cov)
        return cov

    def frame(self, box, radius, width, ramp=GOLD_RAMP) -> None:
        ring = self.mask(lambda d: d.rounded_rectangle(box, radius=radius, outline=255, width=max(1, int(width))))
        self.metal(ring, ramp, soft=width * 0.4)

    def metal(self, cov: np.ndarray, ramp, soft: float) -> None:
        """Polished metal: a vertical ramp over the shape's own height, lit as a bevel."""
        box = _bounds(cov, max(1.0, soft) * 3)
        if box is None:
            return
        local = cov[box]
        rows = np.nonzero(local.max(1) > 0.01)[0]
        grad = np.zeros(local.shape + (3,), np.float32)
        grad[rows[0]:rows[-1] + 1] = gradient_v(rows[-1] + 1 - rows[0], local.shape[1], ramp)
        lit = _shade(local, (1, 1, 1), max(1.0, soft), (-0.55, -0.65, 0.55), 0.6, 0.5, 12.0, None, 0.35, 2.2)
        self.c.over(np.clip(grad * lit, 0, 1), local, box[1].start, box[0].start)

    def text(self, text, fnt, xy, color, *, outline=(0.05, 0.0, 0.0), stroke=0.0, anchor="mm", lamp=None, ramp=None, glow=None):
        size = (self.w, self.h)
        body = text_mask(size, text, fnt, xy, anchor)
        if glow is not None:
            halo = blur(text_mask(size, text, fnt, xy, anchor, stroke=int(stroke * 2 + fnt.size * 0.06)), fnt.size * 0.12)
            self.c.add(np.array(glow, np.float32), halo * 0.85)
        if stroke > 0:
            ring = text_mask(size, text, fnt, xy, anchor, stroke=int(stroke))
            self.c.over(outline, ring)
        if ramp is not None:
            self.metal(body, ramp, soft=fnt.size * 0.04)
        elif color is not None:
            self.c.over(color, body)
        if lamp is not None:
            full = text_mask(size, text, fnt, xy, anchor, stroke=int(stroke)) if stroke > 0 else body
            self.m.add(lamp[0], lamp[1], full)
        return body

    def bulb(self, centre, r, color, lamp) -> None:
        cx, cy = centre
        m = self.mask(lambda d: d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255))
        rim = self.mask(lambda d: d.ellipse((cx - r * 1.35, cy - r * 1.35, cx + r * 1.35, cy + r * 1.35), fill=255))
        self.metal(rim, GOLD_RAMP, soft=r * 0.2)
        self.c.over(shade(m, color, soft=r * 0.6, spec=0.9, shine=20, ambient=0.55), m)
        self.m.add(lamp[0], lamp[1], m)


def fit_font(path: str, text: str, max_w: float, max_h: float) -> ImageFont.FreeTypeFont:
    size = max_h
    f = font(path, size)
    l, t, r, b = f.getbbox(text)
    scale = min(max_w / max(1, r - l), max_h / max(1, b - t))
    return font(path, size * scale)


def background(p: Panel, centre, rays: int) -> None:
    t = p.t
    yy, xx = np.mgrid[0:p.h, 0:p.w].astype(np.float32)
    cx, cy = p.pt(*centre)
    dx, dy = (xx - cx) / p.h, (yy - cy) / p.h
    dist = np.sqrt(dx * dx + dy * dy)
    glow = np.exp(-dist * 2.4)
    p.c.a[..., :3] = np.array(t["bg"], np.float32) + np.array(t["glow"], np.float32) * (glow * 0.55)[..., None]
    angle = np.arctan2(dy, dx)
    # Sunburst printed rays; each ray is its own lamp for the attract chase.
    sector = (angle + math.pi) / (2 * math.pi) * rays
    index = np.floor(sector).astype(np.int32) % rays
    edge = np.abs(sector - np.floor(sector) - 0.5)
    ray = smooth(0.3, 0.22, edge) * smooth(0.04, 0.14, dist) * np.exp(-dist * 0.9)
    p.c.a[..., :3] += np.array(t["ray"], np.float32) * (ray * 0.55)[..., None]
    # Fine diagonal print texture, as on screen-printed glass.
    lines = (np.sin((xx + yy) * 0.35) > 0.85).astype(np.float32) * 0.035
    p.c.a[..., :3] *= (1.0 - lines)[..., None]
    for i in range(rays):
        p.m.add(RAYS, i % 16, ray * (index == i), strength=0.7)


def star(p: Panel, centre, r, lamp) -> None:
    cx, cy = centre
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    m = p.mask(lambda d: d.polygon(pts, fill=255))
    p.c.over((0.15, 0.05, 0.0), dilate(m, int(r * 0.12)))
    p.c.over(shade(m, (1.0, 0.82, 0.2), soft=r * 0.25, spec=0.9, shine=14, ambient=0.5), m)
    p.m.add(lamp[0], lamp[1], m)


def house(p: Panel, centre, size, lamp) -> None:
    cx, cy = centre
    s = size
    pts = [(cx - s * 0.5, cy + s * 0.45), (cx - s * 0.5, cy - s * 0.05), (cx, cy - s * 0.5), (cx + s * 0.5, cy - s * 0.05), (cx + s * 0.5, cy + s * 0.45)]
    outer = p.mask(lambda d: d.polygon(pts, fill=255))
    p.c.over((0.05, 0.0, 0.0), dilate(outer, int(s * 0.14)))
    p.metal(dilate(outer, int(s * 0.08)), GOLD_RAMP, soft=s * 0.05)
    p.c.over((0.75, 0.06, 0.03), outer)
    door = p.mask(lambda d: d.rectangle((cx - s * 0.12, cy + s * 0.08, cx + s * 0.12, cy + s * 0.45), fill=255))
    p.c.over((1.0, 0.85, 0.3), door)
    p.m.add(lamp[0], lamp[1], outer)


def paytable(p: Panel, box, rows, values, ordinals) -> None:
    t = p.t
    u0, v0, u1, v1 = box
    pb = p.box(*box)
    p.fill(pb, p.h * 0.012, tuple(c * 0.6 for c in t["panel"]))
    p.frame(pb, p.h * 0.012, p.h * 0.004)
    row_h = (v1 - v0 - 0.016) / len(rows)
    f = font(HEAVY, p.h * row_h * 0.62)
    for i, (syms, value, ordinal) in enumerate(zip(rows, values, ordinals)):
        rv0 = v0 + 0.008 + i * row_h
        cy = (rv0 + row_h * 0.5) * p.h
        row = p.rect(p.box(u0 + 0.008, rv0 + 0.002, u1 - 0.008, rv0 + row_h - 0.002), p.h * 0.008)
        p.c.over(tuple(c * 1.6 for c in t["panel"]), row * 0.8)
        p.m.add(PAYROW, ordinal, row)
        size = int(p.h * row_h * 0.92)
        for k, sym in enumerate(syms):
            if sym is not None:
                put_symbol(p.c, sym, (u0 + 0.035 + k * 0.05) * p.w, cy, size, shadow=0.4)
        p.text(str(value), f, ((u1 - 0.018) * p.w, cy), YELLOW, outline=(0.25, 0.02, 0.0), stroke=p.h * 0.004, anchor="rm")


def win_lamps(p: Panel, u, vs, colors, line_to, group, radius=0.012) -> None:
    for i, (v, col) in enumerate(zip(vs, colors)):
        cx, cy = p.pt(u, v)
        line = p.mask(lambda d: d.line([(cx, cy), (line_to * p.w, cy)], fill=255, width=int(p.h * (0.006 if i == len(vs) // 2 else 0.003))))
        p.c.over(col, line * 0.85)
        p.m.add(group, i, line, strength=0.8)
        p.bulb((cx, cy), p.h * radius, col, (group, i))


def top_glass(theme: str) -> tuple[Image.Image, Image.Image]:
    t = THEMES[theme]
    p = Panel(int(1024 * SS * TOP_ASPECT), 1024 * SS, t)
    W, H = p.w, p.h
    background(p, (0.375, 0.6), 20)
    p.frame(p.box(0.01, 0.008, 0.99, 0.992), H * 0.025, H * 0.005)
    p.frame(p.box(0.018, 0.016, 0.982, 0.984), H * 0.02, H * 0.0018)

    # Logo: chrome letters, neon outline, every letter its own neon lamp.
    logo = t["logo"]
    f = fit_font(HEAVY_ITALIC, logo, W * 0.6, H * 0.1)
    cx, cy = p.pt(0.355, 0.085)
    total = f.getlength(logo)
    l, top, r, b = f.getbbox(logo, anchor="ls")
    x0, base = cx - total / 2, cy - (top + b) / 2
    p.c.add(np.array(t["glow"], np.float32), blur(text_mask((W, H), logo, f, (x0, base), "ls", stroke=int(H * 0.02)), H * 0.02) * 0.9)
    p.text(logo, f, (x0, base), None, outline=(0.05, 0.0, 0.0), stroke=H * 0.014, anchor="ls")
    letter = 0
    for i, ch in enumerate(logo):
        if ch == " ":
            continue
        lx = x0 + f.getlength(logo[:i])
        ring = text_mask((W, H), ch, f, (lx, base), "ls", stroke=int(H * 0.009))
        p.c.over(t["outline"], ring)
        p.m.add(LOGO, letter, ring)
        letter += 1
    p.text(logo, f, (x0, base), None, anchor="ls", ramp=CHROME)

    # Star banner under the logo.
    banner = p.box(0.13, 0.152, 0.58, 0.212)
    p.fill(banner, H * 0.03, t["accent"])
    p.frame(banner, H * 0.03, H * 0.004)
    if theme == "gold":
        for i in range(3):
            star(p, p.pt(0.2 + i * 0.075, 0.182), H * 0.024, (STARS, i))
    else:
        for i in range(3):
            put_symbol(p.c, SEVEN, *p.pt(0.2 + i * 0.07, 0.182), int(H * 0.07), shadow=0.5)
            p.m.add(STARS, i, p.mask(lambda d, i=i: d.ellipse(p.box(0.2 + i * 0.07 - 0.024, 0.155, 0.2 + i * 0.07 + 0.024, 0.209), fill=255)))
    p.text(t["banner"], font(HEAVY_ITALIC, H * 0.05), p.pt(0.47, 0.182), YELLOW, outline=(0.2, 0.0, 0.0), stroke=H * 0.005, lamp=(STARS, 3))

    # Coin acceptor window and the two status lamps beside it.
    p.fill(p.box(0.7, 0.025, 0.97, 0.115), H * 0.01, (0.02, 0.02, 0.02))
    p.frame(p.box(0.7, 0.025, 0.97, 0.115), H * 0.01, H * 0.003)
    for i, col in enumerate([(1.0, 0.12, 0.08), (0.2, 0.45, 1.0)]):
        box = p.box(0.715, 0.035 + i * 0.038, 0.77, 0.066 + i * 0.038)
        sq = p.rect(box, H * 0.004)
        p.c.over(shade(sq, col, soft=H * 0.006, ambient=0.6, spec=0.4), sq)
        p.m.add(INDICATOR, i, sq)
    p.hole(p.box(*TOP_COIN), H * 0.006)
    p.frame(p.box(TOP_COIN[0] - 0.004, TOP_COIN[1] - 0.004, TOP_COIN[2] + 0.004, TOP_COIN[3] + 0.004), H * 0.008, H * 0.003, CHROME)
    p.text("10 · 20 · 50 Kč", font(BOLD, H * 0.022), p.pt(0.84, 0.135), (1.0, 0.95, 0.85))

    # Paytables: left the small fruit, right the big wins.
    paytable(p, (0.035, 0.228, 0.355, 0.425),
             [[PLUM] * 3, [ORANGE] * 3, [LEMON] * 3, [CHERRY] * 3, [CHERRY, CHERRY, None]],
             [50, 50, 25, 25, 10], [PLUM, ORANGE, LEMON, CHERRY, 9])
    paytable(p, (0.37, 0.228, 0.69, 0.425),
             [[SEVEN] * 3, [BAR] * 3, [BELL] * 3, [MELON] * 3, [GRAPES] * 3],
             [750, 400, 300, 200, 100], [SEVEN, BAR, BELL, MELON, GRAPES])
    bar = p.box(0.2, 0.435, 0.5, 0.466)
    p.fill(bar, H * 0.016, t["accent"])
    p.frame(bar, H * 0.016, H * 0.003)
    p.text("40 – 750", font(HEAVY, H * 0.026), p.pt(0.35, 0.4505), YELLOW, outline=(0.2, 0.0, 0.0), stroke=H * 0.003, lamp=(LABEL, 0))

    # Reel bay: three windows with gold bezels, win-line lamps either side, hold houses below.
    bay = p.box(0.165, 0.47, 0.585, 0.722)
    p.fill(bay, H * 0.012, gradient_v(H, W, [(0.0, (0.02, 0.0, 0.0)), (0.6, tuple(c * 0.9 for c in t["panel"])), (1.0, (0.02, 0.0, 0.0))]))
    p.frame(bay, H * 0.012, H * 0.005)
    vs = [0.52, 0.5575, 0.595, 0.6325, 0.67]
    win_lamps(p, 0.133, vs, LINE_COLORS, 0.165, WINLINE)
    win_lamps(p, 0.617, vs, LINE_COLORS, 0.585, WINLINE)
    for i, (u, v, w, h) in enumerate(TOP_REELS):
        box = p.box(u - w / 2, v, u + w / 2, v + h)
        p.frame((box[0] - H * 0.008, box[1] - H * 0.008, box[2] + H * 0.008, box[3] + H * 0.008), H * 0.01, H * 0.009)
        p.hole(box, H * 0.004)
        house(p, p.pt(u, 0.752), H * 0.04, (HOUSE, i))
    # Printed centre-line arrows on the bay edges.
    for u, sign in ((0.172, 1), (0.578, -1)):
        cx, cy = p.pt(u, 0.595)
        arrow = p.mask(lambda d: d.polygon([(cx - sign * H * 0.004, cy - H * 0.014), (cx + sign * H * 0.014, cy), (cx - sign * H * 0.004, cy + H * 0.014)], fill=255))
        p.c.over((1.0, 0.9, 0.3), arrow)
        p.m.add(WINLINE, 2, arrow)
    p.text("1 HRA = 5 Kč", font(BOLD, H * 0.02), p.pt(0.09, 0.79), (1.0, 0.92, 0.7))

    # Super Turbo multiplier ladder.
    head = p.box(0.72, 0.165, 0.97, 0.258)
    p.fill(head, H * 0.045, (0.03, 0.0, 0.0))
    p.frame(head, H * 0.045, H * 0.005)
    hf = font(HEAVY_ITALIC, H * 0.034)
    p.text("SUPER", hf, p.pt(0.845, 0.193), None, outline=t["outline"], stroke=H * 0.006, ramp=CHROME, lamp=(LADDER, 10))
    p.text("TURBO", hf, p.pt(0.845, 0.232), None, outline=t["outline"], stroke=H * 0.006, ramp=CHROME, lamp=(LADDER, 10))
    sf = font(HEAVY_ITALIC, H * 0.036)
    for i in range(10):
        level = 9 - i
        v = 0.272 + i * 0.052
        step = p.box(0.745, v + 0.004, 0.925, v + 0.048)
        cov = p.fill(step, H * 0.01, (0.06, 0.0, 0.0))
        p.frame(step, H * 0.01, H * 0.003)
        p.c.over(t["accent"], cov * 0.35)
        p.m.add(LADDER, level, cov)
        p.text("x%d" % (level + 1), sf, p.pt(0.835, v + 0.026), YELLOW, outline=(0.25, 0.0, 0.0), stroke=H * 0.004, lamp=(LADDER, level))
    bracket = p.mask(lambda d: d.line([p.pt(0.945, 0.28), p.pt(0.955, 0.28), p.pt(0.955, 0.79), p.pt(0.945, 0.79)], fill=255, width=int(H * 0.005)))
    p.metal(bracket, GOLD_RAMP, soft=H * 0.002)

    # LED windows: credit (MULTIWIN), bet and bonus.
    lf = font(HEAVY_ITALIC, H * 0.03)
    for box, label in ((TOP_CREDIT, "MULTIWIN"), (TOP_BET, "SÁZKA"), (TOP_BONUS, "BONUS")):
        u0, v0, u1, v1 = box
        bezel = p.box(u0 - 0.012, v0 - 0.012, u1 + 0.012, v1 + 0.012)
        p.fill(bezel, H * 0.012, (0.015, 0.0, 0.0))
        p.frame(bezel, H * 0.012, H * 0.005)
        p.hole(p.box(*box), H * 0.004)
        p.text(label, lf, p.pt((u0 + u1) / 2, v0 - 0.032), None, outline=t["outline"], stroke=H * 0.005, ramp=CHROME, lamp=(LABEL, 1))
    return p.c.image((1024, 1024)), p.m.image((512, 512))


def lower_glass(theme: str) -> tuple[Image.Image, Image.Image]:
    t = THEMES[theme]
    p = Panel(int(512 * SS * LOW_ASPECT), 512 * SS, t)
    W, H = p.w, p.h
    background(p, (0.27, 0.5), 14)
    p.frame(p.box(0.005, 0.02, 0.995, 0.98), H * 0.05, H * 0.01)
    p.frame(p.box(0.008, 0.04, 0.992, 0.96), H * 0.04, H * 0.004)

    # Small win table printed as an LED strip.
    strip = p.box(0.12, 0.07, 0.43, 0.19)
    p.fill(strip, H * 0.02, (0.01, 0.0, 0.0))
    p.frame(strip, H * 0.02, H * 0.008)
    sf = font(CONDENSED, H * 0.085)
    for i, value in enumerate(["125", "250", "500", "1000"]):
        p.text(value, sf, p.pt(0.155 + i * 0.077, 0.13), (1.0, 0.12, 0.05), outline=(0.2, 0.0, 0.0), stroke=H * 0.004, lamp=(INFO, i))

    bay = p.box(0.135, 0.215, 0.415, 0.725)
    p.fill(bay, H * 0.03, gradient_v(H, W, [(0.0, (0.02, 0.0, 0.0)), (0.5, tuple(c * 0.9 for c in t["panel"])), (1.0, (0.02, 0.0, 0.0))]))
    p.frame(bay, H * 0.03, H * 0.01)
    win_lamps(p, 0.105, [0.33, 0.47, 0.61], [LINE_COLORS[0], LINE_COLORS[2], LINE_COLORS[3]], 0.135, LOWLINE, radius=0.026)
    for u, v, w, h in LOW_REELS:
        box = p.box(u - w / 2, v, u + w / 2, v + h)
        p.frame((box[0] - H * 0.016, box[1] - H * 0.016, box[2] + H * 0.016, box[3] + H * 0.016), H * 0.02, H * 0.018)
        p.hole(box, H * 0.008)

    # x2 RISK bar.
    risk = p.box(0.15, 0.77, 0.41, 0.93)
    cov = p.fill(risk, H * 0.08, (0.04, 0.0, 0.0))
    p.c.over(t["accent"], cov * 0.5)
    p.frame(risk, H * 0.08, H * 0.012)
    p.m.add(RISKBAR, 0, cov, strength=0.6)
    p.text("x2 RISK", font(HEAVY_ITALIC, H * 0.11), p.pt(0.28, 0.85), None, outline=t["outline"], stroke=H * 0.012, ramp=CHROME, lamp=(RISKBAR, 0))
    # 18+ roundel.
    cx, cy = p.pt(0.055, 0.82)
    r = H * 0.075
    p.c.over((0.95, 0.95, 0.95), p.mask(lambda d: d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)))
    p.c.over((0.85, 0.05, 0.05), p.mask(lambda d: d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=int(H * 0.014))))
    p.text("18+", font(HEAVY, H * 0.06), (cx, cy), (0.05, 0.05, 0.05))

    # Risk ladder: fruit column and doubling values.
    ladder = p.box(0.45, 0.06, 0.975, 0.9)
    p.fill(ladder, H * 0.03, tuple(c * 0.6 for c in t["panel"]))
    p.frame(ladder, H * 0.03, H * 0.01)
    rows = 8
    fruit = [CHERRY, LEMON, ORANGE, PLUM, GRAPES, MELON, BELL, SEVEN]
    vf = font(CONDENSED, H * 0.075)
    for i in range(rows):
        level = rows - 1 - i
        v0 = 0.075 + i * 0.102
        row = p.rect(p.box(0.46, v0 + 0.006, 0.965, v0 + 0.094), H * 0.02)
        p.c.over(tuple(c * 1.8 for c in t["panel"]), row * 0.7)
        p.m.add(RISK, level, row)
        put_symbol(p.c, fruit[level], *p.pt(0.49, v0 + 0.05), int(H * 0.095), shadow=0.4)
        base = 10 * 2 ** level
        for k, value in enumerate([base, base * 5 // 2, base * 5]):
            p.text(str(value), vf, p.pt(0.62 + k * 0.13, v0 + 0.05), YELLOW if k < 2 else (1.0, 0.55, 0.15), outline=(0.2, 0.0, 0.0), stroke=H * 0.005)
    p.text("Hazardní hra · zákaz účasti osob mladších 18 let", font(BOLD, H * 0.04), p.pt(0.71, 0.94), (1.0, 0.92, 0.8))
    return p.c.image((1024, 512)), p.m.image((512, 256))


BUTTONS = ["VÝPLATA", "SÁZKA", "DRŽ", "DRŽ", "DRŽ", "RISK", "START", "INFO"]


def misc(theme: str) -> Image.Image:
    """Button caps (row 0), maker badge, theme sticker and cash-box plate. Final 1024x512."""
    t = THEMES[theme]
    W, H = 1024 * SS, 512 * SS
    c = Canvas(W, H, (0.05, 0.05, 0.05, 1.0))
    u = 128 * SS
    for i, label in enumerate(BUTTONS):
        cx, cy = i * u + u / 2, u / 2
        disc = mask_image((W, H), lambda d: d.ellipse((cx - u * 0.47, cy - u * 0.47, cx + u * 0.47, cy + u * 0.47), fill=255))
        c.over(shade(disc, (0.9, 0.9, 0.9), soft=u * 0.18, spec=0.7, shine=18, ambient=0.75, rim=0.4), disc)
        c.over((0.08, 0.06, 0.06), text_mask((W, H), label, fit_font(HEAVY, label, u * 0.66, u * 0.2), (cx, cy + u * 0.02)))
        if label == "DRŽ":
            c.over((0.08, 0.06, 0.06), text_mask((W, H), str(i - 1), font(HEAVY, u * 0.16), (cx, cy + u * 0.24)))
    # Maker badge: chrome oval, black field.
    bx0, by0, bx1, by1 = 0, u, 384 * SS, 2 * u
    oval = mask_image((W, H), lambda d: d.ellipse((bx0 + 8 * SS, by0 + 10 * SS, bx1 - 8 * SS, by1 - 10 * SS), fill=255))
    inner = mask_image((W, H), lambda d: d.ellipse((bx0 + 22 * SS, by0 + 22 * SS, bx1 - 22 * SS, by1 - 22 * SS), fill=255))
    ramp = np.zeros((H, W, 3), np.float32)
    ramp[by0:by1] = gradient_v(by1 - by0, W, CHROME)
    c.over(ramp * shade(oval, (1, 1, 1), soft=6 * SS, ambient=0.7), oval)
    c.over((0.02, 0.02, 0.025), inner)
    c.over(ramp, text_mask((W, H), "KOVOHRA", font(HEAVY_ITALIC, 58 * SS), ((bx0 + bx1) / 2, (by0 + by1) / 2 - 6 * SS)))
    c.over((0.8, 0.8, 0.82), text_mask((W, H), "BRNO", font(BOLD, 18 * SS), ((bx0 + bx1) / 2, by1 - 34 * SS)))
    # Theme sticker on the cash door: the prying hint as a service warning.
    sx0, sy0, sx1, sy1 = 384 * SS, u, 640 * SS, 384 * SS
    c.over((1.0, 0.83, 0.1), mask_image((W, H), lambda d: d.rectangle((sx0, sy0, sx1, sy1), fill=255)))
    c.over((0.85, 0.05, 0.03), mask_image((W, H), lambda d: d.rectangle((sx0 + 10 * SS, sy0 + 10 * SS, sx1 - 10 * SS, sy1 - 10 * SS), outline=255, width=8 * SS)))
    cx = (sx0 + sx1) / 2
    c.over((0.85, 0.05, 0.03), text_mask((W, H), "POZOR!", font(HEAVY, 46 * SS), (cx, sy0 + 52 * SS)))
    c.over((0.05, 0.05, 0.05), text_mask((W, H), "PÁČ ZÁMKY", font(HEAVY, 34 * SS), (cx, sy0 + 104 * SS)))
    c.over(t["accent"], mask_image((W, H), lambda d: d.rectangle((sx0 + 18 * SS, sy0 + 140 * SS, sx1 - 18 * SS, sy0 + 196 * SS), fill=255)))
    c.over((1, 1, 1), text_mask((W, H), t["name"], fit_font(HEAVY, t["name"], 200 * SS, 40 * SS), (cx, sy0 + 168 * SS)))
    c.over((0.05, 0.05, 0.05), text_mask((W, H), "uvnitř", font(BOLD, 26 * SS), (cx, sy0 + 222 * SS)))
    # Brushed steel cash-box plate.
    px0, py0, px1, py1 = 640 * SS, u, 1024 * SS, 224 * SS
    plate = mask_image((W, H), lambda d: d.rounded_rectangle((px0 + 6 * SS, py0 + 6 * SS, px1 - 6 * SS, py1 - 6 * SS), radius=10 * SS, fill=255))
    streaks = np.repeat(noise(H, 1, 2, 6), W, axis=1)
    brushed = (0.6 + 0.12 * noise(H, W, 1.5, 5) + 0.08 * streaks)[..., None] * np.array([1.0, 1.0, 1.04], np.float32)
    c.over(np.clip(brushed, 0, 1), plate)
    c.over((0.12, 0.12, 0.13), text_mask((W, H), "POKLADNA", font(HEAVY, 46 * SS), ((px0 + px1) / 2, (py0 + py1) / 2)))
    return c.image((1024, 512))


def glass_atlas(theme: str) -> None:
    top, top_mask = top_glass(theme)
    low, low_mask = lower_glass(theme)
    atlas = Image.new("RGBA", (1024, 2048), (0, 0, 0, 255))
    atlas.paste(top, (0, 0))
    atlas.paste(low, (0, 1024))
    atlas.paste(misc(theme), (0, 1536))
    atlas.save(OUT / f"glass_{theme}.png", optimize=True)
    mask = Image.new("RGB", (512, 1024), (0, 0, 0))
    mask.paste(top_mask, (0, 0))
    mask.paste(low_mask, (0, 512))
    mask.save(OUT / f"glass_{theme}_mask.png", optimize=True)


# ----------------------------------------------------------------------------- run

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    reel_strip().save(OUT / "reel_strip.png", optimize=True)
    for theme in THEMES:
        glass_atlas(theme)


if __name__ == "__main__":
    main()
