class_name StoneCircleIcon
extends Control

# Icona stilizzata "cerchio di pietre" per il bottone Stone Circle in BuildBar (2026-09-07,
# richiesta utente — dopo due giri di feedback: 🗿 leggeva come una testa dell'Isola di Pasqua, 🪨
# come un mucchio di sassi. Nessun emoji Unicode rende bene "cerchio di pietre", quindi disegnata a
# mano invece di un altro tentativo di emoji). Control minimale, solo _draw(): riempie il proprio
# Rect2 (vedi IconButtonRow.configure_slot, che lo ancora PRESET_FULL_RECT dentro lo slot 32x32),
# così scala automaticamente con qualunque dimensione di slot senza valori hardcoded in pixel.
# Cerchi PIENI (non blob irregolari come MicroCellRenderer._draw_stone_circle/BuildingGhost —
# quel dettaglio ha senso in una struttura vera piazzata sulla mappa, qui a pochi pixel di
# distanza sarebbe solo rumore): semplicità voluta, un'icona deve leggersi a colpo d'occhio.

const STONE_COLOR := Color(0.75, 0.73, 0.68, 1.0)
const STONE_OUTLINE_COLOR := Color(0.3, 0.28, 0.24, 1.0)
const STONE_COUNT: int = 6
const RING_RADIUS_RATIO: float = 0.32
const STONE_RADIUS_RATIO: float = 0.14


func _ready() -> void:
	# IGNORE (2026-09-07): questo nodo è puro disegno, mai un bersaglio di input — i click devono
	# raggiungere il Button (TooltipButton) sotto di cui è figlio, altrimenti lo slot smetterebbe
	# di essere cliccabile proprio dove il disegno lo ricopre.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var ring_radius: float = minf(size.x, size.y) * RING_RADIUS_RATIO
	var stone_radius: float = minf(size.x, size.y) * STONE_RADIUS_RATIO
	for i in range(STONE_COUNT):
		# -PI/2 (2026-09-07): il primo masso parte in cima invece che a destra, lettura più
		# naturale di un "cerchio" per un occhio umano.
		var angle: float = TAU * float(i) / float(STONE_COUNT) - PI / 2.0
		var stone_center: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
		draw_circle(stone_center, stone_radius, STONE_COLOR)
		draw_arc(stone_center, stone_radius, 0.0, TAU, 12, STONE_OUTLINE_COLOR, 1.0, true)
