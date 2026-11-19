# TSB - pezzi comuni per le ricette che preparano modelli del pacchetto Quaternius "Stylized Nature MegaKit" (CC0):
# importare dal pacchetto originale (mai modificato), mettere l'origine al piede, esportare in .gltf con le texture in
# comune nella cartella del gruppo (un .glb ne terrebbe una copia per modello).

import os

import bpy

import tsb_style as S

PACK = os.path.normpath(os.path.join(S.ROOT, "..", "third_party", "quaternius_nature_megakit", "glTF"))


def import_model(name, collection):
    """Importa <name>.gltf dal pacchetto in collection; restituisce l'unico oggetto mesh (rinominato in minuscolo)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PACK, name + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for obj in new:
        for col in list(obj.users_collection):
            col.objects.unlink(obj)
        if obj.type == "MESH":
            collection.objects.link(obj)
        else:
            bpy.data.objects.remove(obj)
    obj = meshes[0]
    obj.name = name.lower()
    obj.parent = None
    return obj


def move_origin_to_foot(obj, foot_band=0.3, unit_width=False):
    """Sposta i vertici in modo che il centro della base sia in (0, 0, 0). foot_band: metri sopra il punto più basso
    che contano come base. unit_width: scala il modello perché la sua larghezza massima sia 1 (la taglia la dà Godot)."""
    mesh = obj.data
    mesh.transform(obj.matrix_world)
    obj.matrix_world.identity()
    min_z = min(v.co.z for v in mesh.vertices)
    foot = [v.co for v in mesh.vertices if v.co.z < min_z + foot_band]
    cx = sum(c.x for c in foot) / len(foot)
    cy = sum(c.y for c in foot) / len(foot)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= min_z
    width = max(max(abs(v.co.x), abs(v.co.y)) for v in mesh.vertices) * 2.0
    if unit_width and width > 0.0:
        for v in mesh.vertices:
            v.co /= width
    mesh.update()
    height = max(v.co.z for v in mesh.vertices)
    width = max(max(abs(v.co.x), abs(v.co.y)) for v in mesh.vertices) * 2.0
    print("TSB %s: alto %.2f, largo %.2f, %d triangoli" % (obj.name, height, width,
          sum(len(p.vertices) - 2 for p in mesh.polygons)))


def export_gltf(obj, group):
    """render3d/assets/models/<group>/<nome>.gltf + .bin, texture in comune in <group>/textures/."""
    folder = os.path.join(S.ROOT, "render3d", "assets", "models", group)
    path = os.path.join(folder, obj.name + ".gltf")
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              use_selection=True, export_apply=True)
    print("TSB exported", path)
