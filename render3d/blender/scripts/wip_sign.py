# TSB - ricetta Blender del cartello "cantiere" (wip_sign): si vede su ogni edificio piazzato e non ancora allestito
# (BuildingConstructionStage = 0), come il cartello del 2D (MicroCellRenderer._draw_construction_wip_marker).
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/wip_sign.py            (solo .blend)
#          blender -b --factory-startup -P render3d/blender/scripts/wip_sign.py -- --export (anche il .glb)
#
# Dal 2D (1 px = 1 m): palo alto 2 m largo 0,3 (WIP_SIGN_POST_*), triangolo giallo di raggio 1,4 con bordo scuro e punto
# esclamativo (WIP_SIGN_PLATE_*, WIP_SIGN_MARK_*), centrato poco sopra la cima del palo. Giallo su entrambe le facce.
# Palo un po' storto, come un ramo piantato.

import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
from mathutils import Vector  # noqa: E402

POST_COLOR = (0.35, 0.25, 0.15)      # WIP_SIGN_POST_COLOR
POST_HEIGHT = 2.0                    # WIP_SIGN_POST_HEIGHT
POST_RADIUS = 0.15 * 0.6             # WIP_SIGN_POST_WIDTH / 2, un po' più sottile
PLATE_COLOR = (0.95, 0.75, 0.10)     # WIP_SIGN_PLATE_COLOR
OUTLINE_COLOR = (0.15, 0.10, 0.05)   # WIP_SIGN_PLATE_OUTLINE_COLOR
OUTLINE_WIDTH = 0.18                 # WIP_SIGN_PLATE_OUTLINE_WIDTH (0,25), un po' meno
PLATE_RADIUS = 1.4                   # WIP_SIGN_PLATE_RADIUS
MARK_COLOR = (0.15, 0.10, 0.05)      # WIP_SIGN_MARK_COLOR
MARK_WIDTH = 0.35                    # WIP_SIGN_MARK_WIDTH
PLATE_THICKNESS = 0.06
SEED = 11


def triangle(center, radius):
    # Stessi vertici del 2D (punta in alto), con z verso l'alto invece di y verso il basso.
    cx, cz = center
    return [(cx, cz + radius), (cx - radius * 0.9, cz - radius * 0.75), (cx + radius * 0.9, cz - radius * 0.75)]


def build(collection, material):
    rng = random.Random(SEED)
    mb = S.MeshBuilder()
    # Palo dietro la lastra, piantato un po' nel terreno.
    top = Vector((0.03, -0.10, POST_HEIGHT + PLATE_RADIUS * 0.2))
    points = S.bent_line(Vector((0.0, -0.10, -0.15)), top, (0.04, 0.02), count=5, rng=rng)
    S.add_tube(mb, points, [POST_RADIUS * (1.0 - 0.2 * i / 4) for i in range(5)], POST_COLOR, sides=6, rng=rng)
    # Lastra: bordo scuro (più grande, più sottile), giallo sopra su tutte e due le facce, segno ancora sopra.
    plate_center = (0.0, POST_HEIGHT + PLATE_RADIUS * 0.3)
    t = PLATE_THICKNESS / 2
    S.add_prism(mb, triangle(plate_center, PLATE_RADIUS + OUTLINE_WIDTH), -t, t, OUTLINE_COLOR)
    S.add_prism(mb, triangle(plate_center, PLATE_RADIUS), -t - 0.01, t + 0.01, PLATE_COLOR)
    # Punto esclamativo (2D: trattino da -0,45 a +0,15 del raggio sotto il centro, puntino a +0,4; y del 2D va in giù).
    cx, cz = plate_center
    half = MARK_WIDTH / 2
    bar_top = cz + PLATE_RADIUS * 0.45
    bar_bottom = cz - PLATE_RADIUS * 0.15
    bar = [(cx - half, bar_bottom), (cx + half, bar_bottom), (cx + half * 1.15, bar_top), (cx - half * 1.15, bar_top)]
    S.add_prism(mb, bar, -t - 0.02, t + 0.02, MARK_COLOR)
    S.add_prism(mb, S.disc_xz((cx, cz - PLATE_RADIUS * 0.4), half * 1.05, 8), -t - 0.02, t + 0.02, MARK_COLOR)
    return mb.to_object("wip_sign", collection, material)


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    material = S.vertex_color_material()
    col = S.new_collection("wip_sign")
    build(col, material)
    S.add_review_ground(col, (0.0, 0.0))
    S.add_review_light_and_camera((0.0, 0.0), distance=10.0)
    S.save_blend("wip_sign")
    if export:
        S.export_glb(col, "buildings", "wip_sign")


import bpy  # noqa: E402,F401

main()
