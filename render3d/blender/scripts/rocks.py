# TSB - ROCCE e SASSI dal pacchetto Quaternius "Stylized Nature MegaKit" (CC0, versione Standard gratuita).
# Lancio:  blender -b --factory-startup -P render3d/blender/scripts/rocks.py [-- --export]
#
# Rocce della cava: Rock_Medium_1..3. Sassi da raccogliere: Pebble_Round_1..5 e Pebble_Square_1..6. Dal pacchetto
# originale (mai modificato), con origine al centro della base e larghezza 1: la taglia la decide Godot come prima
# (Rock3D e Pebble3D, dalle misure del 2D). Texture del pacchetto (Rocks_Diffuse, PathRocks_Diffuse).
# Con --export scrive render3d/assets/models/rocks/<nome>.gltf (+ .bin, texture in comune in textures/);
# senza, salva solo il .blend da guardare.

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import tsb_style as S  # noqa: E402
import quaternius_lib as Q  # noqa: E402

ROWS = (
    ("rocce", ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]),
    ("sassi tondi", ["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5"]),
    ("sassi squadrati", ["Pebble_Square_1", "Pebble_Square_2", "Pebble_Square_3", "Pebble_Square_4",
                         "Pebble_Square_5", "Pebble_Square_6"]),
)
SPACING = 1.6
# Base: i vertici fino a 5 cm sopra il punto più basso, in metri del pacchetto (prima di portare la larghezza a 1).
FOOT_BAND = 0.05


def main():
    export = "--export" in sys.argv
    S.reset_scene()
    root = S.new_collection("rocce")
    for row, (title, names) in enumerate(ROWS):
        col = S.new_collection(title, root)
        y = row * 2.0
        for i, name in enumerate(names):
            obj = Q.import_model(name, col)
            Q.move_origin_to_foot(obj, foot_band=FOOT_BAND, unit_width=True)
            if export:
                Q.export_gltf(obj, "rocks")
            x = (i - (len(names) - 1) / 2) * SPACING
            obj.location = (x, y, 0.0)
        S.add_label(col, title, (-(len(names) / 2 + 1) * SPACING, y, 0.1), size=0.3)
    S.add_review_ground(root, (0.0, 2.0), size=12.0)
    S.add_review_light_and_camera((0.0, 2.0), distance=8.0)
    S.save_blend("rocks")


import bpy  # noqa: E402

main()
