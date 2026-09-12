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
#
# Secondo tipo, Pebble Circle (2026-09-07, richiesta utente) — building_type_name (sotto) dice quale
# sagoma disegnare: "hut" (default, comportamento invariato) resta la capanna descritta sopra,
# "pebble_circle" disegna invece un anello di massi grezzi senza porta/rotazione (vedi
# _draw_pebble_circle). Stesso nodo/stesso ciclo di vita per entrambi, nessun sottotipo di classe.

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

# Pebble Circle — stessa palette/geometria di MicroCellRenderer._draw_pebble_circle (duplicata
# apposta, stesso principio già in uso per la capanna), qui però anche con la variante rossa "non
# edificabile" (PEBBLE_CIRCLE_INVALID_COLOR), che l'edificio già piazzato non ha bisogno di avere.
# RIVISTA (2026-09-07, richiesta utente: "le pietre sono tutte uguali e sembrano sfocate") — non
# più cerchi perfetti ma poligoni irregolari (vedi _draw_pebble_circle/_pebble_blob_polygon sotto),
# stessa identica logica di MicroCellRenderer (duplicata, non condivisa: vedi commento in testa al
# file) così l'anteprima e l'edificio finito mostrano esattamente la stessa sagoma per sassolino.
# RITARATA 2026-09-12 (rename Stone Circle -> Pebble Circle, richiesta utente — sassolini più
# piccoli e più numerosi) — STESSI valori di MicroCellRenderer, mai lasciati disallineare.
const PEBBLE_CIRCLE_COLOR := Color(0.60, 0.58, 0.54, 0.75)
const PEBBLE_CIRCLE_OUTLINE_COLOR := Color(0.24, 0.22, 0.19, 0.85)
const PEBBLE_CIRCLE_INVALID_COLOR := Color(0.75, 0.15, 0.15, 0.75)
const PEBBLE_CIRCLE_INVALID_OUTLINE_COLOR := Color(0.4, 0.05, 0.05, 0.85)
const PEBBLE_CIRCLE_OUTLINE_WIDTH: float = 0.5
const PEBBLE_CIRCLE_RING_RADIUS: float = 4.0
const PEBBLE_CIRCLE_PEBBLE_RADIUS: float = 0.45
const PEBBLE_CIRCLE_PEBBLE_COUNT: int = 14
const PEBBLE_CIRCLE_BLOB_VERTEX_COUNT: int = 8

# Deposit Site (2026-09-08, richiesta utente) — "sito di deposito", a disegno una chiazza di terra
# battuta SQUADRATA (2026-09-08, revisione richiesta utente: "molto più squadrato", non un quadrato
# perfetto però): nessuna porta/recinto/rotazione (has_door=false, come lo Pebble Circle). Un solo
# poligono a raggio-per-vertice in "norma del massimo" (vedi _deposit_site_polygon: r(angolo) =
# metà-lato / max(|cos|,|sin|), che traccia esattamente un quadrato quando il jitter è 1) più un
# lieve jitter per vertice — stesso principio "blob" già in uso per i sassolini dello Pebble Circle, ma
# qui la funzione radiale di base è quadrata invece che circolare. Seed fisso: a differenza dello
# Pebble Circle questo tipo non è unico, ma la forma identica tra istanze è lo stesso comportamento
# già accettato per la capanna, sempre identica a se stessa.
const DEPOSIT_SITE_COLOR := Color(0.42, 0.34, 0.24, 0.75)
const DEPOSIT_SITE_OUTLINE_COLOR := Color(0.24, 0.18, 0.12, 0.85)
const DEPOSIT_SITE_INVALID_COLOR := Color(0.75, 0.15, 0.15, 0.75)
const DEPOSIT_SITE_INVALID_OUTLINE_COLOR := Color(0.4, 0.05, 0.05, 0.85)
const DEPOSIT_SITE_OUTLINE_WIDTH: float = 0.5
# 4.5 (2026-09-08, richiesta utente: "allarga ancora di più, quasi ad occupare tutta la microcella")
# — la microcella è larga CELL_SIZE=10 (MicroCellRenderer), quindi mezza cella = 5: 4.5 lascia un
# margine minimo prima del bordo anche col jitter massimo (vedi _deposit_site_polygon, fino a ×1.08).
const DEPOSIT_SITE_HALF_SIDE: float = 4.5
const DEPOSIT_SITE_VERTEX_COUNT: int = 8

# Stick Tent (2026-09-12, richiesta utente — collegamento UI/rendering: il .tres/BuildingRules
# esistevano già da un giro precedente, ma non era ancora disegnabile né come ghost né come
# edificio piazzato) — placeholder semplice: cerchio pieno color paglia/marrone chiaro, PIÙ PICCOLO
# del corpo della capanna (HUT_RADIUS=2.5, qui 2.0), SENZA recinto (nessun recinto in stick_tent.
# tres) — "distinguibile da Hut, coerente con tier inferiore" (richiesta utente): forma più
# semplice/più piccola, nessun dettaglio (recinto, ritaglio porta vero) che la capanna invece ha.
# has_door RESTA vero (default di BuildingRules, mai impostato a false in stick_tent.tres — a
# differenza di pebble_circle/deposit_site, che lo mettono esplicitamente a false): la rotazione
# (tasto R) è quindi significativa anche per questo tipo. BUGFIX (2026-09-12, richiesta utente —
# "has_door è vero ma non si vede la porta"): PRIMA di questo passo il ramo stick_tent ignorava del
# tutto `rotation_dir`, disegnando sempre lo stesso cerchio simmetrico indipendentemente
# dall'orientamento — corretto sotto con un piccolo TRIANGOLO (non un vero ritaglio come la
# capanna, coerente con la semplicità del resto della forma) sul bordo del cerchio, nel verso della
# porta.
const STICK_TENT_COLOR := Color(0.78, 0.62, 0.32, 0.75)
const STICK_TENT_OUTLINE_COLOR := Color(0.45, 0.32, 0.15, 0.85)
const STICK_TENT_INVALID_COLOR := Color(0.75, 0.15, 0.15, 0.75)
const STICK_TENT_INVALID_OUTLINE_COLOR := Color(0.4, 0.05, 0.05, 0.85)
const STICK_TENT_OUTLINE_WIDTH: float = 0.4
const STICK_TENT_RADIUS: float = 2.0
# Triangolino "porta" (2026-09-12) — base sul bordo del cerchio, apice verso l'esterno nel verso di
# `direction`, colore scuro (STICK_TENT_DOOR_MARKER_COLOR, non semitrasparente come il corpo del
# cerchio: deve restare ben leggibile anche sopra il ramo "non edificabile" rosso).
const STICK_TENT_DOOR_MARKER_COLOR := Color(0.25, 0.15, 0.06, 1.0)
const STICK_TENT_DOOR_MARKER_HALF_WIDTH: float = 0.7
const STICK_TENT_DOOR_MARKER_HEIGHT: float = 1.1

# Quale sagoma disegnare — valorizzato da GameScene._on_build_submenu_action_pressed subito dopo
# la creazione (2026-09-07, richiesta utente, Pebble Circle): prima di questo passo l'unico tipo
# esistente (hut) rendeva superfluo dirlo esplicitamente a questo nodo. Default "hut" per lo stesso
# motivo (comportamento invariato se mai lasciato non impostato).
var building_type_name: String = "hut"

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
	# Smistamento per tipo (2026-09-07, richiesta utente, Pebble Circle) — nessuna porta/rotazione
	# da mostrare per questo tipo (has_door=false), quindi un ramo completamente separato invece di
	# infilare un altro if dentro la geometria della capanna sotto.
	if building_type_name == "pebble_circle":
		_draw_pebble_circle(PEBBLE_CIRCLE_COLOR if is_buildable else PEBBLE_CIRCLE_INVALID_COLOR,
			PEBBLE_CIRCLE_OUTLINE_COLOR if is_buildable else PEBBLE_CIRCLE_INVALID_OUTLINE_COLOR)
		return
	if building_type_name == "deposit_site":
		_draw_deposit_site(DEPOSIT_SITE_COLOR if is_buildable else DEPOSIT_SITE_INVALID_COLOR,
			DEPOSIT_SITE_OUTLINE_COLOR if is_buildable else DEPOSIT_SITE_INVALID_OUTLINE_COLOR)
		return
	if building_type_name == "stick_tent":
		_draw_stick_tent(STICK_TENT_COLOR if is_buildable else STICK_TENT_INVALID_COLOR,
			STICK_TENT_OUTLINE_COLOR if is_buildable else STICK_TENT_INVALID_OUTLINE_COLOR, rotation_dir)
		return

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


# Anello di sassolini attorno al punto di ancoraggio (0,0) — nessuna porta/rotazione da
# rispettare (has_door=false per questo tipo). Stessa funzione (duplicata apposta, stesso principio
# già in uso per la capanna) di MicroCellRenderer._draw_pebble_circle, così l'anteprima e l'edificio
# finito coincidono esattamente.
func _draw_pebble_circle(color: Color, outline_color: Color) -> void:
	for i in range(PEBBLE_CIRCLE_PEBBLE_COUNT):
		var angle: float = TAU * float(i) / float(PEBBLE_CIRCLE_PEBBLE_COUNT)
		var pebble_center := Vector2(cos(angle), sin(angle)) * PEBBLE_CIRCLE_RING_RADIUS
		var blob := _pebble_blob_polygon(pebble_center, i)
		draw_colored_polygon(blob, color)
		var outline := blob.duplicate()
		outline.append(blob[0])
		draw_polyline(outline, outline_color, PEBBLE_CIRCLE_OUTLINE_WIDTH)


# Stessa identica logica (duplicata apposta) di MicroCellRenderer._pebble_blob_polygon — vedi lì per
# il perché del seed deterministico per indice invece che per posizione/randf() globale.
func _pebble_blob_polygon(center: Vector2, seed_index: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_index
	var pebble_radius: float = PEBBLE_CIRCLE_PEBBLE_RADIUS * rng.randf_range(0.8, 1.2)
	var points := PackedVector2Array()
	for v in range(PEBBLE_CIRCLE_BLOB_VERTEX_COUNT):
		var vertex_angle: float = TAU * float(v) / float(PEBBLE_CIRCLE_BLOB_VERTEX_COUNT)
		var vertex_radius: float = pebble_radius * rng.randf_range(0.75, 1.15)
		points.append(center + Vector2(cos(vertex_angle), sin(vertex_angle)) * vertex_radius)
	return points


# Chiazza di terra battuta attorno al punto di ancoraggio (0,0) — nessuna porta/rotazione da
# rispettare (has_door=false per questo tipo). Stessa funzione (duplicata apposta, vedi commento in
# testa al file) di MicroCellRenderer._draw_deposit_site, così l'anteprima e l'edificio finito
# coincidono esattamente.
func _draw_deposit_site(color: Color, outline_color: Color) -> void:
	var blob := _deposit_site_polygon()
	draw_colored_polygon(blob, color)
	var outline := blob.duplicate()
	outline.append(blob[0])
	draw_polyline(outline, outline_color, DEPOSIT_SITE_OUTLINE_WIDTH)


# Poligono a DEPOSIT_SITE_VERTEX_COUNT lati (8, allineati a incrementi di 45°) con raggio-per-
# vertice in "norma del massimo" invece che circolare — max(|cos|,|sin|) vale 1 ai 4 angoli
# 0/90/180/270° (punti medi dei lati) e cos(45°)≈0.707 ai 4 angoli 45/135/225/315° (angoli veri),
# quindi r(angolo) = DEPOSIT_SITE_HALF_SIDE / max(|cos|,|sin|) traccia ESATTAMENTE un quadrato di
# semilato DEPOSIT_SITE_HALF_SIDE quando il jitter è 1 (i punti medi cadono esattamente sui lati
# retti, nessun vertice extra visibile). Il jitter per-vertice (indipendente su angolo E raggio)
# rompe quella perfezione quel tanto che basta perché non sembri una piastrella geometrica — "non
# proprio un quadrato perfetto" (richiesta utente). Seed fisso (0): un solo poligono per istanza,
# nessun bisogno di variarlo (stesso comportamento già accettato per la sagoma della capanna,
# identica ad ogni piazzamento).
func _deposit_site_polygon() -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var points := PackedVector2Array()
	for v in range(DEPOSIT_SITE_VERTEX_COUNT):
		var base_angle: float = TAU * float(v) / float(DEPOSIT_SITE_VERTEX_COUNT)
		var jittered_angle: float = base_angle + rng.randf_range(-0.05, 0.05)
		var square_radius: float = DEPOSIT_SITE_HALF_SIDE / maxf(absf(cos(base_angle)), absf(sin(base_angle)))
		var vertex_radius: float = square_radius * rng.randf_range(0.9, 1.08)
		points.append(Vector2(cos(jittered_angle), sin(jittered_angle)) * vertex_radius)
	return points


# Cerchio pieno attorno al punto di ancoraggio (0,0) più un piccolo TRIANGOLO sul bordo, nel verso
# di `direction` — has_door resta vero per questo tipo (vedi commento su STICK_TENT_COLOR sopra),
# quindi la rotazione (tasto R) è significativa e va mostrata, anche se non con un vero ritaglio
# come la capanna (coerente con la forma più semplice di questo placeholder). Stessa funzione
# (duplicata apposta, vedi commento in testa al file) di MicroCellRenderer._draw_stick_tent, così
# l'anteprima e l'edificio finito coincidono esattamente.
func _draw_stick_tent(color: Color, outline_color: Color, direction: GameTypes.Direction) -> void:
	draw_circle(Vector2.ZERO, STICK_TENT_RADIUS, color)
	draw_arc(Vector2.ZERO, STICK_TENT_RADIUS, 0.0, TAU, CIRCLE_SEGMENTS, outline_color, STICK_TENT_OUTLINE_WIDTH, true)

	var dir_vector := _direction_vector(direction)
	var perpendicular := Vector2(-dir_vector.y, dir_vector.x)
	var base_center: Vector2 = dir_vector * STICK_TENT_RADIUS
	var apex: Vector2 = dir_vector * (STICK_TENT_RADIUS + STICK_TENT_DOOR_MARKER_HEIGHT)
	draw_colored_polygon(
		PackedVector2Array([
			base_center + perpendicular * STICK_TENT_DOOR_MARKER_HALF_WIDTH,
			base_center - perpendicular * STICK_TENT_DOOR_MARKER_HALF_WIDTH,
			apex,
		]),
		STICK_TENT_DOOR_MARKER_COLOR
	)


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
