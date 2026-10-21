"""Carryout rack (the user, 2026-10-21, from their photos): finished carryout
orders wait here for their customers. A stainless table as long as the cut
table's end is wide, with heated stainless shelves over it (a pass-through warmer): solid
end panels, two long open shelves with folded lips on both sides and heater
strips under them, a heated canopy on top; three tiers for boxes (the table
top and the two shelves). An undershelf low down holds flat boxes.

It stands across the cut table's far end, the end away from the ovens (the
user, 2026-10-21, marked on the plan), the end's full width, its table top
level with the cut table's: the oven tender slides a boxed order along the
cut table and onto it through the open face against the table's end;
whoever works carryout takes it off from the other face.

    blender -b -P tools/blender/carryout_rack.py -- --render

Art-local: the rack's length along x, the cut table's end at -Z, the
carryout side at +Z (in the store: centred on the cut table's end, NEXT_TO
from its centre along its length, -Z toward the ovens). The previews put the
cut table and the ovens where the store has them.
"""

import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

L = 6.3  # the cut table's end: StationArt.Layout.CutTable.depth (the user)
D = 3.0  # deep enough for a Large box with room to slide it in
H = 3.2  # the table's top: the cut table's height
INCH = 2.4 / 14  # Config.StudsPerInch
LARGE_BOX = 14 * INCH + 0.15  # Config.BoxSize.Large
BOX_H = 0.2  # PizzaBox.Wall: a shut box's height
SHELF_T, LIP = 0.08, 0.12  # a heated shelf's thickness; its folded front lip
TIERS = (H, H + 1.35, H + 2.7)  # the box tiers' surfaces: the table top, then the two shelves
CANOPY = TIERS[-1] + 1.35  # the heated canopy's underside
PANEL_T = 0.05
UNDER = 0.6  # the undershelf
CUT_W = 12.8  # StationArt.Layout.CutTable.width: its length
NEXT_TO = CUT_W / 2 + 0.05 + D / 2  # the rack's centre from the cut table's, past its far end

kit.reset()
steel = Mesh("Steel", rgb(140, 145, 152), metal=1.0, rough=0.3)
dark = Mesh("Dark", rgb(32, 33, 36), rough=0.6)

# -- The table: a square-edged top with an apron, square legs on bullet feet,
# an undershelf.
steel.box((L, 0.1, D), (0, H - 0.05, 0))
for sz in (-1, 1):
    steel.box((L, 0.18, 0.04), (0, H - 0.19, sz * (D / 2 - 0.02)))
LEGS_X = (-L / 2 + 0.12, L / 2 - 0.12)
for lx in LEGS_X:
    for sz in (-1, 1):
        lz = sz * (D / 2 - 0.12)
        steel.box((0.12, H - 0.1 - 0.1, 0.12), (lx, 0.1 + (H - 0.2) / 2, lz))
        steel.cyl(0.07, 0.1, (lx, 0.05, lz), segs=10, radius2=0.04)
steel.box((L - 0.1, 0.05, D - 0.2), (0, UNDER, 0))
for sz in (-1, 1):
    steel.box((L - 0.1, 0.1, 0.03), (0, UNDER + 0.05, sz * (D / 2 - 0.1)))  # its turned-up edges

# -- The heated shelves: solid end panels from the table top to the canopy,
# two long open shelves (pass-through: lips folded down on both sides), heater
# strips under the shelves and the canopy.
for x in (-L / 2 + PANEL_T / 2, L / 2 - PANEL_T / 2):
    steel.box((PANEL_T, CANOPY - H, D - 0.1), (x, (H + CANOPY) / 2, 0))
for y in TIERS[1:]:
    steel.box((L - 2 * PANEL_T, SHELF_T, D - 0.1), (0, y - SHELF_T / 2, 0))
    for sz in (-1, 1):
        steel.box((L - 2 * PANEL_T, LIP, 0.03), (0, y - LIP / 2, sz * ((D - 0.1) / 2 + 0.015)))
    dark.box((L - 1.0, 0.02, D - 0.6), (0, y - SHELF_T - 0.01, 0))
steel.box((L, 0.14, D - 0.1), (0, CANOPY + 0.07, 0))
for sz in (-1, 1):
    steel.box((L, 0.18, 0.03), (0, CANOPY - 0.02, sz * ((D - 0.1) / 2 + 0.015)))
for b in range(3):
    bx = -L / 3 + b * L / 3
    for dz in (-0.7, 0.0, 0.7):
        dark.cyl(0.035, L / 3 - 0.6, (bx, CANOPY - 0.04, dz), axis="x", segs=8)

# -- Clearances: nothing may clip (the user). Fails the build if anything does.


def check(label: str, ok: bool):
    print(f"[check] {'ok  ' if ok else 'FAIL'} {label}")
    assert ok, label


check("a Large box fits on a shelf, front to back", LARGE_BOX < D - 0.3)
for i in range(len(TIERS)):
    above = (TIERS[i + 1] - SHELF_T - LIP + SHELF_T if i + 1 < len(TIERS) else CANOPY - 0.08)
    check(f"a stack of five boxes fits on tier {i + 1}, under what's above it", TIERS[i] + 5 * BOX_H + 0.1 < above)
check("the undershelf clears the feet and sits under the apron", 0.1 < UNDER - 0.03 and UNDER + 0.1 < H - 0.28)
check("the rack stands clear of the cut table's end, level with its top", NEXT_TO - D / 2 > CUT_W / 2 + 0.02 and H == 3.2)
check("two Large boxes fit side by side on a shelf, between the end panels", 2 * LARGE_BOX + 0.3 < L - 2 * PANEL_T)
print(f"[layout] length {L}; depth {D}; nextTo {NEXT_TO:.3f}; tiers {TIERS}; canopy {CANOPY:.2f}")

# -- Preview only: box stacks with name tags on the tiers; the cut table and
# the ovens where the store has them (the cut table at (12.65, -3.4) facing
# +X, the rack past its end at (12.65, -3.4 - NEXT_TO) turned to face +Z; the
# ovens at (19.35, 10.1)).
card = Mesh("BoxPreview", rgb(214, 180, 130), rough=0.85)
tag = Mesh("TagPreview", rgb(245, 245, 240), rough=0.6)
SIZES = {"S": 10 * INCH + 0.15, "M": 12 * INCH + 0.15, "L": LARGE_BOX}
STACKS = [(0, -1.5, "LL"), (0, 1.55, "MS"), (1, -1.5, "LLLL"), (1, 1.55, "M"), (2, -1.45, "LM"), (2, 1.6, "SS")]  # (tier, x, boxes bottom up)
for t, cx, boxes in STACKS:
    y = TIERS[t]
    for k, s in enumerate(boxes):
        w = SIZES[s]
        card.box((w, BOX_H - 0.01, w), (cx, y + BOX_H * k + BOX_H / 2, -0.05), bevel=0.01)
    tag.box((0.9, 0.02, 0.45), (cx, y + BOX_H * len(boxes) + 0.01, -0.6))  # the customer's name on top
for m in (card, tag):
    kit.preview(m)


def neighbour(folder: str, at, yaw: float, colours: dict, skip=()):
    """Import another station's .glb, placed in the rack's frame."""
    bpy.ops.import_scene.gltf(filepath=os.path.join(kit.OUT_ROOT, folder, folder + ".glb"))
    for ob in list(bpy.context.selected_objects):
        if ob.name.startswith(skip):
            bpy.data.objects.remove(ob)
            continue
        base = ob.name.split(".")[0]
        ob.name = ob.data.name = folder + base
        ob.matrix_world = Matrix.Translation(rb(*at)) @ kit.rot("y", yaw) @ ob.matrix_world
        mat = bpy.data.materials.new(folder)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = colours.get(base, rgb(30, 30, 33))
        bsdf.inputs["Metallic"].default_value = 1.0 if base in ("Steel", "Body", "Hood", "Conveyor", "Filters", "Paint") else 0.0
        ob.data.materials.clear()
        ob.data.materials.append(mat)


STAINLESS = rgb(140, 145, 152)
neighbour("cut_table", (0, 0, -NEXT_TO), 90, {"Steel": STAINLESS, "Cardboard": rgb(205, 168, 118), "Blanks": rgb(205, 168, 118), "Bottles": rgb(238, 236, 228), "Caps": rgb(200, 35, 35), "Shakers": rgb(230, 215, 170)}, ("Rocker",))
neighbour("ovens", (-(19.35 - 12.65), 0, -(10.1 + 3.4 + NEXT_TO)), 180, {"Body": STAINLESS, "Paint": STAINLESS, "Conveyor": rgb(160, 164, 170), "Hood": STAINLESS, "Filters": rgb(196, 200, 206), "Labels": rgb(235, 110, 30)}, ("Pulley", "Glass"))

kit.finish(
    "carryout_rack",
    [steel, dark],
    [],
    [
        ("carryout_side", (0.0, 5.0, 9.0), (0.0, 4.4, 0.0), 32),
        ("from_cut_table", (-6.5, 6.8, -15.0), (0.0, 4.0, -2.0), 30),
        ("overview", (11.0, 9.5, 8.0), (-1.0, 3.6, -4.0), 30),
        ("plan", (-3.2, 52.0, -13.5), (-3.7, 0.0, -13.5), 30),  # turned like the plan the user marked: the ovens top right
    ],
    kit.args()["render"],
)
