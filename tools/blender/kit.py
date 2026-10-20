"""Shared helpers for the station models (Blender 4.5, run headless).

Everything is built in Roblox art-local coordinates (studs, Y up, the worker at
-Z, the station's floor centre at the origin), the frame StationArt uses, so
the numbers match `StationArt.Layout`. `rb()` maps them to Blender (Z up); the
glTF exporter maps them back (+Y up).

A station script builds `Mesh` pieces (one per Roblox material), then calls
`finish()`: it writes `<out>/<station>.glb` (uploaded to Roblox as one Model),
`<out>/<station>.json` (each mesh's size and centre in studs, for MeshBank) and,
with `--render`, preview PNGs from the cameras the script asks for.
"""

from __future__ import annotations

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

OUT_ROOT = os.path.join(os.path.expanduser("~"), "Roblox-Assets", "models", "dominus")
MAX_TRIS = 10000


def rb(x: float, y: float, z: float) -> Vector:
    """Roblox art-local (x, y, z) -> Blender."""
    return Vector((x, -z, y))


def rot(axis: str, deg: float) -> Matrix:
    """A rotation about a Roblox axis, as a Blender matrix."""
    a = math.radians(deg)
    if axis == "x":
        return Matrix.Rotation(a, 4, "X")
    if axis == "y":
        return Matrix.Rotation(a, 4, "Z")
    return Matrix.Rotation(-a, 4, "Y")  # Roblox Z is Blender -Y


def rgb(r: int, g: int, b: int) -> tuple:
    def lin(c: float) -> float:
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


_scratch = None


def _scratch_mesh():
    global _scratch
    if _scratch is None:
        _scratch = bpy.data.meshes.new("_scratch")
    return _scratch


class Mesh:
    """One output mesh: pieces are built in a temporary bmesh, placed, merged."""

    def __init__(self, name: str, color: tuple, metal: float = 0.0, rough: float = 0.5, instanced: bool = False, grain: bool = False):
        self.name = name
        self.grain = grain  # preview only: mottled like Roblox's Sand material
        self.texture = None  # a bpy image (colour + alpha), uploaded as an Image for its TextureID
        self.alpha = 1.0  # preview only: see-through like the part's Transparency in game
        self.color = color
        self.metal = metal
        self.rough = rough
        self.instanced = instanced  # built at the origin, placed per copy by StationArt
        self.bm = bmesh.new()

    # -- merge a finished temporary bmesh, moved to `at` (Roblox coords)
    def add(self, tmp, at=(0, 0, 0), r: Matrix | None = None):
        if r is not None:
            bmesh.ops.transform(tmp, matrix=r, verts=tmp.verts[:])
        bmesh.ops.translate(tmp, vec=rb(*at), verts=tmp.verts[:])
        me = _scratch_mesh()
        tmp.to_mesh(me)
        tmp.free()
        self.bm.from_mesh(me)

    def box(self, size, at, bevel: float = 0.0, segs: int = 1, r: Matrix | None = None):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=(size[0], size[2], size[1]), verts=tmp.verts[:])
        if bevel > 0:
            bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=bevel, segments=segs, affect="EDGES", profile=0.5, clamp_overlap=True)
        self.add(tmp, at, r)

    def cyl(self, radius: float, length: float, at, axis: str = "y", segs: int = 16, radius2: float | None = None, caps: bool = True):
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=caps, cap_tris=False, segments=segs, radius1=radius, radius2=radius if radius2 is None else radius2, depth=length)
        r = None
        if axis == "x":
            r = Matrix.Rotation(math.pi / 2, 4, "Y")
        elif axis == "z":
            r = Matrix.Rotation(math.pi / 2, 4, "X")
        self.add(tmp, at, r)

    def rod(self, p0, p1, radius: float, segs: int = 8, caps: bool = True):
        a, b = rb(*p0), rb(*p1)
        d = b - a
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=caps, cap_tris=False, segments=segs, radius1=radius, radius2=radius, depth=d.length)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        bmesh.ops.rotate(tmp, verts=tmp.verts[:], cent=(0, 0, 0), matrix=q.to_matrix())
        bmesh.ops.translate(tmp, vec=(a + b) / 2, verts=tmp.verts[:])
        me = _scratch_mesh()
        tmp.to_mesh(me)
        tmp.free()
        self.bm.from_mesh(me)

    def prism(self, profile, x0: float, x1: float, at=(0, 0, 0), open_edges=(), thickness: float = 0.0):
        """Extrude a side profile [(z, y), ...] from x0 to x1. Profile edge i (point i to
        i + 1) can be left open; an open shell is then solidified inward by `thickness`."""
        tmp = bmesh.new()
        left = [tmp.verts.new(rb(x0, y, z)) for z, y in profile]
        right = [tmp.verts.new(rb(x1, y, z)) for z, y in profile]
        tmp.faces.new(list(reversed(left)))
        tmp.faces.new(right)
        n = len(profile)
        for i in range(n):
            if i not in open_edges:
                j = (i + 1) % n
                tmp.faces.new((left[i], left[j], right[j], right[i]))
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
        if thickness:
            bmesh.ops.solidify(tmp, geom=tmp.faces[:], thickness=thickness)
        self.add(tmp, at)

    def merge(self, other: "Mesh", at=(0, 0, 0), r: Matrix | None = None):
        """Copy another mesh's geometry in, turned by `r` then moved to `at`."""
        self.add(other.bm.copy(), at, r)

    def tris(self) -> int:
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def bounds(self):
        """(min, max) corners in Roblox coords."""
        pts = [Vector((v.co.x, v.co.z, -v.co.y)) for v in self.bm.verts]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        return lo, hi


def rounded_rect(w: float, d: float, r: float, segs: int = 4):
    """Points (x, z) around a w x d rounded rectangle, counter-clockwise seen from above (+Y)."""
    pts = []
    r = min(r, w / 2, d / 2)
    for cx, cz, a0 in ((w / 2 - r, -d / 2 + r, -90), (w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180)):
        for i in range(segs + 1):
            a = math.radians(a0 + 90 * i / segs)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def loft(mesh: Mesh, rings, close_bottom: bool = True, at=(0, 0, 0), thickness: float = 0.0, close_top: bool = False, r: Matrix | None = None):
    """Skin rings [(y, [(x, z), ...]), ...] (same point count) into a surface; optionally solidify."""
    tmp = bmesh.new()
    vrings = [[tmp.verts.new(rb(x, y, z)) for x, z in pts] for y, pts in rings]
    n = len(vrings[0])
    for a, b in zip(vrings, vrings[1:]):
        for i in range(n):
            j = (i + 1) % n
            tmp.faces.new((a[i], a[j], b[j], b[i]))
    if close_bottom:
        tmp.faces.new(list(reversed(vrings[0])))
    if close_top:
        tmp.faces.new(vrings[-1])
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
    if thickness:
        bmesh.ops.solidify(tmp, geom=tmp.faces[:], thickness=thickness)
    mesh.add(tmp, at, r)


def _mitres(path, before=None, after=None):
    """Per point of a polyline [(x, z)], the left normal mitred to its neighbours (length 1/cos of half the turn).
    `before` / `after`: points the line comes from / goes on to beyond its ends (in another mesh), so the
    end faces are mitred to meet that mesh's end exactly."""
    path = ([before] if before else []) + list(path) + ([after] if after else [])
    def left(a, b):
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        return (-(b[1] - a[1]) / ln, (b[0] - a[0]) / ln)
    out = []
    for i in range(len(path)):
        ns = []
        if i > 0:
            ns.append(left(path[i - 1], path[i]))
        if i < len(path) - 1:
            ns.append(left(path[i], path[i + 1]))
        if len(ns) == 2:
            (ax, az), (bx, bz) = ns
            k = 1 + ax * bx + az * bz
            out.append(((ax + bx) / k, (az + bz) / k))
        else:
            out.append(ns[0])
    return out[(1 if before else 0):len(out) - (1 if after else 0)]


def ribbon(mesh: Mesh, path, d0: float, d1: float, y0: float, y1: float, before=None, after=None):
    """A wall along a polyline [(x, z)], d0..d1 to its left (mitred at the corners, and at
    the ends to `before` / `after`), from y0 to y1."""
    ms = _mitres(path, before, after)
    near = [(x + mx * d0, z + mz * d0) for (x, z), (mx, mz) in zip(path, ms)]
    far = [(x + mx * d1, z + mz * d1) for (x, z), (mx, mz) in zip(path, ms)]
    outline = near + far[::-1]
    loft(mesh, [(y0, outline), (y1, outline)], close_bottom=True, close_top=True)


def tube(mesh: Mesh, path, y: float, radius: float, segs: int = 12, before=None, after=None):
    """A round rod along a level polyline [(x, z)] at height y, mitred at the corners, capped."""
    tmp = bmesh.new()
    rings = []
    for (x, z), (mx, mz) in zip(path, _mitres(path, before, after)):
        ring = []
        for i in range(segs):
            a = math.tau * i / segs
            c, s = math.cos(a) * radius, math.sin(a) * radius
            ring.append(tmp.verts.new(rb(x + mx * c, y + s, z + mz * c)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            tmp.faces.new((a[i], a[j], b[j], b[i]))
    tmp.faces.new(rings[0][::-1])
    tmp.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
    mesh.add(tmp)


def cut(mesh: Mesh, cutter: Mesh):
    """Subtract `cutter` from `mesh` (exact boolean), e.g. a hole through a handle."""
    def obj(m):
        me = bpy.data.meshes.new(m.name + "_cut")
        m.bm.to_mesh(me)
        ob = bpy.data.objects.new(m.name + "_cut", me)
        bpy.context.scene.collection.objects.link(ob)
        return ob
    a, b = obj(mesh), obj(cutter)
    mod = a.modifiers.new("cut", "BOOLEAN")
    mod.operation, mod.solver, mod.object = "DIFFERENCE", "EXACT", b
    me = bpy.data.meshes.new_from_object(a.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.bm.free()
    mesh.bm = bmesh.new()
    mesh.bm.from_mesh(me)
    for ob in (a, b):
        bpy.data.objects.remove(ob)


def planar_uv(mesh: Mesh, half: float):
    """UVs projected from above: the square +-half (x, z) fills the texture."""
    uv = mesh.bm.loops.layers.uv.verify()
    for f in mesh.bm.faces:
        for loop in f.loops:
            x, z = loop.vert.co.x, -loop.vert.co.y
            loop[uv].uv = (x / (2 * half) + 0.5, z / (2 * half) + 0.5)


def lump(mesh: Mesh, seed: int, segs: int = 24, rings: int = 12, squash_top: float = 0.62, squash_bottom: float = 0.12, wobble: float = 0.05):
    """A proofed dough ball: a unit-wide soft dome with a slumped, flat bottom."""
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=segs, v_segments=rings, radius=0.5)
    off = Vector((seed * 7.31, seed * 3.17, seed * 5.53))
    for v in tmp.verts:
        x, y, z = v.co
        z = z * (squash_top if z >= 0 else squash_bottom)
        n = noise.noise(Vector((x, y, z)) * 2.2 + off)
        k = 1 + wobble * n
        v.co = Vector((x * k, y * k, z * (1 + wobble * 0.6 * n)))
    zmin = min(v.co.z for v in tmp.verts)
    bmesh.ops.translate(tmp, vec=(0, 0, -zmin), verts=tmp.verts[:])
    for f in tmp.faces:
        f.smooth = True
    mesh.add(tmp)


def save_png(path: str, rgba):
    """Write an (h, w, 4) float array (row 0 = the image's top) as a PNG."""
    h, w, _ = rgba.shape
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(rgba[::-1].astype("float32").ravel())  # Blender rows run bottom-up
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def decal_preview(name: str, img, size_x: float, size_z: float, at):
    """A flat plane carrying an image, for the preview (the game uses a Decal on a Part's Top face)."""
    me = bpy.data.meshes.new(name)
    x, y, z = at
    corners = [rb(x - size_x / 2, y, z + size_z / 2), rb(x + size_x / 2, y, z + size_z / 2), rb(x + size_x / 2, y, z - size_z / 2), rb(x - size_x / 2, y, z - size_z / 2)]
    me.from_pydata(corners, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, c in enumerate(((0, 1), (1, 1), (1, 0), (0, 0))):
        uv.data[i].uv = c
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------------------


def _material(m: Mesh):
    mat = bpy.data.materials.new(m.name + "_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = m.color
    bsdf.inputs["Metallic"].default_value = m.metal
    bsdf.inputs["Roughness"].default_value = m.rough
    bsdf.inputs["Alpha"].default_value = m.alpha
    if m.texture is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = m.texture
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    if m.grain:
        nt = mat.node_tree
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 90
        tex.inputs["Detail"].default_value = 6
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = tuple(c * 0.7 for c in m.color[:3]) + (1,)
        ramp.color_ramp.elements[1].color = tuple(min(1.0, c * 1.25) for c in m.color[:3]) + (1,)
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.6
        nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _object(m: Mesh, coll):
    me = bpy.data.meshes.new(m.name)
    m.bm.to_mesh(me)
    for p in me.polygons:
        p.use_smooth = True
    # Flat faces stay crisp, curves stay smooth (the exporter splits on sharp edges).
    me.set_sharp_from_angle(angle=math.radians(35))
    ob = bpy.data.objects.new(m.name, me)
    coll.objects.link(ob)
    me.materials.append(_material(m))
    return ob


def preview(m: Mesh):
    """Show a mesh in the preview renders only (the game builds it from parts)."""
    return _object(m, bpy.context.scene.collection)


def _bounds(ob):
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    # Blender -> Roblox: (x, y, z)_rbx = (x, z, -y)_bl
    size = (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)
    c = (lo + hi) / 2
    return size, (c.x, c.z, -c.y)


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return {"render": "--render" in argv}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def finish(station: str, meshes: list[Mesh], placements, cameras, render: bool, wall_z: float | None = None):
    """Export the meshes, write the manifest, and render previews.

    placements: [(mesh_name, (x, y, z) bbox centre, yaw_deg, scale)] extra copies
    of instanced meshes, for the preview only (StationArt places the real ones);
    scale is a number or per-axis (x, y, z).
    cameras: [(file_suffix, eye (x, y, z), target (x, y, z), lens_mm)] in Roblox coords.
    wall_z: a white tile wall behind the piece (its front face at this z), for context.
    """
    out = os.path.join(OUT_ROOT, station)
    os.makedirs(out, exist_ok=True)
    coll = bpy.data.collections.new(station)
    bpy.context.scene.collection.children.link(coll)
    objs = {}
    manifest = {}
    total = 0
    for m in meshes:
        tris = m.tris()
        assert tris <= MAX_TRIS, f"{m.name}: {tris} triangles (budget {MAX_TRIS})"
        ob = _object(m, coll)
        objs[m.name] = ob
        size, centre = _bounds(ob)
        manifest[m.name] = {"size": [round(s, 4) for s in size], "centre": [round(c, 4) for c in centre], "tris": tris, "instanced": m.instanced}
        total += tris
        print(f"[kit] {m.name}: {tris} tris, size {tuple(round(s, 3) for s in size)}")
    print(f"[kit] {station}: {total} tris in {len(meshes)} meshes")

    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs.values():
        ob.select_set(True)
    glb = os.path.join(out, station + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_materials="NONE", export_normals=True)
    with open(os.path.join(out, station + ".json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"[kit] wrote {glb}")

    if not render:
        return
    # Preview: the instanced meshes go where StationArt puts them.
    for name, ob in objs.items():
        if manifest[name]["instanced"]:
            ob.hide_render = True
    for name, centre, yaw, scale in placements:
        src = objs[name]
        cp = bpy.data.objects.new(name + "_copy", src.data)
        coll.objects.link(cp)
        c0 = Vector(manifest[name]["centre"])
        # the mesh's own bbox centre to the origin, then scaled, turned and placed
        sx, sy, sz = scale if isinstance(scale, tuple) else (scale, scale, scale)
        cp.matrix_world = Matrix.Translation(rb(*centre)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Diagonal((sx, sz, sy, 1)) @ Matrix.Translation(-rb(*c0))
    _stage(wall_z)
    for suffix, eye, target, lens in cameras:
        cam_data = bpy.data.cameras.new("cam")
        cam_data.lens = lens
        cam = bpy.data.objects.new("cam", cam_data)
        bpy.context.scene.collection.objects.link(cam)
        e, t = rb(*eye), rb(*target)
        cam.location = e
        cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.camera = cam
        path = os.path.join(out, f"{station}_{suffix}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"[kit] rendered {path}")


def _stage(wall_z):
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    sc.view_settings.view_transform = "AgX"
    sc.eevee.use_raytracing = True  # the steel reflects the room
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.62, 0.66, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    sc.world = world
    # Quarry-tile floor, the wall, and bright ceiling panels for the steel to reflect.
    room = [("floor", (40, 0.1, 30), (0, -0.05, 0), rgb(150, 95, 70), 0)]
    if wall_z is not None:
        room.append(("wall", (40, 12, 0.2), (0, 6, wall_z + 0.1), rgb(235, 235, 232), 0))
    room += [(f"lamp{i}", (5, 0.05, 2.5), (x, 11, -2), (1, 1, 1, 1), 6) for i, x in enumerate((-7, 0, 7))]
    for name, size, at, col, glow in room:
        m = Mesh(name, col, rough=0.6)
        m.box(size, at)
        ob = bpy.data.objects.new(name, bpy.data.meshes.new(name))
        m.bm.to_mesh(ob.data)
        mat = _material(m)
        if glow:
            bsdf = mat.node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = glow
        ob.data.materials.append(mat)
        ob.visible_camera = not glow  # the lamps light and reflect, but never block a view
        sc.collection.objects.link(ob)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(40), math.radians(-20), math.radians(30))
    sc.collection.objects.link(sun)
    area = bpy.data.objects.new("panel", bpy.data.lights.new("panel", "AREA"))
    area.data.energy = 2500
    area.data.size = 8
    area.location = rb(0, 12, -3)
    sc.collection.objects.link(area)
