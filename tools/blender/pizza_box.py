"""Closed pizza boxes for approval (the user, 2026-10-23: "more realistic",
after their photos of real die-cut box blanks). The shape a folded blank
makes (src/shared/PizzaBox.luau's): a base tray with double side walls, the
lid lying on it a hair proud all round, its front tuck flap folded down over
the front wall, the dust flaps' rounded ears showing at the back corners, the
corrugated board's flutes along the cut edges. The print is ours
(tools/blender/box_art.py: three designs to choose from).

    python tools/blender/box_art.py
    blender -b -P tools/blender/pizza_box.py -- --render

Renders only (nothing exported for upload until the user picks a design).
Roblox coords: the box's front (the tuck flap) at -Z.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
from kit import Mesh, rb, rgb  # noqa: E402

INCH = 2.4 / 14  # Config.StudsPerInch
SIZES = {"Small": 10 * INCH + 0.15, "Medium": 12 * INCH + 0.15, "Large": 14 * INCH + 0.15}  # Config.BoxSize
H = 0.28  # a box's height (ShopService: 0.3 apart in a stack)
T = 0.025  # board thickness
ART = os.path.join(kit.OUT_ROOT, "pizza_box")
FLUTE = rgb(150, 112, 74)

kit.reset()
images = {}


def image(name):
    if name not in images:
        images[name] = bpy.data.images.load(os.path.join(ART, name + ".png"))
    return images[name]


def quad(name, img, corners, uv=((0, 1), (1, 1), (1, 0), (0, 0))):
    """A flat picture on four Roblox-coord corners (top-left, top-right, bottom-right, bottom-left)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([rb(*c) for c in corners], [], [(0, 1, 2, 3)])
    layer = me.uv_layers.new()
    for i, c in enumerate(uv):
        layer.data[i].uv = c
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)


def box(design, size, at, tag=None):
    """One closed box, its underside centre at `at`; `tag`: a name label on its front wall."""
    w = SIZES[size]
    x, y, z = at
    board = {"classic": rgb(238, 235, 226), "kraft": rgb(186, 146, 102), "bold": rgb(238, 235, 226)}[design]
    body = Mesh(f"Body_{design}_{size}_{y:.2f}", board, rough=0.85)
    edge = Mesh(f"Flute_{design}_{size}_{y:.2f}", FLUTE, rough=0.95, grain=True)
    lid_top = y + H
    # The base tray: bottom and the four walls (the sides doubled, rolled over at the top).
    body.box((w - 0.02, T, w - 0.02), (x, y + T / 2, z))
    for sx in (-1, 1):
        body.box((2 * T, H - T, w - 0.02), (x + sx * (w / 2 - 0.01 - T), y + H / 2, z), bevel=0.008)
        body.cyl(T, w - 0.04, (x + sx * (w / 2 - 0.01 - T), lid_top - T - 0.004, z), axis="z", segs=8)
    body.box((w - 0.02, H - T, T), (x, y + H / 2, z + w / 2 - 0.01 - T / 2))
    body.box((w - 0.02, H - 2 * T, T), (x, y + H / 2 - T / 2, z - w / 2 + 0.01 + T / 2))
    # The lid, a hair proud all round, its tuck flap down over the front wall.
    body.box((w + 0.01, T, w + 0.01), (x, lid_top - T / 2, z), bevel=0.006)
    body.box((w - 0.06, H - T - 0.02, T), (x, y + H / 2 + 0.01, z - w / 2 - T / 2), bevel=0.004)
    # The dust flaps' rounded ears poking out at the back corners.
    for sx in (-1, 1):
        body.cyl(0.07, T, (x + sx * (w / 2 + 0.005), lid_top - 0.09, z + w / 2 - 0.12), axis="x", segs=12)
    # The corrugated board's cut edges, a darker kraft line.
    edge.box((w + 0.012, 0.006, 0.006), (x, lid_top - T / 2, z - w / 2 - 0.008))
    edge.box((w - 0.058, 0.006, 0.006), (x, y + 0.02, z - w / 2 - T - 0.002))
    kit.preview(body)
    kit.preview(edge)
    # The print: the lid (its flap end, the bottom of the art, toward the front), the side band.
    o = 0.002
    # (Read from the front, -Z, the art's left is at +X.)
    quad(f"Lid_{design}_{y:.2f}_{x:.2f}", image("lid_" + design), [
        (x + w / 2, lid_top + o, z + w / 2), (x - w / 2, lid_top + o, z + w / 2),
        (x - w / 2, lid_top + o, z - w / 2), (x + w / 2, lid_top + o, z - w / 2)])
    bh = H - T - 0.06
    for sx in (-1, 1):
        fx = x + sx * (w / 2 - 0.01 + o)
        zs = (z - w / 2 + 0.05, z + w / 2 - 0.05) if sx == -1 else (z + w / 2 - 0.05, z - w / 2 + 0.05)
        quad(f"Band_{design}_{y:.2f}_{x:.2f}_{sx}", image("band_" + design), [
            (fx, y + 0.03 + bh, zs[0]), (fx, y + 0.03 + bh, zs[1]), (fx, y + 0.03, zs[1]), (fx, y + 0.03, zs[0])])
    if tag:
        fz, ty = z - w / 2 - T - 0.004, y + H / 2 + 0.01
        quad(f"Tag_{y:.2f}_{x:.2f}", image("label"), [
            (x + 0.8, ty + 0.1, fz), (x - 0.8, ty + 0.1, fz), (x - 0.8, ty - 0.1, fz), (x + 0.8, ty - 0.1, fz)])


# Three designs side by side, each a stack: a Large, a Large, a Medium on top,
# the customer's name label on the bottom box (the user, 2026-10-23).
for i, design in enumerate(("classic", "kraft", "bold")):
    x = (i - 1) * 3.6
    for k, size in enumerate(("Large", "Large", "Medium")):
        box(design, size, (x, 0.3 * k, 0), tag=(k == 0))
    box(design, "Large", (x, 0, -3.6))  # one on its own, lid toward the camera

# A counter under them (the cut table's top), for scale and light.
counter = Mesh("Counter", rgb(140, 145, 152), metal=1.0, rough=0.35)
counter.box((12, 0.1, 9), (0, -0.05, -1.5))
kit.preview(counter)

kit.finish(
    "pizza_box",
    [],
    [],
    [
        ("overview", (-5.5, 5.5, -9.0), (0.0, 0.2, -1.6), 40),
        ("top", (0.0, 11.0, -1.9), (0.0, 0.0, -1.8), 45),
        ("classic", (-6.2, 1.3, -1.9), (-3.6, 0.42, -1.1), 42),
        ("lids", (0.0, 4.2, -7.6), (0.0, 0.2, -3.6), 40),
    ],
    kit.args()["render"],
)
