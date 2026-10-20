"""Sauce corner, after the user's photos: separate stainless tables pushed
together, their connecting ends the same size (tools/blender/layout.py). The
trapezoid corner table along the angled lobby wall, between the dough table's
end and the sauce table, its front parallel to its back; the sauce table, its
front flush with the makeline's. Each stands on its own four legs with rails
low down at the sides and back, open underneath (no shelves, nothing stored
under the sauce table). Rolled front edges and backsplashes meet the next
table's mitred, so nothing overlaps. On the corner table: two tall wire
pizza-screen racks side by side, backs to its splash. On the sauce table: the
Cambro-style sauce tub in the back corner against the makeline, its red-handled
spoodle resting on the rim, the saucing spot right in front of it, drips
around the spot. Also the instanced pieces other code uses: the pizza screen
(scaled to each pizza size, with a wire mesh texture) and the spoodle the
Sauce minigame holds.

    blender -b -P tools/blender/sauce_table.py -- --render

Art-local = the sauce table's centre (layout.SAUCE_CX/CZ), worker at -Z.
StationArt.Layout.SauceTable takes its numbers from this script's printout.
StationArt keeps the gameplay pieces: the SkinSlot_<n> markers and RackBounds
come from its screenRack.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import layout as LY  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

H = 3.4
W, D = LY.MAKELINE_X - LY.SAUCE_LEFT_X, LY.SAUCE_DEPTH  # the sauce table
C1, C2, C3, C4 = (LY.to_sauce(*p) for p in (LY.C1, LY.C2, LY.C3, LY.C4))  # the corner table
CORNER = [C1, C2, C4, C3]
SAUCE = [(-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)]
DOUGH = [LY.to_sauce(x, z) for x, z in ((LY.DOUGH_FRONT_X, 9.9), (LY.DOUGH_FRONT_X, LY.DOUGH_END_Z), (LY.DOUGH_BACK_X, LY.DOUGH_END_Z), (LY.DOUGH_BACK_X, 9.9))]
RACK_LIFT = 0.35  # slots raised so the minigame's spoodle (held 0.26 up, tipped) passes under the lowest ledges
SLOTS, SPACING = 15, 0.2  # Config.Dough.SlotsPerRack
WIRE = 0.05  # StationArt screenRack's wire: a slot marker sits WIRE / 2 over its rail
INCH = 2.4 / 14  # Config.StudsPerInch
PIZZA = {"Small": 10 * INCH, "Medium": 12 * INCH, "Large": 14 * INCH}
SCREEN_RIM = 0.06  # a screen is its pizza's size plus the rim (StationArt.Screen)
LARGE_SCREEN = (14 * INCH + SCREEN_RIM) / 2  # radius
BULL = 0.07  # rolled front edge radius (as on the dough table)
CUP_R, CUP_D = 0.262, 0.17  # the spoodle's cup
SPOODLE_REACH = 1.2 + 0.25 + CUP_R  # the minigame's clamp (Large pizza radius + 0.25) plus the cup
TUB_R = 0.84  # the tub's lip
TUB_X, TUB_Z = W / 2 - TUB_R - 0.01, D / 2 - 0.05 - TUB_R - 0.02  # in the back corner against the makeline and the wall
# The saucing spot right in front of the tub: a Large skin inside the table's
# edge, just out of the minigame spoodle's reach of the tub.
WORK_X = W / 2 - 1.2 - 0.05
WORK_Z = TUB_Z - math.sqrt((SPOODLE_REACH + TUB_R + 0.02) ** 2 - (TUB_X - WORK_X) ** 2)


def unit(v):
    ln = math.hypot(*v)
    return (v[0] / ln, v[1] / ln)


# The racks: side by side on the corner table, backs to its splash, a Large
# screen plus the splash's folded top (0.145) and a hair off it, centred
# between its sides at that depth.
U = unit((C4[0] - C2[0], C4[1] - C2[1]))  # along its back, dough side to sauce side
NRM = (U[1], -U[0]) if (C1[0] - C2[0]) * U[1] - (C1[1] - C2[1]) * U[0] > 0 else (-U[1], U[0])  # toward its front
OFF = LARGE_SCREEN + 0.145 + 0.06


def meet(a, b):
    """Where the line at depth OFF meets the side a -> b (a distance along U from C2)."""
    ox, oz = C2[0] + NRM[0] * OFF, C2[1] + NRM[1] * OFF
    sx, sz = b[0] - a[0], b[1] - a[1]
    det = U[0] * -sz - U[1] * -sx
    return ((a[0] - ox) * -sz - (a[1] - oz) * -sx) / det


middle = (meet(C2, C1) + meet(C4, C3)) / 2
RACKS = [(C2[0] + U[0] * t + NRM[0] * OFF, C2[1] + U[1] * t + NRM[1] * OFF) for t in (middle - 1.25, middle + 1.25)]
RACK_YAW = math.degrees(math.atan2(-NRM[0], -NRM[1]))  # turns a rack's front (-Z) to face N


kit.reset()
steel = Mesh("Steel", rgb(140, 145, 152), metal=1.0, rough=0.28)
rubber = Mesh("Rubber", rgb(30, 30, 33), rough=0.8)
racks = Mesh("Racks", rgb(215, 218, 222), metal=1.0, rough=0.15)
tubs = Mesh("Tubs", rgb(236, 236, 230), rough=0.25)
tubs.alpha = 0.22  # clear plastic, two walls deep (StationArt: Transparency 0.6)
sauce = Mesh("Sauce", rgb(135, 40, 28), rough=0.35)
grips = Mesh("Grips", rgb(200, 35, 35), rough=0.45)
screen = Mesh("Screen", rgb(190, 190, 186), metal=0.8, rough=0.4, instanced=True)
spoodle = Mesh("Spoodle", rgb(200, 204, 210), metal=1.0, rough=0.2, instanced=True)
spoodle_grip = Mesh("SpoodleGrip", rgb(200, 35, 35), rough=0.45, instanced=True)


def circle(r: float, segs: int = 24):
    return [(r * math.cos(math.tau * i / segs), r * math.sin(math.tau * i / segs)) for i in range(segs)]


def inset(poly, dist):
    """The polygon's corners moved dist inward (mitred)."""
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))
    side = 1 if area > 0 else -1  # left of each edge is inside for a counter-clockwise outline
    out = []
    for i, p in enumerate(poly):
        a, b = poly[i - 1], poly[(i + 1) % len(poly)]
        n1 = unit((-(p[1] - a[1]) * side, (p[0] - a[0]) * side))
        n2 = unit((-(b[1] - p[1]) * side, (b[0] - p[0]) * side))
        k = 1 + n1[0] * n2[0] + n1[1] * n2[1]
        out.append((p[0] + dist * (n1[0] + n2[0]) / k, p[1] + dist * (n1[1] + n2[1]) / k))
    return out


def leg(x, z):
    """A tubular leg with a gusset under the top and a bullet foot (as on the dough table)."""
    steel.cyl(0.085, H - 0.45, (x, 0.13 + (H - 0.45) / 2, z), segs=14)
    steel.cyl(0.1, 0.22, (x, H - 0.21, z), segs=14, radius2=0.17)
    steel.cyl(0.065, 0.13, (x, 0.065, z), segs=12, radius2=0.085)
    steel.cyl(0.095, 0.05, (x, 0.15, z), segs=14)


def rail(a, b):
    steel.rod((a[0], 0.65, a[1]), (b[0], 0.65, b[1]), 0.06, segs=10)


# -- The corner table: its trapezoid top, a rolled front edge mitred into the
# dough table's (coming along +z) and the sauce table's (going on along +x),
# an apron under it, a backsplash with a folded top along its back, mitred into
# the sauce table's splash and the dough table's. Legs at its four corners.
kit.loft(steel, [(H - 0.1, CORNER), (H, CORNER)], close_bottom=True, close_top=True)
before, after = (C1[0], C1[1] - 1), (C3[0] + 1, C3[1])
kit.tube(steel, [C1, C3], H - BULL, BULL, before=before, after=after)
kit.ribbon(steel, [C1, C3], 0.045, 0.075, H - 0.3, H - 0.1, before=before, after=after)
back = [C4, C2]
kit.ribbon(steel, back, 0.0, 0.05, H, H + 0.45, before=(C4[0] + 1, C4[1]), after=(C2[0], C2[1] - 1))
kit.ribbon(steel, back, 0.0, 0.14, H + 0.42, H + 0.45, before=(C4[0] + 1, C4[1]), after=(C2[0], C2[1] - 1))
CORNER_LEGS = inset(CORNER, 0.3)
for p in CORNER_LEGS:
    leg(*p)
k1, k2, k4, k3 = CORNER_LEGS
for a, b in ((k1, k2), (k2, k4), (k4, k3)):  # sides and back; open at the front
    rail(a, b)

# -- The sauce table: top, rolled front edge (mitred into the corner table's),
# apron, backsplash (mitred into the corner table's), four legs, side and back
# rails. Nothing underneath.
kit.loft(steel, [(H - 0.1, SAUCE), (H, SAUCE)], close_bottom=True, close_top=True)
front = [C3, (W / 2, -D / 2)]
kit.tube(steel, front, H - BULL, BULL, before=C1)
kit.ribbon(steel, front, 0.045, 0.075, H - 0.3, H - 0.1, before=C1)
kit.ribbon(steel, [(W / 2, D / 2), C4], 0.0, 0.05, H, H + 0.45, after=C2)
SAUCE_LEGS = inset(SAUCE, 0.3)
for p in SAUCE_LEGS:
    leg(*p)
s1, s2, s3, s4 = SAUCE_LEGS  # front-left, front-right, back-right, back-left in art x (makeline at +x)
for a, b in ((s1, s4), (s4, s3), (s3, s2)):
    rail(a, b)

# -- The spoodle (the user's photo): a flat-bottomed stainless cup holding
# 3.5 oz (3 in across, 0.9 in deep inside), a round shaft leaving its rim
# nearly in line, toward the worker (-Z), a flat red grip with a hanging hole.
# Built around the cup's centre; the Sauce minigame tips it back a little.
LIFT = 12.0  # the shaft leaves the cup's rim nearly in line with it (the user's photo)
kit.loft(spoodle, [(-CUP_D / 2, circle(CUP_R - 0.03, 24)), (-CUP_D / 2 + 0.008, circle(CUP_R - 0.012, 24)), (CUP_D / 2 - 0.01, circle(CUP_R, 24)), (CUP_D / 2, circle(CUP_R + 0.014, 24))], thickness=0.012)
d = (0.0, math.sin(math.radians(LIFT)), -math.cos(math.radians(LIFT)))
s0 = (0.0, CUP_D / 2 - 0.02, -CUP_R + 0.01)
end = tuple(a + 0.85 * b for a, b in zip(s0, d))
spoodle.rod(s0, end, 0.03, segs=10)
spoodle.rod(tuple(a - 0.08 * b for a, b in zip(end, d)), end, 0.042, segs=12)  # ferrule
grip = Mesh("_grip", (0, 0, 0, 1))
rr = kit.rounded_rect
kit.loft(grip, [(0.0, rr(0.09, 0.05, 0.022, 3)), (0.06, rr(0.15, 0.042, 0.02, 3)), (0.78, rr(0.17, 0.042, 0.02, 3)), (0.85, rr(0.15, 0.042, 0.02, 3)), (0.87, rr(0.1, 0.036, 0.016, 3))], close_top=True)
hole = Mesh("_hole", (0, 0, 0, 1))
hole.cyl(0.035, 0.2, (0, 0.74, 0), axis="z", segs=16)
kit.cut(grip, hole)
spoodle_grip.merge(grip, at=end, r=kit.rot("x", -(90 - LIFT)))

# -- The sauce tub (the user's photo of the real ones: a clear round
# Cambro-style container): a squat body with a slight taper, a short flare up
# to a wider straight band round the top quarter, a thin lip, two small ear
# tabs on the band; dark sauce inside, smeared up into the band; the spoodle
# lying in it with its flat grip resting on the rim.
TUB = [(0.0, 0.73), (0.03, 0.75), (0.82, 0.785), (0.84, 0.81), (0.86, 0.82), (1.1, 0.825), (1.1, 0.838), (1.15, TUB_R), (1.15, 0.805)]
WALL_T, LEVEL, RIM = 0.022, 0.72, 1.15
kit.loft(tubs, [(y, circle(rad, 48)) for y, rad in TUB], at=(TUB_X, H, TUB_Z), thickness=WALL_T)
for ang in (135, 315):  # ears on the diagonal, clear of the makeline and the wall
    a = math.radians(ang)
    tubs.box((0.075, 0.09, 0.24), (TUB_X + 0.855 * math.cos(a), H + 0.95, TUB_Z - 0.855 * math.sin(a)), bevel=0.012, r=kit.rot("y", ang))


def inner(y: float) -> float:
    if y < 0.82:
        out = 0.75 + (0.785 - 0.75) * (y - 0.03) / 0.79
    elif y < 0.86:
        out = 0.785 + (0.82 - 0.785) * (y - 0.82) / 0.04
    else:
        out = 0.82 + 0.005 * min(1.0, (y - 0.86) / 0.24)
    return out - WALL_T


kit.loft(sauce, [(0.03, circle(inner(0.03) - 0.004, 48)), (LEVEL, circle(inner(LEVEL) - 0.004, 48))], close_bottom=True, close_top=True, at=(TUB_X, H, TUB_Z))
smear = Mesh("_smear", (0, 0, 0, 1))
N = 64


def band(y0, top, gap=0.005):
    """A continuous coat of sauce on the wall from y0 up to top(angle), following the wall."""
    low, high = [], []
    for i in range(N):
        a = math.tau * i / N
        y1 = top(a)
        low.append(smear.bm.verts.new(rb((inner(y0) - gap) * math.cos(a), y0, (inner(y0) - gap) * math.sin(a))))
        high.append(smear.bm.verts.new(rb((inner(y1) - gap) * math.cos(a), y1, (inner(y1) - gap) * math.sin(a))))
    for i in range(N):
        j = (i + 1) % N
        smear.bm.faces.new((low[i], low[j], high[j], high[i]))


def wave(a: float, k: float) -> float:
    return (0.5 + 0.5 * math.sin(3 * a + k)) * (0.6 + 0.4 * math.sin(7 * a + 2 * k))


band(LEVEL - 0.01, lambda a: LEVEL + 0.02 + (0.81 - LEVEL - 0.02) * min(1.0, 0.4 + wave(a, 1)))  # thick below the step
band(0.87, lambda a: 0.875 + 0.15 * wave(a, 4))  # smears up the band
bmesh.ops.solidify(smear.bm, geom=smear.bm.faces[:], thickness=0.004)
sauce.merge(smear, at=(TUB_X, H, TUB_Z))


def resting(alpha: float, yaw: float, back: float):
    """The spoodle's pose in the tub: tipped to `alpha` degrees, its cup `back` behind the centre."""
    r = kit.rot("y", yaw) @ kit.rot("x", alpha - LIFT)
    dz = Vector((math.sin(math.radians(yaw)) * back, 0, math.cos(math.radians(yaw)) * back))  # away from the grip
    return r, (TUB_X + dz.x, H + LEVEL - 0.09, TUB_Z + dz.z)


def grip_low_at_rim(alpha: float, yaw: float, back: float) -> float:
    """The lowest point of the grip's flat underside over the rim's top (or +inf if it misses the rim)."""
    r, at = resting(alpha, yaw, back)
    t = (0.0, math.sin(math.radians(90 - LIFT)), math.cos(math.radians(90 - LIFT)))  # the grip's flat face normal
    low = math.inf
    for i in range(175):
        u = 0.005 * i
        local = [e + u * dd - 0.021 * tt for e, dd, tt in zip(end, d, t)]
        p = r @ rb(*local)
        x, y, z = p.x + at[0], p.z + at[1], -p.y + at[2]
        if 0.805 <= math.hypot(x - TUB_X, z - TUB_Z) <= TUB_R:
            low = min(low, y)
    return low


YAW, BACK = -20.0, 0.34  # grip out over the front rim, angled away from the skin
lo_a, hi_a = 2.0, 44.0
for _ in range(30):  # tip it until the grip's underside sits on the rim
    mid = (lo_a + hi_a) / 2
    if grip_low_at_rim(mid, YAW, BACK) < H + RIM:
        lo_a = mid
    else:
        hi_a = mid
assert grip_low_at_rim(hi_a, YAW, BACK) < H + RIM + 0.01, "the grip doesn't reach the rim"
pose, at = resting(hi_a, YAW, BACK)
print(f"[sauce] spoodle rests at {hi_a:.1f} degrees")
steel.merge(spoodle, at=at, r=pose)
grips.merge(spoodle_grip, at=at, r=pose)

# -- Sauce drips around the saucing spot (from the spoodle, flat on the steel).
DRIPS = ((-1.35, -0.45, 0.16), (-1.5, -0.3, 0.06), (-1.0, 0.85, 0.11), (-1.15, 0.72, 0.05), (0.75, 1.05, 0.08))
for dx_, dz_, r in DRIPS:
    ring = [(WORK_X + dx_ + x * (1 + 0.12 * math.sin(2.3 * i + dx_)), WORK_Z + dz_ + z * (1 + 0.12 * math.sin(2.3 * i + dx_))) for i, (x, z) in enumerate(circle(r, 16))]
    kit.loft(sauce, [(H + 0.004, ring)], close_bottom=False, close_top=True)

# -- Two tall wire pizza-screen racks side by side (the user's photo): a wire
# base on the counter, two back posts joined by an arch, and per slot a wire
# each side that runs forward from the post, steps in (so every screen size
# rests on it, the big ones overhanging) and dips at the front tip. Slot
# heights as in StationArt's screenRack (with RACK_LIFT). The posts stand clear
# of a Large screen's rim.
PW, LX, BACK_POST = 0.9, 0.75, 0.9  # post and ledge half-widths (a Small screen is 0.89 in radius), posts behind centre
top_rail = H + 0.2 + RACK_LIFT + (SLOTS - 1) * SPACING
y_top = top_rail + 0.12
r = 0.02
rack, feet = Mesh("_rack", (0, 0, 0, 1)), Mesh("_feet", (0, 0, 0, 1))
zb, zf = BACK_POST, -0.85
base = [(-0.9, -1.0), (0.9, -1.0), (0.9, zb + 0.05), (-0.9, zb + 0.05)]
for (ax, az), (bx_, bz_) in zip(base, base[1:] + base[:1]):
    rack.rod((ax, H + 0.025, az), (bx_, H + 0.025, bz_), 0.025, segs=6)
rack.rod((-0.9, H + 0.025, 0), (0.9, H + 0.025, 0), 0.025, segs=6)
for sx in (-1, 1):
    rack.rod((sx * PW, H + 0.02, zb), (sx * PW, y_top, zb), 0.03, segs=8)
    feet.box((0.1, 0.03, 0.1), (sx * 0.9, H + 0.015, -1.0))
    feet.box((0.1, 0.03, 0.1), (sx * 0.9, H + 0.015, zb + 0.05))
arch = [(-PW * math.cos(math.pi * i / 8), y_top + 0.3 * math.sin(math.pi * i / 8), zb) for i in range(9)]
for a, b in zip(arch, arch[1:]):
    rack.rod(a, b, 0.03, segs=8, caps=False)
for i in range(SLOTS):
    y = top_rail - i * SPACING
    for sx in (-1, 1):
        path = [(sx * PW, y, zb), (sx * PW, y, zb - 0.45), (sx * LX, y, zb - 0.6), (sx * LX, y, zf + 0.1), (sx * LX, y - 0.05, zf)]
        for a, b in zip(path, path[1:]):
            rack.rod(a, b, r, segs=6, caps=False)
for cx, cz in RACKS:
    racks.merge(rack, at=(cx, 0, cz), r=kit.rot("y", RACK_YAW))
    rubber.merge(feet, at=(cx, 0, cz), r=kit.rot("y", RACK_YAW))
print(f"[sauce] racks at {[(round(x, 3), round(z, 3)) for x, z in RACKS]}, turned {RACK_YAW:.1f} degrees")

# -- The pizza screen, 1 stud across (StationArt scales it to each pizza): a
# wire mesh disc with a solid rolled rim. The texture's holes are clear.
RS = 0.5
kit.loft(screen, [(0.0, circle(RS - 0.016, 48))], close_bottom=False, close_top=True)
kit.loft(screen, [(-0.001, circle(RS - 0.016, 48))], close_bottom=True, close_top=False)
kit.loft(screen, [(y, circle(rad, 48)) for y, rad in ((-0.012, RS - 0.018), (-0.012, RS), (0.02, RS), (0.02, RS - 0.018), (-0.012, RS - 0.0181))], close_bottom=False)
kit.planar_uv(screen, RS)


def screen_texture(px: int):
    """Aluminium wire mesh in diamonds (clear holes), a solid band and rim outside r = 0.47."""
    v, u = (np.mgrid[0:px, 0:px] + 0.5) / px - 0.5
    rad = np.hypot(u, v)
    pitch, wire = 9, 2.6
    a, b = (u + v) * px / pitch, (u - v) * px / pitch
    on = (np.abs(a - np.round(a)) * pitch < wire / 2) | (np.abs(b - np.round(b)) * pitch < wire / 2)
    solid = rad > 0.47
    rgba = np.zeros((px, px, 4))
    shade = 0.72 + 0.06 * np.sin(u * 40) * np.cos(v * 37)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = shade, shade, shade * 0.97
    rgba[..., 3] = np.where(on | solid, 1.0, 0.0)
    rgba[solid, :3] = 0.78
    return rgba


out = os.path.join(kit.OUT_ROOT, "sauce_table")
os.makedirs(out, exist_ok=True)
screen.texture = kit.save_png(os.path.join(out, "screen_mesh.png"), screen_texture(512))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


def inside(poly, x, z):
    hit = False
    for (ax, az), (bx_, bz_) in zip(poly, poly[1:] + poly[:1]):
        if (az > z) != (bz_ > z) and x < ax + (z - az) * (bx_ - ax) / (bz_ - az):
            hit = not hit
    return hit


def ring(cx, cz, rad, n=72):
    return [(cx + rad * math.cos(math.tau * i / n), cz + rad * math.sin(math.tau * i / n)) for i in range(n)]


def side_dist(x, z, a, b):
    """Distance from (x, z) to the line a -> b, positive on its left."""
    ux, uz = unit((b[0] - a[0], b[1] - a[1]))
    return (x - a[0]) * -uz + (z - a[1]) * ux


TOPS = (CORNER, SAUCE, DOUGH)


def on_top(x, z):
    return any(inside(t, x, z) for t in TOPS)


for k, (cx, cz) in enumerate(RACKS, 1):
    depth = side_dist(cx, cz, C2, C4) if side_dist(C1[0], C1[1], C2, C4) > 0 else -side_dist(cx, cz, C2, C4)
    check(f"rack {k}: Large screens clear the corner splash and its fold", depth - LARGE_SCREEN >= 0.145 + 0.02)
    check(f"rack {k}: posts clear the fold", depth - BACK_POST - 0.03 >= 0.145 + 0.02)
    check(f"rack {k}: Large screens over the counters", all(on_top(x, z) for x, z in ring(cx, cz, LARGE_SCREEN)))
    feet_at = [(cx + a * U[0] - o * NRM[0], cz + a * U[1] - o * NRM[1]) for a in (-0.95, 0.95) for o in (-1.05, BACK_POST + 0.1)]
    check(f"rack {k}: base on the counters", all(on_top(x, z) for x, z in feet_at))
    print(f"[check] note rack {k}: base corners on the corner table: {sum(inside(CORNER, x, z) for x, z in feet_at)}/4")
    check(f"rack {k}: screens clear the skin being sauced", math.hypot(cx - WORK_X, cz - WORK_Z) >= 1.2 + LARGE_SCREEN + 0.02)
check("racks: Large screens clear each other", math.hypot(RACKS[0][0] - RACKS[1][0], RACKS[0][1] - RACKS[1][1]) >= 2 * LARGE_SCREEN + 0.02)
check("racks: the minigame spoodle (top 0.42 up) passes under the lowest ledge tip", 0.2 + RACK_LIFT - 0.02 - 0.05 >= 0.26 + CUP_D / 2 + CUP_R * math.sin(math.radians(15)) + 0.01)
check("skin at the spot on the sauce table", all(inside(SAUCE, x, z) for x, z in ring(WORK_X, WORK_Z, 1.2)))
EARS = TUB_R + 0.06
check("tub on the sauce table, short of the makeline and the backsplash", all(inside(SAUCE, x, z) for x, z in ring(TUB_X, TUB_Z, TUB_R)) and TUB_X + TUB_R <= W / 2 and TUB_Z + TUB_R <= D / 2 - 0.05)
check("tub's ears clear of the makeline and the backsplash", all(TUB_X + EARS * math.cos(math.radians(a)) <= W / 2 - 0.01 and TUB_Z - EARS * math.sin(math.radians(a)) <= D / 2 - 0.06 for a in (135, 315)))
check("tub clear of the minigame spoodle's reach", math.hypot(TUB_X - WORK_X, TUB_Z - WORK_Z) >= SPOODLE_REACH + TUB_R + 0.019)
check("tub clear of the racks' screens", all(math.hypot(TUB_X - cx, TUB_Z - cz) >= LARGE_SCREEN + EARS for cx, cz in RACKS))
check("drips on the sauce table, off the tub and the skin", all(inside(SAUCE, WORK_X + dx, WORK_Z + dz) and math.hypot(WORK_X + dx - TUB_X, WORK_Z + dz - TUB_Z) > TUB_R + r and math.hypot(dx, dz) > 1.2 for dx, dz, r in DRIPS))
for name, poly, legs in (("corner", CORNER, CORNER_LEGS), ("sauce", SAUCE, SAUCE_LEGS)):
    check(f"{name} table's legs under its own top (gussets inside)", all(min(abs(side_dist(x, z, a, b)) for a, b in zip(poly, poly[1:] + poly[:1])) >= 0.17 and inside(poly, x, z) for x, z in legs))
dough_legs = [LY.to_sauce(LY.DOUGH_CX - lz, LY.DOUGH_CZ + lx) for lx in (-6.15, 1.2, 6.15) for lz in (-1.95, 1.95)]
all_legs = CORNER_LEGS + SAUCE_LEGS + dough_legs
check("legs of neighbouring tables don't touch (gussets 0.17)", all(math.hypot(a[0] - b[0], a[1] - b[1]) >= 0.36 for i, a in enumerate(all_legs) for b in all_legs[i + 1:]))
gap = min(LY.wall_face_z(x) - z for x, z in ((LY.C2[0] + t * (LY.C4[0] - LY.C2[0]), LY.C2[1] + t * (LY.C4[1] - LY.C2[1])) for t in (i / 50 for i in range(51))) if x < LY.WALL_B[0])
check(f"corner table's back stays in front of the angled wall (closest {gap:.3f})", gap > 0.0)
pose_r, pose_at = pose, at
for m in (spoodle, spoodle_grip):
    worst = math.inf
    for v in m.bm.verts:
        q = pose_r @ v.co
        x, y, z = q.x + pose_at[0], q.z + pose_at[1], -q.y + pose_at[2]
        if y < H + RIM - 0.001:
            worst = min(worst, inner(y - H) - math.hypot(x - TUB_X, z - TUB_Z))
    check(f"resting {m.name} stays inside the tub below the rim (margin {worst:.3f})", worst > 0.0)
print(f"[layout] sauce table {W:.3f} x {D:.3f} at shop ({LY.SAUCE_CX:.3f}, {LY.SAUCE_CZ:.3f}); spot ({WORK_X:.3f}, {WORK_Z:.3f}); tub ({TUB_X:.3f}, {TUB_Z:.3f})")
print(f"[layout] corner C1..C4 {[tuple(round(v, 3) for v in c) for c in (C1, C2, C3, C4)]}")
print(f"[layout] racks {[tuple(round(v, 3) for v in c) for c in RACKS]} yaw {RACK_YAW:.2f}")

# -- Preview only: skins on screens of their own size in the racks (as the game
# shows them), a skin being sauced at the spot with the spoodle, and the
# neighbours for context: the dough table (its meshes, with its cornmeal bin
# underneath), the makeline from +W/2, the walls.
skins = Mesh("SkinsPreview", rgb(234, 222, 186), rough=0.7)
place = []
lo, hi = screen.bounds()
sc = (lo + hi) / 2
order = ("Small", "Large", "Medium", "Medium", "Large", "Small", "Large", "Medium", "Small", "Large", "Medium")
for k, ((cx, cz), filled) in enumerate(zip(RACKS, ((1, 2, 3, 5, 6, 8, 9, 11), (2, 4, 5, 9, 10)))):
    for j, i in enumerate(filled):
        size = order[(j + 3 * k) % len(order)]
        dsk = PIZZA[size]
        marker = top_rail - (i - 1) * SPACING + WIRE / 2
        place.append(("Screen", (cx, marker + 0.02 + sc.y, cz), 0, (dsk + SCREEN_RIM, 1, dsk + SCREEN_RIM)))
        kit.loft(skins, [(marker + 0.035, circle(dsk / 2, 40)), (marker + 0.095, circle(dsk / 2 - 0.04, 40))], close_top=True, at=(cx, 0, cz))
kit.loft(skins, [(H + 0.0, circle(PIZZA["Large"] / 2, 40)), (H + 0.06, circle(PIZZA["Large"] / 2 - 0.04, 40))], close_top=True, at=(WORK_X, 0, WORK_Z))
wet = Mesh("SaucePreview", rgb(190, 35, 25), rough=0.3)
kit.loft(wet, [(H + 0.062, [(x * (1 + 0.04 * math.sin(5 * k)), z * (1 + 0.04 * math.sin(5 * k))) for k, (x, z) in enumerate(circle(0.75, 40))])], close_bottom=False, close_top=True, at=(WORK_X - 0.15, 0, WORK_Z + 0.05))
# the spoodle as the minigame holds it: cup 0.26 over the spot, tipped back 15 degrees
for m, col in ((spoodle, rgb(200, 204, 210)), (spoodle_grip, rgb(200, 35, 35))):
    held = Mesh(m.name + "Held", col, metal=1.0 if m is spoodle else 0.0, rough=0.3)
    held.merge(m, at=(WORK_X + 0.55, H + 0.26, WORK_Z - 0.25), r=kit.rot("x", 15))
    kit.preview(held)
# The makeline (code-built today): cabinet from x = W/2, front at -D/2, its work surface at H.
line = Mesh("MakelinePreview", rgb(150, 155, 162), metal=1.0, rough=0.3)
line.box((9.0, H - 0.1, D), (W / 2 + 4.5, (H - 0.1) / 2, 0))
line.box((9.0, 0.1, D), (W / 2 + 4.5, H - 0.05, 0))
grate = Mesh("GratePreview", rgb(45, 46, 50), rough=0.5)
grate.box((8.7, 0.012, 2.9), (W / 2 + 4.5, H + 0.006, -0.95))
# Walls: the angled wall, the high wall, the dough show's low wall (shop coords from MapBuilder).
walls = Mesh("WallsPreview", rgb(235, 235, 232), rough=0.7)
(ax, az), (bx, bz) = (LY.to_sauce(*LY.WALL_A), LY.to_sauce(*LY.WALL_B))
span = math.hypot(bx - ax, bz - az)
walls.box((span + 0.6, 5.1, 0.6), ((ax + bx) / 2, 2.55, (az + bz) / 2), r=kit.rot("y", -math.degrees(math.atan2(bz - az, bx - ax))))
hx0, hz0 = LY.to_sauce(-2.4, 28.3)
walls.box((18, 5.1, 0.6), (hx0 + 9, 2.55, hz0 + 0.3))
lx0, lz0 = LY.to_sauce(-8.7, 9.9)
lx1, lz1 = LY.to_sauce(-8.1, 23.2)
walls.box((lx1 - lx0, 4.0, lz1 - lz0), ((lx0 + lx1) / 2, 2.0, (lz0 + lz1) / 2))
for m in (skins, wet, line, grate, walls):
    kit.preview(m)
bpy.ops.import_scene.gltf(filepath=os.path.join(kit.OUT_ROOT, "stretch_table", "stretch_table.glb"))
dough_at = LY.to_sauce(LY.DOUGH_CX, LY.DOUGH_CZ)
for ob in list(bpy.context.selected_objects):
    if ob.name.startswith(("Tray", "Ball")):
        bpy.data.objects.remove(ob)
        continue
    ob.name = ob.data.name = 'Dough' + ob.name  # keep the station's own mesh names free
    # dough-table art -> here: FACE_RIGHT (its art -Z faces shop +X)
    ob.matrix_world = Matrix.Translation(rb(dough_at[0], 0, dough_at[1])) @ Matrix.Rotation(math.radians(-90), 4, "Z") @ ob.matrix_world
    mat = bpy.data.materials.new("dough")
    mat.use_nodes = True
    col = {"DoughSteel": rgb(140, 145, 152), "DoughBin": rgb(235, 232, 225)}.get(ob.name.split(".")[0], rgb(60, 62, 68))
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = col
    mat.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0 if ob.name.startswith("DoughSteel") else 0.0
    ob.data.materials.clear()
    ob.data.materials.append(mat)

kit.finish(
    "sauce_table",
    [steel, rubber, racks, tubs, sauce, grips, screen, spoodle, spoodle_grip],
    place,
    [
        ("overview", (5.0, 9.5, -11.5), (-2.5, 2.4, -0.8), 30),
        ("photo", (3.0, 6.4, -13.5), (-4.5, 2.4, -1.5), 30),
        ("plan", (-2.5, 34.0, -2.5), (-2.5, 3.4, -0.5), 30),
        ("corner", (-1.4, 5.4, -7.0), (-4.2, 2.6, -2.8), 32),
        ("legs", (-1.0, 2.2, -8.5), (-4.0, 1.6, -1.5), 26),
        ("tub", (TUB_X - 1.0, H + 2.2, TUB_Z - 2.6), (TUB_X, H + 0.7, TUB_Z), 38),
        ("tubside", (TUB_X - 0.6, H + 0.9, TUB_Z - 2.8), (TUB_X, H + 0.6, TUB_Z), 40),
        ("spoodle", (WORK_X + 1.6, H + 2.0, WORK_Z - 2.6), (WORK_X + 0.2, H + 0.15, WORK_Z - 0.1), 38),
    ],
    kit.args()["render"],
)
