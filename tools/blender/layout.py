"""Store positions the station models must meet exactly (shop coords, as in
MapBuilder: x across the store, z toward the street, y up).

The production run is separate tables pushed together, their connecting ends
the same size (user, 2026-10-20): the dough (stretch) table along the dough
show wall, a trapezoid corner table along the angled lobby wall, the sauce
table, then the makeline. The corner table's front runs parallel to its back,
so with its sides equal to the dough table's end (4.4) and the sauce table's
end (4.7), and the sauce table's front flush with the makeline's, its slope
and the sauce table's left end are fixed.
"""

# The dough (stretch) table: StationArt.Layout.StretchTable, placed at (-5.4, 16.25) facing +X.
DOUGH_CX, DOUGH_CZ = -5.4, 16.25
DOUGH_FRONT_X, DOUGH_BACK_X, DOUGH_END_Z = -3.2, -7.6, 22.6
DOUGH_DEPTH = DOUGH_FRONT_X - DOUGH_BACK_X  # 4.4

# The makeline starts at x 3.4; its front is at z 23.6, the high wall's face at 28.3.
MAKELINE_X, LINE_FRONT_Z, BACK_WALL_Z = 3.4, 23.6, 28.3
SAUCE_DEPTH = BACK_WALL_Z - LINE_FRONT_Z  # 4.7

SLOPE = SAUCE_DEPTH / DOUGH_DEPTH  # the corner table's front and back (dz/dx)
SAUCE_LEFT_X = DOUGH_FRONT_X + (LINE_FRONT_Z - DOUGH_END_Z) / SLOPE

# The corner table: front corners C1 (at the dough table) and C3 (at the sauce
# table), back corners C2 and C4.
C1 = (DOUGH_FRONT_X, DOUGH_END_Z)
C2 = (DOUGH_BACK_X, DOUGH_END_Z)
C3 = (SAUCE_LEFT_X, LINE_FRONT_Z)
C4 = (SAUCE_LEFT_X, BACK_WALL_Z)

# The sauce table's centre (its art origin).
SAUCE_CX, SAUCE_CZ = (SAUCE_LEFT_X + MAKELINE_X) / 2, (LINE_FRONT_Z + BACK_WALL_Z) / 2

# The angled lobby wall's inner face (MapBuilder's CornerWall, 0.6 thick).
WALL_A = (-8.4, 23.2)
WALL_B = (-2.4, 28.9)


def wall_face_z(x: float) -> float:
    (ax, az), (bx, bz) = WALL_A, WALL_B
    dx, dz = bx - ax, bz - az
    ln = (dx * dx + dz * dz) ** 0.5
    nx, nz = dz / ln * 0.3, -dx / ln * 0.3  # half its thickness, toward the kitchen
    return az + nz + (x - ax - nx) * dz / dx


def to_dough(x: float, z: float):
    """Shop (x, z) -> the dough table's art-local (x, z): its art -Z faces shop +X."""
    return z - DOUGH_CZ, DOUGH_CX - x


def to_sauce(x: float, z: float):
    """Shop (x, z) -> the sauce table's art-local (x, z)."""
    return x - SAUCE_CX, z - SAUCE_CZ


# The makeline: StationArt.Layout.MakeLine, art origin at (10.2, 25.4), 13.6
# wide (four 3.4 sections: the user, 2026-10-20), its front 1.8 ahead of the
# origin (z 23.6, flush with the sauce table's), its back on the high wall
# (28.3), its left end against the sauce table (x 3.4).
MAKELINE_CX, MAKELINE_CZ = 10.2, 25.4
MAKELINE_W, MAKELINE_FRONT = 13.6, -1.8


def to_makeline(x: float, z: float):
    """Shop (x, z) -> the makeline's art-local (x, z)."""
    return x - MAKELINE_CX, z - MAKELINE_CZ


assert abs(MAKELINE_CX - MAKELINE_W / 2 - MAKELINE_X) < 1e-9 and abs(MAKELINE_CZ + MAKELINE_FRONT - LINE_FRONT_Z) < 1e-9
