"""Ready rack (user, 2026-10-20): the 15-screen wire rack (the same rack as the
sauce corner's, its slots spaced for topped pizzas) on a square stainless
table at the makeline's end, made like the other tables: the rolled front edge
running on from the makeline's, an apron under it, a backsplash with a folded
top against the high wall, four tubular legs with gussets and bullet feet,
rails low down at the sides and back, open underneath. The rack stands at the
back, its front to the makers; the front of the table stays clear.

    blender -b -P tools/blender/ready_rack.py -- --render

Art-local = StationArt.Layout.ReadyRack (origin layout.READY_CX/CZ, worker at
-Z, the makeline at -X). StationArt keeps the gameplay pieces: the ReadySlot_<n>
markers and RackBounds come from its screenRack.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import layout as LY  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

H = 3.4
W = D = LY.READY_W
SQUARE = [(-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)]
SLOTS, SPACING = 15, 0.3  # Config.ReadyRack.Slots; StationArt.Layout.ReadyRack.slotSpacing (topped pizzas)
WIRE = 0.05  # StationArt screenRack's wire: a slot marker sits WIRE / 2 over its rail
INCH = 2.4 / 14  # Config.StudsPerInch
PIZZA = {"Small": 10 * INCH, "Medium": 12 * INCH, "Large": 14 * INCH}
SCREEN_RIM = 0.06  # a screen is its pizza's size plus the rim (StationArt.Screen)
LARGE_SCREEN = (14 * INCH + SCREEN_RIM) / 2  # radius
BULL = 0.07  # rolled front edge radius (as on the makeline)
FOLD = 0.145  # the backsplash's folded top, out from the wall
# The rack: centred across the table, back toward the splash (a Large screen
# plus the fold and a hair off it, as on the corner table).
RACK_X, RACK_Z = 0.0, D / 2 - (LARGE_SCREEN + FOLD + 0.06)
TOP_RAIL = H + 0.2 + (SLOTS - 1) * SPACING

kit.reset()
steel = Mesh("Steel", rgb(140, 145, 152), metal=1.0, rough=0.28)
rubber = Mesh("Rubber", rgb(30, 30, 33), rough=0.8)
racks = Mesh("Racks", rgb(215, 218, 222), metal=1.0, rough=0.15)


def inset(poly, dist):
    return [(x - math.copysign(dist, x), z - math.copysign(dist, z)) for x, z in poly]


def leg(x, z):
    """A tubular leg with a gusset under the top and a bullet foot (as on the other tables)."""
    steel.cyl(0.085, H - 0.45, (x, 0.13 + (H - 0.45) / 2, z), segs=14)
    steel.cyl(0.1, 0.22, (x, H - 0.21, z), segs=14, radius2=0.17)
    steel.cyl(0.065, 0.13, (x, 0.065, z), segs=12, radius2=0.085)
    steel.cyl(0.095, 0.05, (x, 0.15, z), segs=14)


def rail(a, b):
    steel.rod((a[0], 0.65, a[1]), (b[0], 0.65, b[1]), 0.06, segs=10)


# -- The table: top, the rolled front edge running straight on from the
# makeline's, an apron, a backsplash with a folded top, four legs, side and
# back rails. Nothing underneath.
kit.loft(steel, [(H - 0.1, SQUARE), (H, SQUARE)], close_bottom=True, close_top=True)
front = [(-W / 2, -D / 2), (W / 2, -D / 2)]
kit.tube(steel, front, H - BULL, BULL)
kit.ribbon(steel, front, 0.045, 0.075, H - 0.3, H - 0.1)
back = [(W / 2, D / 2), (-W / 2, D / 2)]
kit.ribbon(steel, back, 0.0, 0.05, H, H + 0.45)
kit.ribbon(steel, back, 0.0, FOLD, H + 0.42, H + 0.45)
LEGS = inset(SQUARE, 0.3)
for p in LEGS:
    leg(*p)
fl, fr, br, bl = LEGS
for a, b in ((fl, bl), (bl, br), (br, fr)):  # sides and back; open at the front
    rail(a, b)

# -- The rack (kit.wire_rack, as on the sauce corner).
rack, feet = kit.wire_rack(H, TOP_RAIL, SLOTS, SPACING)
racks.merge(rack, at=(RACK_X, 0, RACK_Z))
rubber.merge(feet, at=(RACK_X, 0, RACK_Z))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


check("legs under the top (gussets inside)", all(min(W / 2 - abs(x), D / 2 - abs(z)) >= 0.17 for x, z in LEGS))
check("legs clear of the makeline's cabinet end", min(x for x, _ in LEGS) - 0.17 > -W / 2)
check("Large screens clear the backsplash and its fold", D / 2 - RACK_Z - LARGE_SCREEN >= FOLD + 0.02)
check("rack posts clear the fold", D / 2 - RACK_Z - kit.RACK_BACK_POST - 0.03 >= FOLD + 0.02)
check("Large screens over the table", abs(RACK_X) + LARGE_SCREEN <= W / 2 and RACK_Z - LARGE_SCREEN >= -D / 2 + BULL)
check("rack base on the table", all(abs(RACK_X) + 0.95 <= W / 2 and -D / 2 <= RACK_Z + z <= D / 2 - 0.05 for z in kit.RACK_BASE))
kds_x1 = LY.to_ready(10.2 + 7.5, 0)[0]  # MapBuilder's TicketBoard: 15 wide at x 10.2, y 8.1..11.1 over the floor at 1
check("rack clear of the ticket screen over the makeline", RACK_X - kit.RACK_POST - 0.05 > kds_x1 or TOP_RAIL + 0.42 < 8.1 - 1)
check("table short of the side wall (its stripe at x 23.45)", LY.READY_CX + W / 2 <= 23.45)
print(f"[layout] ready table {W:.3f} square at shop ({LY.READY_CX:.3f}, {LY.READY_CZ:.3f}); rack ({RACK_X:.3f}, {RACK_Z:.3f}), top slot {TOP_RAIL:.3f}")

# -- Preview only: topped pizzas on screens of their own size in some slots,
# the makeline (its meshes) on the left.
screens = Mesh("ScreenPreview", rgb(190, 190, 186), metal=0.8, rough=0.4)
crust = Mesh("CrustPreview", rgb(234, 222, 186), rough=0.7)
chs = Mesh("CheesePreview", rgb(255, 225, 120), rough=0.6)
pep = Mesh("PepPreview", rgb(165, 35, 35), rough=0.5)


def circle(r: float, segs: int = 40):
    return [(r * math.cos(math.tau * i / segs), r * math.sin(math.tau * i / segs)) for i in range(segs)]


for i, size in ((1, "Large"), (2, "Medium"), (4, "Large"), (5, "Small"), (7, "Large"), (8, "Medium"), (10, "Large"), (13, "Small")):
    y = TOP_RAIL - (i - 1) * SPACING + WIRE / 2
    d = PIZZA[size]
    kit.loft(screens, [(y, circle((d + SCREEN_RIM) / 2)), (y + 0.02, circle((d + SCREEN_RIM) / 2))], close_top=True, at=(RACK_X, 0, RACK_Z))
    kit.loft(crust, [(y + 0.02, circle(d / 2)), (y + 0.08, circle(d / 2 - 0.03))], close_top=True, at=(RACK_X, 0, RACK_Z))
    kit.loft(chs, [(y + 0.082, circle(d / 2 - 0.12))], close_bottom=False, close_top=True, at=(RACK_X, 0, RACK_Z))
    for k in range(9):
        a, rr = k * 2.4, (0.2 + 0.5 * ((k * 7) % 5) / 4) * d / 2.4
        kit.loft(pep, [(y + 0.085, circle(0.1, 10)), (y + 0.1, circle(0.1, 10))], close_top=True, at=(RACK_X + rr * math.cos(a), 0, RACK_Z + rr * math.sin(a)))
side = Mesh("SideWallPreview", rgb(235, 235, 232), rough=0.7)
sx = LY.to_ready(23.45, 0)[0]
side.box((0.5, 10.0, D + 6), (sx + 0.25, 5.0, D / 2 - (D + 6) / 2))
for m in (screens, crust, chs, pep, side):
    kit.preview(m)
line_at = LY.to_ready(LY.MAKELINE_CX, LY.MAKELINE_CZ)
bpy.ops.import_scene.gltf(filepath=os.path.join(kit.OUT_ROOT, "makeline", "makeline.glb"))
for ob in list(bpy.context.selected_objects):
    base = ob.name.split(".")[0]
    ob.name = ob.data.name = "Line" + base
    ob.matrix_world = Matrix.Translation(rb(line_at[0], 0, line_at[1])) @ ob.matrix_world
    mat = bpy.data.materials.new("line")
    mat.use_nodes = True
    col = {"Steel": rgb(140, 145, 152), "Dark": rgb(40, 41, 45), "Pans": rgb(28, 28, 30)}.get(base, rgb(200, 170, 110))
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = 1.0 if base == "Steel" else 0.0
    ob.data.materials.clear()
    ob.data.materials.append(mat)

kit.finish(
    "ready_rack",
    [steel, rubber, racks],
    [],
    [
        ("overview", (-4.0, 8.5, -11.0), (-0.5, 4.2, 0.3), 30),
        ("rack", (1.6, 6.6, -4.2), (RACK_X, 5.6, RACK_Z), 36),
        ("join", (-4.2, 5.0, -4.8), (-W / 2, 3.2, -1.2), 32),
        ("legs", (1.5, 1.9, -7.5), (0.0, 1.4, 0.0), 30),
        ("side", (7.5, 6.5, -5.0), (0.0, 4.0, 0.5), 32),
    ],
    kit.args()["render"],
    wall_z=D / 2,
)
