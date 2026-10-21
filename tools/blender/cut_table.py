"""Cut table, after the user's photos of real ones (2026-10-21): a stainless
table on casters with a square-edged top, solid end panels and back, two full
shelves underneath, a round middle post at the front. On top: a stack of
boxes per size lying completely unfolded (the tender folds the top one on its
stack in the game, slides the pizza in, cuts and shuts it), a recessed trough
with the rockers between two stacks, the side boxes (two sizes: wings and
pasta share the bigger, SuperCakes the smaller) lying unfolded in their own
stacks out of the way at the far end, a seasoning insert behind the Medium
stack.
Underneath: more blanks, a case of boxes, bins of side-box blanks. A trash
can on the counter side. (The user, 2026-10-21: no printer on the top.)

    blender -b -P tools/blender/cut_table.py -- --render

Art-local = StationArt.Layout.CutTable (worker at -Z, the ovens off +X).
StationArt keeps the gameplay pieces as parts: Blank_<Size> (BoxSize), the
top blank of each pizza-box stack, which the cut minigame folds into a box
once the pizza on it is cut; Blank_<Side> (SideBox), the side stacks' top
blanks, folded the same way once sides can be ordered; CutLanding; the size tags on
the front edge. Also the rocker (Rocker + RockerGrips, instanced): two in the
trough, and the cut minigame's own.
"""

import math
import os
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import pizzabox as PB  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

# StationArt.Layout.CutTable
H, D = 3.2, 6.3
INCH = 2.4 / 14  # Config.StudsPerInch
SIZES = (("Small", 10), ("Medium", 12), ("Large", 14))
BOX = {s: n * INCH + 0.15 for s, n in SIZES}  # Config.BoxSize: the pizza plus 0.15
BLANK = 0.03  # one flat box
TOP_T = 0.15  # the top's thickness (square edge)


def blank(bs):
    """A pizza box blank lying completely unfolded (w, d): pizzabox.py's die-cut sheet."""
    return PB.blank_size(PB.pizza(bs))


# The stacks along the front, small to large from the oven end, the rocker
# trough between Medium and Large; past Large, the far-end strip.
COUNT = {"Small": 16, "Medium": 18, "Large": 20}
TROUGH_W, SIDE_W = 0.6, 2.0
W = round(0.2 + sum(blank(BOX[s])[0] for s, _ in SIZES) + 0.25 + 0.15 + TROUGH_W + 0.15 + 0.25 + SIDE_W + 0.15 + 0.05, 1)
FRONT = -D / 2 + 0.2  # the stacks' front edge
stacks = {}  # size -> (x, z of the blank's centre, bs, top of the stack)
x = W / 2 - 0.2
for size, _ in SIZES:
    bs = BOX[size]
    bw, bd = blank(bs)
    if size == "Large":
        TROUGH_X = x + 0.25 - 0.15 - TROUGH_W / 2
        x -= TROUGH_W + 0.3 - 0.25
    stacks[size] = (x - bw / 2, FRONT + bd / 2, bs, H + COUNT[size] * BLANK)
    x -= bw + 0.25
SIDE_X0, SIDE_X1 = -W / 2 + 0.15, x + 0.1  # the far-end strip
TROUGH_Z0, TROUGH_Z1 = FRONT + 0.1, FRONT + 4.2


def tray_at(size):
    """The tray's centre (x, z) on a stack: the base panel's centre."""
    sx, _, bs, _ = stacks[size]
    return sx, FRONT + PB.tray_from_front(PB.pizza(bs))


LANDING = tray_at("Large")  # CutLanding: a pulled pizza waits on the Large stack

kit.reset()
STAINLESS = rgb(140, 145, 152)
steel = Mesh("Steel", STAINLESS, metal=1.0, rough=0.28)
dark = Mesh("Dark", rgb(40, 41, 45), rough=0.5)
card = Mesh("Cardboard", rgb(205, 168, 118), rough=0.85)
blanks = Mesh("Blanks", rgb(205, 168, 118), rough=0.85)
rocker = Mesh("Rocker", rgb(200, 204, 210), metal=1.0, rough=0.25, instanced=True)
rocker_grips = Mesh("RockerGrips", rgb(28, 28, 30), rough=0.5, instanced=True)
bottles = Mesh("Bottles", rgb(238, 236, 228), rough=0.35)
caps = Mesh("Caps", rgb(200, 35, 35), rough=0.4)
shakers = Mesh("Shakers", rgb(230, 215, 170), rough=0.4)
trash = Mesh("Trash", rgb(70, 72, 78), rough=0.6)


def tray(m: Mesh, x0, x1, z0, z1, y0, y1, lip=0.03):
    """A stainless liner dropped into an opening x0..x1, z0..z1: bottom at y0, walls to y1, a lip on top."""
    t = 0.02
    m.box((x1 - x0, t, z1 - z0), ((x0 + x1) / 2, y0 + t / 2, (z0 + z1) / 2))
    for z in (z0 + t / 2, z1 - t / 2):
        m.box((x1 - x0, y1 - y0, t), ((x0 + x1) / 2, (y0 + y1) / 2, z))
    for x_ in (x0 + t / 2, x1 - t / 2):
        m.box((t, y1 - y0, z1 - z0), (x_, (y0 + y1) / 2, (z0 + z1) / 2))
    for z in (z0 - lip / 2, z1 + lip / 2):
        m.box((x1 - x0 + 2 * lip, 0.012, lip), ((x0 + x1) / 2, y1 + 0.006, z))
    for x_ in (x0 - lip / 2, x1 + lip / 2):
        m.box((lip, 0.012, z1 - z0), (x_, y1 + 0.006, (z0 + z1) / 2))


# -- The top: square-edged, cut round the rocker trough and the seasoning
# insert (both lined with dropped-in stainless pans).
# The seasoning insert behind the Medium stack (long side along the table).
INSERT_Z0 = FRONT + blank(BOX["Medium"])[1] + 0.12
INSERT = (stacks["Medium"][0] - 0.55, stacks["Medium"][0] + 0.55, INSERT_Z0, INSERT_Z0 + 0.6)  # x0, x1, z0, z1
TROUGH = (TROUGH_X - TROUGH_W / 2, TROUGH_X + TROUGH_W / 2, TROUGH_Z0, TROUGH_Z1)


def top_piece(x0, x1, z0, z1):
    if x1 - x0 > 1e-6 and z1 - z0 > 1e-6:
        steel.box((x1 - x0, TOP_T, z1 - z0), ((x0 + x1) / 2, H - TOP_T / 2, (z0 + z1) / 2))


holes = sorted([INSERT, TROUGH])
xs = [-W / 2]
for c in holes:
    xs += [c[0], c[1]]
xs.append(W / 2)
for i in range(len(xs) - 1):
    x0, x1 = xs[i], xs[i + 1]
    hole = next((c for c in holes if abs(c[0] - x0) < 1e-9 and abs(c[1] - x1) < 1e-9), None)
    if hole:
        top_piece(x0, x1, -D / 2, hole[2])
        top_piece(x0, x1, hole[3], D / 2)
    else:
        top_piece(x0, x1, -D / 2, D / 2)
tray(steel, TROUGH[0], TROUGH[1], TROUGH[2], TROUGH[3], H - 0.42, H)
tray(steel, INSERT[0], INSERT[1], INSERT[2], INSERT[3], H - 0.32, H)

# -- The base: square corner legs on casters, solid end panels and back, two
# full shelves, a round middle post at the front (and a caster under the back's middle).
LEG = 0.16
WHEEL_R, MOUNT_Y = 0.2, 0.46
legs = [(sx * (W / 2 - LEG / 2), sz * (D / 2 - LEG / 2)) for sx in (-1, 1) for sz in (-1, 1)]
for lx, lz in legs:
    steel.box((LEG, H - TOP_T - MOUNT_Y, LEG), (lx, MOUNT_Y + (H - TOP_T - MOUNT_Y) / 2, lz))
PANEL_Y0 = 0.55
for sx in (-1, 1):
    steel.box((0.03, H - TOP_T - PANEL_Y0, D - 2 * LEG), (sx * (W / 2 - 0.015), PANEL_Y0 + (H - TOP_T - PANEL_Y0) / 2, 0))
steel.box((W - 2 * LEG, H - TOP_T - PANEL_Y0, 0.03), (0, PANEL_Y0 + (H - TOP_T - PANEL_Y0) / 2, D / 2 - 0.015))
SHELVES = (0.6, 1.75)
for y in SHELVES:
    steel.box((W - 0.06, 0.04, D - 0.1), (0, y, 0.02))
    steel.box((W - 2 * LEG, 0.12, 0.03), (0, y - 0.04, -D / 2 + 0.06))  # turned-down front edge
POST_X = 0.0
steel.cyl(0.07, H - TOP_T - MOUNT_Y, (POST_X, MOUNT_Y + (H - TOP_T - MOUNT_Y) / 2, -D / 2 + 0.1), segs=14)
for y in SHELVES:
    steel.cyl(0.09, 0.12, (POST_X, y + 0.08, -D / 2 + 0.1), segs=14)  # collars
casters = legs + [(POST_X, -D / 2 + 0.1), (POST_X, D / 2 - LEG / 2)]
for cx, cz in casters:
    steel.box((0.22, 0.03, 0.22), (cx, MOUNT_Y - 0.015, cz))
    steel.cyl(0.05, 0.06, (cx, MOUNT_Y - 0.06, cz), segs=10)
    for sx in (-1, 1):
        steel.box((0.02, MOUNT_Y - 0.09 - WHEEL_R, 0.1), (cx + sx * 0.08, WHEEL_R + (MOUNT_Y - 0.09 - WHEEL_R) / 2, cz + 0.05))
    dark.cyl(WHEEL_R, 0.1, (cx, WHEEL_R, cz + 0.05), axis="x", segs=18)
    steel.cyl(0.07, 0.11, (cx, WHEEL_R, cz + 0.05), axis="x", segs=10)

# -- On top: the boxes lying completely unfolded (the die-cut sheet, its tabs
# and flaps), one stack per size, front edges lined up. Drawn three blanks to
# a slab (a hair between slabs shows the layers); the top blank of each is
# StationArt's Blank_<Size>, the one the cut minigame folds.
SLAB = 3


def blank_stack(m, kind, tx, tz, y0, n, seed):
    """n blanks lying flat from y0 up, the tray centre at (tx, tz)."""
    for k in range(0, n, SLAB):
        c = min(SLAB, n - k)
        j = 0.012 * math.sin(k * 2.3 + seed)
        PB.draw(m, kind, PB.root_at(tx + j, y0 + BLANK * (k + c) - 0.002, tz + 0.6 * j), thick=BLANK * c - 0.004)


for size, _ in SIZES:
    tx, tz = tray_at(size)
    blank_stack(blanks, PB.pizza(BOX[size]), tx, tz, H, COUNT[size] - 1, tx)

# -- The rocker (the user's photo, a two-handled pizza rocker): a steel
# crescent, its spine straight, its cutting edge one long convex arc narrowing
# to the ends, a black handle riveted along the spine at each end. Built
# standing (length along X, edge down), its origin the lowest point of the
# edge, where the cut minigame's rocking pivots. StationArt stands two in the
# trough and gives the minigame its own copy (ReplicatedStorage.Rocker).
R_LEN, R_DEPTH, R_END = 3.4, 0.55, 0.12  # 20 in long; the blade's depth at the middle and at its ends
R_T = 0.022  # plate thickness
R_GRIP_L, R_GRIP_H, R_GRIP_W = 0.9, 0.17, 0.19  # each handle: length, height, width


def r_edge(x):
    return (R_DEPTH - R_END) * (2 * x / R_LEN) ** 2


outline = [(-R_LEN / 2 + R_LEN * i / 40, r_edge(-R_LEN / 2 + R_LEN * i / 40)) for i in range(41)]
outline += [(R_LEN / 2, R_DEPTH), (-R_LEN / 2, R_DEPTH)]
tmp = bmesh.new()
lo = [tmp.verts.new(rb(x_, y_, -R_T / 2)) for x_, y_ in outline]
hi = [tmp.verts.new(rb(x_, y_, R_T / 2)) for x_, y_ in outline]
faces = [tmp.faces.new(lo), tmp.faces.new(hi[::-1])]
for k in range(len(outline)):
    j = (k + 1) % len(outline)
    tmp.faces.new((lo[k], lo[j], hi[j], hi[k]))
bmesh.ops.triangulate(tmp, faces=faces, ngon_method="EAR_CLIP")
bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
rocker.add(tmp)
GRIP_Y = R_DEPTH - 0.04 + R_GRIP_H / 2  # the tang runs up into the handle
for sgn in (-1, 1):
    gx = sgn * (R_LEN / 2 - R_GRIP_L / 2 + 0.06)  # a little past the blade's end
    kit.loft(rocker_grips, [(y_, kit.rounded_rect(R_GRIP_L * k, R_GRIP_W * k, 0.07 * k, 4)) for y_, k in ((GRIP_Y - R_GRIP_H / 2, 0.94), (GRIP_Y - R_GRIP_H / 2 + 0.03, 1.0), (GRIP_Y + R_GRIP_H / 2 - 0.03, 1.0), (GRIP_Y + R_GRIP_H / 2, 0.9))], close_top=True, at=(gx, 0, 0))
    for rx in (gx - 0.25, gx + 0.25):  # rivets through the handle, a head each side
        for zs in (-1, 1):
            rocker.cyl(0.03, 0.01, (rx, GRIP_Y, zs * (R_GRIP_W / 2 + 0.003)), axis="z", segs=10)
R_HEIGHT = GRIP_Y + R_GRIP_H / 2
# Two stand in the trough, edge down on its pan, handles up, along its length.
TROUGH_ROCKERS = [(TROUGH_X + ox, H - 0.4, (TROUGH_Z0 + TROUGH_Z1) / 2) for ox in (-0.14, 0.14)]

# -- The seasoning insert behind the Medium stack: two shakers and a squeeze
# bottle standing in its pan.
IZ = (INSERT[2] + INSERT[3]) / 2
for x_ in (INSERT[0] + 0.2, INSERT[0] + 0.5):
    shakers.cyl(0.13, 0.42, (x_, H - 0.3 + 0.21, IZ), segs=14)
    caps.cyl(0.135, 0.06, (x_, H - 0.3 + 0.45, IZ), segs=14)
    caps.cyl(0.135, 0.04, (x_, H - 0.3 + 0.5, IZ), segs=14, radius2=0.09)
bx_ = INSERT[0] + 0.85
bottles.cyl(0.13, 0.55, (bx_, H - 0.3 + 0.275, IZ), segs=14)
bottles.cyl(0.13, 0.06, (bx_, H - 0.3 + 0.58, IZ), segs=14, radius2=0.07)
caps.cyl(0.05, 0.14, (bx_, H - 0.3 + 0.68, IZ), segs=10, radius2=0.015)

# -- The side boxes (the user: two sizes the side items share), lying unfolded
# like the pizza boxes, out of the way at the far end, front to back. The top
# blank of each is StationArt's.
SIDE_COUNT = 14
SX = (SIDE_X0 + SIDE_X1) / 2
side_front = {"SideLarge": FRONT, "SideSmall": FRONT + PB.blank_size(PB.SIDES["SideLarge"])[1] + 0.2}
side_x = {"SideLarge": SX, "SideSmall": SX}
side_stacks = {}  # name -> (tray x, tray z, top)
for name, kind in PB.SIDES.items():
    tz_ = side_front[name] + PB.tray_from_front(kind)
    blank_stack(blanks, kind, side_x[name], tz_, H, SIDE_COUNT - 1, tz_)
    side_stacks[name] = (side_x[name], tz_, H + SIDE_COUNT * BLANK)

# -- Underneath: unfolded blanks on the middle shelf; a case of boxes and
# three sloped bins of side-box blanks on the bottom shelf.
UNDER = (("Large", -W / 4, 12), ("Medium", W / 4, 12))
for size, sx_, count in UNDER:
    bw, bd = blank(BOX[size])
    blank_stack(blanks, PB.pizza(BOX[size]), sx_, 0.02 - bd / 2 + PB.tray_from_front(PB.pizza(BOX[size])), SHELVES[1] + 0.02, count, sx_)
BINS = (-4.9, -3.5, -2.1)
BIN_W, BIN_D, BIN_H = 1.2, 1.8, 0.55
for bx in BINS:
    by = SHELVES[0] + 0.02
    steel.box((BIN_W, 0.02, BIN_D), (bx, by + 0.01, 0.2))
    for sx in (-1, 1):
        steel.prism([(0.2 - BIN_D / 2, by), (0.2 + BIN_D / 2, by), (0.2 + BIN_D / 2, by + BIN_H), (0.2 - BIN_D / 2 + 0.3, by + BIN_H), (0.2 - BIN_D / 2, by + 0.3)], bx + sx * BIN_W / 2 - (0.01 if sx > 0 else 0), bx + sx * BIN_W / 2 + (0.01 if sx < 0 else 0))
    steel.box((BIN_W, BIN_H, 0.02), (bx, by + BIN_H / 2, 0.2 + BIN_D / 2))
    steel.box((BIN_W, 0.3, 0.02), (bx, by + 0.15, 0.2 - BIN_D / 2))
    for i in range(9):
        card.box((BIN_W - 0.12, 0.03, BIN_D - 0.15), (bx, by + 0.04 + 0.035 * i, 0.22))
CASE = (3.1, 3.4, 0.62, 3.0)  # x, w, h, d
card.box((CASE[1], CASE[2], CASE[3]), (CASE[0], SHELVES[0] + 0.02 + CASE[2] / 2, 0.0), bevel=0.02)

# -- The trash can on the counter side.
TX, TZ, TR, TH = 0.0, D / 2 + 0.9, 0.65, 2.2
kit.loft(trash, [(0.0, kit.rounded_rect(2 * TR * 0.9, 2 * TR * 0.9, TR * 0.9, 8)), (TH, kit.rounded_rect(2 * TR, 2 * TR, TR, 8))], close_bottom=True, at=(TX, 0, TZ), thickness=0.03)
kit.tube(trash, [(TX + TR * math.cos(math.tau * k / 32), TZ + TR * math.sin(math.tau * k / 32)) for k in range(33)], TH, 0.04, segs=8)
for sx in (-1, 1):
    trash.box((0.08, 0.12, 0.35), (TX + sx * (TR + 0.03), TH - 0.25, TZ))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


def footprint(size):
    sx, sz, bs, _ = stacks[size]
    bw, bd = blank(bs)
    return (sx - bw / 2 - 0.02, sz - bd / 2, sx + bw / 2 + 0.02, sz + bd / 2 + 0.02)


def overlap(a, b, gap=0.0):
    return a[0] < b[2] + gap and b[0] < a[2] + gap and a[1] < b[3] + gap and b[1] < a[3] + gap


FEET = [footprint(s) for s, _ in SIZES]
trough_r = (TROUGH[0] - 0.03, TROUGH[2] - 0.03, TROUGH[1] + 0.03, TROUGH[3] + 0.03)
insert_r = (INSERT[0] - 0.03, INSERT[2] - 0.03, INSERT[1] + 0.03, INSERT[3] + 0.03)


def side_foot(name):
    x_, tz_, _ = side_stacks[name]
    sw, sd = PB.blank_size(PB.SIDES[name])
    z0 = tz_ - PB.tray_from_front(PB.SIDES[name])
    return (x_ - sw / 2 - 0.02, z0, x_ + sw / 2 + 0.02, z0 + sd + 0.02)


FAR = tuple(side_foot(n) for n in PB.SIDES) + (insert_r,)
check("stacks on the top, front 0.2 in, back short of the edge", all(f[0] > -W / 2 and f[2] < W / 2 and f[1] >= -D / 2 + 0.2 - 1e-9 and f[3] < D / 2 - 0.05 for f in FEET))
check("stacks clear of each other, the trough and the far end", not any(overlap(a, b) for i, a in enumerate(FEET) for b in FEET[i + 1:]) and not any(overlap(f, r, 0.05) for f in FEET for r in (trough_r,) + FAR))
check("side stacks and the insert on the top, clear of each other", all(r[0] > -W / 2 + 0.05 and r[2] < W / 2 - 0.05 and r[1] >= -D / 2 + 0.2 - 1e-9 and r[3] < D / 2 - 0.05 for r in FAR) and not any(overlap(a, b, 0.05) for i, a in enumerate(FAR) for b in FAR[i + 1:]))
check("side stacks stay in the far-end strip", all(side_foot(n)[2] < SIDE_X1 + 0.05 for n in PB.SIDES))
check("rockers stand inside the trough, clear of each other", TROUGH_W / 2 - 0.02 > 0.14 + R_GRIP_W / 2 + 0.01 and 0.14 > R_GRIP_W / 2 + 0.01 and R_LEN + 0.12 < TROUGH_Z1 - TROUGH_Z0 - 0.1)
check("a Large pizza (2.4) fits the Large box's walls", BOX["Large"] - 2 * 0.04 > 2.4)
check("CutLanding's pizza on the Large stack's base panel", abs(LANDING[1] - (FRONT + PB.tray_from_front(PB.pizza(BOX["Large"])))) < 1e-9)
check("shelf stacks under the top, inside the panels, clear of the post", all(SHELVES[1] + 0.02 + BLANK * c < H - TOP_T - 0.05 for _, _, c in UNDER) and all(abs(sx_) + blank(BOX[s])[0] / 2 < W / 2 - 0.05 and abs(sx_ - POST_X) - blank(BOX[s])[0] / 2 > 0.1 and blank(BOX[s])[1] < D - 0.2 for s, sx_, _ in UNDER))
check("bottom shelf: bins and the case under the middle shelf, clear of the post and each other", max(BINS) + BIN_W / 2 < POST_X - 0.1 and min(BINS) - BIN_W / 2 > -W / 2 + 0.05 and all(b - a > BIN_W for a, b in zip(BINS, BINS[1:])) and CASE[0] - CASE[1] / 2 > POST_X + 0.1 and CASE[0] + CASE[1] / 2 < W / 2 - 0.05 and SHELVES[0] + 0.02 + max(CASE[2], BIN_H) < SHELVES[1] - 0.1)
check("wheels under the bottom shelf", 2 * WHEEL_R < SHELVES[0] - 0.05)
check("trash clear of the table's back", TZ - TR - 0.04 > D / 2 + 0.05)
print(f"[layout] rockers {[(round(x_, 3), round(y_, 3), round(z_, 3)) for x_, y_, z_ in TROUGH_ROCKERS]}")
print(f"[layout] sides { {n: tuple(round(v, 3) for v in t) for n, t in side_stacks.items()} } (tray x, z, top)")
print(f"[layout] W {W}; stacks { {s: (round(c[0], 3), round(c[1], 3), round(c[3], 3)) for s, c in stacks.items()} }; landing ({LANDING[0]:.3f}, {LANDING[1]:.3f})")

# -- Preview only: the top blanks (StationArt's parts), a pulled pizza
# waiting on the Large one, a pizza being cut flat on the Medium one; and,
# beside the table, a Large box at five points of the fold (what the cut
# minigame plays once the pizza's cut).
pv = Mesh("BlankPreview", rgb(214, 180, 130), rough=0.85)
for size, _ in SIZES:
    tx, tz = tray_at(size)
    PB.draw(pv, PB.pizza(BOX[size]), PB.root_at(tx, stacks[size][3], tz))
for name, (x_, tz_, top_) in side_stacks.items():
    PB.draw(pv, PB.SIDES[name], PB.root_at(x_, top_, tz_))
piz = Mesh("PizzaPreview", rgb(214, 160, 90), rough=0.7)
chs = Mesh("CheesePreview", rgb(245, 205, 110), rough=0.6)
cuts = Mesh("CutPreview", rgb(120, 80, 40), rough=0.8)


def pizza_at(x_, y0, z_, d_, cut=False, yaw=0.0):
    kit.loft(piz, [(y0, kit.rounded_rect(d_, d_, d_ / 2, 8)), (y0 + 0.08, kit.rounded_rect(d_ - 0.06, d_ - 0.06, d_ / 2 - 0.03, 8))], close_top=True, at=(x_, 0, z_))
    kit.loft(chs, [(y0 + 0.082, kit.rounded_rect(d_ - 0.4, d_ - 0.4, d_ / 2 - 0.2, 8))], close_bottom=False, close_top=True, at=(x_, 0, z_))
    if cut:
        for k in range(4):
            cuts.box((d_ - 0.1, 0.01, 0.025), (x_, y0 + 0.088, z_), r=kit.rot("y", yaw + 45 * k))


for size, d_, cut in (("Large", 2.4, False), ("Medium", 12 * INCH, True)):
    tx, tz = tray_at(size)
    pizza_at(tx, stacks[size][3], tz, d_, cut)
fold = Mesh("FoldPreview", rgb(214, 180, 130), rough=0.85)
FOLD_AT = [(t_, -10.0 + 3.6 * k) for k, t_ in enumerate((0.2, 0.5, 0.8, 1.15, PB.TIME))]
for t_, z_ in FOLD_AT:
    PB.draw(fold, PB.pizza(BOX["Large"]), PB.root_at(16.0, PB.THICK, z_, -90), t=t_)
    if t_ < 1.3:
        pizza_at(16.0, PB.THICK, z_, 2.4, True)
# The two side boxes folding, in their own rows off past the oven end.
for k, (t_, _z) in enumerate(FOLD_AT):
    for name, zrow in (("SideLarge", 8.8), ("SideSmall", 11.6)):
        PB.draw(fold, PB.SIDES[name], PB.root_at(8.0 + 2.5 * k, PB.THICK, zrow), t=t_)
for m in (pv, piz, chs, cuts, fold):
    kit.preview(m)

kit.finish(
    "cut_table",
    [steel, dark, card, blanks, rocker, rocker_grips, bottles, caps, shakers, trash],
    [(m.name, (x_, y_ + (m.bounds()[0].y + m.bounds()[1].y) / 2, z_), yaw, 1) for m in (rocker, rocker_grips) for x_, y_, z_, yaw in [(*t, 90) for t in TROUGH_ROCKERS] + [(W / 2 + 6, 2.0 - R_HEIGHT / 2, -6.0, 0)]],
    [
        ("overview", (4.0, 12.0, -16.0), (-0.6, 2.6, 0.2), 32),
        ("fold", (36.0, 12.0, -2.8), (16.0, 0.3, -2.8), 62),
        ("foldclose", (19.5, 3.2, -9.5), (16.0, 0.2, -6.4), 44),
        ("sidefold", (13.0, 7.5, 2.5), (13.0, 0.2, 10.2), 58),
        ("rocker", (W / 2 + 6, 2.15, -12.4), (W / 2 + 6, 2.05, -6.0), 36),
        ("rockerside", (W / 2 + 8.8, 3.0, -9.0), (W / 2 + 6, 2.0, -6.0), 40),
        ("top", (0.5, 11.0, -8.0), (0.0, 3.6, 0.3), 42),
        ("farend", (-2.6, 6.5, -6.5), (-5.2, 3.6, -0.3), 36),
        ("under", (1.0, 1.9, -10.5), (0.0, 1.4, 0.0), 36),
        ("back", (-3.0, 8.5, 13.0), (0.0, 3.0, 0.5), 32),
    ],
    kit.args()["render"],
)
