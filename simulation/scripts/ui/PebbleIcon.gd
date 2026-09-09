class_name PebbleIcon
extends Control

# Icona stilizzata "ghiaia/sassolini sparsi" per il riquadro risorsa trasportata (2026-09-09,
# richiesta utente — dopo feedback: l'emoji 🪨 [un macigno singolo] non rende "tanti sassolini
# piccoli", nessun emoji Unicode rende bene "ghiaia sparsa" nemmeno cercando alternative (castagna/
# pietra da curling/pallino, tutte scartate). Disegnata a mano, stesso principio di StickIcon/
# StoneCircleIcon. 🪨 stesso liberato per un futuro "stone" [materiale da costruzione DISTINTO,
# vedi stone_circle.tres.required_materials, ancora senza .tres/icona propria] — vedi IconRegistry.
#
# A differenza di StoneCircleIcon (6 massi GRANDI disposti in un cerchio PERFETTO — leggibile come
# "struttura", voluto lì), qui le posizioni sono uno sparpagliamento IRREGOLARE (mai un pattern
# geometrico riconoscibile) di pallini PICCOLI e di dimensione variabile — è proprio questa
# irregolarità/piccolezza a leggere come "ghiaia" invece che "cerchio di pietre" o "un macigno
# solo". Offset FISSI (mai randf(): icona statica, nessun bisogno di variare tra un redraw e
# l'altro, stesso principio "nessun unseeded randf()" già seguito altrove nel progetto).

const PEBBLE_COLOR := Color(0.58, 0.57, 0.54, 1.0)
const PEBBLE_OUTLINE_COLOR := Color(0.32, 0.31, 0.29, 1.0)

# (x_ratio, y_ratio, radius_ratio) — posizione relativa a `size` + raggio relativo al lato minore,
# sparsi a mano per un aspetto "casuale ma leggibile", non un pattern a griglia/cerchio.
const PEBBLES := [
	Vector3(0.22, 0.28, 0.12),
	Vector3(0.55, 0.18, 0.10),
	Vector3(0.78, 0.35, 0.13),
	Vector3(0.35, 0.55, 0.11),
	Vector3(0.65, 0.60, 0.09),
	Vector3(0.85, 0.72, 0.10),
	Vector3(0.15, 0.75, 0.09),
	Vector3(0.48, 0.82, 0.08),
]


func _ready() -> void:
	# IGNORE (stesso principio di StoneCircleIcon/StickIcon): puro disegno, mai un bersaglio di
	# input — il tooltip sul riquadro trasportato vive sul CONTENITORE (carried_resource_box), non
	# su questa icona, vedi HumanIndividualInfoPanel._update_carried_resource_box.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	for pebble in PEBBLES:
		var center := Vector2(pebble.x * size.x, pebble.y * size.y)
		var radius: float = pebble.z * side
		draw_circle(center, radius, PEBBLE_COLOR)
		draw_arc(center, radius, 0.0, TAU, 8, PEBBLE_OUTLINE_COLOR, 1.0, true)
