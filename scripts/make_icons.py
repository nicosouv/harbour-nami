#!/usr/bin/env python3
"""Cuts the app icon out of its artwork and writes every size the RPM ships.

    docker compose run --rm icons

Reads icons/new-harbour-nami.jpg, which is a rendering of the leaf on a dark
background, and writes a transparent PNG at 86, 108, 128 and 172 plus a
master beside them. Changing the icon is a matter of replacing the source
and running this again.

The interesting part is the matte. A threshold alone leaves a dark rim: the
pixels along the edge are the leaf blended with the navy behind it, and
dropping the background without accounting for that keeps its colour in
them. So the alpha is a soft ramp on brightness, and every partly
transparent pixel has its true colour solved back out of the blend.
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: run this through `docker compose run --rm icons`")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "icons" / "new-harbour-nami.jpg"
SIZES = (86, 108, 128, 172)

# The brightness ramp that separates artwork from background. The navy tops
# out around 55 and the leaf never goes below 180, so there is room to put a
# soft edge between them without catching either.
LO, HI = 60, 115


def matte(image):
    """The artwork on transparency, with the background's colour taken back
    out of the edge pixels."""
    width, height = image.size
    px = image.load()

    # Averaged over the four corners rather than read from one pixel: the
    # background carries a slight vignette
    corners = [px[x, y] for x in (2, width - 3) for y in (2, height - 3)]
    bg = tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))

    out = Image.new("RGBA", image.size)
    op = out.load()
    for y in range(height):
        for x in range(width):
            p = px[x, y]
            value = max(p)
            if value <= LO:
                op[x, y] = (0, 0, 0, 0)
                continue
            if value >= HI:
                op[x, y] = (p[0], p[1], p[2], 255)
                continue

            alpha = (value - LO) / (HI - LO)
            colour = tuple(
                min(255, max(0, int(round((p[i] - (1 - alpha) * bg[i]) / alpha))))
                for i in range(3))
            op[x, y] = colour + (int(round(alpha * 255)),)

    return out


def main():
    if not SOURCE.exists():
        sys.exit(f"no artwork at {SOURCE}")

    cut = matte(Image.open(SOURCE).convert("RGB"))

    # Square, centred on the artwork, so the leaf reaches the edges of the
    # canvas the way the icon it replaces does
    box = cut.getbbox()
    side = max(box[2] - box[0], box[3] - box[1])
    cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    master = cut.crop((cx - side // 2, cy - side // 2,
                       cx - side // 2 + side, cy - side // 2 + side))

    master.save(ROOT / "icons" / "harbour-nami.png")
    print(f"master {master.size[0]}x{master.size[1]}")

    for size in SIZES:
        target = ROOT / "icons" / f"{size}x{size}" / "harbour-nami.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.LANCZOS).save(target)
        print(f"{size}x{size}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
