class_name Animals3D
extends Node3D

# Oggetto 3D: gli animali come pupazzi semplici fatti a codice (2026-11-21, richiesta utente, passo 1: come le persone).
# Un quadrupede comune per tutte le specie (busto, testa, quattro zampe): cambiano solo le proporzioni, da SHAPES per
# specie selvatica (i domestici usano quella d'origine, come la sagoma del 2D). Lunghezza, colore, grandezza per età,
# posizione e direzione vengono dal 2D (GameStateReader.animals); le zampe vanno con la strada fatta (WalkSteps3D),
# a coppie in diagonale come al trotto. Anello a terra per l'animale selezionato.
# Leggero come le persone: una MultiMesh per pezzo, creata una volta; a ogni fotogramma solo le posizioni delle copie.
# Dettagli di specie (orecchie, corna, code, uccelli, salti del coniglio): passo 2.

# Misure in frazioni della lunghezza della sagoma 2D (coda e orecchie comprese), davanti verso -Z:
# leg = altezza delle zampe, body = lunghezza / altezza / larghezza del busto, head = grandezza della testa,
# head_up = quanto la testa sta sopra il centro del busto (in altezze del busto).
const SHAPES := {
	"rabbit": {"leg": 0.1, "body": Vector3(0.62, 0.38, 0.38), "head": 0.3, "head_up": 0.35},
	"deer": {"leg": 0.48, "body": Vector3(0.6, 0.26, 0.22), "head": 0.17, "head_up": 1.4},
	"boar": {"leg": 0.2, "body": Vector3(0.66, 0.36, 0.3), "head": 0.26, "head_up": 0.1},
	"tarpan": {"leg": 0.42, "body": Vector3(0.58, 0.28, 0.22), "head": 0.18, "head_up": 1.2},
	"wild_donkey": {"leg": 0.4, "body": Vector3(0.58, 0.28, 0.22), "head": 0.19, "head_up": 1.1},
	"aurochs": {"leg": 0.32, "body": Vector3(0.62, 0.36, 0.3), "head": 0.19, "head_up": 0.4},
	"mouflon": {"leg": 0.34, "body": Vector3(0.58, 0.3, 0.26), "head": 0.2, "head_up": 0.8},
	"bezoar": {"leg": 0.36, "body": Vector3(0.58, 0.3, 0.25), "head": 0.2, "head_up": 0.9},
	"wolf": {"leg": 0.3, "body": Vector3(0.56, 0.24, 0.2), "head": 0.21, "head_up": 0.6},
	"partridge": {"leg": 0.12, "body": Vector3(0.6, 0.48, 0.48), "head": 0.3, "head_up": 0.7},
}
const DEFAULT_SHAPE := {"leg": 0.3, "body": Vector3(0.6, 0.3, 0.25), "head": 0.2, "head_up": 0.6}
# Grandezza rispetto alla sagoma 2D, uguale per tutte le specie (2026-11-21, richiesta utente: troppo grandi, -20%). La
# sagoma 2D è vista dall'alto con orecchie e coda; nel 3D zampe e altezza la fanno sembrare più grossa.
const SIZE_3D := 0.8
# Zampe: spessore (frazione della lunghezza) e attacco sotto il busto (frazioni di larghezza e lunghezza del busto).
const LEG_THICK := 0.07
const LEG_SPREAD := Vector2(0.3, 0.32)
const LEG_SWING := 0.5
# Un passo ogni STRIDE lunghezze del corpo.
const STRIDE := 0.7
# Sotto questa strada in un fotogramma (microcelle) l'animale è fermo: zampe dritte.
const MOVING_MIN := 0.0005
const LEG_DARKEN := 0.25
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const RING_RADIUS := 0.45

enum Part { BODY, HEAD, LEG_FL, LEG_FR, LEG_BL, LEG_BR, RING }

# Un blocco di dati per pezzo, consegnato al motore una volta per fotogramma (InstanceBuffer3D).
var _buffers: Array[InstanceBuffer3D] = []
var _steps := WalkSteps3D.new()


func _init(material: Material) -> void:
	name = "Animals"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 1.0
	capsule.radial_segments = 8
	capsule.rings = 2
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var ring := TorusMesh.new()
	ring.inner_radius = RING_RADIUS - 0.03
	ring.outer_radius = RING_RADIUS
	ring.rings = 24
	ring.ring_segments = 4
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = RING_COLOR
	for part in Part.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = part != Part.RING
		match part:
			Part.BODY, Part.HEAD:
				multimesh.mesh = sphere
			Part.RING:
				multimesh.mesh = ring
			_:
				multimesh.mesh = capsule
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = ring_material if part == Part.RING else material
		if part == Part.RING:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_buffers.append(InstanceBuffer3D.new(multimesh))


func update(snapshot: AnimalsSnapshot3D) -> void:
	var count := snapshot.size()
	for buffer in _buffers:
		buffer.begin()
	for i in range(count):
		var length := snapshot.lengths[i] * SIZE_3D
		var shape: Dictionary = SHAPES.get(snapshot.species[i], DEFAULT_SHAPE)
		var id := snapshot.ids[i]
		var ground := snapshot.grounds[i]
		var moving := _steps.walked(id, ground) > MOVING_MIN
		var swing := sin(_steps.phase(id, ground, moving, STRIDE * length)) * LEG_SWING
		var facing := snapshot.facings[i]
		var forward := Vector3(facing.x, 0.0, facing.y)
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var place := snapshot.positions[i]
		var y := GroundHeight3D.land_height(ground.x, ground.y)
		var body := Transform3D(Basis.looking_at(forward, Vector3.UP).scaled(Vector3.ONE * length), Vector3(place.x, y, place.y))
		var color := snapshot.colors[i]
		var leg_color := color.darkened(LEG_DARKEN)
		var leg: float = shape["leg"]
		var size: Vector3 = shape["body"]
		var head: float = shape["head"]
		var body_y := leg + size.y * 0.5
		# Busto: ellissoide (x = larghezza, y = altezza, z = lunghezza).
		_put(Part.BODY, body * People3D._box(Vector3(0.0, body_y, 0.0), Vector3(size.z, size.y, size.x)), color)
		var head_center := Vector3(0.0, body_y + size.y * float(shape["head_up"]) * 0.5, -(size.x * 0.5 + head * 0.15))
		_put(Part.HEAD, body * People3D._box(head_center, Vector3(head * 0.8, head * 0.8, head * 1.1)), color)
		# Zampe: dall'attacco sotto il busto fino a terra; avanti-sinistra con dietro-destra, come al trotto.
		var top := leg + size.y * 0.25
		var extent := Vector3(LEG_THICK, top, LEG_THICK)
		var lx := size.z * LEG_SPREAD.x
		var lz := size.x * LEG_SPREAD.y
		_put(Part.LEG_FL, body * People3D._limb(Vector3(-lx, top, -lz), extent, swing), leg_color)
		_put(Part.LEG_FR, body * People3D._limb(Vector3(lx, top, -lz), extent, -swing), leg_color)
		_put(Part.LEG_BL, body * People3D._limb(Vector3(-lx, top, lz), extent, -swing), leg_color)
		_put(Part.LEG_BR, body * People3D._limb(Vector3(lx, top, lz), extent, swing), leg_color)
		if snapshot.selected[i] == 1:
			var ring := Transform3D(Basis.IDENTITY.scaled(Vector3(length, 1.0, length)), Vector3(place.x, y + 0.01, place.y))
			_put(Part.RING, ring, RING_COLOR)
	for buffer in _buffers:
		buffer.commit()
	_steps.end_frame()


func _put(part: int, transform: Transform3D, color: Color) -> void:
	_buffers[part].add(transform, color)
