"""Front counter designs for approval (the user, 2026-10-23: "we're going to
overhaul the front counter, render some designs"). No carryout warmer on it
(orders wait on the carryout rack by the ovens). Each holds the ordering
screen (the Register: a POS facing the staff with a customer display on its
back) and a second POS, at the end away from the makeline (the store-layout
documents), the cash drawers out of the customers' sight. Sizes are the
current counter's: 13.5 long, 3.8 deep, its top at 4.4.

    python tools/blender/box_art.py      (the bold lid art is design C's logo panel)
    blender -b -P tools/blender/front_counter.py -- --render

The user picked C (2026-10-23): `-- --export` builds C alone at the origin
(no POS: the game's Register art sits on it) and writes its meshes for upload
(Wood, Back, Steel; the logo is a Part with the lid art as a Decal in game).

Art-local: length along X, the customers at -Z, the staff at +Z.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

L, D, TOP = 13.5, 3.8, 4.4
SPACING = 20
RED, CHARCOAL = rgb(214, 48, 39), rgb(38, 40, 46)
QUARTZ, STAINLESS, BLACK = rgb(232, 232, 228), rgb(140, 145, 152), rgb(26, 26, 28)
TILE, GROUT = rgb(246, 246, 243), rgb(200, 200, 196)

kit.reset()
EXPORT = "--export" in sys.argv


def logo(name, x, y, z, s):
    """The bold box lid as a square logo panel facing the customers (-Z)."""
    img = bpy.data.images.load(os.path.join(kit.OUT_ROOT, "pizza_box", "lid_bold.png"))
    me = bpy.data.meshes.new(name)
    # (Read from the customers' side, -Z, the art's left is at +X.)
    me.from_pydata([rb(x + s / 2, y + s / 2, z), rb(x - s / 2, y + s / 2, z), rb(x - s / 2, y - s / 2, z), rb(x + s / 2, y - s / 2, z)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, c in enumerate(((0, 1), (1, 1), (1, 0), (0, 0))):
        uv.data[i].uv = c
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)


def pos(dark, glow, x, y, z, customer_screen=True):
    """A POS on the counter top at (x, y, z): base, neck, a touch screen tipped
    back toward the staff (+Z), and a small display on its back for the customer."""
    dark.box((0.55, 0.08, 0.5), (x, y + 0.04, z))
    dark.box((0.14, 0.55, 0.14), (x, y + 0.35, z + 0.05))
    tilt = kit.rot("x", -20)
    dark.box((1.25, 0.85, 0.09), (x, y + 0.85, z + 0.08), r=tilt)
    glow.box((1.13, 0.73, 0.01), (x, y + 0.85 + 0.0, z + 0.08 + 0.05), r=tilt)
    if customer_screen:
        dark.box((0.75, 0.45, 0.06), (x, y + 1.45, z + 0.0))
        glow.box((0.66, 0.37, 0.01), (x, y + 1.45, z - 0.035))


def staff_side(body, x0, top_y):
    """The staff's side, the same for every design: an open bay with a shelf,
    the cash drawers under the POS end, a footrest kick."""
    body.box((L - 0.4, 0.06, D - 0.9), (x0, 1.4, 0.35))
    for k, dx in enumerate((-L / 2 + 2.0, -L / 2 + 4.6)):
        body.box((1.4, 0.35, 0.06), (x0 + dx, top_y - 0.45, D / 2 - 0.02))


meshes = []
floor = Mesh("LobbyFloor", rgb(150, 95, 70), rough=0.6)  # past the kit's stage floor, under all three
floor.box((80, 0.1, 44), (0, -0.07, 0))
meshes.append(floor)

# -- A: Classic. A charcoal body with a red band, a quartz top proud all round,
# a black recessed kick; the two POS at the end away from the makeline.
xa = -SPACING
a_body = Mesh("A_Body", CHARCOAL, rough=0.5)
a_red = Mesh("A_Red", RED, rough=0.4)
a_top = Mesh("A_Top", QUARTZ, rough=0.25)
a_kick = Mesh("A_Kick", BLACK, rough=0.6)
a_dark, a_glow = Mesh("A_Pos", BLACK, rough=0.4), Mesh("A_Screen", rgb(70, 140, 210), rough=0.2)
a_kick.box((L - 0.1, 0.35, D - 0.5), (xa, 0.175, 0.05))
a_body.box((L, TOP - 0.12 - 0.35, D - 0.2), (xa, 0.35 + (TOP - 0.47) / 2, 0.1))
a_red.box((L + 0.01, 0.55, 0.03), (xa, 3.0, -D / 2 + 0.085))
a_red.box((L + 0.01, 0.08, 0.03), (xa, 2.55, -D / 2 + 0.085))
a_top.box((L + 0.3, 0.12, D + 0.25), (xa, TOP - 0.06, 0.0), bevel=0.03)
staff_side(a_body, xa, TOP)
pos(a_dark, a_glow, xa - L / 2 + 2.0, TOP, 0.5)
pos(a_dark, a_glow, xa - L / 2 + 4.6, TOP, 0.5)
meshes += [a_body, a_red, a_top, a_kick, a_dark, a_glow]

# -- B: Two-tier tile. The walls' white subway tile on the front, a red kick;
# the staff work at a stainless top, the customers at a raised quartz
# transaction ledge with a glass guard on standoffs over it.
xb = 0
b_tile, b_grout = Mesh("B_Tile", TILE, rough=0.3), Mesh("B_Grout", GROUT, rough=0.8)
b_red, b_steel = Mesh("B_Red", RED, rough=0.4), Mesh("B_Steel", STAINLESS, metal=1.0, rough=0.3)
b_top = Mesh("B_Ledge", QUARTZ, rough=0.25)
b_glass = Mesh("B_Glass", rgb(200, 225, 235), rough=0.05)
b_glass.alpha = 0.25
b_dark, b_glow = Mesh("B_Pos", BLACK, rough=0.4), Mesh("B_Screen", rgb(70, 140, 210), rough=0.2)
LEDGE = TOP + 0.65
b_red.box((L, 0.4, D - 0.3), (xb, 0.2, 0.05))
b_tile.box((L, LEDGE - 0.4 - 0.1, 1.2), (xb, 0.4 + (LEDGE - 0.5) / 2, -D / 2 + 0.6))  # the tiled front wall up to the ledge
b_tile.box((L, TOP - 0.1 - 0.4, D - 1.4), (xb, 0.4 + (TOP - 0.5) / 2, 0.6))
for k in range(int((LEDGE - 0.5) / 0.32)):  # grout: courses 0.32 high, joints staggered 0.64 apart
    y = 0.4 + (k + 1) * 0.32
    b_grout.box((L, 0.018, 0.012), (xb, y, -D / 2 - 0.005))
    off = 0.32 * (k % 2)
    n = int(L / 0.64)
    for j in range(n + 1):
        jx = -L / 2 + off + j * 0.64
        if -L / 2 < jx < L / 2:
            b_grout.box((0.018, 0.32, 0.012), (xb + jx, y - 0.16, -D / 2 - 0.005))
b_steel.box((L, 0.1, D - 1.2), (xb, TOP - 0.05, 0.6))
b_top.box((L + 0.2, 0.1, 1.5), (xb, LEDGE - 0.05, -D / 2 + 0.55), bevel=0.02)
for sx in range(-3, 4):
    b_steel.cyl(0.05, 1.3, (xb + sx * 2.1, LEDGE + 0.65, -D / 2 + 0.55))
b_glass.box((L, 1.0, 0.04), (xb, LEDGE + 0.85, -D / 2 + 0.55))
staff_side(b_tile, xb, TOP)
pos(b_dark, b_glow, xb - L / 2 + 2.0, TOP, 0.7, customer_screen=False)
pos(b_dark, b_glow, xb - L / 2 + 4.6, TOP, 0.7, customer_screen=False)
for dx in (-L / 2 + 2.0, -L / 2 + 4.6):  # customer displays on the ledge
    b_dark.box((0.75, 0.45, 0.06), (xb + dx, LEDGE + 0.35, -D / 2 + 0.9))
    b_dark.box((0.1, 0.12, 0.1), (xb + dx, LEDGE + 0.06, -D / 2 + 0.9))
    b_glow.box((0.66, 0.37, 0.01), (xb + dx, LEDGE + 0.35, -D / 2 + 0.865))
meshes += [b_tile, b_grout, b_red, b_steel, b_top, b_glass, b_dark, b_glow]

# -- C: Wood and steel. Warm vertical wood slats on the front with the brand
# panel in the middle, a stainless top and kick, stainless end caps.
xc = 0 if EXPORT else SPACING
c_wood = Mesh("Wood" if EXPORT else "C_Wood", rgb(150, 104, 66), rough=0.7, grain=True)
c_back = Mesh("Back" if EXPORT else "C_Back", rgb(40, 32, 26), rough=0.8)
c_steel = Mesh("Steel" if EXPORT else "C_Steel", STAINLESS, metal=1.0, rough=0.3)
c_dark, c_glow = Mesh("C_Pos", BLACK, rough=0.4), Mesh("C_Screen", rgb(70, 140, 210), rough=0.2)
c_steel.box((L, 0.4, D - 0.3), (xc, 0.2, 0.05))
c_back.box((L - 0.2, TOP - 0.1 - 0.4, D - 0.3), (xc, 0.4 + (TOP - 0.5) / 2, 0.05))
n = int((L - 0.3) / 0.3)
for j in range(n):
    sx = -L / 2 + 0.25 + j * (L - 0.5) / (n - 1)
    c_wood.box((0.22, TOP - 0.1 - 0.45, 0.08), (xc + sx, 0.42 + (TOP - 0.55) / 2, -D / 2 + 0.11), bevel=0.01)
for sx in (-1, 1):
    c_steel.box((0.1, TOP - 0.1, D), (xc + sx * (L / 2 - 0.05), (TOP - 0.1) / 2, 0))
c_steel.box((L + 0.2, 0.1, D + 0.2), (xc, TOP - 0.05, 0), bevel=0.02)
c_steel.box((2.7, 2.7, 0.04), (xc, 2.35, -D / 2 + 0.05))
logo("C_Logo", xc, 2.35, -D / 2 + 0.025, 2.5)
staff_side(c_back, xc, TOP)
print(f"[layout] logo panel {2.5} square at (0, 2.35, {-D / 2 + 0.025:.3f})")
if EXPORT:
    kit.finish("front_counter", [c_wood, c_back, c_steel], [], [("C_export", (-9.0, 6.5, -13.0), (0.0, 2.6, 0.0), 32)], kit.args()["render"])
    sys.exit(0)
pos(c_dark, c_glow, xc - L / 2 + 2.0, TOP, 0.5)
pos(c_dark, c_glow, xc - L / 2 + 4.6, TOP, 0.5)
meshes += [c_wood, c_back, c_steel, c_dark, c_glow]

for m in meshes:
    ob = kit.preview(m)
    if m.alpha < 1:
        ob.data.materials[0].surface_render_method = "BLENDED"
    if m.name.endswith("Screen"):
        bsdf = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = m.color
        bsdf.inputs["Emission Strength"].default_value = 1.5

cams = []
for tag, x in (("A_classic", xa), ("B_twotier", xb), ("C_woodsteel", xc)):
    cams.append((tag + "_customer", (x - 9.0, 6.5, -13.0), (x, 2.6, 0.0), 32))
    cams.append((tag + "_staff", (x + 7.5, 7.5, 9.0), (x - 1.5, 3.6, 0.0), 32))
kit.finish("front_counter", [], [], cams, kit.args()["render"])
print("[check] ok", math.isclose(TOP, 4.4))
