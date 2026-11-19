# TSB - libreria di stile condivisa dai modelli Blender (vedi render3d/PIPELINE_3D.txt, sezioni 3-4).
# Colori presi dal 2D (stesse costanti dei disegni e delle icone), materiale a colori nei vertici, pezzi comuni
# (rami, sassi, legature), scena di revisione, salvataggio del .blend ed export del .glb.
# Misure in metri (1 microcella = 10 m; Godot scala x 0,1 all'import). Z in alto in Blender = Y in alto in Godot.
# Davanti (porta) verso +Y di Blender = -Z di Godot.

import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

# --- Tavolozza (sRGB, come le Color() di Godot) --------------------------------------------------------------
STICK_MAIN = (0.42, 0.30, 0.16)   # StickIcon.STICK_COLOR_MAIN
STICK_LIGHT = (0.55, 0.40, 0.22)  # StickIcon.STICK_COLOR_LIGHT
STICK_DARK = (0.32, 0.22, 0.11)   # StickIcon.STICK_COLOR_DARK
STICK_TONES = (STICK_MAIN, STICK_LIGHT, STICK_DARK)
ROPE = (0.80, 0.70, 0.48)         # FishingLineIcon.ROPE_COLOR
ROPE_DARK = (0.52, 0.42, 0.26)    # FishingLineIcon.ROPE_DARK_COLOR
PEBBLE = (0.58, 0.57, 0.54)       # PebbleIcon.PEBBLE_COLOR
STRAW = (0.66, 0.58, 0.36)        # fibra vegetale secca
SHADOW = (0.10, 0.07, 0.04)       # interno buio (porta, sotto la copertura)
REVIEW_GROUND = (0.36, 0.42, 0.22)  # solo per la scena di revisione, non si esporta

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def jitter_color(color, rng, amount=0.06):
    shift = (rng.random() - 0.5) * 2.0 * amount
    return (
        min(max(color[0] + shift, 0.0), 1.0),
        min(max(color[1] + shift, 0.0), 1.0),
        min(max(color[2] + shift * 0.6, 0.0), 1.0),
    )


# --- Costruttore di mesh a colori per faccia -----------------------------------------------------------------
class MeshBuilder:
    """Accumula vertici, facce (antiorarie viste da fuori) e un colore per faccia; facce piatte."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.colors = []

    def add_vert(self, v):
        self.verts.append(Vector(v))
        return len(self.verts) - 1

    def add_face(self, indices, color):
        self.faces.append(tuple(indices))
        self.colors.append(color)

    def add_bmesh(self, bm, color_of_face):
        base = len(self.verts)
        bm.verts.ensure_lookup_table()
        for v in bm.verts:
            self.verts.append(v.co.copy())
        for f in bm.faces:
            self.add_face([base + v.index for v in f.verts], color_of_face(f))

    def to_object(self, name, collection, material):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.validate()
        attr = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for poly, color in zip(mesh.polygons, self.colors):
            poly.use_smooth = False
            for li in poly.loop_indices:
                attr.data[li].color_srgb = (color[0], color[1], color[2], 1.0)
        mesh.color_attributes.active_color = attr
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


# --- Pezzi comuni --------------------------------------------------------------------------------------------
def _frame(direction):
    d = direction.normalized()
    helper = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(helper).normalized()
    v = d.cross(u).normalized()
    return d, u, v


def add_tube(mb, points, radii, color, sides=5, rng=None, twist=0.0):
    """Ramo/palo: tubo a pochi lati lungo una polilinea, raggio per punto, chiuso alle due estremità."""
    rings = []
    for i, p in enumerate(points):
        if i == 0:
            direction = points[1] - points[0]
        elif i == len(points) - 1:
            direction = points[-1] - points[-2]
        else:
            direction = points[i + 1] - points[i - 1]
        d, u, v = _frame(direction)
        ring = []
        for j in range(sides):
            a = math.tau * j / sides + twist
            wobble = 1.0 + ((rng.random() - 0.5) * 0.25 if rng else 0.0)
            ring.append(mb.add_vert(p + (u * math.cos(a) + v * math.sin(a)) * radii[i] * wobble))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            c = jitter_color(color, rng, 0.03) if rng else color
            mb.add_face([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]], c)
    mb.add_face(list(rings[-1]), color)
    mb.add_face(list(reversed(rings[0])), color)


def bent_line(start, end, bend, count=5, rng=None):
    """Punti da start a end con una piega laterale a metà (un ramo, non una riga dritta, come in StickIcon)."""
    axis = end - start
    _, u, v = _frame(axis)
    side = u * bend[0] + v * bend[1]
    points = []
    for i in range(count):
        t = i / (count - 1)
        p = start + axis * t + side * math.sin(math.pi * t)
        if rng and 0 < i < count - 1:
            p += Vector(((rng.random() - 0.5) * 0.03, (rng.random() - 0.5) * 0.03, (rng.random() - 0.5) * 0.03))
        points.append(p)
    return points


def add_stone(mb, center, size, rng, color=PEBBLE, squash=0.6):
    """Sasso sfaccettato: inviluppo convesso di punti a caso (stesso spirito di FacetedStoneMesh)."""
    bm = bmesh.new()
    for _ in range(12):
        a = rng.random() * math.tau
        z = rng.random() * 2.0 - 1.0
        r = math.sqrt(1.0 - z * z)
        k = 0.75 + rng.random() * 0.25
        bm.verts.new((math.cos(a) * r * size * k, math.sin(a) * r * size * k, z * size * squash * k))
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co += Vector(center)
    mb.add_bmesh(bm, lambda f: jitter_color(color, rng, 0.05))
    bm.free()


def add_prism(mb, outline_xz, y_min, y_max, color, offset=(0.0, 0.0, 0.0)):
    """Lastra: poligono convesso nel piano XZ (x, z) estruso lungo Y da y_min a y_max, un solo colore."""
    bm = bmesh.new()
    front = [bm.verts.new((x + offset[0], y_max + offset[1], z + offset[2])) for x, z in outline_xz]
    back = [bm.verts.new((x + offset[0], y_min + offset[1], z + offset[2])) for x, z in outline_xz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(outline_xz)
    for i in range(n):
        k = (i + 1) % n
        bm.faces.new([front[i], back[i], back[k], front[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mb.add_bmesh(bm, lambda f: color)
    bm.free()


def disc_xz(center, radius, segments=8):
    return [(center[0] + math.cos(math.tau * i / segments) * radius, center[1] + math.sin(math.tau * i / segments) * radius)
            for i in range(segments)]


def add_lashing(mb, center, axis, radius, height, rng, turns=3):
    """Legatura di corda: qualche anello schiacciato attorno a un incrocio di rami."""
    d, u, v = _frame(axis)
    for t in range(turns):
        offset = d * (t - (turns - 1) / 2) * height
        pts = []
        for j in range(9):
            a = math.tau * j / 8
            pts.append(Vector(center) + offset + (u * math.cos(a) + v * math.sin(a)) * radius)
        add_tube(mb, pts, [height * 0.35] * len(pts), ROPE if t % 2 == 0 else ROPE_DARK, sides=4, rng=rng)


# --- Scena di revisione, salvataggio, export -----------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def vertex_color_material(name="TSB_VertexColor"):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def new_collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col


def add_review_ground(collection, center, size=10.0):
    """Una microcella (10 m) d'erba sotto il modello, solo per guardarlo: non va nell'export."""
    mb = MeshBuilder()
    h = size / 2
    ids = [mb.add_vert((center[0] + x, center[1] + y, 0.0)) for x, y in ((-h, -h), (h, -h), (h, h), (-h, h))]
    mb.add_face(ids, REVIEW_GROUND)
    return mb.to_object("review_ground", collection, vertex_color_material())


def add_label(collection, text, location, size=0.6):
    curve = bpy.data.curves.new(name="label_" + text, type="FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new("label_" + text, curve)
    obj.location = location
    obj.rotation_euler = (math.radians(70), 0.0, 0.0)
    collection.objects.link(obj)
    return obj


def add_review_light_and_camera(target, distance=16.0):
    sun_data = bpy.data.lights.new("sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    bpy.context.scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("camera")
    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (target[0], target[1] - distance, distance * 0.7)
    cam.rotation_euler = (math.radians(58), 0.0, 0.0)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def save_blend(name):
    path = os.path.join(ROOT, "render3d", "blender", "sources", name + ".blend")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Aprendo il file si vedono subito i colori (anteprima materiale) invece del grigio.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                for space in area.spaces:
                    if space.type == "VIEW_3D":
                        space.shading.type = "MATERIAL"
                        space.clip_end = 1000.0
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("TSB saved", path)
    return path


def export_glb(collection, category, name):
    """Esporta una collezione (senza terreno di revisione ed etichette) in render3d/assets/models/<categoria>/."""
    path = os.path.join(ROOT, "render3d", "assets", "models", category, name + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.all_objects:
        if obj.type == "MESH" and not obj.name.startswith("review_"):
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print("TSB exported", path)
    return path
