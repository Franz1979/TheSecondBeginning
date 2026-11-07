class_name PlacedTrapLayer
extends Node2D

# Disegno delle trappole montate di una macrocella (2026-11-07, TrapService). Figlio del container della cella, sopra gli
# oggetti del renderer e sotto la nebbia (che la copre come il resto). Si ridisegna da sé quando cambiano le trappole
# (GameData.placed_traps_revision).
#
# Vista dall'alto, non l'icona del magazzino (2026-11-07, richiesta utente: l'icona a tutta microcella sembrava una rete di
# 10 m). La rete per uccelli vista dall'alto è solo una linea: due paletti (puntini scuri) e la rete tesa tra loro (filo
# chiaro un po' insaccato, con l'ombra). Una trappola senza disegno proprio ha un simbolino (_draw_symbol).

const CELL_SIZE: float = MicroCellRenderer.CELL_SIZE
const POLE_COLOR := Color(0.30, 0.20, 0.10, 1.0)
const NET_COLOR := Color(0.86, 0.80, 0.64, 0.95)
const NET_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SYMBOL_COLOR := Color(0.85, 0.75, 0.50, 0.95)
const BROKEN_NET_COLOR := Color(0.62, 0.56, 0.44, 0.75)

var _macro_coords: Vector2i = Vector2i.ZERO
var _drawn_revision: int = -1


func setup(macro_coords: Vector2i) -> void:
	_macro_coords = macro_coords
	_drawn_revision = -1
	queue_redraw()


func _process(_delta: float) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data != null and game_data.placed_traps_revision != _drawn_revision:
		queue_redraw()


func _draw() -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	_drawn_revision = game_data.placed_traps_revision
	for trap in TrapService.traps_in_macro_cell(game_data, _macro_coords):
		var rules := TrapService.get_rules(trap.trap_name)
		var top_left := Vector2(trap.lot) * CELL_SIZE
		if rules != null and rules.trap_quarry == TrapService.QUARRY_BIRDS:
			_draw_bird_net(top_left, trap.id)
		else:
			_draw_symbol(top_left)
	for broken in TrapService.broken_in_macro_cell(game_data, _macro_coords):
		var top_left := Vector2(int(broken.get("lot_x", 0)), int(broken.get("lot_y", 0))) * CELL_SIZE
		var rules := TrapService.get_rules(String(broken.get("trap_name", "")))
		if rules != null and rules.trap_quarry == TrapService.QUARRY_BIRDS:
			_draw_broken_bird_net(top_left, int(broken.get("id", 0)))


# Rete rotta (posto a riposo, TrapService.broken_traps): stessi paletti, uno storto, e la rete strappata a metà che pende
# dai due lati in due pezzi spenti.
func _draw_broken_bird_net(top_left: Vector2, trap_id: int) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var angle := deg_to_rad(-25.0 if trap_id % 2 == 0 else 20.0)
	var half := Vector2(cos(angle), sin(angle)) * CELL_SIZE * 0.3
	var normal := Vector2(-half.y, half.x).normalized()
	var a := center - half
	var b := center + half + normal * CELL_SIZE * 0.06
	var torn_a := center - half * 0.15 + normal * CELL_SIZE * 0.12
	var torn_b := center + half * 0.2 + normal * CELL_SIZE * 0.16
	draw_polyline(PackedVector2Array([a, a.lerp(torn_a, 0.5) + normal * CELL_SIZE * 0.05, torn_a]), BROKEN_NET_COLOR, CELL_SIZE * 0.04, true)
	draw_polyline(PackedVector2Array([b, b.lerp(torn_b, 0.5) + normal * CELL_SIZE * 0.04, torn_b]), BROKEN_NET_COLOR, CELL_SIZE * 0.04, true)
	draw_circle(a, CELL_SIZE * 0.05, POLE_COLOR)
	draw_circle(b, CELL_SIZE * 0.045, POLE_COLOR)


# Rete tesa vista dall'alto: lunga circa 6 m sulla microcella, di sbieco (verso stabile per trappola, dal suo id).
func _draw_bird_net(top_left: Vector2, trap_id: int) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var angle := deg_to_rad(-25.0 if trap_id % 2 == 0 else 20.0)
	var half := Vector2(cos(angle), sin(angle)) * CELL_SIZE * 0.3
	var normal := Vector2(-half.y, half.x).normalized()
	var a := center - half
	var b := center + half
	var sag := center + normal * CELL_SIZE * 0.05
	var shadow := normal * CELL_SIZE * 0.06
	draw_polyline(PackedVector2Array([a + shadow, sag + shadow, b + shadow]), NET_SHADOW_COLOR, CELL_SIZE * 0.06, true)
	draw_polyline(PackedVector2Array([a, sag, b]), NET_COLOR, CELL_SIZE * 0.05, true)
	draw_circle(a, CELL_SIZE * 0.05, POLE_COLOR)
	draw_circle(b, CELL_SIZE * 0.05, POLE_COLOR)


# Simbolino generico: un piccolo cerchio chiaro con una croce.
func _draw_symbol(top_left: Vector2) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var radius := CELL_SIZE * 0.15
	draw_arc(center, radius, 0.0, TAU, 16, SYMBOL_COLOR, CELL_SIZE * 0.05, true)
	var d := radius * 0.7
	draw_line(center + Vector2(-d, -d), center + Vector2(d, d), SYMBOL_COLOR, CELL_SIZE * 0.04, true)
	draw_line(center + Vector2(-d, d), center + Vector2(d, -d), SYMBOL_COLOR, CELL_SIZE * 0.04, true)
