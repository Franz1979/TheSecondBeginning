# TSB - ricetta Blender della tenda di rami (stick_tent), con le fasi del cantiere.
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/stick_tent.py            (solo .blend)
#          blender -b --factory-startup -P render3d/blender/scripts/stick_tent.py -- --export (anche i .glb)
#
# Dal 2D (TentShapes.draw_stick_tent): raggio 2 m (RADIUS 2.0, 1 px = 1 m), 22 rami a raggiera con lunghezza,
# spessore e tono irregolari e le punte oltre il colmo, copertura chiusa (il terreno non si vede), nodo scuro dove i
# rami si incrociano, porta su un lato. Dai materiali di stick_tent.tres: 40 bastoni (rami e copertura), 20 sassolini
# (anello al piede), 3 corde di fibra (legatura in cima), 20 fibre vegetali (intreccio della copertura).
#
# Fasi (una collezione ciascuna, affiancate per la revisione; l'aggancio all'avanzamento del lavoro si decide dopo):
#   0 cantiere   - sassi in cerchio, mucchio di rami, corda
#   1 struttura  - tripode legato in cima + pali della porta
#   2 copertura  - tutti i rami, intreccio fino a metà altezza
#   3 finita

import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

# Tutta la tenda ingrandita di questo fattore (2026-11-19, richiesta utente: 1,1); le misure sotto restano quelle del 2D.
MODEL_SCALE = 1.1
RADIUS = 2.0            # raggio al piede (m), come il 2D
APEX_HEIGHT = 2.7       # colmo
TIP_EXTRA_MIN = 0.25    # punte oltre il colmo (STICK_BRANCH_OUTER_EXTRA del 2D)
TIP_EXTRA_RANGE = 0.45
BRANCH_COUNT = 22       # STICK_BRANCH_COUNT
BRANCH_RADIUS_MIN = 0.045
BRANCH_RADIUS_RANGE = 0.035
ANGLE_JITTER = 0.22     # STICK_BRANCH_ANGLE_JITTER
BEND = 0.12
DOOR_ANGLE = math.pi / 2          # porta verso +Y (davanti)
DOOR_HALF_ANGLE = math.radians(17)
DOOR_HEIGHT = 1.25
SHELL_INSET = 0.06      # copertura appena dentro i rami
SHELL_SEGMENTS = 20
SHELL_ROWS = 5
PEBBLE_COUNT = 20
PEBBLE_RING = RADIUS + 0.12
SEED = 7

PHASES = ("0_cantiere", "1_struttura", "2_copertura", "3_finita")
PHASE_SPACING = 7.0


def _angle_dist(a, b):
    return abs((a - b + math.pi) % math.tau - math.pi)


def branch_angles(rng):
    """22 angoli irregolari; quelli che cadono nella porta vanno sui due stipiti."""
    angles = []
    for i in range(BRANCH_COUNT):
        a = math.tau * i / BRANCH_COUNT + (rng.random() - 0.5) * ANGLE_JITTER
        if _angle_dist(a, DOOR_ANGLE) < DOOR_HALF_ANGLE:
            side = 1.0 if ((a - DOOR_ANGLE + math.pi) % math.tau - math.pi) > 0 else -1.0
            a = DOOR_ANGLE + side * (DOOR_HALF_ANGLE + 0.02)
        angles.append(a)
    return angles


def apex():
    return Vector((0.0, 0.0, APEX_HEIGHT))


def add_branch(mb, angle, rng, foot_radius=RADIUS):
    foot = Vector((math.cos(angle) * foot_radius, math.sin(angle) * foot_radius, -0.05))
    cross = apex() + Vector(((rng.random() - 0.5) * 0.18, (rng.random() - 0.5) * 0.18, (rng.random() - 0.5) * 0.12))
    direction = (cross - foot).normalized()
    tip = cross + direction * (TIP_EXTRA_MIN + TIP_EXTRA_RANGE * rng.random())
    points = S.bent_line(foot, tip, ((rng.random() - 0.5) * BEND, (rng.random() - 0.5) * BEND), count=6, rng=rng)
    base_r = BRANCH_RADIUS_MIN + BRANCH_RADIUS_RANGE * rng.random()
    radii = [base_r * (1.0 - 0.5 * i / (len(points) - 1)) for i in range(len(points))]
    color = S.jitter_color(rng.choice(S.STICK_TONES), rng, 0.08)
    S.add_tube(mb, points, radii, color, sides=5, rng=rng, twist=rng.random())


def add_shell(mb, rng, max_height):
    """Copertura chiusa di rami fitti e fibra intrecciata: un cono a facce, con l'apertura della porta.
    Faccia esterna a toni di ramo (qualche toppa di fibra), faccia interna buia."""
    rows = []
    for r in range(SHELL_ROWS + 1):
        t = r / SHELL_ROWS
        z = APEX_HEIGHT * 0.96 * t
        radius = (RADIUS - SHELL_INSET) * (1.0 - t * 0.97)
        ring = []
        for s in range(SHELL_SEGMENTS):
            a = math.tau * s / SHELL_SEGMENTS
            wob = 1.0 + (rng.random() - 0.5) * 0.06 if 0 < r < SHELL_ROWS else 1.0
            ring.append(Vector((math.cos(a) * radius * wob, math.sin(a) * radius * wob, z)))
        rows.append(ring)
    for r in range(SHELL_ROWS):
        for s in range(SHELL_SEGMENTS):
            k = (s + 1) % SHELL_SEGMENTS
            mid_a = math.tau * (s + 0.5) / SHELL_SEGMENTS
            low_z = rows[r][s].z
            if low_z >= max_height:
                continue
            if _angle_dist(mid_a, DOOR_ANGLE) < DOOR_HALF_ANGLE and low_z < DOOR_HEIGHT:
                continue
            quad = [rows[r][s], rows[r][k], rows[r + 1][k], rows[r + 1][s]]
            outside = [mb.add_vert(p) for p in quad]
            tone = S.STRAW if rng.random() < 0.18 else rng.choice(S.STICK_TONES)
            mb.add_face(outside, S.jitter_color(tone, rng, 0.05))
            inside = [mb.add_vert(p - Vector((p.x, p.y, 0)).normalized() * 0.02 if p.length > 0.01 else p) for p in quad]
            mb.add_face(list(reversed(inside)), S.SHADOW)


def add_floor_shadow(mb):
    """Pavimento buio dentro la tenda: dalla porta non si vede l'erba."""
    ids = []
    for s in range(SHELL_SEGMENTS):
        a = math.tau * s / SHELL_SEGMENTS
        ids.append(mb.add_vert((math.cos(a) * (RADIUS - SHELL_INSET), math.sin(a) * (RADIUS - SHELL_INSET), 0.01)))
    mb.add_face(ids, S.SHADOW)


def add_pebble_ring(mb, rng):
    for i in range(PEBBLE_COUNT):
        a = math.tau * i / PEBBLE_COUNT + (rng.random() - 0.5) * 0.12
        if _angle_dist(a, DOOR_ANGLE) < DOOR_HALF_ANGLE * 0.8:
            continue  # niente sassi sulla soglia
        r = PEBBLE_RING + (rng.random() - 0.5) * 0.08
        S.add_stone(mb, (math.cos(a) * r, math.sin(a) * r, 0.03), 0.10 + rng.random() * 0.06, rng)


def add_pebble_pile(mb, rng, center):
    """I 20 sassolini ancora a mucchio, prima di metterli in cerchio."""
    for i in range(PEBBLE_COUNT):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * 0.35
        z = 0.03 + max(0.0, 0.18 - r * 0.45) * (0.5 + rng.random() * 0.5)
        S.add_stone(mb, (center[0] + math.cos(a) * r, center[1] + math.sin(a) * r, z), 0.09 + rng.random() * 0.05, rng)


def add_stick_pile(mb, rng, center):
    """Mucchio di rami a terra in attesa di essere alzati."""
    for i in range(9):
        a = 0.35 + (rng.random() - 0.5) * 0.3
        length = 2.6 + rng.random() * 0.6
        off = Vector(((rng.random() - 0.5) * 0.4, (rng.random() - 0.5) * 0.5, 0.05 + 0.07 * (i // 3)))
        d = Vector((math.cos(a), math.sin(a), 0.0))
        start = Vector(center) + off - d * length / 2
        end = Vector(center) + off + d * length / 2
        r = 0.04 + rng.random() * 0.02
        S.add_tube(mb, S.bent_line(start, end, (0.0, (rng.random() - 0.5) * 0.08), count=4, rng=rng),
                   [r, r * 0.9, r * 0.75, r * 0.6], S.jitter_color(rng.choice(S.STICK_TONES), rng, 0.08), rng=rng)


def add_rope_coil(mb, rng, center):
    for t in range(3):
        pts = []
        rr = 0.18 - t * 0.04
        for j in range(9):
            a = math.tau * j / 8
            pts.append(Vector(center) + Vector((math.cos(a) * rr, math.sin(a) * rr, 0.02 + t * 0.02)))
        S.add_tube(mb, pts, [0.018] * len(pts), S.ROPE if t % 2 == 0 else S.ROPE_DARK, sides=4, rng=rng)


def build_phase(phase, collection, material, offset_x):
    rng = random.Random(SEED)  # stesso seme per ogni fase: i rami restano gli stessi da una fase all'altra
    angles = branch_angles(rng)
    branch_rngs = [random.Random(SEED * 1000 + i) for i in range(BRANCH_COUNT)]
    mb = S.MeshBuilder()
    deco = random.Random(SEED + 1)
    if phase == 0:
        add_pebble_pile(mb, deco, (-0.9, 0.7, 0.0))
        add_stick_pile(mb, deco, (0.2, -0.3, 0.0))
        add_rope_coil(mb, deco, (-0.9, -0.9, 0.0))
    else:
        add_pebble_ring(mb, deco)
        # Tripode (tre rami ben distribuiti) e i due stipiti della porta, sempre gli stessi rami del modello finito.
        door = [i for i, a in enumerate(angles) if abs(_angle_dist(a, DOOR_ANGLE) - DOOR_HALF_ANGLE - 0.02) < 1e-6]
        tripod = [0, BRANCH_COUNT // 3, 2 * BRANCH_COUNT // 3]
        frame = set(tripod) | set(door)
        for i, a in enumerate(angles):
            if phase >= 2 or i in frame:
                add_branch(mb, a, branch_rngs[i])
        S.add_lashing(mb, apex(), Vector((0, 0, 1)), 0.11, 0.05, deco)
        if phase >= 2:
            add_floor_shadow(mb)
            add_shell(mb, random.Random(SEED + 2), APEX_HEIGHT * (0.5 if phase == 2 else 1.0))
    obj = mb.to_object("stick_tent_" + PHASES[phase], collection, material)
    # Misura finale scritta nella mesh (non nella scala dell'oggetto: il gioco prende la mesh così com'è).
    obj.data.transform(Matrix.Scale(MODEL_SCALE, 4))
    obj.location.x = offset_x
    return obj


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    material = S.vertex_color_material()
    root = S.new_collection("stick_tent")
    for phase, name in enumerate(PHASES):
        col = S.new_collection("stick_tent_" + name, root)
        x = (phase - 1.5) * PHASE_SPACING
        build_phase(phase, col, material, x)
        S.add_review_ground(col, (x, 0.0))
        S.add_label(col, name.split("_", 1)[1], (x, -4.2, 0.3))
    S.add_review_light_and_camera((0.0, 0.0), distance=22.0)
    S.save_blend("stick_tent")
    if export:
        for phase, name in enumerate(PHASES):
            col = bpy.data.collections["stick_tent_" + name]
            obj = bpy.data.objects["stick_tent_" + name]
            old = obj.location.x
            obj.location.x = 0.0
            S.export_glb(col, "buildings", "stick_tent_" + name)
            obj.location.x = old


import bpy  # noqa: E402

main()
