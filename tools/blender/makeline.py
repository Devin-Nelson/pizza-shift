"""Makeline, after the user's photos: a stainless refrigerated base (doors at both
ends, a drawer bank between, a recessed kick plate), the same rolled front edge
as the sauce table running straight on from it, a wire grate work surface the
pizzas ride on (flush at 3.4), a refrigerated rail of pans between stainless
bars with the food modelled in them, and a sloped stainless canopy over the
pans. The rail, as in the user's store photo, from the sauce table's end (the
maker's right): the big cheese pan, pepperoni, then columns of two pans (back,
front): pineapple and ham, onions and green peppers, black olives and
mushrooms, chicken and sausage; the rest of the rail (the condenser end) holds
nothing. The Cheese spot is the first on the line (where the sauced pizza is
pushed over), in front of the cheese; Toppings next, in front of the toppings.
Each food is its own mesh: StationArt names them Pan_<food>, and gives the
game's toppings the Topping attribute (the toppings minigame clicks them;
onions, chicken and sausage aren't on the menu yet).

    blender -b -P tools/blender/makeline.py -- --render

Art-local = StationArt.Layout.MakeLine (origin layout.MAKELINE_CX/CZ, worker at
-Z, the sauce table at -X). StationArt keeps the gameplay pieces as parts: the
scale plates and ScaleDisplays (their SurfaceGui), the SaucedQueue /
CheesedQueue markers.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import layout as LY  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

# StationArt.Layout.MakeLine
W, H = LY.MAKELINE_W, 3.4
FRONT, BACK = LY.MAKELINE_FRONT, LY.to_makeline(0, LY.BACK_WALL_Z)[1]  # -1.8, 2.9
GRATE_DEPTH, BOARD_Z = 2.9, -0.3
BULL = 0.07  # the rolled front edge, as on the sauce table

# The rail behind the grate: slots between stainless bars, from the sauce end.
RAIL_F, RAIL_B = BOARD_Z + GRATE_DEPTH / 2 + 0.05, 2.5  # 1.2 .. 2.5
RAIL_TOP = H + 0.25
BAR = 0.06  # divider bars between pans
SLOT0 = -W / 2 + 0.3
PW = (W - 0.6) / 15  # slot pitch
OPEN_F, OPEN_B = RAIL_F + 0.1, RAIL_B - 0.1  # pan openings (z)
PAN_DEPTH = 0.32  # bottoms (and their wall thickness) clear of the cabinet top (H - 0.1)
# Columns from the sauce end: (slots wide, the foods in it back to front).
RAIL = [(3, ("Cheese",)), (1, ("Pepperoni",)), (1, ("Pineapple", "Ham")), (1, ("Onions", "Peppers")), (1, ("Olives", "Mushrooms")), (1, ("Chicken", "Sausage"))]
USED = sum(n for n, _ in RAIL)  # the rest of the rail is closed
COLORS = {  # Config.IngredientColors, and StationArt's for the foods not on the menu
    "Cheese": rgb(255, 225, 120), "Pepperoni": rgb(165, 35, 35), "Ham": rgb(240, 160, 160), "Pineapple": rgb(255, 230, 80),
    "Peppers": rgb(50, 150, 50), "Mushrooms": rgb(200, 185, 160), "Olives": rgb(35, 35, 35),
    "Onions": rgb(240, 236, 222), "Chicken": rgb(225, 205, 170), "Sausage": rgb(125, 95, 80),
}
TOPPINGS = ("Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives")  # Config.Toppings


def bound_x(i: int) -> float:
    """The bar after slot i (0 = the rail's sauce-end edge)."""
    return SLOT0 + PW * i


# The spots: Cheese first, as close to the sauce end as its scale read-out (to
# the maker's right) allows; Toppings centred on the topping pans.
CHEESE_X = -W / 2 + 0.1 + 1.0 / 2 + 1.75  # the read-out (1.0 wide, 1.75 right of the spot) just on the line
TOPPINGS_X = (bound_x(RAIL[0][0]) + bound_x(USED)) / 2

kit.reset()
steel = Mesh("Steel", rgb(140, 145, 152), metal=1.0, rough=0.28)
dark = Mesh("Dark", rgb(40, 41, 45), metal=0.3, rough=0.6)
pans = Mesh("Pans", rgb(28, 28, 30), rough=0.4)
food = {k: Mesh("Food_" + k, c, rough=0.5) for k, c in COLORS.items()}

# -- Cabinet: body, doors at the ends, two drawers in each column between,
# bar handles, a recessed kick plate.
BODY_F = FRONT + 0.1
steel.box((W, H - 0.1 - 0.4, BACK - BODY_F), (0, 0.4 + (H - 0.5) / 2, (BODY_F + BACK) / 2))
dark.box((W - 0.1, 0.4, BACK - BODY_F - 0.15), (0, 0.2, (BODY_F + 0.15 + BACK) / 2))
SECTIONS = 5
sw = W / SECTIONS
for k in range(1, SECTIONS + 1):
    x = -W / 2 + sw * (k - 0.5)
    rows = (1.9,) if k in (1, SECTIONS) else (2.55, 1.25)
    for y in rows:
        hgt = 2.5 if len(rows) == 1 else 1.2
        dark.box((sw - 0.1, hgt + 0.04, 0.01), (x, y, BODY_F - 0.005))  # the gap round each front
        steel.box((sw - 0.16, hgt, 0.05), (x, y, BODY_F - 0.035), bevel=0.012)
        hy = y + hgt / 2 - 0.22
        hx0, hx1 = (x - 0.6, x + 0.6) if len(rows) == 2 else ((x + 0.3, x + 1.3) if k == 1 else (x - 1.3, x - 0.3))
        steel.rod((hx0, hy, BODY_F - 0.06), (hx0, hy, BODY_F - 0.17), 0.028, caps=False)
        steel.rod((hx1, hy, BODY_F - 0.06), (hx1, hy, BODY_F - 0.17), 0.028, caps=False)
        steel.rod((hx0 - 0.03, hy, BODY_F - 0.17), (hx1 + 0.03, hy, BODY_F - 0.17), 0.035)

# -- Top: the rolled front edge (as the sauce table's, straight on), a frame
# round the grate, the dark well under the grate, and the grate: rods running
# along the line (the pizzas slide along it), crossbars under them.
kit.tube(steel, [(-W / 2, FRONT), (W / 2, FRONT)], H - BULL, BULL)
steel.box((W, 0.1, BODY_F - FRONT + 0.05), (0, H - 0.05, (FRONT + BODY_F) / 2 + 0.025))
GR_F, GR_B = FRONT + BULL + 0.12, RAIL_F - 0.05
for sx in (-1, 1):
    steel.box((0.15, 0.1, GR_B - BODY_F), (sx * (W / 2 - 0.075), H - 0.05, (BODY_F + GR_B) / 2))
dark.box((W - 0.3, 0.04, GR_B - FRONT - 0.1), (0, H - 0.2, (FRONT + 0.1 + GR_B) / 2))
rods = 24
for i in range(rods):
    z = GR_F + (GR_B - 0.04 - GR_F) * i / (rods - 1)
    steel.cyl(0.0175, W - 0.32, (0, H - 0.0175, z), axis="x", segs=8)
for i in range(11):
    x = -W / 2 + 0.3 + i * (W - 0.6) / 10
    steel.box((0.05, 0.05, GR_B - GR_F + 0.04), (x, H - 0.06, (GR_F + GR_B) / 2))

# -- The rail: a stainless housing rising behind the grate, bars round and
# between the pan openings, a centre bar in each two-pan column, a solid top
# over the unused (condenser) end.
steel.box((W, RAIL_TOP - H + 0.1, 0.05), (0, (H - 0.1 + RAIL_TOP) / 2, RAIL_F + 0.025))
steel.box((W, RAIL_TOP - H + 0.1, 0.05), (0, (H - 0.1 + RAIL_TOP) / 2, RAIL_B - 0.025))
steel.box((W, 0.03, OPEN_F - RAIL_F), (0, RAIL_TOP - 0.015, (RAIL_F + OPEN_F) / 2))
steel.box((W, 0.03, RAIL_B - OPEN_B), (0, RAIL_TOP - 0.015, (OPEN_B + RAIL_B) / 2))
steel.box((0.3, 0.03, OPEN_B - OPEN_F), (-W / 2 + 0.15, RAIL_TOP - 0.015, (OPEN_F + OPEN_B) / 2))
end_x = bound_x(USED) + BAR / 2
steel.box((W / 2 - end_x, 0.03, OPEN_B - OPEN_F), ((end_x + W / 2) / 2, RAIL_TOP - 0.015, (OPEN_F + OPEN_B) / 2))
MID_Z = (OPEN_F + OPEN_B) / 2
slot = 0
for n, foods in RAIL:
    slot += n
    steel.box((BAR, 0.03, OPEN_B - OPEN_F), (bound_x(slot), RAIL_TOP - 0.015, MID_Z))
    if len(foods) == 2:
        steel.box((PW - BAR, 0.03, 0.04), (bound_x(slot - 0.5), RAIL_TOP - 0.015, MID_Z))

# -- Pans: inserts, tapered, a lip resting on the bars. Full depth for the
# cheese and pepperoni, two to a column for the rest.
pan_rects = {}  # food -> (cx, cz, inside width, inside depth) at the rim


def pan(cx, cz, w0, d0, lip_x, lip_z):
    kit.loft(pans, [(RAIL_TOP - PAN_DEPTH, kit.rounded_rect(w0 - 0.09, d0 - 0.09, 0.05, 3)), (RAIL_TOP, kit.rounded_rect(w0, d0, 0.06, 3)), (RAIL_TOP + 0.015, kit.rounded_rect(w0 + lip_x, d0 + lip_z, 0.06, 3))], at=(cx, 0, cz), close_bottom=True, thickness=0.015)
    return (cx, cz, w0 - 0.03, d0 - 0.03)


slot = 0
for n, foods in RAIL:
    x0, x1 = bound_x(slot) + (BAR / 2 if slot else 0), bound_x(slot + n) - BAR / 2
    w0 = x1 - x0 - 0.01
    if len(foods) == 1:
        pan_rects[foods[0]] = pan((x0 + x1) / 2, MID_Z, w0, OPEN_B - OPEN_F - 0.01, BAR - 0.01, 0.08)
    else:
        half = (OPEN_B - OPEN_F - 0.04) / 2
        for f, cz in zip(foods, (MID_Z + 0.02 + half / 2, MID_Z - 0.02 - half / 2)):  # back, front
            pan_rects[f] = pan((x0 + x1) / 2, cz, w0, half - 0.01, BAR - 0.01, 0.03)
    slot += n


def inside_at(name: str, y: float):
    """The pan's inside half-sizes at height y (its walls taper toward the bottom)."""
    cx, cz, w, d = pan_rects[name]
    t = min(1.0, max(0.0, (RAIL_TOP - y) / PAN_DEPTH))  # 0 at the rim, 1 at the bottom
    return cx, cz, (w - 0.09 * t) / 2, (d - 0.09 * t) / 2


rng = random.Random(7)


def mound(name: str, top: float, bulge: float):
    """The food's body: a gentle dome filling the pan wall to wall."""
    cx, cz, hw, hd = inside_at(name, top - 0.02)
    hw, hd = hw - 0.004, hd - 0.004
    nx, nz = 12, 8
    tmp = bmesh.new()
    grid = {}
    for a in range(nx + 1):
        for b in range(nz + 1):
            u, v = a / nx * 2 - 1, b / nz * 2 - 1
            y = top - 0.02 + bulge * (1 - u ** 4) * (1 - v ** 4) + 0.006 * noise.noise(Vector((u * 3 + cx, v * 3, 0.5)))
            grid[a, b] = tmp.verts.new(rb(cx + u * hw, y, cz + v * hd))
    for a in range(nx):
        for b in range(nz):
            tmp.faces.new((grid[a, b], grid[a + 1, b], grid[a + 1, b + 1], grid[a, b + 1]))
    for f in tmp.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    food[name].add(tmp)
    return lambda x, z: top - 0.02 + bulge * (1 - ((x - cx) / hw) ** 4) * (1 - ((z - cz) / hd) ** 4)


def scatter(name: str, piece, count: int, reach: float, surface, lift=(0.005, 0.04), tilt=0.45):
    """`count` pieces on the food's surface, each kept `reach` inside the pan wall."""
    cx, cz, hw, hd = inside_at(name, RAIL_TOP - 0.05)
    for _ in range(count):
        x = cx + rng.uniform(-hw + reach, hw - reach)
        z = cz + rng.uniform(-hd + reach, hd - reach)
        y = surface(x, z) + rng.uniform(*lift)
        tmp = piece()
        r = Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "X") @ Matrix.Rotation(rng.uniform(-tilt, tilt), 4, "Y")
        bmesh.ops.transform(tmp, matrix=r, verts=tmp.verts[:])
        food[name].add(tmp, at=(x, y, z))


def disc(r, t, segs=12):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=t)
    return tmp


def block(sx, sy, sz):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=(sx, sz, sy), verts=tmp.verts[:])
    return tmp


def lump(r):
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=r)
    for v in tmp.verts:
        v.co *= rng.uniform(0.75, 1.15)
    return tmp


def ring(ro, ri, t, segs=10):
    tmp = bmesh.new()
    pts = [(math.cos(math.tau * k / segs), math.sin(math.tau * k / segs)) for k in range(segs)]
    rows = [[tmp.verts.new((rad * c, rad * s, y)) for c, s in pts] for rad, y in ((ro, -t / 2), (ro, t / 2), (ri, t / 2), (ri, -t / 2))]
    for a, b in zip(rows, rows[1:] + rows[:1]):
        for k in range(segs):
            j = (k + 1) % segs
            tmp.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
    return tmp


def slab(prof, t):
    """A thin flat piece with outline `prof` (x, y in the horizontal plane)."""
    tmp = bmesh.new()
    lo = [tmp.verts.new((x, y, -t / 2)) for x, y in prof]
    hi = [tmp.verts.new((x, y, t / 2)) for x, y in prof]
    tmp.faces.new(lo[::-1])
    tmp.faces.new(hi)
    for k in range(len(prof)):
        j = (k + 1) % len(prof)
        tmp.faces.new((lo[k], lo[j], hi[j], hi[k]))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
    return tmp


def mushroom_slice():
    """A cut through a mushroom: the cap's round top and the stem below."""
    return slab([(0.09 * math.cos(math.pi * k / 8), 0.075 * math.sin(math.pi * k / 8)) for k in range(9)] + [(-0.09, -0.012), (-0.03, -0.012), (-0.03, -0.07), (0.03, -0.07), (0.03, -0.012), (0.09, -0.012)], 0.022)


def ham_slice():
    """A folded slice of ham: a rounded square, bent."""
    s = rng.uniform(0.09, 0.12)
    tmp = slab(kit.rounded_rect(2 * s, 2 * s * rng.uniform(0.7, 1.0), 0.03, 2), 0.012)
    for v in tmp.verts:
        v.co.z += 0.18 * v.co.x * v.co.x / s  # a gentle fold
    return tmp


TOP = RAIL_TOP - 0.06
# Cheese: shredded mozzarella heaped in the big pan.
surf = mound("Cheese", TOP - 0.03, 0.045)
scatter("Cheese", lambda: block(rng.uniform(0.09, 0.16), 0.016, 0.018), 420, 0.09, surf, (0.0, 0.02))
# Pepperoni: slices, shingled.
surf = mound("Pepperoni", TOP - 0.04, 0.035)
scatter("Pepperoni", lambda: disc(0.1, 0.02), 46, 0.11, surf, (0.005, 0.045))
# The two-pan columns: back pans first, as in the user's photo.
surf = mound("Pineapple", TOP - 0.05, 0.03)
scatter("Pineapple", lambda: block(rng.uniform(0.08, 0.1), 0.05, 0.06), 34, 0.07, surf)
surf = mound("Ham", TOP - 0.05, 0.03)
scatter("Ham", ham_slice, 22, 0.13, surf, (0.005, 0.03), tilt=0.3)
surf = mound("Onions", TOP - 0.05, 0.03)
scatter("Onions", lambda: block(*(rng.uniform(0.04, 0.06) for _ in range(3))), 60, 0.05, surf)
surf = mound("Peppers", TOP - 0.05, 0.03)
scatter("Peppers", lambda: block(rng.uniform(0.06, 0.1), 0.022, 0.04), 55, 0.07, surf)
surf = mound("Olives", TOP - 0.045, 0.03)
scatter("Olives", lambda: ring(0.05, 0.022, 0.022), 30, 0.075, surf)
surf = mound("Mushrooms", TOP - 0.05, 0.03)
scatter("Mushrooms", mushroom_slice, 22, 0.1, surf)
surf = mound("Chicken", TOP - 0.05, 0.03)
scatter("Chicken", lambda: block(rng.uniform(0.07, 0.11), 0.04, rng.uniform(0.05, 0.07)), 30, 0.08, surf)
surf = mound("Sausage", TOP - 0.05, 0.03)
scatter("Sausage", lambda: lump(rng.uniform(0.03, 0.045)), 50, 0.06, surf)

# -- The canopy: a sloped stainless lid over the pans, a turned-down front
# edge, triangular cheeks at the ends, a back panel against the wall.
C_F, C_B = RAIL_F + 0.2, BACK - 0.03
C_YF, C_YB = H + 1.05, H + 1.45
ang = math.degrees(math.atan2(C_YB - C_YF, C_B - C_F))
span = math.hypot(C_B - C_F, C_YB - C_YF)
steel.box((W, 0.04, span), (0, (C_YF + C_YB) / 2, (C_F + C_B) / 2), r=kit.rot("x", -ang))
steel.box((W, 0.16, 0.04), (0, C_YF - 0.07, C_F + 0.01))
steel.box((W, C_YB - RAIL_TOP + 0.02, 0.05), (0, (RAIL_TOP + C_YB) / 2, BACK - 0.025))
for sx in (-1, 1):
    cheek = [(RAIL_F + 0.02, RAIL_TOP), (BACK - 0.05, RAIL_TOP), (BACK - 0.05, C_YB - 0.02), (C_F, C_YF - 0.02)]
    steel.prism([(z, y) for z, y in cheek], sx * (W / 2) - (0.06 if sx > 0 else 0), sx * (W / 2) + (0.06 if sx < 0 else 0))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


def verts(m: Mesh):
    return [(v.co.x, v.co.z, -v.co.y) for v in m.bm.verts]


for name, m in food.items():
    worst = math.inf
    for x, y, z in verts(m):
        cx, cz, hw, hd = inside_at(name, y)
        worst = min(worst, hw - abs(x - cx), hd - abs(z - cz))
    top = max(y for _, y, _ in verts(m))
    check(f"{name} stays inside its pan (margin {worst:.3f}), at most a hair over the rim ({top - RAIL_TOP:.3f})", worst > 0 and top < RAIL_TOP + 0.02)
check("pans clear of the cabinet top", min(y for _, y, _ in verts(pans)) > H - 0.1)
all_steel = verts(steel) + verts(dark) + verts(pans)
check("nothing past the sauce table (x -8.5) or the far end (8.5)", all(-W / 2 - 1e-4 <= x <= W / 2 + 1e-4 for x, _, _ in all_steel))
check("nothing into the high wall (z 2.9)", all(z <= BACK + 1e-4 for _, _, z in all_steel))
check("the grate's first rod clears the rolled edge", GR_F - 0.0175 > FRONT + BULL)
R, PLATE, DISPLAY = 1.2, 1.35, (1.75, 0.5)  # a Large's radius, the scale plate's half-width, the read-out's offset and half-width
for spot in (CHEESE_X, TOPPINGS_X):
    check(f"scale plate at x {spot:.3f} lies on the top, clear of the rolled edge and the rail", -W / 2 + 0.16 < spot - PLATE and spot + PLATE < W / 2 - 0.16 and FRONT + BULL < BOARD_Z - PLATE and BOARD_Z + PLATE < GR_B)
    check(f"read-out at x {spot - DISPLAY[0]:.3f} on the line", spot - DISPLAY[0] - DISPLAY[1] >= -W / 2 + 0.05)
check("the Cheese and Toppings pizzas don't overlap", TOPPINGS_X - CHEESE_X >= 2 * R + 0.05)
check("the Toppings read-out sits between the two pizzas", CHEESE_X + R < TOPPINGS_X - DISPLAY[0] - DISPLAY[1] and TOPPINGS_X - DISPLAY[0] + DISPLAY[1] < TOPPINGS_X - R + 0.06)
check("the cheese pan is behind the Cheese spot", abs(pan_rects["Cheese"][0] - CHEESE_X) < pan_rects["Cheese"][2] / 2)
check("every topping pan is in the Toppings camera (within 2.8 of the spot)", all(abs(pan_rects[t][0] - TOPPINGS_X) + PW / 2 < 2.8 for t in TOPPINGS))
print(f"[layout] cheeseX {CHEESE_X:.3f} toppingsX {TOPPINGS_X:.3f}")

# -- Preview only: pizzas at the Cheese and Toppings spots; the sauce table
# (its meshes) on the left, the high wall behind.
piz = Mesh("PizzaPreview", rgb(234, 222, 186), rough=0.7)
red = Mesh("SaucePreview", rgb(190, 35, 25), rough=0.4)
chs = Mesh("CheesePreview", rgb(255, 225, 120), rough=0.6)
pep = Mesh("PepPreview", rgb(165, 35, 35), rough=0.5)
for x, layers in ((CHEESE_X, 2), (TOPPINGS_X, 3)):
    kit.loft(piz, [(H, kit.rounded_rect(2.4, 2.4, 1.2, 8)), (H + 0.06, kit.rounded_rect(2.34, 2.34, 1.17, 8))], close_top=True, at=(x, 0, BOARD_Z))
    kit.loft(red, [(H + 0.062, kit.rounded_rect(2.0, 2.0, 1.0, 8))], close_bottom=False, close_top=True, at=(x, 0, BOARD_Z))
    if layers >= 2:
        kit.loft(chs, [(H + 0.066, kit.rounded_rect(1.95, 1.95, 0.97, 8))], close_bottom=False, close_top=True, at=(x, 0, BOARD_Z))
    if layers >= 3:
        for k in range(12):
            a, rr = k * 2.4, 0.3 + 0.5 * ((k * 7) % 5) / 4
            kit.loft(pep, [(H + 0.07, kit.rounded_rect(0.2, 0.2, 0.1, 3)), (H + 0.085, kit.rounded_rect(0.2, 0.2, 0.1, 3))], close_top=True, at=(x + rr * math.cos(a), 0, BOARD_Z + rr * math.sin(a)))
walls = Mesh("WallsPreview", rgb(235, 235, 232), rough=0.7)
walls.box((26, 5.1, 0.6), (-3, 2.55, BACK + 0.3))
for m in (piz, red, chs, pep, walls):
    kit.preview(m)
sauce_at = LY.to_makeline(LY.SAUCE_CX, LY.SAUCE_CZ)
bpy.ops.import_scene.gltf(filepath=os.path.join(kit.OUT_ROOT, "sauce_table", "sauce_table.glb"))
for ob in list(bpy.context.selected_objects):
    if ob.name.startswith(("Screen", "Spoodle")):
        bpy.data.objects.remove(ob)
        continue
    ob.name = ob.data.name = "Sauce" + ob.name
    ob.matrix_world = Matrix.Translation(rb(sauce_at[0], 0, sauce_at[1])) @ ob.matrix_world
    mat = bpy.data.materials.new("sauce")
    mat.use_nodes = True
    base = ob.name.split(".")[0]
    col = {"SauceSteel": rgb(140, 145, 152), "SauceRacks": rgb(215, 218, 222), "SauceTubs": rgb(236, 236, 230), "SauceSauce": rgb(135, 40, 28), "SauceGrips": rgb(200, 35, 35)}.get(base, rgb(30, 30, 33))
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = 1.0 if base in ("SauceSteel", "SauceRacks") else 0.0
    if base == "SauceTubs":
        bsdf.inputs["Alpha"].default_value = 0.22
    ob.data.materials.clear()
    ob.data.materials.append(mat)

kit.finish(
    "makeline",
    [steel, dark, pans] + list(food.values()),
    [],
    [
        ("overview", (-4.5, 9.0, -11.0), (-2.5, 2.6, 0.5), 30),
        ("pans", (-3.6, 6.4, -2.0), (-3.6, 3.6, 1.85), 32),
        ("rail", (-3.6, 9.5, -0.4), (-3.6, 3.6, 1.85), 34),
        ("junction", (-6.0, 5.4, -5.6), (-8.5, 3.0, -1.6), 30),
        ("cheesecam", (CHEESE_X, H + 2.9, BOARD_Z - 1.75), (CHEESE_X, H, BOARD_Z), 28),
        ("toppingscam", (TOPPINGS_X, H + 2.6, BOARD_Z - 2.2), (TOPPINGS_X, H, BOARD_Z), 28),
    ],
    kit.args()["render"],
)
