"""Stretch table: steel table with the dough trays, proofed dough balls, tray
dollies, the cornmeal bin and the cornmeal on the top.

    blender -b -P tools/blender/stretch_table.py -- --render

Sizes follow StationArt.Layout.StretchTable (keep them in step). Static meshes
are built where they stand (art-local); Tray and Ball1-3 are built at the origin
and placed per copy by StationArt (trays named DoughTrayWall, balls DoughBall).
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import layout  # noqa: E402
from kit import Mesh, rgb  # noqa: E402

# StationArt.Layout.StretchTable
W, D, H = 12.7, 4.4, 3.4
WORK_X, WORK_Z = 3.8, -0.6
TRAY_Z, TRAY_W, TRAY_D = 0.45, 2.25, 3.25
TRAYS = {
    "Small": {"x": -5.0, "ball": 0.6, "rows": [1, 2, 1, 2, 1, 2, 1]},
    "Medium": {"x": -2.6, "ball": 0.74, "rows": [2, 1, 2, 1, 2]},
    "Large": {"x": -0.2, "ball": 0.92, "rows": [2, 2, 2]},
}
TRAY_H = 0.375  # 3" deep
TRAY_FLOOR = 0.03
TRAY_PITCH = TRAY_H - 0.03  # stacked trays nest a little
LEGS_X = (-6.15, 1.2, 6.15)
LEGS_Z = (-1.95, 1.95)
DOLLIES_X = (-4.85, -2.5, -0.15)
DOLLY_Z = 0.1
DOLLY_TOP = 0.32
STACK = 7
BIN_X, BIN_W = 3.8, 2.2
BIN_FILL = 1.95  # cornmeal level in the bin
# The cornmeal dusting: a Decal on a square Part (StationArt).
DUST_X, DUST_Z, DUST_SIZE = WORK_X, -0.15, 4.0

kit.reset()
steel = Mesh("Steel", rgb(196, 200, 206), metal=1.0, rough=0.28)
rubber = Mesh("Rubber", rgb(25, 25, 28), rough=0.8)
dolly = Mesh("Dollies", rgb(62, 64, 70), rough=0.6)
binm = Mesh("Bin", rgb(235, 232, 225), rough=0.4)
tray = Mesh("Tray", rgb(45, 125, 215), rough=0.45, instanced=True)
balls = [Mesh(f"Ball{i}", rgb(234, 222, 186), rough=0.7, instanced=True) for i in (1, 2, 3)]

# -- The table: top with a rolled front edge, aprons, a backsplash against the
# dough show wall, an open base (dollies roll in from the front) on six legs
# with gussets and bullet feet, side rails and a back rail.
steel.box((W, 0.08, D), (0, H - 0.04, 0), bevel=0.01)
# The rolled front edge; its end at the corner table is mitred to that table's front.
kit.tube(steel, [(-W / 2, -D / 2), (W / 2, -D / 2)], H - 0.07, 0.07, after=layout.to_dough(*layout.C3))
steel.box((W, 0.2, 0.03), (0, H - 0.18, -D / 2 + 0.06))
steel.box((W, 0.2, 0.03), (0, H - 0.18, D / 2 - 0.02))
for sx in (-1, 1):
    steel.box((0.03, 0.2, D - 0.1), (sx * (W / 2 - 0.02), H - 0.18, 0))
# Backsplash with a folded top, its corner end mitred to the corner table's splash.
splash = [(W / 2, D / 2), (-W / 2, D / 2)]
kit.ribbon(steel, splash, 0.0, 0.05, H, H + 0.45, before=layout.to_dough(*layout.C4))
kit.ribbon(steel, splash, 0.0, 0.14, H + 0.42, H + 0.45, before=layout.to_dough(*layout.C4))
for lx in LEGS_X:
    for lz in LEGS_Z:
        steel.cyl(0.085, H - 0.45, (lx, 0.13 + (H - 0.45) / 2, lz), segs=14)
        steel.cyl(0.1, 0.22, (lx, H - 0.21, lz), segs=14, radius2=0.17)  # gusset
        steel.cyl(0.065, 0.13, (lx, 0.065, lz), segs=12, radius2=0.085)  # bullet foot
        steel.cyl(0.095, 0.05, (lx, 0.15, lz), segs=14)  # collar
    steel.rod((lx, 0.65, LEGS_Z[0]), (lx, 0.65, LEGS_Z[1]), 0.06, segs=10)
steel.rod((LEGS_X[0], 0.65, LEGS_Z[1]), (LEGS_X[-1], 0.65, LEGS_Z[1]), 0.06, segs=10)

# -- Tray dollies under the trays: a moulded base with a locating rim, steel
# caster forks, rubber wheels.
for dx in DOLLIES_X:
    bw, bd = TRAY_W + 0.16, TRAY_D + 0.16
    dolly.box((bw, 0.1, bd), (dx, DOLLY_TOP - 0.05 - 0.04, DOLLY_Z), bevel=0.03, segs=2)
    for sx in (-1, 1):
        dolly.box((0.06, 0.07, bd), (dx + sx * (bw / 2 - 0.03), DOLLY_TOP - 0.005, DOLLY_Z), bevel=0.01)
    for sz in (-1, 1):
        dolly.box((bw, 0.07, 0.06), (dx, DOLLY_TOP - 0.005, DOLLY_Z + sz * (bd / 2 - 0.03)), bevel=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = dx + sx * (bw / 2 - 0.2), DOLLY_Z + sz * (bd / 2 - 0.2)
            steel.box((0.14, 0.05, 0.14), (cx, 0.165, cz))
            steel.box((0.02, 0.1, 0.1), (cx - 0.045, 0.1, cz))
            steel.box((0.02, 0.1, 0.1), (cx + 0.045, 0.1, cz))
            rubber.cyl(0.07, 0.06, (cx, 0.07, cz), axis="x", segs=12)

# -- The cornmeal bin under the stretch spot: a rolling ingredient bin with a
# sloped front, its lid slid back so the cornmeal shows (StationArt fills it:
# a Sand part at BIN_FILL).
BIN_Z0, BIN_Z1, BIN_BOT, BIN_TOP = -1.55, 1.55, 0.22, 2.7
profile = [(BIN_Z0, BIN_BOT), (BIN_Z1, BIN_BOT), (BIN_Z1, BIN_TOP), (-0.35, BIN_TOP), (BIN_Z0, 2.15)]
binm.prism(profile, BIN_X - BIN_W / 2, BIN_X + BIN_W / 2, open_edges=(3,), thickness=0.05)
binm.box((BIN_W + 0.04, 0.06, 0.08), (BIN_X, 2.16, BIN_Z0 + 0.02), bevel=0.02)  # front lip
fill = Mesh("CornmealFill", rgb(236, 196, 92), rough=0.9, grain=True)
fill.box((BIN_W - 0.12, 0.02, BIN_Z1 - BIN_Z0 - 0.15), (BIN_X, BIN_FILL, 0))
kit.preview(fill)
for sx in (-1, 1):
    for sz in (-1, 1):
        cx, cz = BIN_X + sx * (BIN_W / 2 - 0.25), sz * 1.3
        steel.box((0.02, 0.12, 0.11), (cx - 0.045, 0.12, cz))
        steel.box((0.02, 0.12, 0.11), (cx + 0.045, 0.12, cz))
        rubber.cyl(0.08, 0.06, (cx, 0.08, cz), axis="x", segs=12)


# -- Cornmeal on the top: a dusting over the stretch spot (a texture, flat, so
# the Stretch minigame's own pile and ring sit on it).
def dust_texture(px: int, seed: int):
    """The cornmeal dusting as an RGBA image: grains thick in drifts around the
    centre, thinning to loose grains at the edges (alpha = cornmeal)."""
    rng = np.random.default_rng(seed)
    v, u = (np.mgrid[0:px, 0:px] + 0.5) / px * 2 - 1  # -1..1, row 0 = top

    def value_noise(res):
        g = rng.random((res + 1, res + 1))
        x, y = (u + 1) / 2 * res, (v + 1) / 2 * res
        i, j = np.minimum(x.astype(int), res - 1), np.minimum(y.astype(int), res - 1)
        fx, fy = x - i, y - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        top = g[j, i] * (1 - fx) + g[j, i + 1] * fx
        bot = g[j + 1, i] * (1 - fx) + g[j + 1, i + 1] * fx
        return top * (1 - fy) + bot * fy

    n = 0.5 * value_noise(4) + 0.3 * value_noise(9) + 0.2 * value_noise(23)
    r = np.hypot(u * 1.05, v * 1.2)
    field = np.clip((1 - r) * 1.5, 0, 1) * (0.25 + 1.2 * n)
    rgba = np.zeros((px, px, 4))
    # a thin film where it lies thick, so dense drifts read as solid
    film = np.clip((field - 0.55) / 0.35, 0, 1)
    rgba[..., :3] = np.array([0.93, 0.78, 0.40])
    rgba[..., 3] = film * 0.85
    # grains: kept with the field's probability, 1-3 px, shades of yellow
    count = px * px // 6
    gx, gy = rng.integers(0, px, count), rng.integers(0, px, count)
    keep = rng.random(count) < np.clip(field[gy, gx] * 1.2, 0, 1) ** 1.3
    gx, gy = gx[keep], gy[keep]
    shade = rng.random(len(gx))
    cols = np.array([0.98, 0.86, 0.52]) * (1 - shade[:, None]) + np.array([0.80, 0.58, 0.20]) * shade[:, None]
    rad = rng.choice([0, 1, 1, 2], len(gx))
    for k in (0, 1, 2):
        sel = rad >= k
        for dx in range(-k, k + 1):
            for dy in range(-k, k + 1):
                if dx * dx + dy * dy > k * k + 1:
                    continue
                x, y = np.clip(gx[sel] + dx, 0, px - 1), np.clip(gy[sel] + dy, 0, px - 1)
                rgba[y, x, :3] = cols[sel]
                rgba[y, x, 3] = 1.0
    return rgba


out = os.path.join(kit.OUT_ROOT, "stretch_table")
os.makedirs(out, exist_ok=True)
dust_img = kit.save_png(os.path.join(out, "cornmeal_dust.png"), dust_texture(1024, 5))
kit.decal_preview("CornmealDust", dust_img, DUST_SIZE, DUST_SIZE, (DUST_X, H + 0.005, DUST_Z))

# -- A dough tray (Dough Pro style, 18 x 26 x 3 in): tapered walls, a rim
# flange with a turned-down lip, ribs on the long sides, grips at the ends.
TAPER = 0.07
pts = lambda w, d, r: kit.rounded_rect(w, d, r, 4)  # noqa: E731
kit.loft(
    tray,
    [
        (0.0, pts(TRAY_W - 2 * TAPER - 0.04, TRAY_D - 2 * TAPER - 0.04, 0.1)),
        (TRAY_H - 0.035, pts(TRAY_W - 0.04, TRAY_D - 0.04, 0.13)),
        (TRAY_H, pts(TRAY_W, TRAY_D, 0.15)),
        (TRAY_H - 0.06, pts(TRAY_W + 0.004, TRAY_D + 0.004, 0.152)),
    ],
    thickness=TRAY_FLOOR,
)
tilt = math.degrees(math.atan2(TAPER, TRAY_H))
for sx in (-1, 1):
    for rz in (-1.05, -0.35, 0.35, 1.05):
        xw = (TRAY_W - 2 * TAPER - 0.04) / 2 + TAPER * 0.5 + 0.012
        tray.box((0.03, TRAY_H - 0.1, 0.05), (sx * xw, (TRAY_H - 0.06) / 2, rz), r=kit.rot("z", -sx * tilt))
for sz in (-1, 1):
    tray.box((0.8, 0.045, 0.05), (0, TRAY_H - 0.09, sz * (TRAY_D / 2 - 0.005)), bevel=0.012)

# -- Proofed dough balls: three slightly different lumps.
for i, b in enumerate(balls):
    kit.lump(b, seed=i + 1)

# -- Preview placements (StationArt does the same at runtime).
lo, hi = tray.bounds()
tray_h = hi.y - lo.y
place = []
for size, t in TRAYS.items():
    place.append(("Tray", (t["x"], H + tray_h / 2, TRAY_Z), 0, 1.0))
    rows = t["rows"]
    n = 0
    for r, count in enumerate(rows, start=1):
        bz = TRAY_Z - TRAY_D / 2 + 0.1 + t["ball"] / 2 + (r - 1) * (TRAY_D - t["ball"] - 0.2) / max(len(rows) - 1, 1)
        for c in range(1, count + 1):
            n += 1
            bx = t["x"] + (0 if count == 1 else (c - 1.5) * (TRAY_W / 2))
            blo, bhi = balls[(n - 1) % 3].bounds()
            s = t["ball"] / (bhi.x - blo.x)
            place.append((f"Ball{(n - 1) % 3 + 1}", (bx, H + TRAY_FLOOR + (bhi.y - blo.y) * s / 2, bz), n * 77, s))
for dx in DOLLIES_X:
    for k in range(STACK):
        place.append(("Tray", (dx, DOLLY_TOP + k * TRAY_PITCH + tray_h / 2, DOLLY_Z), 0, 1.0))

kit.finish(
    "stretch_table",
    [steel, rubber, dolly, binm, tray] + balls,
    place,
    [
        ("overview", (-8.5, 9.0, -12.5), (0.2, 2.2, 0.2), 32),
        ("trays", (-2.6, 7.6, -4.6), (-2.6, 3.3, 0.45), 30),
        ("stretch", (6.5, 7.2, -5.5), (3.2, 2.4, 0.0), 30),
    ],
    kit.args()["render"],
    wall_z=D / 2 + 0.5,
)
