# TSB - ricetta Blender del mucchietto SEGNAPOSTO per le scorte (posti del magazzino, mucchi a terra).
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/pile.py            (solo .blend)
#          blender -b --factory-startup -P render3d/blender/scripts/pile.py -- --export (anche i .glb)
#
# Un solo modello per tutte le risorse (2026-11-19, richiesta utente): tinta NEUTRA chiara, che il gioco colora per
# risorsa (IconRegistry.get_resource_color) moltiplicando il colore dell'istanza; le sfumature chiaro/scuro dei pezzi
# restano e fanno leggere la forma. Quando una risorsa avrà il suo mucchio vero (legna impilata, pietre...) userà quello,
# le altre restano col segnaposto.
#
# Misure dal 2D: un posto della griglia del magazzino è largo 2,2 m (DEPOSIT_SITE_STORAGE_SQUARE_SIDE, passo 2,4 m):
# il mucchietto ci sta dentro, circa 1,9 m di diametro e 0,8-1 m di altezza. Origine al centro, a terra.
#
# Tre forme, una collezione ciascuna:
#   cumulo   - mucchio di grumi sfaccettati (generico)
#   fagotti  - fagotti allungati legati, uno sull'altro
#   sacchi   - tre o quattro sacchi tondeggianti appoggiati

import math
import os
import random
import sys

import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
from mathutils import Vector  # noqa: E402

# Toni neutri (moltiplicati dal colore della risorsa nel gioco): chiaro, medio, scuro.
LIGHT = (0.95, 0.95, 0.93)
MID = (0.82, 0.82, 0.80)
DARK = (0.62, 0.62, 0.60)
TIE = (0.45, 0.45, 0.43)
SPACING = 3.5
SEED = 5
SHAPES = ("cumulo", "fagotti", "sacchi")


def add_lump(mb, center, radii, rng, points=11, tone=None):
    """Grumo sfaccettato: inviluppo convesso di punti a caso in un ellissoide; facce in su più chiare."""
    bm = bmesh.new()
    for _ in range(points):
        a = rng.random() * math.tau
        z = rng.random() * 2.0 - 1.0
        r = math.sqrt(1.0 - z * z)
        k = 0.75 + rng.random() * 0.25
        bm.verts.new(Vector(center) + Vector((math.cos(a) * r * radii[0], math.sin(a) * r * radii[1], z * radii[2])) * k)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Niente sotto il terreno: i punti sotto quota 0 salgono a 0 (fondo piatto).
    for v in bm.verts:
        v.co.z = max(v.co.z, 0.0)
    base = tone or (LIGHT if rng.random() < 0.5 else MID)

    def shade(face):
        n = face.normal.z
        if n < -0.2:
            return DARK
        k = 0.88 + 0.12 * max(n, 0.0)
        c = S.jitter_color(base, rng, 0.03)
        return (c[0] * k, c[1] * k, c[2] * k)

    mb.add_bmesh(bm, shade)
    bm.free()


def build_cumulo(mb, rng):
    # Base larga di grumi, poi un secondo strato più piccolo, un grumo in cima.
    for i in range(7):
        a = math.tau * i / 7 + rng.random() * 0.4
        d = 0.55 + rng.random() * 0.2
        add_lump(mb, (math.cos(a) * d, math.sin(a) * d, 0.12), (0.42, 0.38, 0.28), rng)
    for i in range(4):
        a = math.tau * i / 4 + rng.random() * 0.6
        add_lump(mb, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.35), (0.40, 0.36, 0.30), rng)
    add_lump(mb, (0.05, -0.05, 0.62), (0.32, 0.30, 0.25), rng, tone=LIGHT)


def add_bundle(mb, center, length, radius, angle, rng):
    """Fagotto: grumo allungato con due legature scure."""
    d = Vector((math.cos(angle), math.sin(angle), 0.0))
    bm_center = Vector(center)
    # Ellissoide allungato lungo d: punti costruiti nel sistema (d, laterale, su).
    side = Vector((-d.y, d.x, 0.0))
    bm = bmesh.new()
    for _ in range(22):
        a = rng.random() * math.tau
        t = rng.random() * 2.0 - 1.0
        k = 0.85 + rng.random() * 0.15
        p = bm_center + d * (t * length * 0.5) + (side * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)) * radius * k * math.sqrt(1.0 - 0.3 * t * t)
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co.z = max(v.co.z, 0.0)
    base = LIGHT if rng.random() < 0.5 else MID
    mb.add_bmesh(bm, lambda f: DARK if f.normal.z < -0.2 else S.jitter_color(base, rng, 0.03))
    bm.free()
    # Legature: anellini scuri a un quarto e tre quarti.
    for s in (-0.25, 0.25):
        ring_center = bm_center + d * (s * length)
        pts = []
        for j in range(9):
            a = math.tau * j / 8
            pts.append(ring_center + (side * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)) * radius * 1.02)
        S.add_tube(mb, pts, [0.035] * len(pts), TIE, sides=4)


def build_fagotti(mb, rng):
    add_bundle(mb, (0.0, -0.38, 0.22), 1.7, 0.24, 0.1, rng)
    add_bundle(mb, (0.05, 0.12, 0.22), 1.6, 0.24, -0.08, rng)
    add_bundle(mb, (-0.05, 0.55, 0.20), 1.4, 0.22, 0.15, rng)
    add_bundle(mb, (0.0, -0.12, 0.62), 1.5, 0.23, 0.05, rng)
    add_bundle(mb, (0.02, 0.33, 0.60), 1.3, 0.22, -0.12, rng)


def add_sack(mb, center, size, tilt, rng):
    """Sacco: corpo tondo schiacciato e un collo stretto legato in cima, un po' inclinato."""
    c = Vector(center)
    add_lump(mb, c + Vector((0, 0, size * 0.55)), (size * 0.55, size * 0.5, size * 0.55), rng, points=14)
    neck = c + Vector((tilt[0], tilt[1], size * 1.15))
    add_lump(mb, neck, (size * 0.18, size * 0.18, size * 0.16), rng, points=8, tone=MID)
    S.add_tube(mb, [neck + Vector((0, 0, -size * 0.12)) + Vector((math.cos(a), math.sin(a), 0)) * size * 0.17
                    for a in [math.tau * j / 8 for j in range(9)]], [0.03] * 9, TIE, sides=4)


def build_sacchi(mb, rng):
    add_sack(mb, (-0.42, -0.2, 0.0), 0.75, (-0.08, 0.0), rng)
    add_sack(mb, (0.42, -0.25, 0.0), 0.70, (0.06, -0.04), rng)
    add_sack(mb, (0.0, 0.42, 0.0), 0.78, (0.0, 0.08), rng)
    add_sack(mb, (0.05, 0.0, 0.45), 0.62, (0.05, 0.05), rng)


BUILDERS = {"cumulo": build_cumulo, "fagotti": build_fagotti, "sacchi": build_sacchi}


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    material = S.vertex_color_material()
    root = S.new_collection("pile")
    for i, name in enumerate(SHAPES):
        col = S.new_collection("pile_" + name, root)
        x = (i - 1) * SPACING
        mb = S.MeshBuilder()
        BUILDERS[name](mb, random.Random(SEED + i))
        obj = mb.to_object("pile_" + name, col, material)
        obj.location.x = x
        S.add_review_ground(col, (x, 0.0), size=SPACING * 0.9)
        S.add_label(col, name, (x, -1.9, 0.2), size=0.4)
    S.add_review_light_and_camera((0.0, 0.0), distance=12.0)
    S.save_blend("pile")
    if export:
        for name in SHAPES:
            obj = bpy.data.objects["pile_" + name]
            old = obj.location.x
            obj.location.x = 0.0
            S.export_glb(bpy.data.collections["pile_" + name], "props", "pile_" + name)
            obj.location.x = old


import bpy  # noqa: E402

main()
