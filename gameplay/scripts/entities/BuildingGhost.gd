class_name BuildingGhost
extends Node2D

# Anteprima visiva "fantasma" di un edificio che segue il mouse — per ora SOLO estetica, nessuna
# azione di piazzamento reale (vedi BuildBar/GameScene: nessun sistema di materiali/spazio libero/
# tech esiste ancora, vedi discussione con l'utente). Disegna una capanna TONDA dentro un recinto
# TONDO — "una o dentro una O" — vista DALL'ALTO (non più pareti+tetto di profilo, primo tentativo
# scartato il 2026-08-30 quando è arrivata la richiesta di orientare la porta: di profilo la
# rotazione non si potrebbe leggere a schermo; poi resa tonda con recinto quadrato, poi anche il
# recinto reso tondo — stessa richiesta, coerente con la discussione sul diametro realistico di
# una capanna preistorica). La porta è un vero RITAGLIO a V nel cerchio (non una toppa colorata
# sopra, vedi _hut_polygon: il poligono della capanna segue il cerchio tranne nel punto della
# porta, dove rientra fino all'apice invece di seguire l'arco). Centrato sullo stesso punto di
# ancoraggio (0,0) = il "terreno" sotto il mouse. Semitrasparente apposta per leggersi chiaramente
# come anteprima, non un edificio già piazzato.
#
# Nodo puro (Node2D + _draw(), niente MultiMesh: qui ne esiste sempre e solo UNA istanza alla
# volta, a differenza degli individui vegetali/animali dove il MultiMesh serve a evitare migliaia
# di draw call). Posizione aggiornata dal chiamante (GameScene) ogni frame mentre il piazzamento è
# attivo — questo nodo non legge da solo il mouse, resta muto sul "quando", si limita a sapere
# "come disegnarsi". `rotation_dir` invece è impostato dal chiamante solo al tasto R (vedi
# GameScene._unhandled_input), non ogni frame.

const COLOR := Color(0.55, 0.42, 0.28, 0.75)
const OUTLINE_COLOR := Color(0.3, 0.22, 0.12, 0.85)
const FENCE_COLOR := Color(0.45, 0.35, 0.2, 0.75)

# Palette alternativa quando is_buildable è false (terreno non edificabile — vedi GameScene.
# _is_position_buildable) — stessa forma, solo tinta rossa al posto del marrone, stessa alpha di
# semitrasparenza della controparte sopra.
const INVALID_COLOR := Color(0.75, 0.15, 0.15, 0.75)
const INVALID_OUTLINE_COLOR := Color(0.4, 0.05, 0.05, 0.85)
const INVALID_FENCE_COLOR := Color(0.65, 0.15, 0.15, 0.75)

const HUT_RADIUS: float = 2.5
const OUTLINE_WIDTH: float = 0.6
const FENCE_RADIUS: float = 4.0
const FENCE_WIDTH: float = 0.4
const GATE_LENGTH: float = 1.5
const DOOR_NOTCH_HALF_WIDTH: float = 1.0
const DOOR_NOTCH_DEPTH: float = 1.3
const CIRCLE_SEGMENTS: int = 24

# Aggiornato da GameScene ogni frame insieme alla posizione (vedi _is_position_buildable) — questo
# nodo resta comunque muto sul PERCHÉ (acqua/fiume/pietra/fuori mappa), sa solo "disegnami di
# rosso oppure no". Setter con guard+queue_redraw: senza, ridisegnerebbe ad ogni frame anche
# quando il valore non cambia (il chiamante lo scrive ogni frame, non solo ai cambi di stato).
var is_buildable: bool = true:
	set(value):
		if is_buildable == value:
			return
		is_buildable = value
		queue_redraw()

# Orientamento corrente della porta — SOUTH di default (verso il basso/il player), cambiato solo
# dal tasto R (GameScene._unhandled_input chiama rotate_clockwise), mai ogni frame come position.
# Il valore al momento del piazzamento diventa Building.rotation (vedi GameScene._place_building_at).
var rotation_dir: GameTypes.Direction = GameTypes.Direction.SOUTH:
	set(value):
		if rotation_dir == value:
			return
		rotation_dir = value
		queue_redraw()


func rotate_clockwise() -> void:
	rotation_dir = (rotation_dir + 1) % 4


func _draw() -> void:
	var color := COLOR if is_buildable else INVALID_COLOR
	var outline_color := OUTLINE_COLOR if is_buildable else INVALID_OUTLINE_COLOR
	var fence_color := FENCE_COLOR if is_buildable else INVALID_FENCE_COLOR

	_draw_fence(fence_color, rotation_dir)
	var hut_points := _hut_polygon(rotation_dir)
	draw_colored_polygon(hut_points, color)
	# Riempie il ritaglio della porta col colore del bordo (vedi commento in
	# MicroCellRenderer._draw_buildings) invece di lasciarlo trasparente sul terreno sotto.
	draw_colored_polygon(
		PackedVector2Array([hut_points[0], hut_points[hut_points.size() - 1], hut_points[hut_points.size() - 2]]),
		outline_color
	)
	var outline_points := hut_points.duplicate()
	outline_points.append(hut_points[0])
	draw_polyline(outline_points, outline_color, OUTLINE_WIDTH)


# Recinto: linea circolare CONTINUA con una vera apertura in corrispondenza della porta (stesso
# spicchio mancante di _hut_polygon) più una linea corta verso l'esterno sull'imbocco a simulare
# il cancello aperto — niente tratteggio (richiesta utente, 2026-08-30: leggeva come sfumature
# indistinte vicino alla capanna, non come un recinto). Stessa funzione (duplicata apposta, vedi
# commento in testa al file) di MicroCellRenderer._draw_building_fence.
func _draw_fence(color: Color, direction: GameTypes.Direction) -> void:
	var dir_vector := _direction_vector(direction)
	var gate_center_angle: float = dir_vector.angle()
	var gate_half_angle: float = DOOR_NOTCH_HALF_WIDTH / FENCE_RADIUS
	var start_angle: float = gate_center_angle + gate_half_angle
	var end_angle: float = gate_center_angle - gate_half_angle + TAU
	draw_arc(Vector2.ZERO, FENCE_RADIUS, start_angle, end_angle, CIRCLE_SEGMENTS, color, FENCE_WIDTH, true)

	var hinge_dir := Vector2(cos(start_angle), sin(start_angle))
	var hinge: Vector2 = hinge_dir * FENCE_RADIUS
	draw_line(hinge, hinge + hinge_dir * GATE_LENGTH, color, FENCE_WIDTH)


# Poligono della capanna: segue il cerchio di raggio HUT_RADIUS per quasi tutto il giro, tranne
# nello spicchio della porta (centrato sull'angolo di `direction`), dove rientra fino a un apice
# più vicino al centro (DOOR_NOTCH_DEPTH) — un vero ritaglio, non una toppa colorata sopra. Stessa
# funzione (duplicata apposta, vedi commento in testa al file) di
# MicroCellRenderer._building_hut_polygon, così l'anteprima e l'edificio finito mostrano la porta
# esattamente nello stesso punto una volta piazzato.
func _hut_polygon(direction: GameTypes.Direction) -> PackedVector2Array:
	var dir_vector := _direction_vector(direction)
	var door_center_angle: float = dir_vector.angle()
	var half_angle: float = DOOR_NOTCH_HALF_WIDTH / HUT_RADIUS
	var start_angle: float = door_center_angle + half_angle
	var sweep: float = TAU - half_angle * 2.0
	var points := PackedVector2Array()
	for i in range(CIRCLE_SEGMENTS + 1):
		var t: float = float(i) / float(CIRCLE_SEGMENTS)
		var angle: float = start_angle + sweep * t
		points.append(Vector2(cos(angle), sin(angle)) * HUT_RADIUS)
	points.append(dir_vector * (HUT_RADIUS - DOOR_NOTCH_DEPTH))
	return points


func _direction_vector(direction: GameTypes.Direction) -> Vector2:
	match direction:
		GameTypes.Direction.NORTH:
			return Vector2(0, -1)
		GameTypes.Direction.EAST:
			return Vector2(1, 0)
		GameTypes.Direction.WEST:
			return Vector2(-1, 0)
		_: # SOUTH, anche default
			return Vector2(0, 1)
