class_name HumanIndividualView
extends Node2D

# Resa visiva PLACEHOLDER dell'individuo controllabile — sarà sostituita in blocco al passaggio
# al 3D senza toccare HumanIndividual (legge solo il suo stato via setup(), non lo modifica mai).
# Un semplice cerchio disegnato immediate-mode, stesso approccio minimale già usato altrove per
# i placeholder di questo modulo.

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/AnimalGroupRenderer
const RADIUS: float = 1.5
const COLOR := Color(0.9, 0.82, 0.25, 1.0)
const SELECTION_COLOR := Color(1.0, 1.0, 1.0, 0.9)
# Aderente al bordo del pallino (piccolo margine, non staccato) e tratto sottile — prima un gap di
# 3px e uno spessore di 1.5 lo facevano leggere come un anello separato invece che come
# un'evidenziazione del pallino stesso.
const SELECTION_RADIUS: float = RADIUS + 0.3
const SELECTION_WIDTH: float = 0.6

var individual: HumanIndividual


func setup(p_individual: HumanIndividual) -> void:
	individual = p_individual


func _process(_delta: float) -> void:
	if individual == null:
		return
	position = individual.position * CELL_SIZE
	queue_redraw()


func _draw() -> void:
	if individual == null:
		return
	draw_circle(Vector2.ZERO, RADIUS, COLOR)
	if individual.is_selected:
		draw_arc(Vector2.ZERO, SELECTION_RADIUS, 0, TAU, 24, SELECTION_COLOR, SELECTION_WIDTH)
