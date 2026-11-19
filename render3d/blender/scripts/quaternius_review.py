# TSB - scena di REVISIONE del pacchetto Quaternius "Stylized Nature MegaKit" (CC0, versione Standard gratuita).
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/quaternius_review.py
#
# Solo per guardare: importa dal pacchetto originale (fuori dal progetto Godot, in
# Project_TheSecondBeginning/third_party/quaternius_nature_megakit/, mai modificato) pini, alberi, cespugli e rocce,
# in file ordinate con il nome sotto, accanto alle nostre conifere fatte a ricetta per confronto. Non esporta niente:
# quello che ci piace passerà poi da una ricetta che lo adatta (scala, colori, pezzi separati) prima di entrare nel gioco.

import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402

PACK = os.path.normpath(os.path.join(S.ROOT, "..", "third_party", "quaternius_nature_megakit", "glTF"))
ROWS = (
    ("Pini", ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], 9.0),
    ("Alberi", ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], 9.0),
    ("Alberi contorti", ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"], 9.0),
    ("Alberi secchi", ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"], 9.0),
    ("Cespugli e piante", ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big", "Plant_7_Big"], 4.0),
    ("Rocce e sassi", ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3", "Pebble_Round_1", "Pebble_Square_1"], 4.0),
)
ROW_SPACING = 12.0


def import_model(name, collection, location):
    path = os.path.join(PACK, name + ".gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in new:
        for col in list(obj.users_collection):
            col.objects.unlink(obj)
        collection.objects.link(obj)
        if obj.parent is None:
            obj.location = (obj.location[0] + location[0], obj.location[1] + location[1], obj.location[2])
    return new


def main():
    S.reset_scene()
    root = S.new_collection("quaternius")
    for row, (title, names, spacing) in enumerate(ROWS):
        col = S.new_collection("q_" + title, root)
        y = row * ROW_SPACING
        for i, name in enumerate(names):
            x = (i - (len(names) - 1) / 2) * spacing
            import_model(name, col, (x, y))
            S.add_label(col, name, (x, y - 3.0, 0.2), size=0.6)
        S.add_label(col, title, (-(len(names) / 2 + 1) * spacing, y, 0.2), size=1.0)
    S.add_review_light_and_camera((0.0, ROW_SPACING * 2), distance=60.0)
    S.save_blend("quaternius_review")


import bpy  # noqa: E402

main()
