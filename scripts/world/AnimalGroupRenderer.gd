class_name AnimalGroupRenderer
extends Node2D

# Nodo generico e riusabile: un'istanza per specie animale. Non contiene alcuna logica
# specifica di una specie — tutti i parametri arrivano via configure(), chiamato una volta dal
# nodo che lo istanzia (oggi solo MacroCellScene per "rabbit"). Disegna i gruppi tramite un
# singolo MultiMeshInstance2D (corpo ovale + orecchie unite in un'unica mesh, vedi
# _build_body_and_ears_mesh) che si aggiorna e ridisegna da solo ogni frame quando cambiano le
# trasformazioni istanza — a differenza di MicroCellRenderer, qui NON si usa _draw()/
# queue_redraw(): un redraw manuale a ogni frame rifarebbe inutilmente anche i buffer statici
# (erba, pietre, alberi) di tutta la cella.
const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer
const BODY_SEGMENTS: int = 16
# Il corpo non è un'ellisse simmetrica: il raggio Y viene scalato da un fattore che assottiglia
# il muso (+X, direzione di marcia) e allarga i fianchi (-X, posteriore) — vedi
# _build_body_and_ears_mesh — per leggersi come un coniglio affusolato invece di un maialino.
const BODY_FRONT_WIDTH_RATIO: float = 0.55
const BODY_REAR_WIDTH_RATIO: float = 1.25
# Ancorate vicino al muso (+X, direzione di marcia): puntando in avanti-e-leggermente-fuori,
# le orecchie si estendono oltre la punta del muso in spazio libero (nessuna sagoma del corpo
# lì), quindi restano nettamente visibili senza bisogno di un ancoraggio laterale estremo —
# a differenza dei tentativi all'indietro (135°/150°/160° dall'asse di marcia), che finivano
# per leggersi come alette/ali ai lati o restare sepolti nel fianco largo del corpo.
const EAR_ANCHOR_RATIO: float = 0.75 # frazione di body_length a cui ancorare le orecchie
const EAR_ANCHOR_LATERAL_RATIO: float = 0.3 # frazione di body_width per lo scarto laterale: vicine tra loro, non allargate
# Angolo dall'asse di marcia locale +X, mirrorato ±side: piccolo (10°, era 20°: più dritte,
# meno divaricate — a 20° con orecchie sottili si leggevano come antenne) così le due orecchie
# restano quasi parallele all'asse di marcia invece di aprirsi a V.
const EAR_ANGLE_FROM_HEADING: float = 10.0 * PI / 180.0
# Coda: piccolo cerchio sul retro (-X), stesso colore uniforme del resto (vedi color in configure).
const TAIL_RADIUS: float = 0.85
const TAIL_ANCHOR_RATIO: float = 0.9 # frazione di body_length: leggermente arretrata rispetto alla punta posteriore, così risulta "attaccata"
const TAIL_SEGMENTS: int = 8

# Popolazione -> numero di gruppi disegnati: individui rappresentati da ciascuna icona,
# arriva da AnimalRules.visual_group_size (letto dal chiamante, mai hardcoded qui).
var individuals_per_group: int = 1
var move_speed: float = 0.0 # microcelle/secondo
var turn_rate: float = 0.0 # radianti/secondo massimi di deriva casuale della direzione

# Cluster: stessa popolazione -> quanti gruppi disegnare, arriva da AnimalRules.max_individuals_per_cluster
# (letto dal chiamante, mai hardcoded qui). Un cluster è un punto che vaga con la STESSA logica
# di un gruppo (deriva + rimbalzo, vedi _clusters sotto) ma non viene disegnato: serve solo da
# centro verso cui i gruppi che gli appartengono vengono debolmente attratti (vedi
# _apply_cluster_attraction), niente vero flocking (no separazione/allineamento tra gruppi, no
# attrazione tra cluster diversi).
var max_individuals_per_cluster: int = 1
var cluster_comfort_radius: float = 5.0 # microcelle: entro questo raggio dal centro-cluster nessuna trazione
var cluster_attraction_strength: float = 1.5 # quanto forte la trazione oltre il raggio comfort

# Movimento a balzi dei gruppi (vedi AnimalVisualGroup.MacroPhase/MicroPhase e _update_group_phase),
# arrivano da AnimalRules (letti dal chiamante, mai hardcoded qui). move_speed sopra resta usato
# solo per il vagare continuo dei centri-cluster invisibili.
var hop_speed: float = 0.0
var movement_phase_duration_min: float = 2.0
var movement_phase_duration_max: float = 5.0
var rest_phase_duration_min: float = 3.0
var rest_phase_duration_max: float = 7.0
var hop_duration_min: float = 0.2
var hop_duration_max: float = 0.4
var hop_pause_min: float = 0.1
var hop_pause_max: float = 0.3

# Se assegnato (vedi MacroCellScene._ready), i gruppi si muovono solo quando clock.is_playing
# è true — stesso orologio che governa l'avanzamento giorno/anno, così i conigli si fermano
# in pausa e durante le finestre di dialogo bloccanti (che già mettono in pausa il clock, vedi
# _on_blocking_dialog_visibility_changed). Se null (nessun clock assegnato), il movimento resta
# sempre attivo — comportamento invariato per contesti che non hanno un GameClockController.
var clock: GameClockController = null

var _groups: Array = [] # Array[AnimalVisualGroup]
var _clusters: Array = [] # Array[AnimalVisualGroup], riusata come "centro mobile", mai disegnata
var _multimesh: MultiMesh
var _multimesh_instance: MultiMeshInstance2D
var _configured: bool = false


func configure(params: Dictionary) -> void:
	individuals_per_group = max(int(params.get("individuals_per_group", 1)), 1)
	move_speed = float(params.get("move_speed", 3.0))
	turn_rate = float(params.get("turn_rate", 1.5))
	max_individuals_per_cluster = max(int(params.get("max_individuals_per_cluster", 1)), 1)
	cluster_comfort_radius = float(params.get("cluster_comfort_radius", 5.0))
	cluster_attraction_strength = float(params.get("cluster_attraction_strength", 1.5))
	hop_speed = float(params.get("hop_speed", 6.0))
	movement_phase_duration_min = float(params.get("movement_phase_duration_min", 2.0))
	movement_phase_duration_max = float(params.get("movement_phase_duration_max", 5.0))
	rest_phase_duration_min = float(params.get("rest_phase_duration_min", 3.0))
	rest_phase_duration_max = float(params.get("rest_phase_duration_max", 7.0))
	hop_duration_min = float(params.get("hop_duration_min", 0.2))
	hop_duration_max = float(params.get("hop_duration_max", 0.4))
	hop_pause_min = float(params.get("hop_pause_min", 0.1))
	hop_pause_max = float(params.get("hop_pause_max", 0.3))

	var body_length: float = float(params.get("body_length", 3.0))
	var body_width: float = float(params.get("body_width", 1.3))
	var ear_length: float = float(params.get("ear_length", 2.7))
	var ear_width: float = float(params.get("ear_width", 0.5))
	var color: Color = params.get("color", Color(0.93, 0.91, 0.87, 0.95))

	var mesh := _build_body_and_ears_mesh(body_length, body_width, ear_length, ear_width, color)

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = mesh
	_multimesh.instance_count = 0

	_multimesh_instance = MultiMeshInstance2D.new()
	_multimesh_instance.multimesh = _multimesh
	add_child(_multimesh_instance)

	_configured = true


# Puro toggle di visibilità: il movimento resta governato solo da clock.is_playing (play/pausa
# del tempo), nessun concetto separato di "freeze" — se il giocatore vuole fermarli mette in
# pausa il gioco, questo bottone serve solo a non vederli (es. mentre costruisce).
func set_animals_visible(v: bool) -> void:
	if _multimesh_instance != null:
		_multimesh_instance.visible = v


# Ricalcola quanti gruppi disegnare da una popolazione totale (arrotondato), aggiungendo
# nuovi gruppi in posizione/direzione casuale o rimuovendo quelli in eccesso dalla fine
# dell'array — i gruppi già esistenti non vengono mai spostati da questa chiamata.
func set_population(total_population: int) -> void:
	if not _configured:
		return

	var target_groups: int = int(round(float(max(total_population, 0)) / individuals_per_group))

	while _groups.size() < target_groups:
		_groups.append(_make_random_group())
	while _groups.size() > target_groups:
		_groups.pop_back()

	_multimesh.instance_count = _groups.size()
	_resync_clusters(total_population)

	for i in range(_groups.size()):
		_write_instance_transform(i, _groups[i])


# Ricalcola quanti cluster servono (formula: ceil(popolazione/max_individuals_per_cluster),
# mai più dei gruppi disponibili) e riassegna cluster_index a ogni gruppo, riempiendo i cluster
# in sequenza (i primi groups_per_cluster_cap gruppi al cluster 0, i successivi al cluster 1,
# ecc. — l'ultimo cluster assorbe l'eventuale resto). Chiamata da set_population ogni volta che
# la popolazione cambia: riassegnare tutti i cluster_index da zero è economico (poche decine di
# gruppi al più) e non causa scatti visivi, perché la posizione del gruppo non cambia — solo il
# centro verso cui viene debolmente attratto, e l'attrazione stessa è già graduale (vedi
# _apply_cluster_attraction).
func _resync_clusters(total_population: int) -> void:
	if _groups.is_empty():
		_clusters.clear()
		return

	var num_clusters: int = int(ceil(float(max(total_population, 0)) / max_individuals_per_cluster))
	num_clusters = clamp(num_clusters, 1, _groups.size())

	while _clusters.size() < num_clusters:
		_clusters.append(_make_random_group())
	while _clusters.size() > num_clusters:
		_clusters.pop_back()

	var groups_per_cluster_cap: int = max(1, int(floor(float(max_individuals_per_cluster) / individuals_per_group)))
	for i in range(_groups.size()):
		_groups[i].cluster_index = min(i / groups_per_cluster_cap, num_clusters - 1)


func _make_random_group() -> AnimalVisualGroup:
	var position := Vector2(randf_range(0.0, World.WIDTH), randf_range(0.0, World.HEIGHT))
	var direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	var group := AnimalVisualGroup.new(position, direction)
	_randomize_group_phase(group)
	return group


# Stato/timer iniziale scelto a caso (non "tutti freschi in MOVING") così un gruppo appena
# creato — sia all'apertura della scena, sia aggiunto a metà sessione da una popolazione che
# cresce — non risulta sincronizzato con quelli già esistenti. Irrilevante per i centri-cluster
# (che ignorano questi campi), ma innocuo lasciarlo girare anche per loro.
func _randomize_group_phase(group: AnimalVisualGroup) -> void:
	if randf() < 0.5:
		group.macro_phase = AnimalVisualGroup.MacroPhase.MOVING
		group.macro_phase_timer = randf_range(movement_phase_duration_min, movement_phase_duration_max)
		if randf() < 0.5:
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
			group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)
		else:
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOP_PAUSE
			group.micro_phase_timer = randf_range(hop_pause_min, hop_pause_max)
	else:
		group.macro_phase = AnimalVisualGroup.MacroPhase.RESTING
		group.macro_phase_timer = randf_range(rest_phase_duration_min, rest_phase_duration_max)


# Avanza la macchina a stati a due livelli di un gruppo di un frame. Chiamata sempre (anche
# quando il gruppo non si muove), così i timer procedono indipendentemente dal fatto che questo
# frame produca o meno uno spostamento — vedi _process per la regola che decide il movimento.
func _update_group_phase(group: AnimalVisualGroup, delta: float) -> void:
	group.macro_phase_timer -= delta
	if group.macro_phase == AnimalVisualGroup.MacroPhase.MOVING:
		group.micro_phase_timer -= delta
		if group.micro_phase_timer <= 0.0:
			if group.micro_phase == AnimalVisualGroup.MicroPhase.HOPPING:
				group.micro_phase = AnimalVisualGroup.MicroPhase.HOP_PAUSE
				group.micro_phase_timer = randf_range(hop_pause_min, hop_pause_max)
			else:
				group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
				group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)
		if group.macro_phase_timer <= 0.0:
			group.macro_phase = AnimalVisualGroup.MacroPhase.RESTING
			group.macro_phase_timer = randf_range(rest_phase_duration_min, rest_phase_duration_max)
	else:
		if group.macro_phase_timer <= 0.0:
			group.macro_phase = AnimalVisualGroup.MacroPhase.MOVING
			group.macro_phase_timer = randf_range(movement_phase_duration_min, movement_phase_duration_max)
			group.micro_phase = AnimalVisualGroup.MicroPhase.HOPPING
			group.micro_phase_timer = randf_range(hop_duration_min, hop_duration_max)


# Livello 1: movimento casuale semplice, non un vero sistema di IA. I cluster (centri invisibili)
# vagano in modo continuo (deriva + rimbalzo, come sempre); i gruppi disegnati invece si
# muovono a balzi (vedi _update_group_phase) — deriva della direzione e attrazione verso il
# cluster restano sempre attive anche da fermi, solo l'avanzamento è gated dalla fase HOPPING.
func _process(delta: float) -> void:
	if not _configured or _groups.is_empty():
		return
	if clock != null and not clock.is_playing:
		return

	# I cluster avanzano per primi (stessa logica di sempre) così i gruppi, elaborati subito
	# dopo, tirano verso il centro già aggiornato di questo frame invece che verso quello vecchio.
	for cluster in _clusters:
		cluster.direction = cluster.direction.rotated(randf_range(-turn_rate, turn_rate) * delta)
		cluster.position += cluster.direction * move_speed * delta
		_bounce_at_bounds(cluster)

	for i in range(_groups.size()):
		var group: AnimalVisualGroup = _groups[i]
		group.direction = group.direction.rotated(randf_range(-turn_rate, turn_rate) * delta)
		_apply_cluster_attraction(group, delta)
		_update_group_phase(group, delta)
		if group.macro_phase == AnimalVisualGroup.MacroPhase.MOVING and group.micro_phase == AnimalVisualGroup.MicroPhase.HOPPING:
			group.position += group.direction * hop_speed * delta
			_bounce_at_bounds(group)
		_write_instance_transform(i, group)


# Guinzaglio elastico verso il centro del proprio cluster: nessuna trazione entro
# cluster_comfort_radius (i gruppi possono vagare liberamente vicino al centro), oltre quella
# soglia la direzione viene reindirizzata gradualmente (slerp, pesato dallo sforamento) verso il
# centro — non un vero steering behavior, solo un bias sulla stessa deriva casuale di sempre.
func _apply_cluster_attraction(group: AnimalVisualGroup, delta: float) -> void:
	if _clusters.is_empty():
		return
	var cluster: AnimalVisualGroup = _clusters[group.cluster_index]
	var offset: Vector2 = group.position - cluster.position
	var distance: float = offset.length()
	if distance <= cluster_comfort_radius:
		return
	var pull_direction: Vector2 = -offset / distance
	var pull_strength: float = clamp((distance - cluster_comfort_radius) / cluster_comfort_radius, 0.0, 1.0)
	var pull_weight: float = clamp(pull_strength * cluster_attraction_strength * delta, 0.0, 1.0)
	group.direction = group.direction.slerp(pull_direction, pull_weight)


func _bounce_at_bounds(group: AnimalVisualGroup) -> void:
	if group.position.x < 0.0:
		group.position.x = 0.0
		group.direction.x = abs(group.direction.x)
	elif group.position.x > World.WIDTH:
		group.position.x = World.WIDTH
		group.direction.x = -abs(group.direction.x)

	if group.position.y < 0.0:
		group.position.y = 0.0
		group.direction.y = abs(group.direction.y)
	elif group.position.y > World.HEIGHT:
		group.position.y = World.HEIGHT
		group.direction.y = -abs(group.direction.y)


func _write_instance_transform(index: int, group: AnimalVisualGroup) -> void:
	var transform := Transform2D(group.direction.angle(), group.position * CELL_SIZE)
	_multimesh.set_instance_transform_2d(index, transform)


# Corpo a goccia (ventaglio con raggio Y assottigliato verso il muso e allargato verso i
# fianchi) + due orecchie lunghe protese in avanti oltre il muso + coda (piccolo cerchio)
# accumulati in un'unica sessione SurfaceTool con un UNICO colore uniforme, cosicché ogni
# specie resti un solo MultiMesh/una sola draw call indipendentemente dal numero di gruppi.
# Asse locale +X = direzione di marcia (stessa convenzione di FISH in MicroCellRenderer).
static func _build_body_and_ears_mesh(
	body_length: float, body_width: float, ear_length: float, ear_width: float, color: Color
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)

	var body_points := PackedVector2Array()
	for i in range(BODY_SEGMENTS):
		var angle: float = (float(i) / float(BODY_SEGMENTS)) * TAU
		# t: 0 sul punto più posteriore (-X), 1 sul punto più anteriore/muso (+X) — modula il
		# raggio Y così il corpo si legge come una goccia affusolata invece di un'ellisse.
		var t: float = (cos(angle) + 1.0) / 2.0
		var width_scale: float = lerp(BODY_REAR_WIDTH_RATIO, BODY_FRONT_WIDTH_RATIO, t)
		body_points.append(Vector2(cos(angle) * body_length, sin(angle) * body_width * width_scale))
	_append_fan_triangles(st, body_points)

	var anchor_x: float = body_length * EAR_ANCHOR_RATIO
	for side in [-1.0, 1.0]:
		var ear_dir: Vector2 = Vector2.RIGHT.rotated(side * EAR_ANGLE_FROM_HEADING)
		var anchor := Vector2(anchor_x, side * body_width * EAR_ANCHOR_LATERAL_RATIO)
		var perpendicular := ear_dir.rotated(PI / 2.0)
		var base_a := anchor - perpendicular * (ear_width / 2.0)
		var base_b := anchor + perpendicular * (ear_width / 2.0)
		var tip := anchor + ear_dir * ear_length
		_append_triangle(st, base_a, base_b, tip)

	var tail_center := Vector2(-body_length * TAIL_ANCHOR_RATIO, 0.0)
	var tail_points := PackedVector2Array()
	for i in range(TAIL_SEGMENTS):
		var angle: float = (float(i) / float(TAIL_SEGMENTS)) * TAU
		tail_points.append(tail_center + Vector2(cos(angle), sin(angle)) * TAIL_RADIUS)
	_append_fan_triangles(st, tail_points, tail_center)

	return st.commit()


static func _append_fan_triangles(st: SurfaceTool, points: PackedVector2Array, center: Vector2 = Vector2.ZERO) -> void:
	var center_v3 := Vector3(center.x, center.y, 0.0)
	var count := points.size()
	for i in range(count):
		var a := Vector3(points[i].x, points[i].y, 0.0)
		var b := Vector3(points[(i + 1) % count].x, points[(i + 1) % count].y, 0.0)
		st.add_vertex(center_v3)
		st.add_vertex(a)
		st.add_vertex(b)


static func _append_triangle(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	st.add_vertex(Vector3(a.x, a.y, 0.0))
	st.add_vertex(Vector3(b.x, b.y, 0.0))
	st.add_vertex(Vector3(c.x, c.y, 0.0))
