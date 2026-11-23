class_name WeaponDropsSnapshot3D
extends RefCounted

# Armi scagliate a terra in attesa di recupero (2026-11-21): i DroppedWeaponMarker del 2D (GameScene.
# _dropped_weapon_markers), poche e rilette a ogni fotogramma (lo stesso oggetto, clear()). Array paralleli.

# Nome dell'arma (wooden_spear, stone_spear, stone_knife...).
var weapons := PackedStringArray()
# Punto di caduta nella vista 3D (x, z) in microcelle, e in microcelle assolute del mondo (altezza del terreno).
var positions := PackedVector2Array()
var grounds := PackedVector2Array()
# Inclinazione del segnaposto 2D (radianti) e seme fisso del lancio (id del cacciatore).
var rotations := PackedFloat32Array()
var seeds := PackedInt32Array()


func clear() -> void:
	weapons.clear()
	positions.clear()
	grounds.clear()
	rotations.clear()
	seeds.clear()


func size() -> int:
	return positions.size()
