#!/usr/bin/env python3
"""Centre participant photos on their faces for use as pixel-art reference.

Detects a face with OpenCV's YuNet detector, levels the eyes and crops a
square that frames hairline-to-chin with the eyes at a fixed position, then
writes one centred crop per photo plus a labelled contact sheet. Output size
defaults to 192 (the 3x atlas cell), so a crop lines up with the 64x64 cell
the painted faces used (eyes at ~45% height).

Requirements: opencv-python-headless (>= 4.10 for FaceDetectorYN).

    python3 tools/faces/center_faces.py --out centered_faces          # all photos
    python3 tools/faces/center_faces.py --single homeless_pictures/hero.png
    python3 tools/faces/center_faces.py --size 64 --out /tmp/f

The YuNet model is bundled at tools/faces/face_detection_yunet_2023mar.onnx and
re-downloaded on first run if it is missing.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
PICS = PROJECT / "homeless_pictures"
MODEL = HERE / "face_detection_yunet_2023mar.onnx"
MODEL_URL = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"

# Eyes land at 45% of the crop height; hairline ~2%, chin ~98% for a typical face.
EYE_FRACTION = 0.45
# Crop side = this multiple of the interocular distance.
SIDE_EYE_RATIO = 3.0
SCORE_THRESHOLD = 0.5


def _ensure_model() -> Path:
    if not MODEL.exists():
        import urllib.request
        print(f"downloading YuNet model to {MODEL}")
        urllib.request.urlretrieve(MODEL_URL, MODEL)
    return MODEL


def _detector(size: tuple[int, int]):
    det = cv2.FaceDetectorYN.create(
        str(_ensure_model()), "", (size[0], size[1]),
        SCORE_THRESHOLD, 0.3, 100,
    )
    det.setInputSize(size)
    return det


def detect_face(image: np.ndarray, det) -> tuple[np.ndarray, np.ndarray] | None:
    """Return (eyes(2x2, left-right), score) of the best face, or None."""
    _, faces = det.detect(image)
    if faces is None or len(faces) == 0:
        return None
    best = max(faces, key=lambda f: f[14])
    landmarks = best[4:14].reshape(5, 2)
    eyes = landmarks[:2][np.argsort(landmarks[:2, 0])]  # left, right by x
    return eyes, best[14]


def _level_and_crop(image: np.ndarray, eyes: np.ndarray, size: int) -> np.ndarray | None:
    """Rotate so the eyes are level, then crop a centred square around the face."""
    (x0, y0), (x1, y1) = eyes[0], eyes[1]
    mid = np.array([(x0 + x1) / 2.0, (y0 + y1) / 2.0])
    d = float(np.hypot(x1 - x0, y1 - y0))
    if d < 1.0:
        return None
    side = SIDE_EYE_RATIO * d
    angle = math.degrees(math.atan2(y1 - y0, x1 - x0))

    pad = int(math.ceil(side))
    bordered = cv2.copyMakeBorder(image, pad, pad, pad, pad, cv2.BORDER_REFLECT)
    # Rotate around the eye midpoint in the *bordered* frame, so that point stays
    # fixed under the warp and the crop below is centred on it.
    matrix = cv2.getRotationMatrix2D((float(mid[0]) + pad, float(mid[1]) + pad), -angle, 1.0)
    rotated = cv2.warpAffine(bordered, matrix, (bordered.shape[1], bordered.shape[0]), flags=cv2.INTER_LINEAR)

    # The rotation centre (eye midpoint) is invariant under the rotation; now level.
    cx = mid[0] + pad
    cy = mid[1] + pad
    left = int(round(cx - side / 2.0))
    top = int(round(cy - EYE_FRACTION * side))
    crop = rotated[top:top + int(round(side)), left:left + int(round(side))]
    if crop.size == 0:
        return None
    return cv2.resize(crop, (size, size), interpolation=cv2.INTER_AREA)


def center(image: np.ndarray, det, size: int) -> np.ndarray | None:
    found = detect_face(image, det)
    if found is None:
        return None
    eyes, _score = found
    return _level_and_crop(image, eyes, size)


def _contact_sheet(crops: list[tuple[str, np.ndarray]], size: int) -> np.ndarray:
    cols = 6
    rows = math.ceil(len(crops) / cols)
    sheet = np.full((rows * size, cols * size, 3), 40, dtype=np.uint8)
    for i, (name, crop) in enumerate(crops):
        r, c = divmod(i, cols)
        sheet[r * size:(r + 1) * size, c * size:(c + 1) * size] = crop
        cv2.putText(sheet, name, (c * size + 4, r * size + size - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1, cv2.LINE_AA)
    return sheet


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", help="photo files; default: every image in homeless_pictures/")
    parser.add_argument("--out", default="homeless_pictures_centered", help="output directory")
    parser.add_argument("--size", type=int, default=192, help="output crop size in pixels (square)")
    parser.add_argument("--single", help="render one photo to <out>/preview.png and stop")
    args = parser.parse_args()

    if args.single:
        paths = [Path(args.single)]
    elif args.paths:
        paths = [Path(p) for p in args.paths]
    else:
        paths = sorted(p for p in PICS.iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg"))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    det = _detector((320, 320))
    crops: list[tuple[str, np.ndarray]] = []
    missed: list[str] = []
    for path in paths:
        image = cv2.imread(str(path))
        if image is None:
            print(f"skip {path.name}: cannot read", file=sys.stderr)
            continue
        det.setInputSize((image.shape[1], image.shape[0]))
        crop = center(image, det, args.size)
        if crop is None:
            missed.append(path.name)
            print(f"MISS {path.name}: no face detected", file=sys.stderr)
            continue
        cv2.imwrite(str(out / (path.stem + ".centered.png")), crop)
        crops.append((path.stem, crop))
        print(f"ok {path.name} -> {path.stem}.centered.png")

    if args.single:
        if crops:
            cv2.imwrite(str(out / "preview.png"), crops[0][1])
        return 0 if crops else 1

    if crops:
        cv2.imwrite(str(out / "contact_sheet.png"), _contact_sheet(crops, args.size))
    print(f"\n{len(crops)} centred, {len(missed)} missed -> {out}")
    if missed:
        print("missed: " + ", ".join(missed))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
