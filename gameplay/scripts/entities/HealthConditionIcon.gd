class_name HealthConditionIcon
extends Node2D

# Icone di salute sopra la testa di un pipottino (2026-10-25, richiesta utente — UX di malattie e ferite): un distintivo
# tondo con una punta verso la testa, uno per categoria. Malattia: faccina con il termometro in bocca. Ferita: cerotto.
# Sfondo rosso se una condizione di quella categoria è in fase acuta, giallo se sono tutte in convalescenza
# (HealthConditionService). Con malattia e ferita insieme i due distintivi stanno affiancati. Figlio di
# HumanIndividualView, che ogni frame ne annulla rotazione e scala (resta dritta e della stessa misura per tutti) e la
# mette sopra la testa; qui si ridisegna solo quando cambia lo stato, mai a ogni frame.

enum State { NONE, ACUTE, CONVALESCENCE }

const ACUTE_COLOR := Color(0.82, 0.16, 0.14)
const CONVALESCENCE_COLOR := Color(0.95, 0.74, 0.16)
const OUTLINE_COLOR := Color(0.08, 0.06, 0.05, 0.95)
const HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const FACE_COLOR := Color(1.0, 0.93, 0.8)
const FACE_LINE_COLOR := Color(0.25, 0.15, 0.1)
const CHEEK_COLOR := Color(0.95, 0.45, 0.4, 0.8)
const THERMOMETER_COLOR := Color(0.92, 0.95, 1.0)
const THERMOMETER_BULB_COLOR := Color(0.9, 0.1, 0.1)
const BANDAGE_COLOR := Color(0.93, 0.78, 0.6)
const BANDAGE_PAD_COLOR := Color(0.98, 0.93, 0.85)
const BANDAGE_EDGE_COLOR := Color(0.55, 0.38, 0.25)
# Misure in pixel del mondo (stessa scala di HumanIndividualView.CELL_SIZE).
const RADIUS: float = 1.8
const OUTLINE_WIDTH: float = 0.3
const TAIL_HALF_WIDTH: float = 0.55
const TAIL_LENGTH: float = 0.9
# Spazio tra due distintivi affiancati.
const GAP: float = 0.4

var illness_state: State = State.NONE
var wound_state: State = State.NONE
# Punta verso la testa sul distintivo singolo; spenta nella lista della popolazione (HumanPopulationInfoPanel).
var show_tail: bool = true


# Stati (malattia, ferita) di un individuo: per categoria ACUTE se una sua condizione è acuta, altrimenti CONVALESCENCE
# se ce n'è una. Unica fonte per la testa del pipottino (HumanIndividualView) e la lista della popolazione.
static func states_for(individual: HumanIndividual) -> Array[State]:
	var illness := State.NONE
	var wound := State.NONE
	for entry in individual.health_conditions:
		var rules := HealthConditionService.get_rules(String(entry.get("id", "")))
		if rules == null:
			continue
		var acute := String(entry.get("phase", HealthConditionService.PHASE_ACUTE)) == HealthConditionService.PHASE_ACUTE
		if rules.category == HealthConditionRules.Category.WOUND:
			wound = _merged_state(wound, acute)
		else:
			illness = _merged_state(illness, acute)
	return [illness, wound]


# Fase acuta vince sulla convalescenza.
static func _merged_state(current: State, acute: bool) -> State:
	if acute or current == State.ACUTE:
		return State.ACUTE
	return State.CONVALESCENCE


func set_states(new_illness_state: State, new_wound_state: State) -> void:
	if new_illness_state == illness_state and new_wound_state == wound_state:
		return
	illness_state = new_illness_state
	wound_state = new_wound_state
	visible = illness_state != State.NONE or wound_state != State.NONE
	queue_redraw()


func _draw() -> void:
	var both := illness_state != State.NONE and wound_state != State.NONE
	var shift := (RADIUS + OUTLINE_WIDTH + GAP / 2.0) if both else 0.0
	if illness_state != State.NONE:
		var center := Vector2(-shift, 0.0)
		_draw_badge(center, illness_state, show_tail and not both)
		_draw_fever_face(center)
	if wound_state != State.NONE:
		var center := Vector2(shift, 0.0)
		_draw_badge(center, wound_state, show_tail and not both)
		_draw_bandage(center)


# Disco col bordo scuro, riflesso in alto a sinistra e, se è da solo, la punta verso la testa.
func _draw_badge(center: Vector2, state: State, with_tail: bool) -> void:
	var fill := ACUTE_COLOR if state == State.ACUTE else CONVALESCENCE_COLOR
	if with_tail:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-TAIL_HALF_WIDTH - OUTLINE_WIDTH, RADIUS * 0.6),
			center + Vector2(TAIL_HALF_WIDTH + OUTLINE_WIDTH, RADIUS * 0.6),
			center + Vector2(0.0, RADIUS + TAIL_LENGTH + OUTLINE_WIDTH),
		]), OUTLINE_COLOR)
	draw_circle(center, RADIUS + OUTLINE_WIDTH, OUTLINE_COLOR)
	if with_tail:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-TAIL_HALF_WIDTH, RADIUS * 0.6),
			center + Vector2(TAIL_HALF_WIDTH, RADIUS * 0.6),
			center + Vector2(0.0, RADIUS + TAIL_LENGTH),
		]), fill)
	draw_circle(center, RADIUS, fill)
	draw_arc(center, RADIUS * 0.78, PI * 1.05, PI * 1.45, 8, HIGHLIGHT_COLOR, 0.3, true)


# Faccina malata: occhi socchiusi, guance arrossate, termometro che esce dalla bocca verso destra.
func _draw_fever_face(center: Vector2) -> void:
	var face_radius := RADIUS * 0.7
	draw_circle(center, face_radius, FACE_COLOR)
	draw_arc(center, face_radius, 0.0, TAU, 16, FACE_LINE_COLOR, 0.12, true)
	# Occhi socchiusi (archi verso il basso) e guance.
	for side in [-1.0, 1.0]:
		var eye := center + Vector2(side * face_radius * 0.38, -face_radius * 0.2)
		draw_arc(eye, face_radius * 0.18, 0.15 * PI, 0.85 * PI, 6, FACE_LINE_COLOR, 0.12, true)
		draw_circle(center + Vector2(side * face_radius * 0.55, face_radius * 0.2), face_radius * 0.15, CHEEK_COLOR)
	# Bocca e termometro.
	var mouth := center + Vector2(0.0, face_radius * 0.45)
	draw_circle(mouth, face_radius * 0.12, FACE_LINE_COLOR)
	var tip := mouth + Vector2(face_radius * 1.05, -face_radius * 0.35)
	draw_line(mouth, tip, FACE_LINE_COLOR, 0.32, true)
	draw_line(mouth, tip, THERMOMETER_COLOR, 0.18, true)
	draw_circle(mouth + Vector2(face_radius * 0.12, -face_radius * 0.04), 0.13, THERMOMETER_BULB_COLOR)


# Cerotto inclinato: striscia color pelle con il bordo, il tampone chiaro al centro e i forellini.
func _draw_bandage(center: Vector2) -> void:
	var half_length := RADIUS * 0.85
	var half_width := RADIUS * 0.32
	draw_set_transform(center, -PI / 4.0, Vector2.ONE)
	draw_rect(Rect2(-half_length - 0.08, -half_width - 0.08, half_length * 2.0 + 0.16, half_width * 2.0 + 0.16), BANDAGE_EDGE_COLOR)
	draw_rect(Rect2(-half_length, -half_width, half_length * 2.0, half_width * 2.0), BANDAGE_COLOR)
	var pad_half := half_width * 0.95
	draw_rect(Rect2(-pad_half, -pad_half + 0.04, pad_half * 2.0, pad_half * 2.0 - 0.08), BANDAGE_PAD_COLOR)
	for x in [-half_length * 0.7, -half_length * 0.5, half_length * 0.5, half_length * 0.7]:
		for y in [-half_width * 0.4, half_width * 0.4]:
			draw_circle(Vector2(x, y), 0.07, BANDAGE_EDGE_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
