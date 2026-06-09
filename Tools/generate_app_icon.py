#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "MDViewer" / "Assets.xcassets" / "AppIcon.appiconset"

SLOTS = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
]


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def interpolate(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(interpolate(top[i], bottom[i], t) for i in range(3))
        draw.line((0, y, size, y), fill=(*color, 255))
    return image


def draw_icon(size: int) -> Image.Image:
    scale = 4
    canvas_size = size * scale
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    bg = gradient(canvas_size, (37, 99, 145), (20, 42, 66))
    bg_mask = rounded_mask(canvas_size, round(canvas_size * 0.22))
    shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    inset = round(canvas_size * 0.06)
    shadow_draw.rounded_rectangle(
        (inset, inset, canvas_size - inset, canvas_size - inset),
        radius=round(canvas_size * 0.2),
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(canvas_size * 0.035)))
    image.alpha_composite(shadow)
    image.paste(bg, (0, 0), bg_mask)

    draw = ImageDraw.Draw(image)
    pad = round(canvas_size * 0.18)
    page = (
        pad,
        round(canvas_size * 0.14),
        canvas_size - pad,
        round(canvas_size * 0.86),
    )
    page_radius = round(canvas_size * 0.055)
    draw.rounded_rectangle(page, radius=page_radius, fill=(248, 250, 252, 255))

    fold = round(canvas_size * 0.17)
    x2, y1 = page[2], page[1]
    draw.polygon(
        [(x2 - fold, y1), (x2, y1), (x2, y1 + fold)],
        fill=(211, 222, 233, 255),
    )
    draw.line(
        [(x2 - fold, y1), (x2, y1 + fold)],
        fill=(180, 196, 212, 255),
        width=max(1, round(canvas_size * 0.008)),
    )

    accent = (21, 99, 173, 255)
    ink = (31, 41, 55, 255)
    muted = (104, 116, 132, 255)
    left = page[0] + round(canvas_size * 0.09)
    top = page[1] + round(canvas_size * 0.18)
    line_height = round(canvas_size * 0.058)
    stroke = max(1, round(canvas_size * 0.018))

    hash_width = max(1, round(canvas_size * 0.016))
    hash_left = left + round(canvas_size * 0.012)
    hash_right = left + round(canvas_size * 0.118)
    hash_top = top - round(canvas_size * 0.052)
    hash_bottom = top + round(canvas_size * 0.066)
    draw.line(
        [(hash_left + round(canvas_size * 0.022), hash_bottom),
         (hash_left + round(canvas_size * 0.042), hash_top)],
        fill=accent,
        width=hash_width,
    )
    draw.line(
        [(hash_right - round(canvas_size * 0.042), hash_bottom),
         (hash_right - round(canvas_size * 0.022), hash_top)],
        fill=accent,
        width=hash_width,
    )
    for y in (top - round(canvas_size * 0.018), top + round(canvas_size * 0.03)):
        draw.line(
            [(hash_left, y), (hash_right, y)],
            fill=accent,
            width=hash_width,
        )

    for row in range(4):
        y = top + round(canvas_size * 0.14) + row * line_height
        length = [0.46, 0.36, 0.5, 0.28][row]
        draw.rounded_rectangle(
            (
                left,
                y,
                left + round(canvas_size * length),
                y + max(2, round(canvas_size * 0.016)),
            ),
            radius=max(1, round(canvas_size * 0.008)),
            fill=ink if row == 0 else muted,
        )

    chevron_y = page[3] - round(canvas_size * 0.16)
    chevron_x = page[0] + round(canvas_size * 0.5)
    arrow = round(canvas_size * 0.068)
    draw.line(
        [(chevron_x - arrow, chevron_y - arrow // 2), (chevron_x, chevron_y + arrow // 2)],
        fill=accent,
        width=stroke,
    )
    draw.line(
        [(chevron_x + arrow, chevron_y - arrow // 2), (chevron_x, chevron_y + arrow // 2)],
        fill=accent,
        width=stroke,
    )

    return image.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    images = []

    for points, scale in SLOTS:
        pixels = points * scale
        filename = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        draw_icon(pixels).save(ICONSET / filename)
        images.append(
            {
                "filename": filename,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{points}x{points}",
            }
        )

    (ICONSET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
