"""Box blanks, mirroring src/shared/PizzaBox.luau (keep the two in step): the
die-cut panels of a pizza box, their hinges and folds, and the pose at any
point of the fold. Roblox axes throughout (mathutils matrices); kit.rb maps to
Blender when the boxes are drawn. A kind is (w, d, h).

The shape and fold lines are the user's reference blank (2026-10-24, a
die-cut sheet measured on a 400 px base): the base's front corners cut off on
a diagonal (43 across, 103 back) with the side walls only beside the rest;
a full-width back wall with a tab at each end; a front wall between the cuts;
the lid on the back wall, its front corners creased on the same diagonal so
they fold down over the cut corners, each carrying the front piece of the
lid's side flap; the lid's side flaps behind those; a tuck along the lid's
front with an ear tab at each end. Everything scales with the box, the wall
height included (WALL: 61 / 400 of the width, as on the reference).

Panels are rectangles (rect: x0, x1, z0, z1) or right triangles (tri: the
right-angle corner, then the other two), in their own hinge frame: X along
the hinge, +Z away from it, folding turns +Z toward +Y (the board's inside).
"""

import math

import bmesh
from mathutils import Matrix, Vector

from kit import rb

WALL, THICK, TIME = 61 / 400, 0.025, 1.6  # WALL: the wall height as a share of the box's width (the reference's)
CUT_W, CUT_D = 43 / 400, 103 / 400  # the front corner cut, as shares of the width / depth
UPPER_PAST = 41 / 61  # the side flap's front piece runs past the lid's front by this much of a wall
IDENT = Matrix.Identity(4)


def pizza(bs):
    return (bs, bs, WALL * bs)


def _yaw(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def _at(x, y, z):
    return Matrix.Translation((x, y, z))


def _line(p0, p1, side):
    """A hinge along p0 -> p1 (x, z points in the parent's frame), its +Z toward
    `side`: (hinge matrix, a function taking parent points into it)."""
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dz)
    dx, dz = dx / n, dz / n
    nx, nz = -dz, dx  # X x Y
    if (side[0] - p0[0]) * nx + (side[1] - p0[1]) * nz < 0:
        return _line(p1, p0, side)
    m = Matrix(((dx, 0, nx, p0[0]), (0, 1, 0, 0), (dz, 0, nz, p0[1]), (0, 0, 0, 1)))

    def into(q):
        qx, qz = q[0] - p0[0], q[1] - p0[1]
        return (qx * dx + qz * dz, qx * nx + qz * nz)

    return m, into


def panels(kind):
    """[dict(name, parent, hinge, fold, t0, t1, rect | tri, print)]"""
    w, d, h = kind
    T = THICK
    cw, cd = CUT_W * w, CUT_D * d
    out = []

    def add(**p):
        p.setdefault("fold", 0)
        p.setdefault("t0", 0)
        p.setdefault("t1", 0)
        p.setdefault("hinge", IDENT)
        p.setdefault("print", None)
        out.append(p)
        return len(out) - 1

    base = add(name="Base", parent=None, rect=(-w / 2, w / 2, -d / 2 + cd, d / 2))
    add(name="BaseFront", parent=base, rect=(-w / 2 + cw, w / 2 - cw, -d / 2, -d / 2 + cd))
    for s in (1, -1):
        add(name="BaseCorner", parent=base, tri=((s * (w / 2 - cw), -d / 2 + cd), (s * w / 2, -d / 2 + cd), (s * (w / 2 - cw), -d / 2)))
        # Side walls beside the uncut part only (panel x = -s * the base's z).
        x0, x1 = (-d / 2, d / 2 - cd) if s == 1 else (-d / 2 + cd, d / 2)
        add(name="Side", parent=base, hinge=_at(s * w / 2, 0, 0) @ _yaw(s * 90), fold=90, t0=0, t1=0.3, rect=(x0, x1, 0, h))
    add(name="Front", parent=base, hinge=_at(0, 0, -d / 2) @ _yaw(180), fold=90, t0=0.2, t1=0.5, rect=(-(w / 2 - cw), w / 2 - cw, 0, h))
    back = add(name="Back", parent=base, hinge=_at(0, 0, d / 2), fold=90, t0=0.2, t1=0.5, rect=(-w / 2, w / 2, 0, h))
    for s in (1, -1):
        # End tabs: they fold in against the side walls (panel x = -s * the wall's z).
        x0, x1 = (-(h - 0.02), -0.02) if s == 1 else (0.02, h - 0.02)
        add(name="BackTab", parent=back, hinge=_at(s * (w / 2 - T), 0, 0) @ _yaw(s * 90), fold=90, t0=0.45, t1=0.65, rect=(x0, x1, 0, 0.95 * h))
    lid = add(name="Lid", parent=back, hinge=_at(0, 0, h), fold=90, t0=0.85, t1=1.35, rect=(-w / 2 - T, w / 2 + T, 0, d - cd), print="LidMain")
    add(name="LidFront", parent=lid, rect=(-(w / 2 - cw), w / 2 - cw, d - cd, d), print="LidFront")
    tuck = add(name="Tuck", parent=lid, hinge=_at(0, 0, d - 2 * T), fold=90, t0=1.15, t1=1.5, rect=(-(w / 2 - cw), w / 2 - cw, 0, h))
    for s in (1, -1):
        # The lid's side flap behind the crease (panel x = -s * the lid's z).
        x0, x1 = (-(d - cd), 0) if s == 1 else (0, d - cd)
        side = add(name="LidSide", parent=lid, hinge=_at(s * (w / 2 + T), 0, 0) @ _yaw(s * 90), fold=90, t0=0.95, t1=1.25, rect=(x0, x1, 0, h), print="Band")
        # Its front piece, on the crease across the flap's front end: with the
        # flap down it swings in along the cut corner (CUT_ANGLE), running a
        # little past the lid's front.
        fx = -s * (d - cd)
        hinge2, into2 = _line((fx, 0), (fx, h), (fx - s, 0))
        ex0, ex1 = sorted((into2((fx, 0))[0], into2((fx, h))[0]))
        cut = math.hypot(cw, cd)  # the cut corner's length
        flap = add(name="CornerFlap", parent=side, hinge=hinge2, fold=CUT_ANGLE, t0=1.15, t1=1.4, rect=(ex0, ex1, 0, cut))
        # The rest of the piece, past the cut corner, tucks in behind the front wall.
        add(name="CornerTip", parent=flap, hinge=_at(0, 0, cut), fold=100 - CUT_ANGLE, t0=1.25, t1=1.45, rect=(ex0, ex1, 0, cd + UPPER_PAST * h - cut))
        # The lid's front corner, creased on the diagonal: it tucks under the lid,
        # leaving the lid's corner cut like the base's.
        p0, p1, apex = (s * (w / 2 - cw), d), (s * w / 2, d - cd), (s * w / 2, d)
        hinge, into = _line(p0, p1, apex)
        add(name="LidCorner", parent=lid, hinge=hinge, fold=180, t0=1.0, t1=1.3, tri=(into(apex), into(p0), into(p1)))
        # The lid inside the crease stays: its corner ends up cut like the base's.
        add(name="LidInner", parent=lid, tri=((s * (w / 2 - cw), d - cd), (s * w / 2, d - cd), (s * (w / 2 - cw), d)), print="LidInner")
        # Ear tabs on the tuck's ends (panel x = -s * the tuck's z).
        x0, x1 = (-h, 0) if s == 1 else (0, h)
        add(name="Ear", parent=tuck, hinge=_at(s * (w / 2 - cw), 0, 0) @ _yaw(s * 90), fold=90, t0=1.25, t1=1.5, rect=(x0, x1, 0, 0.9 * cw))
    return out


CUT_ANGLE = math.degrees(math.atan2(CUT_W, CUT_D))  # the cut corner's angle off the side, for a square box


def blank_size(kind):
    """(width, depth) of the flat blank: base and lid plus the walls round them."""
    w, d, h = kind
    return w + 2 * h, 2 * d + 3 * h


def tray_from_front(kind):
    """How far the base's centre sits behind the blank's front edge (the front wall's)."""
    w, d, h = kind
    return d / 2 + h


def _ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def frames(ps, root, t):
    """Each panel's hinge frame at t seconds into the fold, the base's top-centre at `root`."""
    out = []
    for p in ps:
        if p["parent"] is None:
            out.append(root)
        else:
            angle = p["fold"] * _ease((t - p["t0"]) / max(p["t1"] - p["t0"], 1e-3))
            out.append(out[p["parent"]] @ p["hinge"] @ Matrix.Rotation(math.radians(-angle), 4, "X"))
    return out


def outline(p):
    """The panel's corners (x, z) in its own frame."""
    if "rect" in p:
        x0, x1, z0, z1 = p["rect"]
        return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    return list(p["tri"])


def draw(mesh, kind, root, t=0.0, thick=THICK, y0=0.0):
    """Add the box's panels to `mesh`, posed at t: each a slab `thick` deep from
    y0 down (the frame's plane is the board's inside face; y0 = -THICK / 2 and
    thick = THICK / 2 draws just its outside layer)."""
    ps = panels(kind)
    for p, m in zip(ps, frames(ps, root, t)):
        pts = outline(p)
        tmp = bmesh.new()
        top = [tmp.verts.new(rb(*(m @ Vector((x, y0, z))))) for x, z in pts]
        bottom = [tmp.verts.new(rb(*(m @ Vector((x, y0 - thick, z))))) for x, z in pts]
        tmp.faces.new(top)
        tmp.faces.new(list(reversed(bottom)))
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            tmp.faces.new((top[i], top[j], bottom[j], bottom[i]))
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
        mesh.add(tmp)


def root_at(x, y, z, yaw=0.0):
    """A box's root: the base's top-centre at (x, y, z), turned by yaw degrees."""
    return _at(x, y, z) @ _yaw(yaw)
