# TSB - ricetta Blender della conifera (albero, sottotipo "conifer" di TREE), varianti di forma da semi diversi.
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/conifer.py            (solo .blend)
#          blender -b --factory-startup -P render3d/blender/scripts/conifer.py -- --export (anche i .glb)
#
# Riferimento (2026-11-19, foto dell'utente: abeti innevati): si vedono i RAMI, a palchi, che partono dal tronco, scendono
# e rialzano appena la punta; tra un palco e l'altro c'è aria e si intravede il tronco. Nello stile del 3D (facce piatte,
# colori pieni, pochi poligoni). Terza stesura: la prima (dischi tondi) era troppo regolare, la seconda (ciuffi a
# blocco) non mostrava i rami.
# Ogni ramo è una FRONDA: striscia piatta a schiena d'asino (costola più alta, bordi che ricadono), larga al centro e
# stretta in punta, bordi frastagliati, curva verso il basso. Lunghezze, pendenze, angoli e palchi irregolari, qualche
# ramo mancante, punta piegata.
#
# Ogni variante è fatta di TRE pezzi separati (oggetti distinti, poi mesh distinte nel gioco):
#   tronco - fusto e radici (sempre visibile)
#   chioma - fronde verdi e cima
#   neve   - strisce bianche sulla costola delle fronde: pronte per l'inverno, nel gioco spente finché non si fanno le
#            stagioni
# Origine al piede del tronco. Misure in metri (1 microcella = 10 m): la taglia del singolo albero (età) la decide il
# gioco ingrandendo in proporzione, la forma resta questa. Altre varianti = altre righe in VARIANTS (seme diverso).
#
# Revisione: fila davanti senza neve, fila dietro con la neve.

import math
import os
import random
import sys

import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
from mathutils import Vector  # noqa: E402

# Verdi delle conifere del 3D di oggi (Trees3D.CONIFER_GREEN_A/B) e vicini, sotto delle fronde, corteccia, neve.
GREENS = ((0.173, 0.322, 0.196), (0.243, 0.416, 0.227), (0.20, 0.36, 0.20), (0.27, 0.43, 0.24))
GREEN_UNDER = (0.09, 0.18, 0.11)
BARK = (0.30, 0.22, 0.16)
BARK_DARK = (0.22, 0.16, 0.11)
SNOW = (0.92, 0.94, 0.97)

# altezza, raggio della chioma in basso, palchi, inizio della chioma (frazione dell'altezza), raggio del tronco, seme,
# pancia (<1 piena, >1 a cono dritto), piega della punta (m).
VARIANTS = {
    "alta": {"height": 22.0, "radius": 4.6, "tiers": 13, "crown_base": 0.30, "trunk": 0.38, "seed": 11, "profile": 1.0, "bend": 0.6},
    "slanciata": {"height": 20.0, "radius": 3.6, "tiers": 13, "crown_base": 0.25, "trunk": 0.32, "seed": 53, "profile": 1.2, "bend": 0.9},
    "media": {"height": 15.0, "radius": 4.8, "tiers": 11, "crown_base": 0.14, "trunk": 0.34, "seed": 23, "profile": 0.85, "bend": 0.4},
    "tozza": {"height": 12.0, "radius": 5.0, "tiers": 10, "crown_base": 0.10, "trunk": 0.33, "seed": 71, "profile": 0.75, "bend": 0.3},
    "giovane": {"height": 7.0, "radius": 2.8, "tiers": 8, "crown_base": 0.06, "trunk": 0.16, "seed": 37, "profile": 0.9, "bend": 0.2},
}

BRANCHES_MIN = 7           # fronde per palco
BRANCHES_RANGE = 4
MISSING_CHANCE = 0.12      # un ramo che manca: buchi irregolari nella sagoma
SEGMENTS = 5               # pezzi lungo una fronda
WIDTH = 0.42               # larghezza massima della fronda (frazione della sua lunghezza)
RIDGE = 0.10               # quanto la costola sta più in alto dei bordi (frazione della lunghezza)
THICKNESS = 0.05           # spessore sotto la costola (frazione della lunghezza)
DROOP_MIN = 0.45           # quanto scende la fronda (frazione della lunghezza)
DROOP_RANGE = 0.25
TIP_LIFT = 0.02            # punta che rialza appena (frazione della lunghezza)
JAG = 0.35                 # frastagliatura dei bordi (frazione della larghezza)
TIER_JITTER = 0.30         # spostamento in quota di un palco (frazione del passo)
TOP_RADIUS = 0.08          # raggio in punta rispetto al raggio in basso
SNOW_FROM = 0.08           # la neve va da qui...
SNOW_TO = 0.80             # ...a qui lungo la fronda
SNOW_WIDTH = 0.55          # larghezza della neve rispetto alla fronda
SNOW_LIFT = 0.05
TRUNK_SIDES = 6
SPACING = 12.0


def radius_at(v, t):
    """Raggio della chioma a quota t (0 = in basso, 1 = in punta)."""
    return v["radius"] * (TOP_RADIUS + (1.0 - TOP_RADIUS) * (1.0 - t) ** v["profile"])


def tip_offset(v, z):
    """La punta piegata da un lato: lo spostamento cresce verso l'alto (nulla sotto metà altezza)."""
    k = max(0.0, (z / v["height"] - 0.5) / 0.5)
    return Vector((v["bend"] * k * k, v["bend"] * 0.3 * k * k, 0.0))


def add_hull(mb, center, along, side, up, points, rng, color_of_face):
    """Ciuffo sfaccettato: inviluppo convesso di punti a caso in un ellissoide (semiassi along/side/up, vettori)."""
    bm = bmesh.new()
    for _ in range(points):
        a = rng.random() * math.tau
        z = rng.random() * 2.0 - 1.0
        r = math.sqrt(1.0 - z * z)
        k = 0.7 + rng.random() * 0.3
        bm.verts.new(Vector(center) + along * (math.cos(a) * r * k) + side * (math.sin(a) * r * k) + up * (z * k))
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mb.add_bmesh(bm, color_of_face)
    bm.free()


def add_trunk(mb, v, rng):
    height = v["height"]
    points = []
    for k in range(7):
        z = height * 0.98 * k / 6
        p = Vector((0, 0, z)) + tip_offset(v, z)
        if 0 < k < 6:
            p += Vector(((rng.random() - 0.5) * 0.2, (rng.random() - 0.5) * 0.2, 0.0))
        points.append(p)
    radii = [v["trunk"] * (1.0 - 0.88 * k / 6) for k in range(7)]
    S.add_tube(mb, points, radii, BARK, sides=TRUNK_SIDES, rng=rng)
    # Radici appena accennate al piede.
    for i in range(3 + int(rng.random() * 2)):
        a = math.tau * i / 4 + rng.random() * 0.8
        foot = Vector((math.cos(a), math.sin(a), 0.0)) * v["trunk"] * (1.8 + rng.random())
        S.add_tube(mb, [Vector((0, 0, v["trunk"] * 0.8)), foot + Vector((0, 0, -0.05))],
                   [v["trunk"] * 0.45, v["trunk"] * 0.12], BARK_DARK, sides=4, rng=rng)


def tier_heights(v, rng):
    """Quote dei palchi, a passo irregolare."""
    bottom = v["height"] * v["crown_base"]
    top = v["height"] * 0.92
    step = (top - bottom) / v["tiers"]
    heights = []
    for i in range(v["tiers"]):
        z = bottom + (top - bottom) * (i / (v["tiers"] - 1)) ** 0.95
        if 0 < i < v["tiers"] - 1:
            z += (rng.random() - 0.5) * 2.0 * TIER_JITTER * step
        heights.append(z)
    return heights


def frond_spine(start, out, length, droop, rng):
    """Costola della fronda: parte dal tronco, scende e rialza appena la punta; con un po' di storto laterale."""
    side = Vector((-out.y, out.x, 0.0))
    wander = (rng.random() - 0.5) * 0.25 * length
    spine = []
    for k in range(SEGMENTS + 1):
        s = k / SEGMENTS
        drop = droop * (0.35 * s + 0.65 * s * s) - TIP_LIFT * length * max(0.0, s - 0.7) / 0.3
        spine.append(start + out * (length * s) + side * (wander * s * s) + Vector((0, 0, -drop)))
    return spine, side


def frond_width(s):
    """Larga a un terzo, stretta all'attacco e in punta."""
    return math.sin(math.pi * (0.12 + 0.88 * s) ** 0.8)


def add_frond(mb, spine, side, length, base_color, rng):
    """Fronda a schiena d'asino: costola, bordi sinistro e destro più bassi, chiglia sotto; bordi frastagliati."""
    rows = []
    for k, p in enumerate(spine):
        s = k / SEGMENTS
        w = WIDTH * length * frond_width(s) * 0.5
        jag = 1.0 + (JAG if k % 2 == 1 else -JAG * 0.3) * (0.6 + rng.random() * 0.8)
        drop = RIDGE * length * frond_width(s)
        left = p + side * (w * jag) + Vector((0, 0, -drop))
        right = p - side * (w * (2.0 - jag) if k % 2 == 1 else w * jag) + Vector((0, 0, -drop))
        keel = p + Vector((0, 0, -drop * 0.6 - THICKNESS * length))
        rows.append([mb.add_vert(left), mb.add_vert(p), mb.add_vert(right), mb.add_vert(keel)])
    for k in range(SEGMENTS):
        a = rows[k]
        b = rows[k + 1]
        top = S.jitter_color(base_color, rng, 0.03)
        lit = (min(top[0] * 1.12, 1.0), min(top[1] * 1.12, 1.0), min(top[2] * 1.12, 1.0))
        # Sopra: due falde (sinistra più chiara, verso la luce), sotto: due falde scure fino alla chiglia.
        mb.add_face([a[0], b[0], b[1], a[1]], lit)
        mb.add_face([a[1], b[1], b[2], a[2]], top)
        mb.add_face([a[0], a[3], b[3], b[0]], GREEN_UNDER)
        mb.add_face([a[2], b[2], b[3], a[3]], GREEN_UNDER)
    first = rows[0]
    mb.add_face([first[0], first[1], first[2], first[3]], GREEN_UNDER)


def add_frond_snow(mb, spine, side, length, rng):
    """Neve: striscia sulla costola, dall'attacco a poco prima della punta, appena sollevata."""
    ids = []
    for k, p in enumerate(spine):
        s = k / SEGMENTS
        if s < SNOW_FROM - 1e-6 or s > SNOW_TO + 0.2:
            continue
        w = WIDTH * length * frond_width(s) * 0.5 * SNOW_WIDTH
        drop = RIDGE * length * frond_width(s) * SNOW_WIDTH
        lift = Vector((0, 0, SNOW_LIFT))
        ids.append((mb.add_vert(p + side * w + Vector((0, 0, -drop)) + lift),
                    mb.add_vert(p + lift + Vector((0, 0, 0.04 * length))),
                    mb.add_vert(p - side * w + Vector((0, 0, -drop)) + lift)))
    for k in range(len(ids) - 1):
        a = ids[k]
        b = ids[k + 1]
        mb.add_face([a[0], b[0], b[1], a[1]], S.jitter_color(SNOW, rng, 0.02))
        mb.add_face([a[1], b[1], b[2], a[2]], S.jitter_color((SNOW[0] * 0.9, SNOW[1] * 0.92, SNOW[2]), rng, 0.02))


def build_variant(name, v, collection, material, offset, with_snow):
    rng = random.Random(v["seed"])
    trunk = S.MeshBuilder()
    add_trunk(trunk, v, rng)
    crown = S.MeshBuilder()
    snow = S.MeshBuilder()
    heights = tier_heights(v, rng)
    for z in heights:
        t = (z - heights[0]) / max(heights[-1] - heights[0], 0.01)
        radius = radius_at(v, t)
        count = BRANCHES_MIN + int(rng.random() * (BRANCHES_RANGE + 1))
        if t > 0.75:
            count = max(4, count - 3)
        twist = rng.random() * math.tau
        base = GREENS[int(rng.random() * len(GREENS))]
        center = Vector((0, 0, z)) + tip_offset(v, z)
        for k in range(count):
            if rng.random() < MISSING_CHANCE and t < 0.8:
                continue
            a = twist + math.tau * k / count + (rng.random() - 0.5) * (math.tau / count) * 0.7
            out = Vector((math.cos(a), math.sin(a), 0.0))
            length = radius * (0.75 + rng.random() * 0.45)
            droop = length * (DROOP_MIN + rng.random() * DROOP_RANGE)
            start = center + out * (v["trunk"] * 0.6) + Vector((0, 0, (rng.random() - 0.5) * 0.3))
            spine, side = frond_spine(start, out, length, droop, rng)
            add_frond(crown, spine, side, length, base, rng)
            add_frond_snow(snow, spine, side, length, rng)
    # Cima: un ciuffo stretto e alto, piegato col resto.
    top = v["height"] * 0.96
    tip_center = Vector((0, 0, top)) + tip_offset(v, top)
    r = v["radius"] * TOP_RADIUS * 1.1
    add_hull(crown, tip_center, Vector((r, 0, 0)), Vector((0, r, 0)), Vector((0, 0, v["height"] * 0.06)), 7, rng,
             lambda f: S.jitter_color(GREENS[0], rng, 0.03))
    add_hull(snow, tip_center + Vector((0, 0, v["height"] * 0.025)), Vector((r * 0.7, 0, 0)), Vector((0, r * 0.7, 0)),
             Vector((0, 0, v["height"] * 0.025)), 6, rng, lambda f: S.jitter_color(SNOW, rng, 0.02))
    objects = [trunk.to_object("conifer_%s_tronco" % name, collection, material),
               crown.to_object("conifer_%s_chioma" % name, collection, material)]
    if with_snow:
        objects.append(snow.to_object("conifer_%s_neve" % name, collection, material))
    for obj in objects:
        obj.location = Vector(offset)
    return objects


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    material = S.vertex_color_material()
    root = S.new_collection("conifer")
    names = list(VARIANTS.keys())
    for row, with_snow in enumerate((False, True)):
        for i, name in enumerate(names):
            suffix = "_neve" if with_snow else ""
            col = S.new_collection("conifer_" + name + suffix, root)
            x = (i - (len(names) - 1) / 2) * SPACING
            y = row * SPACING
            build_variant(name, VARIANTS[name], col, material, (x, y, 0.0), with_snow)
            S.add_review_ground(col, (x, y), size=SPACING)
            S.add_label(col, name + (" + neve" if with_snow else ""), (x, y - SPACING / 2 + 0.5, 0.3), size=1.2)
    S.add_review_light_and_camera((0.0, SPACING / 2), distance=60.0)
    S.save_blend("conifer")
    if export:
        # Un .glb per variante con i tre pezzi (tronco, chioma, neve) come mesh separate, al piede (origine).
        for name in names:
            col = bpy.data.collections["conifer_" + name + "_neve"]
            moved = []
            for obj in col.all_objects:
                if obj.type == "MESH" and not obj.name.startswith("review_"):
                    moved.append((obj, obj.location.copy()))
                    obj.location = (0.0, 0.0, 0.0)
            S.export_glb(col, "vegetation", "conifer_" + name)
            for obj, loc in moved:
                obj.location = loc


import bpy  # noqa: E402

main()
