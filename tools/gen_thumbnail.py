#!/usr/bin/env python3
"""Generate thumbnail.png — the mod-portal card, by laying Land Title
Registry's drop shadow behind the MTS mark.

The card itself was drawn by hand, not by a script, so this tool does not
redraw it: it reads the untouched original from tools/thumbnail-flat.png,
recovers the ink (the three mark letters and the subtitle) as a mask with
per-pixel coverage, and re-composites it over a ground that carries the
shadow. Everything but the shadow therefore comes through byte for byte —
the letters keep their exact anti-aliased edges, and re-running the tool
reproduces the same output rather than stacking a second shadow.

The shadow is LTR's, unchanged (see land-title-registry/tools/gen_thumbnail.py):
a centred black halo, no offset to one side. Black rather than white because
the ground is dark, so the halo sinks into it and reads as depth beneath the
glyphs instead of a rim drawn around them. Strength lifts the blur's
midtones; past roughly 2 the halo stops falling off and becomes a plate.

Only the mark is haloed. The subtitle is left flat, as it is on LTR's card.

Run from the repo root:  python3 tools/gen_thumbnail.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
BG = (43, 43, 43)
FRAME = (26, 26, 26)
FRAME_INSET = 16
FRAME_WIDTH = 12

HALO = (0, 0, 0)
HALO_RADIUS = 8
HALO_STRENGTH = 1.5

# The card's ink, sampled from the original. The mark carries the same three
# team colors the mod uses for teams 1-3; the subtitle is plain grey.
MARK_COLORS = ((230, 57, 70), (245, 184, 46), (74, 158, 255))
SUBTITLE_COLOR = (212, 212, 212)

# Squared per-channel slack allowed when deciding an anti-aliased pixel really
# is a blend of the ground and one ink. Pixels further off every ink's line
# than this are ground, not ink.
INK_TOLERANCE = 12 ** 2


def ground_image():
    """The card with its ink removed: charcoal, and the frame band over it."""
    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)
    far = SIZE - FRAME_INSET
    d.rectangle([FRAME_INSET, FRAME_INSET, far, far], outline=FRAME, width=FRAME_WIDTH)
    return img


def mark_coverage(card, ground):
    """How much of each pixel the MARK covers, 0-255.

    An ink pixel is the ground blended toward one ink color, so projecting it
    onto each ink's line and keeping the closest fit recovers both which ink
    drew it and how far the blend went. The subtitle is recovered too, only to
    be dropped — it is what keeps grey anti-aliasing from being mistaken for a
    faint edge of the blue S and picking up a shadow it should not have.
    """
    cp, gp = card.load(), ground.load()
    mask = Image.new("L", (SIZE, SIZE), 0)
    mp = mask.load()

    inks = MARK_COLORS + (SUBTITLE_COLOR,)
    for y in range(SIZE):
        for x in range(SIZE):
            pixel, base = cp[x, y], gp[x, y]
            if pixel == base:
                continue
            best = None
            for ink in inks:
                span = tuple(ink[i] - base[i] for i in range(3))
                den = sum(v * v for v in span)
                if den == 0:
                    continue
                t = sum((pixel[i] - base[i]) * span[i] for i in range(3)) / den
                t = min(1.0, max(0.0, t))
                off = sum((pixel[i] - (base[i] + t * span[i])) ** 2 for i in range(3))
                if best is None or off < best[0]:
                    best = (off, t, ink)
            if best is None:
                continue
            off, t, ink = best
            if off <= INK_TOLERANCE and ink in MARK_COLORS:
                mp[x, y] = round(t * 255)
    return mask


def halo_for(mask):
    """A blurred copy of the mark's coverage, to sit directly behind it."""
    halo = mask.filter(ImageFilter.GaussianBlur(HALO_RADIUS))
    return halo.point(lambda v: min(255, int(v * HALO_STRENGTH)))


def build(root):
    card = Image.open(root / "tools/thumbnail-flat.png").convert("RGB")
    if card.size != (SIZE, SIZE):
        raise SystemExit(f"expected a {SIZE}x{SIZE} card, got {card.size[0]}x{card.size[1]}")

    ground = ground_image()
    mask = mark_coverage(card, ground)
    halo = halo_for(mask)

    # Halo under the ink, ink over it: darkening the ground by the halo and
    # then letting the ink sit back on top is the same composite the LTR
    # script builds by pasting layers, written as a delta so every pixel the
    # halo does not reach stays exactly as the original drew it.
    out = card.copy()
    op = out.load()
    cp, gp, mp, hp = card.load(), ground.load(), mask.load(), halo.load()
    for y in range(SIZE):
        for x in range(SIZE):
            shade = hp[x, y]
            if shade == 0:
                continue
            behind = (255 - mp[x, y]) / 255  # the ground still showing through
            drop = shade / 255 * behind
            base, pixel = gp[x, y], cp[x, y]
            op[x, y] = tuple(
                max(0, round(pixel[i] - (base[i] - HALO[i]) * drop)) for i in range(3)
            )
    return out


def main():
    root = Path(__file__).resolve().parent.parent
    out = root / "thumbnail.png"
    build(root).save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
