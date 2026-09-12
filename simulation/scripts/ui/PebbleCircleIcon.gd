class_name PebbleCircleIcon
extends Control

# Icona stilizzata "cerchio di sassolini" per il bottone Pebble Circle in BuildBar (2026-09-07,
# richiesta utente — dopo due giri di feedback: 🗿 leggeva come una testa dell'Isola di Pasqua, 🪨
# come un mucchio di sassi. Nessun emoji Unicode rende bene "cerchio di sassolini", quindi disegnata
# a mano invece di un altro tentativo di emoji — RINOMINATO da Stone Circle, 2026-09-12, richiesta
# utente: l'edificio rappresenta oggi dei sassolini raccolti, "Stone Circle" resta il nome riservato
# a un futuro edificio DAVVERO fatto di pietre vere). Control minimale, solo _draw(): riempie il proprio
# Rect2 (vedi IconButtonRow.configure_slot, che lo ancora PRESET_FULL_RECT dentro lo slot 32x32),
# così scala automaticamente con qualunque dimensione di slot senza valori hardcoded in pixel.
# Cerchi PIENI (non blob irregolari come MicroCellRenderer._draw_pebble_circle/BuildingGhost —
# quel dettaglio ha senso in una struttura vera piazzata sulla mappa, qui a pochi pixel di
# distanza sarebbe solo rumore): semplicità voluta, un'icona deve leggersi a colpo d'occhio.

const PEBBLE_COLOR := Color(0.75, 0.73, 0.68, 1.0)
const PEBBLE_OUTLINE_COLOR := Color(0.3, 0.28, 0.24, 1.0)
# Sassolini più piccoli e più numerosi (2026-09-12, richiesta utente — rename Stone Circle -> Pebble
# Circle: l'edificio rappresenta oggi dei sassolini, non i massi che un futuro vero "Stone Circle"
# userà) — 6->12 conteggio, 0.14->0.08 raggio (RING_RADIUS_RATIO invariato: più sassolini più fitti
# sullo stesso anello, non un anello più largo).
const PEBBLE_COUNT: int = 12
const RING_RADIUS_RATIO: float = 0.32
const PEBBLE_RADIUS_RATIO: float = 0.08


func _ready() -> void:
	# IGNORE (2026-09-07): questo nodo è puro disegno, mai un bersaglio di input — i click devono
	# raggiungere il Button (TooltipButton) sotto di cui è figlio, altrimenti lo slot smetterebbe
	# di essere cliccabile proprio dove il disegno lo ricopre.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var ring_radius: float = minf(size.x, size.y) * RING_RADIUS_RATIO
	var pebble_radius: float = minf(size.x, size.y) * PEBBLE_RADIUS_RATIO
	for i in range(PEBBLE_COUNT):
		# -PI/2 (2026-09-07): il primo sassolino parte in cima invece che a destra, lettura più
		# naturale di un "cerchio" per un occhio umano.
		var angle: float = TAU * float(i) / float(PEBBLE_COUNT) - PI / 2.0
		var pebble_center: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
		draw_circle(pebble_center, pebble_radius, PEBBLE_COLOR)
		draw_arc(pebble_center, pebble_radius, 0.0, TAU, 12, PEBBLE_OUTLINE_COLOR, 1.0, true)
