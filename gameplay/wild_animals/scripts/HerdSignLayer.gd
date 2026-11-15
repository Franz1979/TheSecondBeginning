class_name HerdSignLayer
extends Node2D

# Segni dei pascoli (2026-11-15, richiesta utente — «il giocatore vero non saprebbe mai dove pascolano le bestie»): erba
# calpestata attorno a ogni pascolo del registro delle mete abituali (GameData.herd_habit_goals, HerdHabitService) di
# questa macrocella. Il registro dice già dove una specie si ferma sempre: qui solo il disegno, niente conteggi. Figlio del
# container della cella, sopra il renderer, sotto trappole e nebbia. Orme ed escrementi provati e tolti (richiesta utente).
#
# Solo sull'erba libera: niente chiazza dove sono disegnati alberi, arbusti o rocce (anche esaurite, i sassi restano
# disegnati). Una tinta bruna per microcella, più scura al centro del pascolo e sfumata verso il bordo (raggio della sosta,
# AnimalGroupRenderer.HABIT_DWELL_RADIUS), con una piccola variazione fissa per cella.
#
# Nebbia (richiesta utente): il pascolo è un fatto del posto, segue la memoria del terreno (FogOfWarMemory.is_terrain_fresh
# con terrain_memory_days della nebbia, già allungati dalle conoscenze). Si ridisegna quando cambia il registro, l'erba/
# piante/rocce del renderer, il giorno o l'insieme visibile della nebbia.
#
# is_known_pasture: la stessa regola per il pannello d'ispezione della microcella (GameScene), così disegno e testo non
# possono dire cose diverse.

const CELL_SIZE: float = MicroCellRenderer.CELL_SIZE
const GRID_SIZE := 100
# Erba calpestata: colore della terra battuta e opacità al centro del pascolo (al bordo scende verso 0).
const TRAMPLED_COLOR := Color(0.36, 0.30, 0.16)
const TRAMPLED_MAX_ALPHA := 0.45

var _macro_coords: Vector2i = Vector2i.ZERO
var _renderer: MicroCellRenderer
var _cell: LiveMacroCell
var _drawn_day: int = -1
var _drawn_fog_version: int = -1
var _drawn_size: int = -1
# Ultime liste del renderer viste: i set_* del renderer le sostituiscono, basta confrontarne l'identità.
var _seen_sources: Array = []
var _free_grass: Dictionary = {} # Vector2i -> true: erba senza alberi, arbusti né rocce (rifatto solo se il renderer cambia)
var _has_pastures: bool = false


# `cell`: la sua nebbia (fog_of_war_renderer) viene creata dopo questo layer, si legge al momento del disegno.
func setup(macro_coords: Vector2i, cell: LiveMacroCell) -> void:
	_macro_coords = macro_coords
	_cell = cell
	_renderer = cell.renderer
	_drawn_size = -1
	_seen_sources = []
	queue_redraw()


func _process(_delta: float) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	if game_data.herd_habit_goals.size() != _drawn_size or not _sources_unchanged():
		queue_redraw()
	# Giorno e nebbia contano solo se nella cella c'è almeno un pascolo.
	elif _has_pastures and (game_data.get_absolute_day() != _drawn_day or _fog_version() != _drawn_fog_version):
		queue_redraw()


# Punti dei pascoli abituali (in microcelle) di questa macrocella, di qualunque specie. Solo voci della regola attuale
# (HerdHabitService.RULE_VERSION).
static func pastures_of_cell(game_data: GameData, macro_coords: Vector2i) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if game_data == null:
		return result
	var prefix := "%d,%d:" % [macro_coords.x, macro_coords.y]
	var suffix := "#%d" % HerdHabitService.RULE_VERSION
	for key in game_data.herd_habit_goals:
		var text := String(key)
		if not text.begins_with(prefix) or not text.ends_with(suffix):
			continue
		for entry in game_data.herd_habit_goals[key]:
			if entry is Dictionary:
				var point := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
				if not result.has(point):
					result.append(point)
	return result


static func is_in_pasture(game_data: GameData, macro_coords: Vector2i, lot: Vector2i) -> bool:
	var center := Vector2(lot) + Vector2(0.5, 0.5)
	for point in pastures_of_cell(game_data, macro_coords):
		if center.distance_to(point) <= AnimalGroupRenderer.HABIT_DWELL_RADIUS:
			return true
	return false


# Pascolo che il villaggio conosce: dentro un pascolo e con il terreno della microcella ancora ricordato.
static func is_known_pasture(game_data: GameData, cell: LiveMacroCell, macro_coords: Vector2i, lot: Vector2i) -> bool:
	return _is_terrain_remembered(cell, lot, game_data.get_absolute_day()) and is_in_pasture(game_data, macro_coords, lot)


static func _is_terrain_remembered(cell: LiveMacroCell, lot: Vector2i, day: int) -> bool:
	if cell == null or cell.fog_of_war_renderer == null or cell.fog_of_war_renderer.fog_of_war_memory == null:
		return false
	var fog := cell.fog_of_war_renderer
	return fog.fog_of_war_memory.is_terrain_fresh(lot, day, fog.terrain_memory_days)


func _draw() -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	_drawn_size = game_data.herd_habit_goals.size()
	_drawn_day = game_data.get_absolute_day()
	_drawn_fog_version = _fog_version()
	if not _sources_unchanged():
		_rebuild_free_grass()
	var pastures := pastures_of_cell(game_data, _macro_coords)
	_has_pastures = not pastures.is_empty()
	for point in pastures:
		_draw_trampled(point, _drawn_day)


func _fog_version() -> int:
	if _cell == null or _cell.fog_of_war_renderer == null:
		return -1
	return _cell.fog_of_war_renderer.visible_set_version


func _sources() -> Array:
	if _renderer == null:
		return []
	var veg: Dictionary = _renderer.vegetation_positions
	return [
		veg.get(GameTypes.WorldObjectType.GRASS, []),
		veg.get(GameTypes.WorldObjectType.TREE, []),
		veg.get(GameTypes.WorldObjectType.SHRUB, []),
		_renderer.stone_positions,
	]


func _sources_unchanged() -> bool:
	var current := _sources()
	if current.size() != _seen_sources.size():
		return false
	for i in range(current.size()):
		if not is_same(current[i], _seen_sources[i]):
			return false
	return true


func _rebuild_free_grass() -> void:
	_seen_sources = _sources()
	_free_grass.clear()
	if _seen_sources.is_empty():
		return
	for lot in _seen_sources[0]:
		_free_grass[Vector2i(lot.x, lot.y)] = true
	for index in [1, 2]:
		for individual in _seen_sources[index]:
			_free_grass.erase(Vector2i(individual.x, individual.y))
	for rock in _seen_sources[3]:
		_free_grass.erase(Vector2i(rock.x, rock.y))


# Chiazza di erba calpestata: una tinta per microcella d'erba libera, più forte al centro, con un po' di variazione fissa
# per cella così il bordo non è un cerchio perfetto.
func _draw_trampled(point: Vector2, day: int) -> void:
	var radius := AnimalGroupRenderer.HABIT_DWELL_RADIUS
	var reach := int(ceil(radius))
	var origin := Vector2i(floori(point.x), floori(point.y))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var lot := origin + Vector2i(dx, dy)
			if lot.x < 0 or lot.y < 0 or lot.x >= GRID_SIZE or lot.y >= GRID_SIZE or not _free_grass.has(lot):
				continue
			if not _is_terrain_remembered(_cell, lot, day):
				continue
			var distance := (Vector2(lot) + Vector2(0.5, 0.5)).distance_to(point)
			var jitter := float(hash([lot, point]) % 1000) / 1000.0 # 0..1, fisso
			var strength := 1.0 - distance / radius + (jitter - 0.5) * 0.35
			if strength <= 0.0:
				continue
			var color := TRAMPLED_COLOR
			color.a = TRAMPLED_MAX_ALPHA * clampf(strength, 0.0, 1.0)
			draw_rect(Rect2(Vector2(lot) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE)), color)
