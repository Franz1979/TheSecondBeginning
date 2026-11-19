# TSB - PINI dal pacchetto Quaternius "Stylized Nature MegaKit" (CC0, versione Standard gratuita).
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/pines.py [-- --export]
#
# Prende Pine_1..Pine_5 dal pacchetto originale (fuori dal progetto Godot, in
# Project_TheSecondBeginning/third_party/quaternius_nature_megakit/glTF/, mai modificato) e li prepara per il gioco:
# - origine al piede del tronco (centro della base, a terra), così Godot li pianta dove dice il 2D;
# - misure in metri come nel pacchetto (7-10 m): la grandezza vera la decide Godot dall'età dell'albero (Trees3D);
# - un solo oggetto per pino con due superfici (corteccia e aghi) e le texture del pacchetto.
# Con --export scrive render3d/assets/models/vegetation/pines/pine_1..5.gltf (+ .bin, texture in comune in textures/);
# senza, salva solo il .blend da guardare.

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
import quaternius_lib as Q  # noqa: E402

NAMES = ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
SPACING = 9.0


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    root = S.new_collection("pini")
    for i, name in enumerate(NAMES):
        col = S.new_collection(name.lower(), root)
        obj = Q.import_model(name, col)
        Q.move_origin_to_foot(obj)
        if export:
            Q.export_gltf(obj, "vegetation/pines")
        x = (i - (len(NAMES) - 1) / 2) * SPACING
        obj.location = (x, 0.0, 0.0)
        S.add_review_ground(col, (x, 0.0), size=SPACING)
        S.add_label(col, name.lower(), (x, -5.0, 0.2), size=0.6)
    # Riferimento di scala: una persona di 1,7 m accanto al primo pino.
    ref = S.new_collection("review_persona", root)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=1.7, location=(-2 * SPACING + 2.0, 0.0, 0.85))
    person = bpy.context.active_object
    person.name = "review_persona"
    for col in list(person.users_collection):
        col.objects.unlink(person)
    ref.objects.link(person)
    S.add_review_light_and_camera((0.0, 0.0), distance=40.0)
    S.save_blend("pines")


import bpy  # noqa: E402

main()
