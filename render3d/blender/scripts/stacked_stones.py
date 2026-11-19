# TSB - ricetta Blender delle pietre rituali (stacked_stones), con le fasi del cantiere.
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/stacked_stones.py            (solo .blend)
#          blender -b --factory-startup -P render3d/blender/scripts/stacked_stones.py -- --export (anche i .glb)
#
# Dal 2D (PlaceholderBuildingShapes, "stacked_stones", visto dall'alto): pelle stesa come base (raggio 4,1 m), cumulo di
# pietre al centro sempre più chiare verso l'alto, 4 ossa sui lati e 4 rametti sulle diagonali. Qui di lato: la pelle a
# terra, al centro un ometto di pietre piatte impilate (circa 2,5 m) con ai piedi l'anello dei sassolini, ossa piantate
# in piedi sui quattro lati e bastoni piantati sulle diagonali con una striscia di pelle legata in cima.
# Materiali di stacked_stones.tres: 100 sassolini, 10 ossa, 10 bastoni, 5 pelli. Colori dalle icone (HideIcon, BoneIcon,
# StickIcon, PebbleIcon) e dal cumulo del 2D (STACKED_STONES_PILE_COLORS). Una microcella (10 m), senza porta.
#
# Fasi (construction_stage_thresholds = [0.0, 0.5] nel .tres; la fase 0, non allestito, ha solo il cartello):
#   1_base   - pelle stesa, prime pietre dell'ometto, mucchio di sassolini, ossa e bastoni a terra in un fascio
#   2_meta   - ometto a metà, anello di sassolini a metà, ossa piantate, bastoni ancora a terra
#   3_finita - tutto

import math
import os
import random
import sys

import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
from mathutils import Vector  # noqa: E402

HIDE = (0.66, 0.48, 0.30)          # HideIcon.HIDE_COLOR
HIDE_DARK = (0.42, 0.29, 0.17)     # HideIcon.HIDE_DARK_COLOR
BONE = (0.92, 0.89, 0.80)          # BoneIcon.BONE_COLOR
BONE_SHADE = (0.66, 0.62, 0.52)    # BoneIcon.BONE_SHADE_COLOR
CAIRN_DARK = (0.62, 0.60, 0.56)    # STACKED_STONES_PILE_COLORS, dalla base...
CAIRN_LIGHT = (0.81, 0.79, 0.75)   # ...alla cima

# Pelli: 5 (come nella ricetta), lunghe e larghe (zampe comprese), distanza del centro dal mezzo, quanto sale ognuna
# sulla precedente. Sagoma (x lungo il corpo, collo a +x; y di lato) in unità della mezza misura.
HIDE_COUNT = 5
HIDE_LENGTH = 3.4
HIDE_WIDTH = 2.3
HIDE_DISTANCE = 1.9
HIDE_LIFT = 0.012
HIDE_OUTLINE = (
    (1.0, 0.12), (0.72, 0.32), (0.62, 0.62), (0.80, 1.0), (0.48, 0.92), (0.36, 0.52),
    (-0.34, 0.56), (-0.48, 0.96), (-0.78, 1.0), (-0.64, 0.58), (-0.86, 0.30), (-1.08, 0.04),
    (-0.86, -0.30), (-0.64, -0.58), (-0.78, -1.0), (-0.48, -0.96), (-0.34, -0.56),
    (0.36, -0.52), (0.48, -0.92), (0.80, -1.0), (0.62, -0.62), (0.72, -0.32), (1.0, -0.12),
)
# Quota sopra le pelli, dove poggiano ometto e sassolini.
HIDE_THICKNESS = 0.07
# Ometto: raggio di ogni pietra dalla base alla cima (pietre piatte, schiacciate).
CAIRN = (1.05, 0.92, 0.80, 0.68, 0.56, 0.44, 0.33)
CAIRN_SQUASH = 0.34
PEBBLE_RING = 1.55
PEBBLE_COUNT = 28
BONE_RADIUS = 2.7
BONE_LENGTH = 1.6
STICK_RADIUS = 3.1
STICK_HEIGHT = 2.1
SEED = 13

PHASES = ("1_base", "2_meta", "3_finita")
PHASE_SPACING = 10.0


def lerp_color(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def add_hides(mb, rng):
    """Le 5 pelli della ricetta, distese a raggiera e un po' sovrapposte (2026-11-19, richiesta utente: il disco unico
    sembrava un tappeto): sagoma d'animale con collo, quattro zampe e coda, toni un po' diversi."""
    for i in range(HIDE_COUNT):
        angle = math.tau * i / HIDE_COUNT + (rng.random() - 0.5) * 0.35
        out = Vector((math.cos(angle), math.sin(angle), 0.0))
        center = out * (HIDE_DISTANCE + (rng.random() - 0.5) * 0.3)
        # Collo verso fuori, coda verso il centro; ogni pelle un filo più alta della precedente (si sovrappongono).
        add_animal_hide(mb, rng, center, angle, HIDE_LIFT * (i + 1),
                        lerp_color(HIDE, HIDE_DARK, rng.random() * 0.45))


def add_animal_hide(mb, rng, center, angle, z, color):
    along = Vector((math.cos(angle), math.sin(angle), 0.0))
    side = Vector((-along.y, along.x, 0.0))
    scale = 0.9 + rng.random() * 0.2
    points = []
    for x, y in HIDE_OUTLINE:
        x += (rng.random() - 0.5) * 0.08
        y += (rng.random() - 0.5) * 0.08
        points.append(center + along * (x * HIDE_LENGTH * 0.5 * scale) + side * (y * HIDE_WIDTH * 0.5 * scale))
    bm = bmesh.new()
    top = [bm.verts.new((p.x, p.y, z)) for p in points]
    bm.faces.new(top)
    # Bordo che scende fino a terra: la pelle ha uno spessore e non galleggia.
    low = [bm.verts.new((p.x, p.y, 0.0)) for p in points]
    n = len(points)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new([top[k], low[k], low[j], top[j]])
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    dark = lerp_color(color, HIDE_DARK, 0.6)
    # Sopra = tutte le punte in alto (non la normale: la triangolazione di una sagoma concava ne gira qualcuna).
    mb.add_bmesh(bm, lambda f: S.jitter_color(color, rng, 0.02) if min(v.co.z for v in f.verts) > 0.001 else dark)
    bm.free()


def add_cairn(mb, rng, count):
    """Ometto: pietre piatte una sull'altra, ognuna un po' spostata e più chiara della precedente."""
    z = HIDE_THICKNESS
    for i, size in enumerate(CAIRN[:count]):
        half = size * CAIRN_SQUASH
        center = (rng.random() - 0.5) * 0.18, (rng.random() - 0.5) * 0.18, z + half * 0.9
        color = lerp_color(CAIRN_DARK, CAIRN_LIGHT, i / (len(CAIRN) - 1))
        S.add_stone(mb, center, size, rng, color=color, squash=CAIRN_SQUASH)
        z += half * 1.7


def add_pebble_ring(mb, rng, fraction):
    for i in range(int(PEBBLE_COUNT * fraction)):
        a = math.tau * i / PEBBLE_COUNT + (rng.random() - 0.5) * 0.15
        r = PEBBLE_RING + (rng.random() - 0.5) * 0.2
        S.add_stone(mb, (math.cos(a) * r, math.sin(a) * r, HIDE_THICKNESS + 0.06), 0.12 + rng.random() * 0.06, rng)


def add_pebble_pile(mb, rng, center):
    for _ in range(14):
        a = rng.random() * math.tau
        d = rng.random() * 0.45
        S.add_stone(mb, (center[0] + math.cos(a) * d, center[1] + math.sin(a) * d, HIDE_THICKNESS + 0.08 + (0.45 - d) * 0.3),
                    0.13 + rng.random() * 0.05, rng)


def add_bone(mb, rng, base, direction):
    """Osso: fusto chiaro con due nodi alle estremità; direction = asse (in piedi o disteso)."""
    d = Vector(direction).normalized()
    a = Vector(base)
    b = a + d * BONE_LENGTH
    S.add_tube(mb, [a, a.lerp(b, 0.5), b], [0.11, 0.09, 0.11], BONE, sides=5, rng=rng)
    for end in (a, b):
        S.add_stone(mb, tuple(end), 0.19, rng, color=BONE, squash=0.8)


def add_planted_bone(mb, rng, angle):
    out = Vector((math.cos(angle), math.sin(angle), 0.0))
    base = out * BONE_RADIUS + Vector((0, 0, -0.15))
    add_bone(mb, rng, base, Vector((0, 0, 1)) + out * 0.12)


def add_planted_stick(mb, rng, angle):
    """Bastone piantato, appena storto, con una striscia di pelle legata in cima."""
    out = Vector((math.cos(angle), math.sin(angle), 0.0))
    foot = out * STICK_RADIUS + Vector((0, 0, -0.1))
    top = foot + Vector((0, 0, STICK_HEIGHT)) + out * 0.1
    color = S.STICK_TONES[int(rng.random() * len(S.STICK_TONES))]
    S.add_tube(mb, S.bent_line(foot, top, (0.06, 0.03), rng=rng), [0.06, 0.055, 0.05, 0.045, 0.04], color, rng=rng)
    S.add_lashing(mb, top - Vector((0, 0, 0.15)), Vector((0, 0, 1)), 0.06, 0.03, rng, turns=2)
    # Striscia di pelle che pende dalla legatura (lastra sottile, un poco girata dal vento).
    side = Vector((-out.y, out.x, 0.0))
    p = top - Vector((0, 0, 0.18))
    corners = [p + side * 0.02, p + side * 0.30, p + side * 0.24 + Vector((0, 0, -1.0)), p + side * 0.0 + Vector((0, 0, -0.9))]
    ids = [mb.add_vert(c) for c in corners]
    back = [mb.add_vert(c + out * 0.02) for c in corners]
    mb.add_face(ids, HIDE)
    mb.add_face(list(reversed(back)), HIDE_DARK)


def add_material_bundle(mb, rng, center, bones, sticks):
    """Ossa e bastoni ancora a terra, distesi un po' alla rinfusa."""
    c = Vector((center[0], center[1], 0.0))
    for i in range(sticks):
        a = 0.3 + (rng.random() - 0.5) * 0.4
        d = Vector((math.cos(a), math.sin(a), 0.0))
        start = c + Vector((0, (i - sticks / 2) * 0.12, HIDE_THICKNESS + 0.06 + (i % 2) * 0.05)) - d * STICK_HEIGHT * 0.45
        color = S.STICK_TONES[i % len(S.STICK_TONES)]
        S.add_tube(mb, S.bent_line(start, start + d * STICK_HEIGHT * 0.9, (0.03, 0.0), rng=rng), [0.05] * 5, color, rng=rng)
    for i in range(bones):
        a = -0.6 + (rng.random() - 0.5) * 0.5
        d = Vector((math.cos(a), math.sin(a), 0.0))
        start = c + Vector((0.3 + i * 0.18, -0.6, HIDE_THICKNESS + 0.12)) - d * BONE_LENGTH * 0.5
        add_bone(mb, rng, start, d)


def build_phase(phase, collection, material, offset_x):
    mb = S.MeshBuilder()
    add_hides(mb, random.Random(SEED))
    cairn_rng = random.Random(SEED + 1)  # stesso seme per ogni fase: le pietre restano le stesse
    ring_rng = random.Random(SEED + 2)
    items = random.Random(SEED + 3)
    diagonals = [math.pi / 4 + math.pi / 2 * i for i in range(4)]
    cardinals = [math.pi / 2 * i for i in range(4)]
    if phase == 0:
        add_cairn(mb, cairn_rng, 2)
        add_pebble_pile(mb, ring_rng, (1.7, -1.3))
        add_material_bundle(mb, items, (-2.2, 2.0), bones=4, sticks=4)
    elif phase == 1:
        add_cairn(mb, cairn_rng, 4)
        add_pebble_ring(mb, ring_rng, 0.5)
        for a in cardinals:
            add_planted_bone(mb, items, a)
        add_material_bundle(mb, items, (-2.2, 2.0), bones=0, sticks=4)
    else:
        add_cairn(mb, cairn_rng, len(CAIRN))
        add_pebble_ring(mb, ring_rng, 1.0)
        for a in cardinals:
            add_planted_bone(mb, items, a)
        for a in diagonals:
            add_planted_stick(mb, items, a)
    obj = mb.to_object("stacked_stones_" + PHASES[phase], collection, material)
    obj.location.x = offset_x
    return obj


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    material = S.vertex_color_material()
    root = S.new_collection("stacked_stones")
    for phase, name in enumerate(PHASES):
        col = S.new_collection("stacked_stones_" + name, root)
        x = (phase - 1) * PHASE_SPACING
        build_phase(phase, col, material, x)
        S.add_review_ground(col, (x, 0.0))
        S.add_label(col, name.split("_", 1)[1], (x, -5.6, 0.3), size=0.9)
    S.add_review_light_and_camera((0.0, 0.0), distance=30.0)
    S.save_blend("stacked_stones")
    if export:
        for name in PHASES:
            obj = bpy.data.objects["stacked_stones_" + name]
            old = obj.location.x
            obj.location.x = 0.0
            S.export_glb(bpy.data.collections["stacked_stones_" + name], "buildings", "stacked_stones_" + name)
            obj.location.x = old


import bpy  # noqa: E402

main()
