class_name People3D
extends Node3D

# Oggetto 3D: le persone, come pupazzi semplici fatti a codice (2026-11-20, richiesta utente: per cominciare a giocare in
# 3D; più avanti modelli veri). Busto a capsula col colore del vestito, testa coi capelli, viso e naso color pelle verso
# la direzione di marcia, gambe e braccia che oscillano col passo del 2D; capelli lunghi per le donne, pancia per le
# incinte, calotta del copricapo, anello a terra per chi è selezionato. Colori, grandezza (età × sesso) e passo vengono
# dal 2D (GameStateReader.people).
# Leggero: una MultiMesh per pezzo, creata una volta sola; a ogni fotogramma si aggiornano solo le posizioni delle copie
# (niente nodi nuovi, niente forme rifatte). Il clic resta quello del gioco (la mappa 2D sotto il puntatore).

# Altezza di un adulto maschio in microcelle (stilizzata più grande del vero, come gli alberi: 1 microcella = 10 m).
# Provato 0.6 il 2026-11-20 (per farli sembrare meno di corsa): sembravano giganti; poi 0.33 (×1,1), poi di nuovo 0.3
# (richiesta utente 2026-11-21).
const HEIGHT := 0.3
# Passi lunghi (2026-11-20, richiesta utente: col ritmo fisso del 2D, visto di fianco, sembravano correre): nel 3D le
# gambe vanno con la strada fatta, un passo ogni STRIDE altezze del pupazzo, invece che a tempo. Fermi (walk_phase 0 nel
# 2D) tornano dritti. Solo l'aspetto: gli spostamenti restano quelli del gioco.
# 0.9 -> 1.0 (2026-11-21, richiesta utente: gambe ancora un po' troppo veloci, -10% di passi).
const STRIDE := 1.0
# Misure dei pezzi in frazioni dell'altezza (pupazzo alto 1, davanti verso -Z).
const TORSO := Vector3(0.32, 0.42, 0.24)
const TORSO_Y := 0.62
const FEMALE_TORSO := 0.92
const HEAD := 0.2
const HEAD_Y := 0.93
const FACE := Vector3(0.15, 0.15, 0.08)
const NOSE := 0.05
const HIP_Y := 0.42
const HIP_X := 0.07
const LEG := Vector3(0.1, 0.42, 0.1)
const SHOULDER_Y := 0.78
const SHOULDER_X := 0.19
const ARM := Vector3(0.08, 0.36, 0.08)
const LONG_HAIR := Vector3(0.21, 0.28, 0.12)
const BELLY := 0.2
const CAP := Vector3(0.22, 0.12, 0.22)
# Passo: quanto ruotano gambe e braccia (radianti al massimo della fase) e quanto salta il corpo.
const LEG_SWING := 0.55
const ARM_SWING := 0.4
const BOB := 0.025
const SKIN := HumanIndividualView.SKIN_COLOR
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const RING_RADIUS := 0.38

enum Part { TORSO, HEAD, FACE, NOSE, LEG_L, LEG_R, ARM_L, ARM_R, LONG_HAIR, BELLY, CAP, RING }

# Un blocco di dati per pezzo, consegnato al motore una volta per fotogramma (InstanceBuffer3D).
var _buffers: Array[InstanceBuffer3D] = []
# Passo di ogni persona, dalla strada fatta (in comune con gli animali).
var _steps := WalkSteps3D.new()


func _init(material: Material) -> void:
	name = "People"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 1.0
	capsule.radial_segments = 10
	capsule.rings = 3
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 5
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
			Part.TORSO, Part.LEG_L, Part.LEG_R, Part.ARM_L, Part.ARM_R:
				multimesh.mesh = capsule
			Part.RING:
				multimesh.mesh = ring
			_:
				multimesh.mesh = sphere
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = ring_material if part == Part.RING else material
		if part == Part.RING:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_buffers.append(InstanceBuffer3D.new(multimesh))


func update(snapshot: PeopleSnapshot3D) -> void:
	var count := snapshot.size()
	for buffer in _buffers:
		buffer.begin()
	for i in range(count):
		var size := HEIGHT * snapshot.sizes[i]
		var swing := sin(_steps.phase(snapshot.ids[i], snapshot.grounds[i], snapshot.walk_phases[i] != 0.0, STRIDE * size))
		var facing := snapshot.facings[i]
		var forward := Vector3(facing.x, 0.0, facing.y)
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var ground := snapshot.grounds[i]
		var place := snapshot.positions[i]
		var y := GroundHeight3D.land_height(ground.x, ground.y) + absf(swing) * BOB * size
		var body := Transform3D(Basis.looking_at(forward, Vector3.UP).scaled(Vector3.ONE * size), Vector3(place.x, y, place.y))
		var female := snapshot.females[i] == 1
		var clothes := snapshot.body_colors[i]
		var hair := snapshot.hair_colors[i]
		var torso := TORSO * (FEMALE_TORSO if female else 1.0)
		_put(Part.TORSO, body * _box(Vector3(0.0, TORSO_Y, 0.0), torso), clothes)
		_put(Part.HEAD, body * _box(Vector3(0.0, HEAD_Y, 0.0), Vector3.ONE * HEAD), hair)
		_put(Part.FACE, body * _box(Vector3(0.0, HEAD_Y - 0.01, -HEAD * 0.32), FACE), SKIN)
		_put(Part.NOSE, body * _box(Vector3(0.0, HEAD_Y - 0.01, -HEAD * 0.5), Vector3.ONE * NOSE), SKIN)
		_put(Part.LEG_L, body * _limb(Vector3(-HIP_X, HIP_Y, 0.0), LEG, swing * LEG_SWING), SKIN)
		_put(Part.LEG_R, body * _limb(Vector3(HIP_X, HIP_Y, 0.0), LEG, -swing * LEG_SWING), SKIN)
		_put(Part.ARM_L, body * _limb(Vector3(-SHOULDER_X, SHOULDER_Y, 0.0), ARM, -swing * ARM_SWING), clothes)
		_put(Part.ARM_R, body * _limb(Vector3(SHOULDER_X, SHOULDER_Y, 0.0), ARM, swing * ARM_SWING), clothes)
		if female:
			_put(Part.LONG_HAIR, body * _box(Vector3(0.0, HEAD_Y - 0.1, HEAD * 0.35), LONG_HAIR), hair)
		if snapshot.pregnant[i] == 1:
			_put(Part.BELLY, body * _box(Vector3(0.0, TORSO_Y - 0.06, -torso.z * 0.45), Vector3.ONE * BELLY), clothes)
		var cap := snapshot.cap_colors[i]
		if cap.a > 0.0:
			_put(Part.CAP, body * _box(Vector3(0.0, HEAD_Y + 0.06, HEAD * 0.08), CAP), cap)
		if snapshot.selected[i] == 1:
			var ring := Transform3D(Basis.IDENTITY.scaled(Vector3(size, 1.0, size)), Vector3(place.x, y + 0.01, place.y))
			_put(Part.RING, ring, RING_COLOR)
	_put_dead(snapshot)
	for buffer in _buffers:
		buffer.commit()
	_steps.end_frame()


# Morti a terra (2026-11-21, come DeadBodyView del 2D: la stessa figurina distesa a faccia in giù): lo stesso pupazzo
# coricato, la testa verso `dead_heads`, il davanti (-Z) contro il terreno, braccia lungo i fianchi, niente passo, niente
# viso (non si vede). Il busto sta sul punto del 2D, appoggiato al terreno.
func _put_dead(snapshot: PeopleSnapshot3D) -> void:
	for i in range(snapshot.dead_positions.size()):
		var size := HEIGHT * snapshot.dead_sizes[i]
		var head := Vector3(snapshot.dead_heads[i].x, 0.0, snapshot.dead_heads[i].y).normalized()
		var basis := Basis(head.cross(Vector3.UP), head, Vector3.UP).scaled(Vector3.ONE * size)
		var ground := snapshot.dead_grounds[i]
		var place := snapshot.dead_positions[i]
		var female := snapshot.dead_females[i] == 1
		var torso := TORSO * (FEMALE_TORSO if female else 1.0)
		var y := GroundHeight3D.land_height(ground.x, ground.y) + torso.z * 0.5 * size
		var body := Transform3D(basis, Vector3(place.x, y, place.y) - head * TORSO_Y * size)
		var clothes := snapshot.dead_body_colors[i]
		var hair := snapshot.dead_hair_colors[i]
		_put(Part.TORSO, body * _box(Vector3(0.0, TORSO_Y, 0.0), torso), clothes)
		_put(Part.HEAD, body * _box(Vector3(0.0, HEAD_Y, 0.0), Vector3.ONE * HEAD), hair)
		_put(Part.LEG_L, body * _limb(Vector3(-HIP_X, HIP_Y, 0.0), LEG, 0.0), SKIN)
		_put(Part.LEG_R, body * _limb(Vector3(HIP_X, HIP_Y, 0.0), LEG, 0.0), SKIN)
		_put(Part.ARM_L, body * _limb(Vector3(-SHOULDER_X, SHOULDER_Y, 0.0), ARM, 0.0), clothes)
		_put(Part.ARM_R, body * _limb(Vector3(SHOULDER_X, SHOULDER_Y, 0.0), ARM, 0.0), clothes)
		if female:
			_put(Part.LONG_HAIR, body * _box(Vector3(0.0, HEAD_Y - 0.1, HEAD * 0.35), LONG_HAIR), hair)
		if snapshot.dead_selected[i] == 1:
			var ring := Transform3D(Basis.IDENTITY.scaled(Vector3(size, 1.0, size) * 1.4), Vector3(place.x, y - torso.z * 0.5 * size + 0.01, place.y))
			_put(Part.RING, ring, RING_COLOR)


# Pezzo fermo: forma unitaria scalata a `extent` e messa in `center` (coordinate del pupazzo alto 1).
static func _box(center: Vector3, extent: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(extent), center)


# Gamba o braccio: appeso al suo attacco (anca o spalla), ruotato avanti/indietro di `angle` attorno all'asse dei fianchi.
static func _limb(pivot: Vector3, extent: Vector3, angle: float) -> Transform3D:
	var hang := Transform3D(Basis.IDENTITY.scaled(extent), Vector3(0.0, -extent.y * 0.5, 0.0))
	return Transform3D(Basis(Vector3.RIGHT, angle), pivot) * hang


func _put(part: int, transform: Transform3D, color: Color) -> void:
	_buffers[part].add(transform, color)
