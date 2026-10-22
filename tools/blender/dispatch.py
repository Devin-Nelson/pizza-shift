"""Dispatch station (the user, 2026-10-21; the right-hand station in their cut
table photo): where drivers check out delivery orders. A stainless table made
like the others (square-edged top with an apron, square legs on bullet feet,
an undershelf; the user: a small one), an overshelf on four square uprights
with a full top shelf, a small chrome wire grid at the middle of the back on
two posts up to the shelf, the dispatch monitor upright on an arm off it at
chest height, so someone standing at the table can reach out and tap it (the
user: a touch screen). No printer (the user: later, if at all). The monitor's face is StationArt's (a part the game draws the
dispatch screen on, and that takes taps).

    blender -b -P tools/blender/dispatch.py -- --render

Art-local: the driver at -Z, the back at +Z. The previews put the delivery
ready rack (the carryout rack's model) beside it, with stacks of boxes
tagged with their house numbers.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

L, D, H = 5.0, 2.4, 3.2  # length, depth, table height (the other tables')
UNDER = 0.6  # the undershelf
POST = 0.1  # the overshelf's square uprights, and the grid's posts
MOUNT_W = 3.0  # the grid, between its posts
GZ = D / 2 - POST / 2 - 0.04  # the grid's plane, at the back
SCREEN_W, SCREEN_H = 2.0, 1.25  # the monitor's face (StationArt.Layout.Dispatch.screen)
SCREEN_Y = H + 1.45  # its centre: chest height, in reach from the table's front
SCREEN_Z = 0.55  # its face's centre, back from the table's centre
TILT = 0  # upright (the user)
RIM = 0.11  # the top shelf's turned-down rim, below its underside
# The screen dead in the centre of the opening over the table (the user): the
# top shelf's rim as far above it as the table top is below it, the grid even round it.
TOP = 2 * SCREEN_Y - H + RIM
GRID_Y0, GRID_Y1 = SCREEN_Y - 1.1, SCREEN_Y + 1.1

kit.reset()
steel = Mesh("Steel", rgb(140, 145, 152), metal=1.0, rough=0.3)
wire = Mesh("Wire", rgb(215, 218, 222), metal=1.0, rough=0.2)
dark = Mesh("Dark", rgb(32, 33, 36), rough=0.6)

# -- The table.
steel.box((L, 0.1, D), (0, H - 0.05, 0))
for sz in (-1, 1):
    steel.box((L, 0.18, 0.04), (0, H - 0.19, sz * (D / 2 - 0.02)))
for sx in (-1, 1):
    steel.box((0.04, 0.18, D), (sx * (L / 2 - 0.02), H - 0.19, 0))
    for sz in (-1, 1):
        lx, lz = sx * (L / 2 - 0.12), sz * (D / 2 - 0.12)
        steel.box((0.12, H - 0.2, 0.12), (lx, 0.1 + (H - 0.2) / 2, lz))
        steel.cyl(0.07, 0.1, (lx, 0.05, lz), segs=10, radius2=0.04)
steel.box((L - 0.1, 0.05, D - 0.2), (0, UNDER, 0))
for sz in (-1, 1):
    steel.box((L - 0.1, 0.1, 0.03), (0, UNDER + 0.05, sz * (D / 2 - 0.1)))

# -- The overshelf: four uprights from the top, the top shelf with a turned-down rim.
for sx in (-1, 1):
    for sz in (-1, 1):
        steel.box((POST, TOP - H, POST), (sx * (L / 2 - POST / 2 - 0.02), (H + TOP) / 2, sz * (D / 2 - POST / 2 - 0.02)))
steel.box((L, 0.06, D), (0, TOP + 0.03, 0))
for sz in (-1, 1):
    steel.box((L, RIM + 0.03, 0.03), (0, TOP - (RIM - 0.03) / 2, sz * (D / 2 - 0.015)))
for sx in (-1, 1):
    steel.box((0.03, RIM + 0.03, D), (sx * (L / 2 - 0.015), TOP - (RIM - 0.03) / 2, 0))

# -- The wire grid at the middle of the back, on two posts up to the top shelf.
for sx in (-1, 1):
    steel.box((POST, TOP - RIM - H, POST), (sx * (MOUNT_W / 2 + POST / 2), (H + TOP - RIM) / 2, GZ))
nx = round(MOUNT_W / 0.25)
for k in range(nx + 1):
    x = -MOUNT_W / 2 + k * MOUNT_W / nx
    wire.rod((x, GRID_Y0, GZ), (x, GRID_Y1, GZ), 0.012, segs=5, caps=False)
ny = round((GRID_Y1 - GRID_Y0) / 0.25)
for k in range(ny + 1):
    y = GRID_Y0 + k * (GRID_Y1 - GRID_Y0) / ny
    wire.rod((-MOUNT_W / 2 - POST / 2, y, GZ - 0.02), (MOUNT_W / 2 + POST / 2, y, GZ - 0.02), 0.025 if k in (0, ny) else 0.012, segs=5, caps=False)

# -- The monitor on an arm off the grid, tilted back, its face toward the driver.
r = kit.rot("x", TILT)
a = math.radians(TILT)
back = (0, SCREEN_Y + 0.05 * math.sin(a), SCREEN_Z + 0.05 * math.cos(a))  # the bezel's centre, just behind the face
dark.box((SCREEN_W + 0.12, SCREEN_H + 0.12, 0.1), back, r=r)
dark.box((0.45, 0.35, 0.06), (0, back[1] + 0.08 * math.sin(a), back[2] + 0.08 * math.cos(a)), r=r)
ARM_Z0 = back[2] + 0.11
dark.box((0.12, 0.12, GZ - ARM_Z0), (0, SCREEN_Y, (ARM_Z0 + GZ) / 2))

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


half_h = SCREEN_H / 2 + 0.06
top_y = SCREEN_Y + half_h * math.cos(a)
bottom_y = SCREEN_Y - half_h * math.cos(a)
check("the monitor clears the table top and sits on the grid", bottom_y - 0.1 > H and top_y < GRID_Y1 + 0.3)
check("the monitor fits between the grid's posts", SCREEN_W + 0.12 < MOUNT_W)
check("the screen is dead in the centre of the opening (as far from the table as from the shelf's rim, mid-table)", abs((SCREEN_Y - SCREEN_H / 2 - H) - (TOP - RIM - SCREEN_Y - SCREEN_H / 2)) < 1e-9 and abs((GRID_Y0 + GRID_Y1) / 2 - SCREEN_Y) < 1e-9)
check("the grid sits inside the opening", GRID_Y0 > H + 0.1 and GRID_Y1 < TOP - RIM - 0.1)
check("the grid's posts stand clear of the corner uprights", MOUNT_W / 2 + POST < L / 2 - POST - 0.2)
check("the monitor's arm reaches the grid", ARM_Z0 < GZ)
check("the monitor's face is in reach from the table's front (2 studs)", SCREEN_Z + D / 2 < 2.0)
check("the undershelf under the apron", UNDER + 0.1 < H - 0.28)
print(f"[layout] screen {SCREEN_W} x {SCREEN_H} at (0, {SCREEN_Y:.3f}, {SCREEN_Z:.3f}), tilted {TILT}; top shelf {TOP:.2f}")

# -- Preview only: the monitor's face, and the delivery ready rack beside it
# (the carryout rack's model) with stacks tagged by house.
face = Mesh("ScreenPreview", rgb(40, 90, 140), rough=0.3)
face.box((SCREEN_W, SCREEN_H, 0.01), (0, SCREEN_Y - 0.005 * math.sin(a), SCREEN_Z - 0.005 * math.cos(a)), r=r)
RACK_X = L / 2 + 0.15 + 6.3 / 2
card = Mesh("BoxPreview", rgb(214, 180, 130), rough=0.85)
tag = Mesh("TagPreview", rgb(245, 245, 240), rough=0.6)
INCH = 2.4 / 14
for (t, x, n, bs) in ((3.2, -1.55, 2, 14 * INCH + 0.15), (3.2, 1.55, 1, 12 * INCH + 0.15), (4.55, -1.55, 3, 14 * INCH + 0.15), (5.9, 1.55, 2, 10 * INCH + 0.15)):
    for k in range(n):
        card.box((bs, 0.29, bs), (RACK_X + x, t + 0.15 + 0.3 * k, 0.05), bevel=0.01)
    tag.box((1.6, 0.26, 0.02), (RACK_X + x, t + 0.15 + 0.3 * (n - 1), 0.05 - bs / 2 - 0.012))
for m in (face, card, tag):
    kit.preview(m)
bpy.ops.import_scene.gltf(filepath=os.path.join(kit.OUT_ROOT, "carryout_rack", "carryout_rack.glb"))
for ob in list(bpy.context.selected_objects):
    base = ob.name.split(".")[0]
    ob.name = ob.data.name = "Rack" + base
    ob.matrix_world = Matrix.Translation(rb(RACK_X, 0, 0)) @ ob.matrix_world
    mat = bpy.data.materials.new("rack")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgb(140, 145, 152) if base == "Steel" else rgb(32, 33, 36)
    bsdf.inputs["Metallic"].default_value = 1.0 if base == "Steel" else 0.0
    ob.data.materials.clear()
    ob.data.materials.append(mat)

kit.finish(
    "dispatch",
    [steel, wire, dark],
    [],
    [
        ("overview", (-7.0, 7.0, -10.5), (2.5, 4.2, 0.0), 30),
        ("front", (2.0, 5.0, -12.5), (2.0, 4.4, 0.0), 30),
        ("straight", (0.0, 4.65, -30.0), (0.0, 4.65, 0.0), 75),
        ("driver", (0.0, 5.6, -3.4), (0.0, 4.5, 0.6), 40),
        ("side", (-8.5, 5.0, 0.0), (0.0, 4.6, 0.0), 32),
    ],
    kit.args()["render"],
)
