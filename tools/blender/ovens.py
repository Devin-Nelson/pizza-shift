"""Three stacked conveyor ovens, after the user's photo (2026-10-21): each oven
one painted front panel the whole length (the user: not sectioned off) with a
stainless-framed window under a small visor (so you watch the pizzas ride
through), hinges at both ends (the user: symmetrical), stainless
trim up the corners and seams between the ovens, the belt's mouths framed in
stainless on the painted ends, vents on the stainless back, air fingers
inside above the belt; the conveyor's rails the belt's whole length, a crumb
tray under each end, an exit shelf past the exit; at both ends a stainless
housing round the conveyor (the user's clip: the belts come out through
openings in its end, plain panels on its front); a stainless
base on casters; a stainless hood over the stack the belts' whole length (a
gap over the ovens themselves) whose faceted end sections sit on the
housings and overhang the belt ends round banks of baffle grease filters
(the user's photos), and a painted enclosure up to the ceiling. The paint is its own mesh (the user picks the
colour).

    blender -b -P tools/blender/ovens.py -- --render [--paint silver|blue|red|charcoal]

Art-local = StationArt.Layout.Oven (pizzas ride from +Z, the entrance, to -Z,
the exit; belt heights `decks`, lanes at `lanes`). StationArt keeps as parts:
the belts themselves (a wire-mesh Texture the client scrolls at the bake
speed), the slot markers and number tags, the interior lamps. The pulleys at each belt end are an instanced mesh StationArt places
and the client turns at the same speed. Also writes belt_mesh.png (the belt's
wire, clear between the wires).
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
from kit import Mesh, rgb  # noqa: E402

# StationArt.Layout.Oven
W, C, B = 6.6, 7.6, 13.6  # width, bake chamber length, belt length
E = 0.45  # the end columns either side of the chamber (the mouths run through them)
L = C + 2 * E  # the body's length
LANES = (-1.4, 1.4)
DECKS = (5.1, 3.2, 1.3)  # belt heights, top oven first
PITCH = DECKS[0] - DECKS[1]  # one oven's height: they stack flush
BELT_W = W - 0.8  # the belt (StationArt's Belt parts)
BELT_TOP = 0.05  # over the deck height (pizzas sit on it)
RAIL_X = BELT_W / 2 + 0.06  # the conveyor's side rails
MOUTH_X, MOUTH_UP = W / 2 - 0.22, 0.375  # the mouth: half its width, its top over the deck height
PULLEY_R = 0.12
PIZZA_D, PIZZA_T = 2.4, 0.3  # a Large, and how tall one gets with its toppings
WIN = (-2.4, 2.4, 0.1, 0.75)  # the window: z0, z1, and its bottom and top over the deck height
FACE = -W / 2 - 0.05  # the painted front's face
ZH0, ZH1 = L / 2 + 0.08, L / 2 + 0.88  # the stainless housings round the conveyor at each end
TUNNEL_UP, TUNNEL_DOWN = MOUTH_UP + 0.08, 0.25  # each belt's opening through a housing, over and under the deck height
PAINTS = {  # the colour options (the user's photo is the blue)
    "silver": (rgb(140, 145, 152), 1.0, 0.3),
    "blue": (rgb(34, 58, 168), 0.0, 0.22),
    "red": (rgb(214, 48, 39), 0.0, 0.22),  # Config.Brand.Red
    "charcoal": (rgb(38, 40, 46), 0.0, 0.25),  # Config.Brand.Charcoal
}
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PAINT = argv[argv.index("--paint") + 1] if "--paint" in argv else "silver"

kit.reset()
STAINLESS = rgb(140, 145, 152)
body = Mesh("Body", STAINLESS, metal=1.0, rough=0.3)
colour, metal, rough = PAINTS[PAINT]
paint = Mesh("Paint", colour, metal=metal, rough=rough)
conveyor = Mesh("Conveyor", rgb(160, 164, 170), metal=1.0, rough=0.25)
hood = Mesh("Hood", STAINLESS, metal=1.0, rough=0.25)
dark = Mesh("Dark", rgb(38, 39, 43), rough=0.55)
glass = Mesh("Glass", rgb(40, 40, 46), rough=0.05)
glass.alpha = 0.4
label = Mesh("Labels", rgb(235, 110, 30), rough=0.5)
rubber = Mesh("Rubber", rgb(30, 30, 33), rough=0.8)
pulley = Mesh("Pulley", rgb(175, 178, 184), metal=1.0, rough=0.3, instanced=True)


def panel(m, z0, z1, y0_, y1_, x0=FACE, x1=-W / 2 + 0.03):
    """A front panel from z0 to z1, y0 to y1."""
    m.box((x1 - x0, y1_ - y0_, z1 - z0), ((x0 + x1) / 2, (y0_ + y1_) / 2, (z0 + z1) / 2))


def oven(y):
    """One oven, its belt at height y."""
    y0, y1 = y - PITCH + 1.55, y + 1.55  # the body's bottom and top (flush with the ovens above and below)
    floor, roof = y - 0.175, y + 1.375  # the bake chamber
    # The shell: bottom, roof, the stainless back with its vents.
    body.box((W, floor - y0, L), (0, (y0 + floor) / 2, 0))
    body.box((W, y1 - roof, L), (0, (roof + y1) / 2, 0))
    body.box((0.1, y1 - y0, L), (W / 2 - 0.05, (y0 + y1) / 2, 0))
    for row in range(2):
        for k in range(5):
            dark.box((0.02, 0.05, 0.9), (W / 2 + 0.01, y + 0.35 + 0.45 * row, -C / 2 + 1.0 + k * 1.4))
    # The end columns, the mouth through each; painted ends, a stainless frame round the mouth.
    for sz in (-1, 1):
        zc = sz * (C / 2 + E / 2)
        body.box((W, roof - (y + MOUTH_UP), E), (0, (y + MOUTH_UP + roof) / 2, zc))
        for sx in (-1, 1):
            body.box((W / 2 - MOUTH_X, y + MOUTH_UP - floor, E), (sx * (W / 2 + MOUTH_X) / 2, (floor + y + MOUTH_UP) / 2, zc))
        ze = sz * (L / 2 + 0.03)
        paint.box((W, y1 - 0.06 - (y + MOUTH_UP + 0.06), 0.06), (0, (y + MOUTH_UP + 0.06 + y1 - 0.06) / 2, ze))
        paint.box((W, floor - 0.06 - (y0 + 0.06), 0.06), (0, (y0 + 0.06 + floor - 0.06) / 2, ze))
        for sx in (-1, 1):
            paint.box((W / 2 - MOUTH_X - 0.06, y + MOUTH_UP + 0.06 - (floor - 0.06), 0.06), (sx * (W / 2 + MOUTH_X + 0.06) / 2, (floor - 0.06 + y + MOUTH_UP + 0.06) / 2, ze))
        zf = sz * (L / 2 + 0.05)
        body.box((2 * MOUTH_X + 0.12, 0.06, 0.05), (0, y + MOUTH_UP + 0.03, zf))
        body.box((2 * MOUTH_X + 0.12, 0.06, 0.05), (0, floor - 0.03, zf))
        for sx in (-1, 1):
            body.box((0.06, MOUTH_UP + 0.175 + 0.12, 0.05), (sx * (MOUTH_X + 0.03), (floor + y + MOUTH_UP) / 2, zf))
    # The front: one painted panel the whole length, its window in a stainless
    # frame under a visor, hinges at both ends, a warning label.
    wz0, wz1, wy0, wy1 = WIN
    dz0, dz1, dy0, dy1 = -L / 2 + 0.04, L / 2 - 0.04, y0 + 0.06, y1 - 0.06
    panel(paint, dz0, dz1, dy0, y + wy0)
    panel(paint, dz0, dz1, y + wy1, dy1)
    panel(paint, dz0, wz0, y + wy0, y + wy1)
    panel(paint, wz1, dz1, y + wy0, y + wy1)
    glass.box((0.03, wy1 - wy0, wz1 - wz0), (-W / 2 + 0.01, y + (wy0 + wy1) / 2, (wz0 + wz1) / 2))
    bx = FACE - 0.04
    for wy in (wy0, wy1):
        body.box((0.08, 0.08, wz1 - wz0 + 0.16), (bx, y + wy, (wz0 + wz1) / 2), bevel=0.01)
    for wz in (wz0, wz1):
        body.box((0.08, wy1 - wy0 + 0.08, 0.08), (bx, y + (wy0 + wy1) / 2, wz), bevel=0.01)
    vis = math.radians(28)
    body.box((0.3, 0.025, wz1 - wz0 + 0.3), (bx - 0.15 * math.cos(vis), y + wy1 + 0.06 - 0.15 * math.sin(vis), (wz0 + wz1) / 2), r=kit.rot("z", -28))
    for sz in (-1, 1):
        body.box((0.3, 0.12, 0.02), (bx - 0.13, y + wy1 + 0.0, (wz0 + wz1) / 2 + sz * ((wz1 - wz0) / 2 + 0.14)))
    for hz in (dz0 + 0.25, dz1 - 0.25):
        for hy in (dy0 + 0.35, dy1 - 0.35):
            body.cyl(0.06, 0.1, (FACE - 0.05, hy, hz), axis="x", segs=14)
            body.box((0.04, 0.26, 0.1), (FACE - 0.02, hy, hz))
    label.box((0.01, 0.16, 0.24), (FACE - 0.005, dy1 - 0.17, C / 2 - 0.375))
    # The conveyor housings at both ends: blocks round each belt's opening, the
    # opening framed on the housing's end, a seam along its front.
    for sz in (-1, 1):
        zc, hl = sz * (ZH0 + ZH1) / 2, ZH1 - ZH0
        body.box((W, y1 - (y + TUNNEL_UP), hl), (0, (y + TUNNEL_UP + y1) / 2, zc))
        body.box((W, y - TUNNEL_DOWN - y0, hl), (0, (y0 + y - TUNNEL_DOWN) / 2, zc))
        for sx in (-1, 1):
            body.box((W / 2 - MOUTH_X, TUNNEL_UP + TUNNEL_DOWN, hl), (sx * (W / 2 + MOUTH_X) / 2, y + (TUNNEL_UP - TUNNEL_DOWN) / 2, zc))
        zf = sz * (ZH1 + 0.025)
        body.box((2 * MOUTH_X + 0.16, 0.08, 0.05), (0, y + TUNNEL_UP + 0.04, zf))
        body.box((2 * MOUTH_X + 0.16, 0.08, 0.05), (0, y - TUNNEL_DOWN - 0.04, zf))
        for sx in (-1, 1):
            body.box((0.08, TUNNEL_UP + TUNNEL_DOWN + 0.16, 0.05), (sx * (MOUTH_X + 0.04), y + (TUNNEL_UP - TUNNEL_DOWN) / 2, zf))
        dark.box((0.01, 0.03, hl - 0.06), (-W / 2 - 0.005, y0 + 0.015, zc))  # the panel's seam
    # The seam under each oven, across the front.
    body.box((0.1, 0.12, L + 0.1), (FACE - 0.02, y0, 0))
    # Inside, seen through the window: air fingers across the chamber above the belt.
    for k in range(5):
        dark.box((W - 0.4, 0.12, 0.45), (0, y + 1.05, -C / 2 + 0.9 + k * (C - 1.8) / 4))
    # The conveyor: side rails the belt's whole length, a crumb tray under
    # each end, an exit shelf past the exit.
    for sx in (-1, 1):
        conveyor.box((0.08, 0.22, B), (sx * RAIL_X, y + BELT_TOP - 0.11, 0))
        conveyor.box((0.03, 0.05, B), (sx * (RAIL_X - 0.04), y + BELT_TOP + 0.02, 0))  # a lip up the belt's edge
    for sz in (-1, 1):
        z0_, z1_ = ZH1 + 0.1, B / 2 - 2 * PULLEY_R - 0.05
        tz = sz * (z0_ + z1_) / 2
        dark.box((BELT_W, 0.02, z1_ - z0_), (0, y - 0.36, tz))
        for sx in (-1, 1):
            dark.box((0.02, 0.1, z1_ - z0_), (sx * BELT_W / 2, y - 0.31, tz))
    conveyor.box((BELT_W, 0.03, 0.55), (0, y + BELT_TOP - 0.06, -B / 2 - 0.3))
    conveyor.box((BELT_W, 0.12, 0.03), (0, y + BELT_TOP - 0.01, -B / 2 - 0.57))
    for sx in (-1, 1):
        conveyor.box((0.03, 0.12, 0.55), (sx * BELT_W / 2, y + BELT_TOP - 0.01, -B / 2 - 0.3))
        conveyor.box((0.06, 0.06, 0.62), (sx * RAIL_X, y + BELT_TOP - 0.1, -B / 2 - 0.27))  # its brackets


for y in DECKS:
    oven(y)
TOP = DECKS[0] + 1.55
bottom = DECKS[-1] - PITCH + 1.55
body.box((0.1, 0.12, L + 0.1), (FACE - 0.02, TOP, 0))  # the top seam
for z in (-L / 2, L / 2):  # stainless trim up the painted fronts' corners
    body.box((0.1, TOP - bottom, 0.1), (FACE - 0.02, (bottom + TOP) / 2, z))

# The base: a stainless skirt under the bottom oven and the housings, casters at the corners.
body.box((W, bottom - 0.32, 2 * ZH1), (0, 0.32 + (bottom - 0.32) / 2, 0))
for sx in (-1, 1):
    for sz in (-1, 1):
        cx, cz = sx * (W / 2 - 0.35), sz * (ZH1 - 0.35)
        body.box((0.26, 0.03, 0.26), (cx, 0.305, cz))
        body.cyl(0.04, 0.06, (cx, 0.26, cz), segs=8)
        rubber.cyl(0.12, 0.08, (cx, 0.12, cz + 0.04), axis="x", segs=16)
        for fx_ in (-0.06, 0.06):
            body.box((0.02, 0.12, 0.16), (cx + fx_, 0.18, cz + 0.03))

# The hood: a stainless canopy over the stack, the belts' whole length, a gap
# over the ovens themselves; at both ends, over the belts' mouths, it drops
# down to the top oven's height round a bank of baffle grease filters (the
# user's photos): their lower edges on the end section's inner wall, leaning
# out over the belt ends (the user), a plate from their tops out to the skirt.
# The painted enclosure above it
# goes up to the ceiling (14 up).
HW, HD = W + 1.2, B + 0.3
EW, ED = W + 0.5, HD - 0.9
HY0 = TOP + 0.35  # the canopy's bottom edge over the ovens
DROP = TOP  # the end sections' bottom edge
CHAMFER = 0.5  # the hood's corners are cut at 45 degrees (the user's clip)
kit.loft(hood, [(HY0, kit.rounded_rect(HW, HD, CHAMFER, 1)), (HY0 + 0.45, kit.rounded_rect(HW, HD, CHAMFER, 1)), (HY0 + 0.95, kit.rounded_rect(EW, ED, CHAMFER * 0.6, 1))], close_bottom=False, thickness=0.03)
END0 = ZH0 + 0.01  # each end section's inner wall: over the housing's inner edge
FILTER_LEN, FILTER_TILT = 1.06, 41.2
FILTER_Y = (DROP + 0.05 + HY0 + 0.4) / 2
FILTER_DZ, FILTER_DY = FILTER_LEN / 2 * math.cos(math.radians(FILTER_TILT)), FILTER_LEN / 2 * math.sin(math.radians(FILTER_TILT))
FILTER_Z = END0 + 0.035 + FILTER_DZ  # the bank's centre: lower edges against the inner wall (its face, plus the frame's overhang)
filters = Mesh("Filters", rgb(196, 200, 206), metal=1.0, rough=0.12)


def tilted(c, a_deg, x, y, z):
    """A point x, y, z in a filter's frame (tilted a about x) placed at its centre c."""
    a = math.radians(a_deg)
    return (c[0] + x, c[1] + y * math.cos(a) - z * math.sin(a), c[2] + y * math.sin(a) + z * math.cos(a))


for sz in (-1, 1):
    # The end section's skirt down to the housing: its chamfered outline.
    skirt = [(-HW / 2, sz * END0), (-HW / 2, sz * (HD / 2 - CHAMFER)), (-HW / 2 + CHAMFER, sz * HD / 2), (HW / 2 - CHAMFER, sz * HD / 2), (HW / 2, sz * (HD / 2 - CHAMFER)), (HW / 2, sz * END0)]
    if sz < 0:
        skirt = skirt[::-1]
    kit.ribbon(hood, skirt, -0.03, 0.0, DROP, HY0)
    kit.ribbon(hood, skirt, -0.05, 0.03, DROP, DROP + 0.05)  # a finished bottom edge
    hood.box((HW, HY0 + 0.45 - DROP, 0.03), (0, (DROP + HY0 + 0.45) / 2, sz * END0))
    # Three baffle filters across, their lower edges on the inner wall, sloping
    # up and out over the belt's end; a plate from their tops out to the skirt
    # (its chamfered outline) closes the end section above them.
    fw = (HW - 0.3) / 3
    a = -FILTER_TILT if sz > 0 else FILTER_TILT
    zt = FILTER_Z + FILTER_DZ - 0.02  # the tops' distance out (under the plate's edge)
    plate = [(x, sz * z) for x, z in kit.rounded_rect(HW - 0.04, HD - 0.04, CHAMFER, 1) if z > 0] + [(-HW / 2 + 0.02, sz * zt), (HW / 2 - 0.02, sz * zt)]
    plate = [plate[i] for i in sorted(range(len(plate)), key=lambda i: math.atan2(plate[i][1] - sz * (zt + HD / 2) / 2, plate[i][0]))]
    kit.loft(hood, [(FILTER_Y + FILTER_DY - 0.005, plate), (FILTER_Y + FILTER_DY + 0.025, plate)], close_top=True)
    for k in range(3):
        c = (-HW / 2 + 0.15 + fw * (k + 0.5), FILTER_Y, sz * FILTER_Z)
        for lz in (-1, 1):
            filters.box((fw - 0.04, 0.06, 0.07), tilted(c, a, 0, 0, lz * (FILTER_LEN / 2 - 0.035)), r=kit.rot("x", a))
        for lx in (-1, 1):
            filters.box((0.07, 0.06, FILTER_LEN), tilted(c, a, lx * (fw / 2 - 0.055), 0, 0), r=kit.rot("x", a))
        dark.box((fw - 0.14, 0.01, FILTER_LEN - 0.12), tilted(c, a, 0, 0, 0), r=kit.rot("x", a))
        for j in range(6):
            bxj = -fw / 2 + 0.22 + j * (fw - 0.44) / 5
            filters.rod(tilted(c, a, bxj, 0, -(FILTER_LEN / 2 - 0.13)), tilted(c, a, bxj, 0, FILTER_LEN / 2 - 0.13), 0.055, segs=10)
ENC_Y0 = HY0 + 0.95
# Flush on the hood's top edge, never past it (the user, 2026-10-24: it hung
# over the hood): the top ring's shape, chamfered corners and all, inset by the
# hood's skin.
ENC = kit.rounded_rect(EW - 0.08, ED - 0.08, CHAMFER * 0.6, 1)
kit.loft(paint, [(ENC_Y0, ENC), (14, ENC)], close_bottom=True, close_top=True)

# The pulley at each end of a belt (instanced; StationArt places one per end,
# the client turns it): a drum the belt's width, sprocket rings, axle stubs.
pulley.cyl(PULLEY_R, BELT_W - 0.04, (0, 0, 0), axis="x", segs=20)
for k in range(9):
    pulley.cyl(PULLEY_R + 0.012, 0.03, (-BELT_W / 2 + 0.3 + k * (BELT_W - 0.6) / 8, 0, 0), axis="x", segs=20)
for sx in (-1, 1):
    pulley.cyl(0.035, 0.12, (sx * (BELT_W / 2 + 0.03), 0, 0), axis="x", segs=10)
PULLEYS = [(0.0, y + BELT_TOP - PULLEY_R, sz * (B / 2 - PULLEY_R)) for y in DECKS for sz in (-1, 1)]


# The belt's wire (a flat-wire conveyor belt): cross rods with flat links
# zig-zagging between them, clear between the wires. One tile = 0.3 studs.
def belt_texture(px: int):
    v, u = (np.mgrid[0:px, 0:px] + 0.5) / px
    rods = (np.abs(v - 0.25) < 0.045) | (np.abs(v - 0.75) < 0.045)
    zig = np.abs(((u * 4 + np.where(v < 0.5, v, 1 - v) * 4) % 1.0) - 0.5) < 0.09
    on = rods | zig
    shade = 0.7 + 0.08 * np.sin(u * 50) * np.cos(v * 37)
    rgba = np.zeros((px, px, 4))
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = shade, shade, shade * 0.98
    rgba[..., 3] = np.where(on, 1.0, 0.0)
    return rgba


out = os.path.join(kit.OUT_ROOT, "ovens")
os.makedirs(out, exist_ok=True)
belt_png = kit.save_png(os.path.join(out, "belt_mesh.png"), belt_texture(256))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


check("the ovens stack flush (each body as tall as the deck spacing)", all(abs((a - b) - PITCH) < 1e-9 for a, b in zip(DECKS, DECKS[1:])))
check("a pizza with toppings passes the mouths", MOUTH_UP > BELT_TOP + PIZZA_T + 0.02)
check("the window shows the pizza (its bottom below the pizza's top)", WIN[2] < BELT_TOP + 0.12)
check("the window sits in the door", -C / 2 + 0.3 < WIN[0] and WIN[1] < C / 2 - 0.3)
check("the air fingers clear the pizzas", 1.05 - 0.06 > BELT_TOP + PIZZA_T + 0.1)
check("the mouths are wide enough for the belt and its rails", MOUTH_X > RAIL_X + 0.04 + 0.02)
check("both lanes' Large pizzas fit the belt", all(abs(lx) + PIZZA_D / 2 < BELT_W / 2 - 0.05 for lx in LANES))
check("the lanes clear each other", LANES[1] - LANES[0] >= PIZZA_D + 0.1)
check("a pizza at the belt's ends is out past the end columns (its centre 1.3 from the end)", B / 2 - 1.3 - PIZZA_D / 2 > L / 2 - 0.15)
check("the crumb trays sit between the body and the pulleys", L / 2 + 0.1 < B / 2 - 2 * PULLEY_R - 0.05)
check("a gap over the ovens, the hood over the belts' whole length", HY0 > TOP + 0.2 and HD / 2 >= B / 2 and HW > W)
check("the end sections sit on the housings' tops, past the ovens' painted ends", abs(DROP - TOP) < 1e-9 and ZH0 < END0 < ZH1 and ZH0 > L / 2 + 0.06 + 0.015)
check("a pizza at a belt's end is mostly out of the housing (its centre past the housing's end)", B / 2 - 1.3 > ZH1 + 0.1)
check("the belt's rails pass through the housings' openings", MOUTH_X > RAIL_X + 0.04 and TUNNEL_DOWN > 0.17 + 0.03 and TUNNEL_UP > BELT_TOP + PIZZA_T + 0.02)
check("the crumb trays start past the housings", ZH1 + 0.1 < B / 2 - 2 * PULLEY_R - 0.05)
fy_lo = FILTER_Y - FILTER_DY
check("the filters sit inside their end sections, above the belts", fy_lo > DROP + 0.02 and fy_lo > DECKS[0] + PIZZA_T + 0.5)
hi = tilted((0, FILTER_Y, FILTER_Z), -FILTER_TILT, 0, 0, FILTER_LEN / 2)
check("the filters lean out over the belt end: lower edge in, top out", hi[2] > FILTER_Z and hi[1] > FILTER_Y)
inner = tilted((0, FILTER_Y, FILTER_Z), -FILTER_TILT, 0, 0.03, -FILTER_LEN / 2)
check("the filters' lower edges sit against the inner wall (no gap)", abs(inner[2] - (END0 + 0.015)) < 0.005)
check("the filters stop short of the hood's chamfered corners", FILTER_Z + FILTER_DZ + 0.05 < HD / 2 - CHAMFER)
check("the plate past the filters' tops sits under the hood's straight wall", FILTER_Y + FILTER_DY + 0.025 < HY0 + 0.45)
check("the base reaches the bottom oven over the casters", bottom > 0.6)
# MapBuilder: the ovens at shop (8.55, 10.1); the cut table at x -1.3..5.0, z down from 3.0.
check("the exit shelf clears the cut table (beside it, not over it)", 8.55 - BELT_W / 2 > 5.0 + 0.3 or 10.1 - B / 2 - 0.6 > 3.0)
print(f"[layout] pulleys {[tuple(round(v, 3) for v in p) for p in PULLEYS]}; paint {PAINT}")

# -- Preview only: the belts (StationArt's parts, with the wire texture),
# pizzas riding through.
belts = Mesh("BeltPreview", rgb(150, 152, 158), metal=0.8, rough=0.4)
piz = Mesh("PizzaPreview", rgb(214, 160, 90), rough=0.7)
chs = Mesh("CheesePreview", rgb(240, 190, 90), rough=0.6)
for y in DECKS:
    belts.box((BELT_W, 0.03, B - 4 * PULLEY_R), (0, y + BELT_TOP - 0.015, 0))
belts.texture = belt_png
kit.planar_uv(belts, 0.15)  # one tile every 0.3 studs
for (lx, z_), y in zip(((-1.4, 1.0), (1.4, -1.0), (-1.4, -5.3), (1.4, 2.2), (-1.4, 0.4), (1.4, 5.4)), (5.1, 5.1, 3.2, 3.2, 1.3, 1.3)):
    kit.loft(piz, [(y + BELT_TOP, kit.rounded_rect(2.4, 2.4, 1.2, 8)), (y + BELT_TOP + 0.08, kit.rounded_rect(2.34, 2.34, 1.17, 8))], close_top=True, at=(lx, 0, z_))
    kit.loft(chs, [(y + BELT_TOP + 0.082, kit.rounded_rect(2.0, 2.0, 1.0, 8))], close_bottom=False, close_top=True, at=(lx, 0, z_))
for m in (belts, piz, chs):
    kit.preview(m)

CAMERAS = [
    (f"overview_{PAINT}", (-13.0, 6.5, 7.5), (0.0, 4.2, -0.6), 34),
    (f"front_{PAINT}", (-14.5, 4.6, 0.0), (0.0, 4.4, 0.0), 30),
    (f"corner_{PAINT}", (-7.5, 6.6, 9.0), (-3.0, 5.2, 3.6), 38),
    (f"filters_{PAINT}", (-6.0, 3.6, 11.5), (0.0, 7.0, 5.2), 34),
    (f"hood_section_{PAINT}", (-12.0, 6.4, 5.4), (0.0, 6.4, 5.4), 50, 11.5),  # cut through the middle filter at the entrance end
    (f"end_{PAINT}", (-9.5, 5.0, -12.0), (0.0, 4.4, -5.0), 34),
]
if PAINT == "silver":
    CAMERAS += [
        ("window", (-9.5, 4.6, 3.8), (-3.3, 3.55, 0.0), 34),
        ("exit", (-4.5, 4.0, -11.0), (0.0, 3.0, -6.0), 44),
        ("back", (12.0, 7.0, 9.0), (0.0, 4.0, 0.0), 40),
    ]
kit.finish(
    "ovens",
    [body, paint, conveyor, hood, filters, dark, glass, label, rubber, pulley],
    [("Pulley", p, 0, 1) for p in PULLEYS],
    CAMERAS,
    kit.args()["render"],
)
