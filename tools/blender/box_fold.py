"""Renders of the pizza box blank (pizzabox.py, after the user's die-cut
reference): flat, mid-fold and shut, brown kraft inside and white outside,
side by side, for the user's OK.

    blender -b -P tools/blender/box_fold.py -- --render
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402
import pizzabox as PB  # noqa: E402
from kit import Mesh, rgb  # noqa: E402

kit.reset()
kind = PB.pizza(12 / 14 * 2.4 + 0.15)  # a Medium (Config.BoxSize)
inside = Mesh("Kraft", rgb(205, 168, 118), rough=0.9, grain=True)
outside = Mesh("White", rgb(238, 235, 226), rough=0.8)
for t, x in ((0.0, -6.0), (0.75, 0.0), (1.2, 4.6), (PB.TIME, 9.0)):
    root = PB.root_at(x, PB.THICK, 0.0, 180)
    PB.draw(inside, kind, root, t, thick=PB.THICK / 2)
    PB.draw(outside, kind, root, t, thick=PB.THICK / 2, y0=-PB.THICK / 2)
for m in (inside, outside):
    kit.preview(m)
kit.finish(
    "pizza_box_fold",
    [],
    [],
    [
        ("all", (1.5, 9.0, 10.5), (1.5, 0.0, 0.5), 24),
        ("flat_top", (-6.0, 11.0, 0.01), (-6.0, 0.0, 0.0), 30),
        ("shut", (11.8, 3.0, 4.2), (9.0, 0.2, 0.3), 38),
        ("shut_corner", (11.0, 1.4, 3.0), (9.6, 0.25, 1.0), 40),
    ],
    kit.args()["render"],
)
