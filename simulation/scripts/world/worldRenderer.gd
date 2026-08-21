class_name WorldRenderer
extends Node2D

const CELL_SIZE: int = 10
const COLOR_EVENT_MARKER_FRESH := Color(1.0, 0.0, 0.0, 0.9)        # anno in cui l'evento è avvenuto
const COLOR_EVENT_MARKER_RECOVERING := Color(1.0, 0.55, 0.0, 0.75) # anni successivi, fino a esaurimento del bonus
const COLOR_DROUGHT_MARKER_FRESH := Color(0.55, 0.35, 0.05, 0.9)        # marrone, anno della siccità
const COLOR_DROUGHT_MARKER_RECOVERING := Color(0.85, 0.65, 0.15, 0.75)  # giallo ocra, anni successivi
const COLOR_SEA_FLOOD_MARKER_FRESH := Color(0.05, 0.35, 0.55, 0.9)        # blu intenso, anno dell'inondazione
const COLOR_SEA_FLOOD_MARKER_RECOVERING := Color(0.55, 0.75, 0.85, 0.75)  # azzurro salino, anni successivi
const COLOR_PAINT_FLASH := Color(1.0, 1.0, 1.0, 1.0)
const PAINT_FLASH_DURATION: float = 0.35 # secondi, feedback visivo di una cella appena dipinta nel map editor
# Etichetta ID sopra ciascun territorio evidenziato da highlight_group_territories sotto — colore
# fisso (non dipende dal colore del territorio, deve restare leggibile su qualunque tinta) con un
# alone scuro sotto per contrasto anche su territori chiari.
const COLOR_SPECIES_OVERLAY_LABEL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SPECIES_OVERLAY_LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 0.9)
# Dimensione FISSA in pixel schermo (non locali/CELL_SIZE) — usata così com'è, senza alcuna
# contro-scala: vedi _draw_species_territory_overlay_labels per come il disegno esce dal sistema
# di coordinate locale/zoom per renderla davvero costante e nitida.
const SPECIES_OVERLAY_LABEL_SCREEN_FONT_SIZE: int = 14

const RENDERED_EVENT_TYPES := [
	GameTypes.NaturalEventType.FIRE,
	GameTypes.NaturalEventType.DROUGHT,
	GameTypes.NaturalEventType.SEA_FLOOD,
]

var world: World
var game_data: GameData
var show_resource_overlay: bool = true

var selected_cell: MacroCellData = null
# Vector2i -> {"remaining": float, "duration": float}: "duration" è la durata TOTALE con cui la
# cella è stata flashata (serve a normalizzare il fade dell'alpha in _draw, vedi flash_time /
# flash_duration sotto) — non più un unico float fisso (PAINT_FLASH_DURATION), da quando
# flash_cell/flash_cells accettano una durata esplicita (highlight population più lungo del
# feedback-pennello del map editor, ma stesso identico meccanismo di fade).
var flashing_cells: Dictionary = {}

# Vista "Mostra tutti i territori di una specie" (WorldInfoPanel, tab Fauna 2) — parallela e
# indipendente da flashing_cells sopra, mai la tocca: quella resta l'evidenziazione a singolo
# gruppo (bordo bianco lampeggiante), questa mostra PIÙ territori insieme, ciascuno col proprio
# colore e un'etichetta ID al baricentro. Stesso schema di fade (remaining/duration).
# Vector2i -> {"color": Color, "remaining": float, "duration": float}
var _species_territory_overlay_cells: Dictionary = {}
# Array di {"cell": Vector2i, "text": String, "remaining": float, "duration": float}
var _species_territory_overlay_labels: Array = []

func set_selected_cell(cell: MacroCellData) -> void:
	selected_cell = cell
	queue_redraw()

func flash_cell(x: int, y: int, duration: float = PAINT_FLASH_DURATION) -> void:
	flashing_cells[Vector2i(x, y)] = {"remaining": duration, "duration": duration}


# Comodità per evidenziare più celle insieme con la stessa durata (es. tutte le celle del
# territorio di un PopulationGroup) senza dover far iterare a ogni chiamante flash_cell singola.
func flash_cells(coords_list: Array, duration: float = PAINT_FLASH_DURATION) -> void:
	for coords in coords_list:
		flash_cell(coords.x, coords.y, duration)


# Vista "Mostra tutti" (WorldInfoPanel): `entries` è un Array di Dictionary generici, uno per
# territorio da evidenziare — {"cells": Array[Vector2i], "color": Color, "label_text": String,
# "label_cell": Vector2i}. WorldRenderer resta agnostico di PopulationGroup/Territory (stesso
# principio di flash_cells sopra): il chiamante decide già colore/etichetta/baricentro, qui si
# limita a disegnarli. Sovrascrive sempre l'evidenziazione precedente (nessun accumulo tra una
# chiamata e l'altra — "Mostra tutti" premuto due volte di fila non deve sommare vecchie e nuove
# celle/etichette).
func highlight_group_territories(entries: Array, duration: float) -> void:
	_species_territory_overlay_cells.clear()
	_species_territory_overlay_labels.clear()
	for entry in entries:
		var color: Color = entry["color"]
		for coords in entry["cells"]:
			_species_territory_overlay_cells[coords] = {
				"color": color, "remaining": duration, "duration": duration
			}
		_species_territory_overlay_labels.append({
			"cell": entry["label_cell"], "text": entry["label_text"],
			"remaining": duration, "duration": duration
		})
	queue_redraw()

# game_data is optional: MapEditorScene has no calendar/simulation, so it calls setup(world)
# and event markers simply never draw there (guarded in _draw_event_markers).
func setup(_world: World, _game_data: GameData = null) -> void:
	world = _world
	game_data = _game_data
	queue_redraw()


func _process(delta: float) -> void:
	# Le due strutture scadono indipendentemente (early return solo se ENTRAMBE sono vuote):
	# highlight_group_territories può restare attivo anche quando flashing_cells è già vuoto
	# (es. dopo un click su "⌖" singolo, seguito da "Mostra tutti" con durata diversa), e
	# viceversa.
	if flashing_cells.is_empty() and _species_territory_overlay_cells.is_empty() and _species_territory_overlay_labels.is_empty():
		return

	var expired_flash: Array = []
	for pos in flashing_cells.keys():
		var entry: Dictionary = flashing_cells[pos]
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			expired_flash.append(pos)
	for pos in expired_flash:
		flashing_cells.erase(pos)

	var expired_overlay_cells: Array = []
	for pos in _species_territory_overlay_cells.keys():
		var entry: Dictionary = _species_territory_overlay_cells[pos]
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			expired_overlay_cells.append(pos)
	for pos in expired_overlay_cells:
		_species_territory_overlay_cells.erase(pos)

	for i in range(_species_territory_overlay_labels.size() - 1, -1, -1):
		_species_territory_overlay_labels[i]["remaining"] -= delta
		if _species_territory_overlay_labels[i]["remaining"] <= 0.0:
			_species_territory_overlay_labels.remove_at(i)

	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for cell in world.cells:
		var color := get_cell_color(cell)
		var rect := Rect2(
			cell.x * CELL_SIZE,
			cell.y * CELL_SIZE,
			CELL_SIZE,
			CELL_SIZE
		)
		if cell.water_type == GameTypes.WaterType.RIVER:
			_draw_river_cell(cell, rect)
		else:
			draw_rect(rect, color)

		if show_resource_overlay:
			_draw_resource_overlay(cell, rect)

		_draw_event_markers(cell, rect)

		draw_rect(rect, TerrainColors.GRID, false, 1.0)

		if selected_cell != null and cell.x == selected_cell.x and cell.y == selected_cell.y:
			draw_rect(rect, Color(1, 0, 0, 1), false, 2.0)

		var flash_entry: Dictionary = flashing_cells.get(Vector2i(cell.x, cell.y), {})
		var flash_time: float = flash_entry.get("remaining", -1.0)
		if flash_time > 0.0:
			var flash_color := COLOR_PAINT_FLASH
			flash_color.a = clamp(flash_time / float(flash_entry["duration"]), 0.0, 1.0)
			draw_rect(rect, flash_color, false, 3.0)

		# Vista "Mostra tutti" (highlight_group_territories): riempimento nel colore del gruppo
		# (già scelto dal chiamante, alpha propria) + bordo pieno nella stessa tinta per un
		# confine ben visibile — entrambi sfumano insieme col fade standard remaining/duration.
		var overlay_entry: Dictionary = _species_territory_overlay_cells.get(Vector2i(cell.x, cell.y), {})
		var overlay_time: float = overlay_entry.get("remaining", -1.0)
		if overlay_time > 0.0:
			var fade: float = clamp(overlay_time / float(overlay_entry["duration"]), 0.0, 1.0)
			var overlay_color: Color = overlay_entry["color"]
			overlay_color.a *= fade
			draw_rect(rect, overlay_color)
			draw_rect(rect, Color(overlay_color.r, overlay_color.g, overlay_color.b, fade), false, 2.0)

	_draw_species_territory_overlay_labels()


# Etichette ID (una per territorio evidenziato da highlight_group_territories), disegnate DOPO
# il ciclo principale sopra — sono poche (una per gruppo, non una per cella), non vale la pena
# infilarle nel ciclo delle 10000 celle. Alone scuro (4 offset diagonali) sotto il testo per
# restare leggibile sopra qualunque colore di territorio/terreno.
#
# Due tentativi precedenti (contro-scalare font_size in base allo zoom, sia via camera.zoom che
# via get_canvas_transform().get_scale()) erano entrambi strutturalmente sbagliati, non solo nel
# segno: draw_string rasterizza il glifo alla dimensione LOCALE passata, e SOLO DOPO il canvas
# transform (zoom) la ridimensiona per lo schermo — quindi qualunque font_size locale più
# piccolo (necessario per compensare uno zoom-in) produce un bitmap rasterizzato piccolo e poi
# STIRATO in ingrandimento, cioè sfocato, oltre a non annullarsi correttamente. L'unico modo di
# ottenere testo realmente a dimensione fissa E nitido è uscire dal sistema di coordinate
# locale/mondo per la durata di questo disegno: get_global_transform_with_canvas() è la
# trasformazione COMPLETA che il motore applica a questo canvas item per arrivare ai pixel finali
# di schermo (nodo + tutti gli antenati + camera/zoom inclusi); impostare draw_set_transform_
# matrix() alla sua INVERSA annulla quella trasformazione per i draw_string successivi, cosicché
# le coordinate passate a draw_string vengono interpretate come pixel-schermo VERI — a quel punto
# font_size può tornare una costante fissa (rasterizzato direttamente alla risoluzione finale,
# niente stiramento). Le posizioni-cella (in coordinate locali/mondo) vanno quindi convertite
# esplicitamente in pixel-schermo con la stessa trasformazione (ambient_transform * center) prima
# di calcolare text_pos — restare nel sistema locale qui produrrebbe etichette ancorate al punto
# schermo sbagliato. Trasformazione ripristinata all'identità in fondo (difensivo: questa è
# l'ultima chiamata di _draw(), ma non deve lasciare uno stato anomalo per eventuali disegni
# futuri aggiunti dopo di essa).
func _draw_species_territory_overlay_labels() -> void:
	if _species_territory_overlay_labels.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := SPECIES_OVERLAY_LABEL_SCREEN_FONT_SIZE
	var ambient_transform := get_global_transform_with_canvas()
	draw_set_transform_matrix(ambient_transform.affine_inverse())

	for label_entry in _species_territory_overlay_labels:
		var remaining: float = label_entry["remaining"]
		var duration: float = label_entry["duration"]
		if remaining <= 0.0:
			continue
		var fade: float = clamp(remaining / duration, 0.0, 1.0)
		var text: String = label_entry["text"]
		var cell: Vector2i = label_entry["cell"]
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var world_center := Vector2(
			cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0
		)
		var center: Vector2 = ambient_transform * world_center
		var text_pos := center - text_size / 2.0 + Vector2(0.0, text_size.y * 0.35)

		var outline_color := COLOR_SPECIES_OVERLAY_LABEL_OUTLINE
		outline_color.a *= fade
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(
				font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color
			)

		var label_color := COLOR_SPECIES_OVERLAY_LABEL
		label_color.a *= fade
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)

	draw_set_transform_matrix(Transform2D.IDENTITY)


const COLOR_STONE_OVERLAY := Color(0.35, 0.35, 0.35, 0.85)
const COLOR_TREE_OVERLAY := Color(0.10, 0.45, 0.15, 0.85)
const COLOR_GRASS_OVERLAY := Color(0.85, 0.75, 0.20, 0.85)
const COLOR_SHRUB_OVERLAY := Color(0.45, 0.60, 0.15, 0.85)

const RESOURCE_ROW_TYPES := [
	GameTypes.WorldObjectType.ROCK,
	GameTypes.WorldObjectType.TREE,
	GameTypes.WorldObjectType.SHRUB,
	GameTypes.WorldObjectType.GRASS,
]

const RESOURCE_ROW_COLORS := {
	GameTypes.WorldObjectType.ROCK: COLOR_STONE_OVERLAY,
	GameTypes.WorldObjectType.TREE: COLOR_TREE_OVERLAY,
	GameTypes.WorldObjectType.GRASS: COLOR_GRASS_OVERLAY,
	GameTypes.WorldObjectType.SHRUB: COLOR_SHRUB_OVERLAY,
}


func _draw_resource_overlay(cell: MacroCellData, rect: Rect2) -> void:
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return

	var border: float = 1.0
	var inner_size: float = rect.size.x - border * 2.0
	if inner_size <= 0:
		return

	var row_height: float = inner_size / RESOURCE_ROW_TYPES.size()

	for i in range(RESOURCE_ROW_TYPES.size()):
		var resource_type: GameTypes.WorldObjectType = RESOURCE_ROW_TYPES[i]
		var row_y: float = rect.position.y + border + row_height * i
		var row_rect := Rect2(rect.position.x + border, row_y, inner_size, row_height)

		var space: int = state.get_dedicated_space(resource_type)
		if space <= 0:
			continue

		var proportion: float = clamp(float(space) / float(MacroCellState.TOTAL_SPACE), 0.0, 1.0)
		var width: float = max(1.0, row_rect.size.x * proportion)

		draw_rect(Rect2(row_rect.position.x, row_rect.position.y, width, row_rect.size.y), RESOURCE_ROW_COLORS[resource_type])

func _draw_event_markers(cell: MacroCellData, rect: Rect2) -> void:
	if game_data == null:
		return
	var state: MacroCellState = world.get_cell_state_at(cell.x, cell.y)
	if state == null:
		return

	var current_absolute_day := game_data.get_absolute_day()
	for event_type in RENDERED_EVENT_TYPES:
		if not state.is_event_bonus_visible(event_type, current_absolute_day):
			continue

		var is_fresh: bool = state.is_event_bonus_fresh(event_type, current_absolute_day)

		match event_type:
			GameTypes.NaturalEventType.DROUGHT:
				var color: Color = COLOR_DROUGHT_MARKER_FRESH if is_fresh else COLOR_DROUGHT_MARKER_RECOVERING
				_draw_circle_mark(rect, color)
			GameTypes.NaturalEventType.SEA_FLOOD:
				var color: Color = COLOR_SEA_FLOOD_MARKER_FRESH if is_fresh else COLOR_SEA_FLOOD_MARKER_RECOVERING
				_draw_square_mark(rect, color)
			_:
				var color: Color = COLOR_EVENT_MARKER_FRESH if is_fresh else COLOR_EVENT_MARKER_RECOVERING
				_draw_x_mark(rect, color)


func _draw_x_mark(rect: Rect2, color: Color) -> void:
	var margin: float = rect.size.x * 0.15
	var top_left := rect.position + Vector2(margin, margin)
	var top_right := rect.position + Vector2(rect.size.x - margin, margin)
	var bottom_left := rect.position + Vector2(margin, rect.size.y - margin)
	var bottom_right := rect.position + Vector2(rect.size.x - margin, rect.size.y - margin)

	draw_line(top_left, bottom_right, color, 2.0)
	draw_line(top_right, bottom_left, color, 2.0)


func _draw_circle_mark(rect: Rect2, color: Color) -> void:
	var center := rect.position + rect.size / 2.0
	var radius: float = rect.size.x * 0.35
	draw_arc(center, radius, 0.0, TAU, 16, color, 2.0)


func _draw_square_mark(rect: Rect2, color: Color) -> void:
	var margin: float = rect.size.x * 0.2
	var inner := Rect2(rect.position + Vector2(margin, margin), rect.size - Vector2(margin, margin) * 2.0)
	draw_rect(inner, color, false, 2.0)


func get_cell_color(cell: MacroCellData) -> Color:
	return TerrainColors.get_cell_color(cell)


func _draw_river_cell(cell: MacroCellData, rect: Rect2) -> void:
	draw_rect(rect, TerrainColors.PLAIN)

	var center_x: float = rect.position.x + rect.size.x / 2.0
	var center_y: float = rect.position.y + rect.size.y / 2.0
	var thickness: float = rect.size.x * 0.45

	match cell.river_shape:
		GameTypes.RiverShape.VERTICAL:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y), TerrainColors.RIVER)

		GameTypes.RiverShape.HORIZONTAL:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_TOP_RIGHT:
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_RIGHT_BOTTOM:
			draw_rect(Rect2(center_x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_BOTTOM_LEFT:
			draw_rect(Rect2(center_x - thickness / 2.0, center_y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.CORNER_LEFT_TOP:
			draw_rect(Rect2(rect.position.x, center_y - thickness / 2.0, rect.size.x / 2.0, thickness), TerrainColors.RIVER)
			draw_rect(Rect2(center_x - thickness / 2.0, rect.position.y, thickness, rect.size.y / 2.0), TerrainColors.RIVER)
			
		GameTypes.RiverShape.FULL:
			draw_rect(rect, TerrainColors.RIVER)

		_:
			draw_rect(rect, TerrainColors.RIVER)
			
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos: Vector2 = get_local_mouse_position()

			var cell_x: int = int(mouse_pos.x / CELL_SIZE)
			var cell_y: int = int(mouse_pos.y / CELL_SIZE)

			var cell := _get_cell_at(cell_x, cell_y)

			#if cell != null:
				#print(
				#	"Cella x=", cell.x,
				#	" y=", cell.y,
				#	" terrain_base=", cell.terrain_base,
				#	" water_type=", cell.water_type,
				#	" river_shape=", cell.river_shape,
				#	" coast_type=", cell.coast_type,
				#	" biome=", cell.biome
				#)


func _get_cell_at(x: int, y: int) -> MacroCellData:
	if world == null:
		return null

	for cell in world.cells:
		if cell.x == x and cell.y == y:
			return cell

	return null
