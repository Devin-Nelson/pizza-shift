"""Pizza box print art (the user, 2026-10-23: realistic boxes after their
photos of real box blanks). Our brand only (Config.Brand colours, the
Dominus wordmark): the photos give what a box carries, not its look. Writes
each design's lid and side-band PNGs for tools/blender/pizza_box.py.

    python tools/blender/box_art.py

Needs Pillow (the system Python has it) and the Windows fonts.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.expanduser("~"), "Roblox-Assets", "models", "dominus", "pizza_box")
FONTS = "C:/Windows/Fonts/"
RED, CHARCOAL, CREAM, GOLD = (214, 48, 39), (38, 40, 46), (250, 240, 225), (255, 190, 60)
WHITE_BOARD, KRAFT = (238, 235, 226), (186, 146, 102)
N = 1024  # the lid, square


def font(name, size):
    return ImageFont.truetype(FONTS + name, size)


def centred(d, y, text, f, fill, x=N / 2):
    w = d.textlength(text, font=f)
    d.text((x - w / 2, y), text, font=f, fill=fill)


def slice_icon(d, cx, cy, r, crust, cheese, pep):
    """A pizza slice pointing down: the brand's mark (no tiles, no dots-on-a-domino)."""
    top = cy - r * 0.7
    pts = [(cx - r * 0.75, top), (cx + r * 0.75, top), (cx, cy + r * 0.85)]
    d.polygon(pts, fill=cheese)
    d.rounded_rectangle((cx - r * 0.82, top - r * 0.22, cx + r * 0.82, top + r * 0.06), radius=r * 0.12, fill=crust)
    for px, py, pr in ((-0.25, 0.0, 0.13), (0.22, -0.05, 0.12), (0.0, 0.38, 0.11)):
        d.ellipse((cx + px * r - pr * r, cy + py * r - pr * r, cx + px * r + pr * r, cy + py * r + pr * r), fill=pep)


def emblem(d, cx, cy, r, ring, disc, crust, cheese, pep):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ring)
    d.ellipse((cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86), fill=disc)
    slice_icon(d, cx, cy + r * 0.05, r * 0.6, crust, cheese, pep)


def lid(design):
    board, ink, accent = design["board"], design["ink"], design["accent"]
    img = Image.new("RGB", (N, N), board)
    d = ImageDraw.Draw(img)
    # A frame inset from the edge, with the four corners notched like the die-cut lid.
    m, t = 46, 22
    d.rectangle((m, m, N - m, N - m), outline=accent, width=t)
    for x, y in ((m, m), (N - m, m), (m, N - m), (N - m, N - m)):
        d.ellipse((x - 34, y - 34, x + 34, y + 34), fill=board)
    emblem(d, N / 2, 330, 175, accent, design["disc"], GOLD if design["disc"] != GOLD else CHARCOAL, (250, 214, 120), RED if design["disc"] != RED else CHARCOAL)
    centred(d, 528, "DOMINUS", font("impact.ttf", 168), accent)
    centred(d, 712, "PIZZA", font("impact.ttf", 92), ink)
    centred(d, 826, "HAND-TOSSED  \u2022  FRESH DOUGH  \u2022  BAKED TO ORDER", font("bahnschrift.ttf", 34), ink)
    centred(d, 884, "CARRYOUT & DELIVERY", font("arialbd.ttf", 30), accent)
    # The flap end (the box's front, toward the bottom of the image): "THIS SIDE UP", a date box.
    d.text((96, 108), "THIS SIDE UP", font=font("arialbd.ttf", 26), fill=ink)
    d.polygon([(104, 150), (124, 150), (114, 132)], fill=ink)
    d.rectangle((N - 290, 96, N - 96, 150), outline=ink, width=3)
    d.text((N - 282, 108), "DATE", font=font("arialbd.ttf", 26), fill=ink)
    return img


def band(design, size_word):
    """The side walls: one strip, the wordmark and the size."""
    w, h = 1024, 128
    img = Image.new("RGB", (w, h), design["band"])
    d = ImageDraw.Draw(img)
    fg = design["bandInk"]
    d.text((40, 22), "DOMINUS PIZZA", font=font("impact.ttf", 76), fill=fg)
    s = size_word.upper() + " BOX" if size_word else "HOT & FRESH"  # the game uses one band for every size
    f = font("impact.ttf", 64)
    d.text((w - 40 - d.textlength(s, font=f), 30), s, font=f, fill=fg)
    return img


DESIGNS = {
    # White board, red and charcoal print (the user's first and third photos are printed white board).
    "classic": {"board": WHITE_BOARD, "ink": CHARCOAL, "accent": RED, "disc": CHARCOAL, "band": RED, "bandInk": (255, 255, 255)},
    # Plain corrugated kraft, one-colour red print.
    "kraft": {"board": KRAFT, "ink": (120, 30, 26), "accent": RED, "disc": KRAFT, "band": KRAFT, "bandInk": RED},
    # A bold red lid, cream type; white walls with a charcoal band.
    "bold": {"board": RED, "ink": CREAM, "accent": CREAM, "disc": CHARCOAL, "band": CHARCOAL, "bandInk": GOLD},
}

def label(name):
    """The customer's name label (on the bottom box of a carryout stack)."""
    img = Image.new("RGB", (512, 64), (250, 250, 248))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 14, 64), fill=RED)
    centred(d, 6, name, font("arialbd.ttf", 46), CHARCOAL, x=263)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, design in DESIGNS.items():
        lid(design).save(os.path.join(OUT, f"lid_{name}.png"))
        band(design, "Large").save(os.path.join(OUT, f"band_{name}.png"))
        band(design, None).save(os.path.join(OUT, f"band_{name}_any.png"))
        print("wrote", name)
    label("JOHN P.").save(os.path.join(OUT, "label.png"))
    assert math.isclose(N, 1024)
