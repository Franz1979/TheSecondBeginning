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
const FISH_TRAP_COLOR := Color(0.88, 0.76, 0.52, 1.0)
const FISH_TRAP_DARK_COLOR := Color(0.55, 0.42, 0.24, 1.0)
const FISH_TRAP_BROKEN_COLOR := Color(0.66, 0.58, 0.44, 0.8)
const SNARE_CORD_COLOR := Color(0.90, 0.82, 0.60, 1.0)
const SNARE_BROKEN_COLOR := Color(0.62, 0.56, 0.44, 0.75)
# Fossa con pali (2026-11-11): buca scura coperta di rametti, con le punte dei pali che spuntano.
const PIT_COLOR := Color(0.16, 0.11, 0.06, 0.9)
const PIT_COVER_COLOR := Color(0.62, 0.50, 0.30, 0.9)
const PIT_STAKE_COLOR := Color(0.80, 0.66, 0.42, 1.0)
const PIT_BROKEN_COLOR := Color(0.40, 0.34, 0.26, 0.6)

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
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_FISH:
			_draw_fish_trap(trap.lot, top_left, false)
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_SMALL_GAME:
			_draw_snare(top_left, trap.id, false)
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_BIG_GAME:
			_draw_stake_pit(top_left, trap.id, false)
		else:
			_draw_symbol(top_left)
	for broken in TrapService.broken_in_macro_cell(game_data, _macro_coords):
		var top_left := Vector2(int(broken.get("lot_x", 0)), int(broken.get("lot_y", 0))) * CELL_SIZE
		var rules := TrapService.get_rules(String(broken.get("trap_name", "")))
		if rules != null and rules.trap_quarry == TrapService.QUARRY_BIRDS:
			_draw_broken_bird_net(top_left, int(broken.get("id", 0)))
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_FISH:
			_draw_fish_trap(Vector2i(int(broken.get("lot_x", 0)), int(broken.get("lot_y", 0))), top_left, true)
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_SMALL_GAME:
			_draw_snare(top_left, int(broken.get("id", 0)), true)
		elif rules != null and rules.trap_quarry == TrapService.QUARRY_BIG_GAME:
			_draw_stake_pit(top_left, int(broken.get("id", 0)), true)


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


# Nassa vista dall'alto, sul punto d'acqua della microcella (MicroCellRenderer.get_stream_water_point) e lungo la corrente:
# un cono di vimini con la bocca scura controcorrente e due cerchi dell'intreccio. Rotta: stessa sagoma spenta, senza bocca.
func _draw_fish_trap(lot: Vector2i, top_left: Vector2, broken: bool) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var flow := Vector2.RIGHT
	var live_cell := PathfindingService.get_live_cell(_macro_coords)
	if live_cell != null and live_cell.renderer != null:
		var water: Dictionary = live_cell.renderer.get_stream_water_point(lot)
		center = water.get("point", center)
		flow = water.get("flow", flow)
	var across := flow.orthogonal()
	var half_length := CELL_SIZE * 0.21
	var half_width := CELL_SIZE * 0.12
	var mouth := center - flow * half_length
	var tip := center + flow * half_length
	var body_color := FISH_TRAP_BROKEN_COLOR if broken else FISH_TRAP_COLOR
	draw_colored_polygon(PackedVector2Array([mouth + across * half_width, tip, mouth - across * half_width]), body_color)
	for t in [0.35, 0.65]:
		var ring := mouth.lerp(tip, float(t))
		var ring_half := half_width * (1.0 - float(t))
		draw_line(ring + across * ring_half, ring - across * ring_half, FISH_TRAP_DARK_COLOR, CELL_SIZE * 0.03, true)
	if not broken:
		draw_circle(mouth, half_width * 0.75, FISH_TRAP_DARK_COLOR)
	draw_line(mouth + across * half_width, mouth - across * half_width, body_color, CELL_SIZE * 0.05, true)


# Lacci visti dall'alto (2026-11-09): più piccoli della rete, due paletti (puntini scuri) e tra loro un anellino di corda
# chiara. Rotti: corda spenta e anello aperto.
func _draw_snare(top_left: Vector2, trap_id: int, broken: bool) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var angle := deg_to_rad(35.0 if trap_id % 2 == 0 else -30.0)
	var half := Vector2(cos(angle), sin(angle)) * CELL_SIZE * 0.17
	var a := center - half
	var b := center + half
	var color := SNARE_BROKEN_COLOR if broken else SNARE_CORD_COLOR
	var radius := CELL_SIZE * 0.08
	draw_line(a, center - half.normalized() * radius, color, CELL_SIZE * 0.03, true)
	draw_line(center + half.normalized() * radius, b, color, CELL_SIZE * 0.03, true)
	draw_arc(center, radius, 0.0, TAU * (0.7 if broken else 1.0), 14, color, CELL_SIZE * 0.035, true)
	draw_circle(a, CELL_SIZE * 0.04, POLE_COLOR)
	draw_circle(b, CELL_SIZE * 0.04, POLE_COLOR)


# Fossa con pali vista dall'alto: buca quasi grande come la microcella, rametti di copertura di sbieco (verso stabile per
# trappola, dal suo id) e tre punte chiare. Rotta (posto a riposo): solo la buca spenta, senza copertura né pali.
func _draw_stake_pit(top_left: Vector2, trap_id: int, broken: bool) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var radius := CELL_SIZE * 0.36
	draw_circle(center, radius, PIT_BROKEN_COLOR if broken else PIT_COLOR)
	if broken:
		return
	var angle := deg_to_rad(30.0 if trap_id % 2 == 0 else -25.0)
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	for offset in [-0.18, 0.0, 0.18]:
		var mid: Vector2 = center + across * CELL_SIZE * offset
		draw_line(mid - along * radius * 0.85, mid + along * radius * 0.85, PIT_COVER_COLOR, CELL_SIZE * 0.035, true)
	for point in [Vector2(-0.12, -0.10), Vector2(0.13, -0.04), Vector2(-0.02, 0.14)]:
		draw_circle(center + (point as Vector2) * CELL_SIZE, CELL_SIZE * 0.035, PIT_STAKE_COLOR)


# Simbolino generico: un piccolo cerchio chiaro con una croce.
func _draw_symbol(top_left: Vector2) -> void:
	var center := top_left + Vector2.ONE * CELL_SIZE * 0.5
	var radius := CELL_SIZE * 0.15
	draw_arc(center, radius, 0.0, TAU, 16, SYMBOL_COLOR, CELL_SIZE * 0.05, true)
	var d := radius * 0.7
	draw_line(center + Vector2(-d, -d), center + Vector2(d, d), SYMBOL_COLOR, CELL_SIZE * 0.04, true)
	draw_line(center + Vector2(-d, d), center + Vector2(d, -d), SYMBOL_COLOR, CELL_SIZE * 0.04, true)
