class_name CrosshairIcon
extends Node2D

# Mirino del comando di caccia (2026-09-26, richiesta utente — sostituisce l'emoji 🏹, illeggibile a
# dimensione di microcella e simile alla X di annullo). Icona DISEGNATA registrata in IconRegistry.
# COMMAND_ICON_NODES ("hunt"), stesso principio delle altre icone disegnate di questa cartella: nessun
# emoji rende bene il concetto. Cerchio rosso a bordo sottile con due tratti DIAGONALI (a X) che
# partono dal cerchio e si fermano prima del centro, lasciando un piccolo spazio libero attorno al
# bersaglio. Disegno vettoriale (_draw), nitido a qualunque zoom. L'origine del nodo è il CENTRO del
# mirino, in pixel locali della cella (10 px = 1 microcella). Lampeggio e rimozione a cura di chi lo
# mostra (GameScene._spawn_command_icon).

const COLOR := Color(0.9, 0.12, 0.12, 1.0)
const RADIUS_PX: float = 3.0
# Raggio dello spazio libero al centro: i tratti diagonali vanno da qui fino al cerchio.
const CENTER_GAP_PX: float = 1.0
const LINE_WIDTH_PX: float = 0.35
const SEGMENTS: int = 32


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS_PX, 0.0, TAU, SEGMENTS, COLOR, LINE_WIDTH_PX, true)
	# Quattro tratti a 45°/135°/225°/315°: le due diagonali di una X, interrotte al centro.
	for quadrant in range(4):
		var direction := Vector2.from_angle(PI / 4.0 + quadrant * PI / 2.0)
		draw_line(direction * CENTER_GAP_PX, direction * RADIUS_PX, COLOR, LINE_WIDTH_PX, true)
