"""The pizza box blank, mirroring src/shared/PizzaBox.luau (keep the two in
step): its die-cut panels, their hinges and folds, and the pose at any point
of the fold. Roblox axes throughout (mathutils matrices); kit.rb maps to
Blender when the boxes are drawn.
"""

import math

import bmesh
from mathutils import Matrix, Vector

from kit import rb

WALL, THICK, TIME = 0.2, 0.025, 1.45


def _yaw(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def _at(x, y, z):
    return Matrix.Translation((x, y, z))


def panels(bs):
    """[(name, parent index or None, hinge matrix, width, length, fold, from, to)]"""
    W, T = WALL, THICK
    out = [("Base", None, Matrix.Identity(4), bs, bs, 0, 0, 0)]

    def add(*p):
        out.append(p)
        return len(out) - 1

    for s in (1, -1):
        side = add("Side", 0, _at(s * bs / 2, 0, 0) @ _yaw(s * 90), bs, W, 90, 0, 0.3)
        add("SideFlap", side, _at(0, 0, W), bs - 0.04, W - 0.01, 180, 0.55, 0.85)
    front = add("Front", 0, _at(0, 0, -bs / 2) @ _yaw(180), bs - 4 * T, W, 90, 0.25, 0.55)
    back = add("Back", 0, _at(0, 0, bs / 2), bs - 4 * T, W, 90, 0.25, 0.55)
    for wall in (front, back):
        for s in (1, -1):
            add("Tab", wall, _at(s * (bs / 2 - 2 * T), 0, W / 2) @ _yaw(s * 90), W - 0.04, W - 0.02, 90, 0.35, 0.55)
    add("FrontFlap", front, _at(0, 0, W), bs - 0.12, W - 0.01, 180, 0.6, 0.9)
    lid_len = bs - 2 * T
    lid = add("Lid", back, _at(0, 0, W), bs + 2 * T, lid_len, 90, 0.95, 1.45)
    for s in (1, -1):
        add("LidFlap", lid, _at(s * (bs / 2 + T), 0, lid_len / 2) @ _yaw(s * 90), bs - 0.3, W - 0.03, 90, 0.95, 1.2)
    add("Tuck", lid, _at(0, 0, lid_len), bs - 0.12, W - 0.03, 90, 1.05, 1.35)
    return out


def tray_from_front(bs):
    return bs / 2 + 2 * WALL - 0.01


def blank_size(bs):
    """(width, depth) of the flat blank."""
    return bs + 4 * WALL - 0.02, 2 * bs + 4 * WALL - 2 * THICK - 0.04


def _ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def pose(ps, root, t, thick=THICK):
    """Each panel's centre matrix at t seconds into the fold, the base's top-centre at `root`."""
    frames, out = [], []
    for name, parent, hinge, w, l, fold, t0, t1 in ps:
        if parent is None:
            frames.append(root)
            out.append(root @ _at(0, -thick / 2, 0))
        else:
            angle = fold * _ease((t - t0) / max(t1 - t0, 1e-3))
            frame = frames[parent] @ hinge @ Matrix.Rotation(math.radians(-angle), 4, "X")
            frames.append(frame)
            out.append(frame @ _at(0, -thick / 2, l / 2))
    return out


def draw(mesh, bs, root, t=0.0, thick=THICK, skip=()):
    """Add the box's panels to `mesh` (one box each), posed at t."""
    ps = panels(bs)
    for (name, _p, _h, w, l, *_), m in zip(ps, pose(ps, root, t, thick)):
        if name in skip:
            continue
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for v in tmp.verts:
            local = Vector((v.co.x * w, v.co.y * thick, v.co.z * l))
            v.co = rb(*(m @ local))
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
        mesh.add(tmp)


def root_at(x, y, z, yaw=0.0):
    """A box's root: the base's top-centre at (x, y, z), turned by yaw degrees."""
    return _at(x, y, z) @ _yaw(yaw)
