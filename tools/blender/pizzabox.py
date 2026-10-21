"""Box blanks, mirroring src/shared/PizzaBox.luau (keep the two in step): the
die-cut panels of a pizza box, their hinges and folds, and the pose at any
point of the fold. Roblox axes throughout (mathutils matrices); kit.rb maps to
Blender when the boxes are drawn. A kind is (w, d, h).
"""

import math

import bmesh
from mathutils import Matrix, Vector

from kit import rb

WALL, THICK, TIME = 0.2, 0.025, 1.45


def pizza(bs):
    return (bs, bs, WALL)


def _yaw(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def _at(x, y, z):
    return Matrix.Translation((x, y, z))


def panels(kind):
    """[(name, parent index or None, hinge matrix, width, length, fold, from, to)]"""
    w, d, h = kind
    T = THICK
    inner = 2 * T
    out = [("Base", None, Matrix.Identity(4), w, d, 0, 0, 0)]

    def add(*p):
        out.append(p)
        return len(out) - 1

    for s in (1, -1):
        side = add("Side", 0, _at(s * w / 2, 0, 0) @ _yaw(s * 90), d, h, 90, 0, 0.3)
        add("SideFlap", side, _at(0, 0, h), d - 0.04, h - 0.01, 180, 0.55, 0.85)
    front = add("Front", 0, _at(0, 0, -d / 2) @ _yaw(180), w - 2 * inner, h, 90, 0.25, 0.55)
    back = add("Back", 0, _at(0, 0, d / 2), w - 2 * inner, h, 90, 0.25, 0.55)
    for wall in (front, back):
        for s in (1, -1):
            add("Tab", wall, _at(s * (w / 2 - inner), 0, h / 2) @ _yaw(s * 90), h - 0.04, min(h - 0.02, d / 2 - 0.03), 90, 0.35, 0.55)
    add("FrontFlap", front, _at(0, 0, h), w - 0.12, h - 0.01, 180, 0.6, 0.9)
    lid_len = d - 2 * T
    lid = add("Lid", back, _at(0, 0, h), w + 2 * T, lid_len, 90, 0.95, 1.45)
    for s in (1, -1):
        add("LidFlap", lid, _at(s * (w / 2 + T), 0, lid_len / 2) @ _yaw(s * 90), max(d - 0.3, d * 0.6), h - 0.03, 90, 0.95, 1.2)
    add("Tuck", lid, _at(0, 0, lid_len), w - 0.12, h - 0.03, 90, 1.05, 1.35)
    return out


def blank_size(kind):
    """(width, depth) of the flat blank."""
    w, d, h = kind
    return w + 4 * h - 0.02, 2 * d + 4 * h - 2 * THICK - 0.04


def tray_from_front(kind):
    w, d, h = kind
    return d / 2 + 2 * h - 0.01


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


def draw(mesh, kind, root, t=0.0, thick=THICK):
    """Add the box's panels to `mesh` (one box each), posed at t."""
    ps = panels(kind)
    for (name, _p, _h, w, l, *_), m in zip(ps, pose(ps, root, t, thick)):
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
