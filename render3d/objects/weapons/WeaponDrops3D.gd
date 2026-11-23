class_name WeaponDrops3D
extends Node3D

# Oggetto 3D: le armi scagliate a terra in attesa di recupero (2026-11-21), nel punto e con l'inclinazione del
# segnaposto 2D (WeaponDropsSnapshot3D). Modelli nostri (SOURCES_PER_GIOCO/blender/scripts/weapons_ground.py): punta
# nell'origine, arma lungo +X, lunga 1. Posa a caso ma fissa per lancio (seme = id del cacciatore; utente: un po'
# conficcata, un po' distesa): conficcata di sbieco con la punta nel terreno, oppure distesa. Una MultiMesh per arma,
# creata una volta; a ogni fotogramma solo le copie (sono poche). Un'arma senza modello qui non si disegna.

const MODEL_DIR := "res://render3d/assets/models/props/"
# arma -> lunghezza in microcelle (un adulto è alto People3D.HEIGHT = 0.3).
const LENGTHS := {
	"wooden_spear": 0.34,
	"stone_spear": 0.34,
	"stone_knife": 0.1,
}
# Conficcata: inclinazione dalla verticale (radianti, tra i due valori) e quanta parte della lunghezza sta sotto terra.
const STUCK_TILT := Vector2(0.45, 0.8)
const STUCK_SINK := 0.12
# Quota delle armi distese (metà dello spessore dell'asta, in frazioni della lunghezza).
const LYING_LIFT := 0.02

var _buffers: Dictionary = {} # arma -> InstanceBuffer3D


func _init(material: Material) -> void:
	name = "WeaponDrops"
	for weapon in LENGTHS:
		var mesh := ModelMesh3D.load_mesh(MODEL_DIR + "weapon_ground_" + weapon + ".gltf")
		if mesh == null:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		add_child(instance)
		_buffers[weapon] = InstanceBuffer3D.new(multimesh)


func update(snapshot: WeaponDropsSnapshot3D) -> void:
	for buffer in _buffers.values():
		(buffer as InstanceBuffer3D).begin()
	for i in range(snapshot.size()):
		var weapon := snapshot.weapons[i]
		if not _buffers.has(weapon):
			continue
		var length: float = LENGTHS[weapon]
		var h := hash(snapshot.seeds[i])
		var place := snapshot.positions[i]
		var ground := snapshot.grounds[i]
		var y := GroundHeight3D.land_height(ground.x, ground.y)
		# Direzione dell'arma in pianta, dall'inclinazione del 2D (asse X locale del segnaposto).
		var yaw := -snapshot.rotations[i]
		var basis: Basis
		var origin := Vector3(place.x, y, place.y)
		if posmod(h, 2) == 0:
			var tilt := lerpf(STUCK_TILT.x, STUCK_TILT.y, float(posmod(h / 7, 1000)) / 1000.0)
			# +X dell'arma (dalla punta al fondo) verso l'alto, piegata di `tilt` dalla verticale.
			basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5 - tilt)
			origin -= basis.x * length * STUCK_SINK
		else:
			basis = Basis(Vector3.UP, yaw)
			origin.y += LYING_LIFT * length
		(_buffers[weapon] as InstanceBuffer3D).add(Transform3D(basis.scaled(Vector3.ONE * length), origin))
	for buffer in _buffers.values():
		(buffer as InstanceBuffer3D).commit()
