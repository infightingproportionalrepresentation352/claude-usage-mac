#!/usr/bin/env python3
"""Render the macOS AppIcon set.

The mark is the Stream Deck plugin's: dark rounded square, coral ring, white
"C". Ported from make_icons.py in claude-usage-streamdeck-plugin rather than
upscaling its shipped 512px PNG, so 1024 is actually sharp.

Output is committed, so CI needs neither Python nor Pillow. Rerun this only when
the mark changes:

    python packaging/make-appicon.py
"""
import json
import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Sources", "MenuBarApp", "Assets.xcassets", "AppIcon.appiconset",
)

FONTS = [
    "C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "arialbd.ttf",
]

BG = (15, 18, 22, 255)      # #0f1216
TRACK = (35, 40, 47, 255)   # #23282f
CORAL = (217, 119, 87, 255) # #d97757  (Claude accent)
WHITE = (245, 245, 245, 255)

SS = 4          # supersample factor, downscaled with LANCZOS
RING_PCT = 0.72

# macOS icon grid: artwork fills 824 of a 1024 canvas, with a 22.5% corner
# radius. Without the margin the icon sits visibly larger than every native one
# beside it in Finder.
CONTENT_RATIO = 824 / 1024
CORNER_RATIO = 0.225


def _font(px):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def make(size, glyph=True):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    content = s * CONTENT_RATIO
    origin = (s - content) / 2
    d.rounded_rectangle(
        [origin, origin, origin + content - 1, origin + content - 1],
        radius=int(content * CORNER_RATIO),
        fill=BG,
    )

    pad = content * 0.10
    stroke = max(2 * SS, int(content * 0.085))
    box = [
        origin + pad + stroke,
        origin + pad + stroke,
        origin + content - pad - stroke,
        origin + content - pad - stroke,
    ]
    d.arc(box, start=0, end=360, fill=TRACK, width=stroke)
    d.arc(box, start=-90, end=-90 + int(360 * RING_PCT), fill=CORAL, width=stroke)

    if glyph:
        font = _font(int(content * 0.46))
        bbox = d.textbbox((0, 0), "C", font=font)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text(((s - w) / 2 - bbox[0], (s - h) / 2 - bbox[1]), "C", font=font, fill=WHITE)

    return img.resize((size, size), Image.LANCZOS)


# (logical size, scale). macOS wants every one of these.
VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
            (256, 1), (256, 2), (512, 1), (512, 2)]


def main():
    os.makedirs(OUT, exist_ok=True)
    images = []

    for logical, scale in VARIANTS:
        pixels = logical * scale
        name = f"icon_{logical}x{logical}{'@2x' if scale == 2 else ''}.png"
        # At 16pt the ring alone reads; a "C" inside it is mush either way, and
        # dropping it keeps the silhouette legible in a Finder list.
        make(pixels, glyph=pixels >= 32).save(os.path.join(OUT, name))
        images.append({
            "size": f"{logical}x{logical}",
            "idiom": "mac",
            "filename": name,
            "scale": f"{scale}x",
        })
        print(f"  {name}  ({pixels}px)")

    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}},
                  f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    print("Rendering AppIcon ->", OUT)
    main()
    print("done.")
