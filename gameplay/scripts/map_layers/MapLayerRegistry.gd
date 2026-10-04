class_name MapLayerRegistry
extends RefCounted

# Registro dei layer della mappa (2026-09-27, richiesta utente — menu "Layer" della barra in alto). Un solo layer
# attivo alla volta (o nessuno); GameScene legge da qui cosa mostrare nel menu, cosa disegnare sulla macrocella
# corrente e cosa sulla minimappa. Aggiungere un layer = aggiungere una voce a LAYERS (più, se disponibile, il suo
# overlay e/o la sua funzione per la minimappa), nessun'altra modifica a GameScene o al menu.
#
# Ogni voce:
#   - "id": identificatore stabile (String);
#   - "name_key": chiave tr() del nome nel menu;
#   - "icon": emoji mostrata davanti al nome nel menu;
#   - "available": false = segnaposto, in grigio nel menu con il tooltip "In arrivo" (map_layer_coming_soon);
#   - "map_overlay": script di un Node2D disegnato sulla macrocella corrente, figlio del suo container, con
#     show_cell(cell: LiveMacroCell) e get_cell() -> LiveMacroCell (null = nessun disegno sulla mappa);
#   - "overlay_params" (opzionale): {proprietà: valore} assegnati all'overlay appena creato, prima che entri
#     nell'albero — un solo script per più layer (es. InfluenceLayerOverlay.influence_type);
#   - "minimap_method": nome di un metodo di QUESTA classe che disegna il layer sulla minimappa, firma
#     (canvas: Control, cell_px: float, world: World, visible_cells: Dictionary) ("" = nessun disegno).

const NONE_ID := ""

const LAYERS: Array[Dictionary] = [
	{
		"id": "walkability", "name_key": "map_layer_walkability", "icon": "🚧", "available": true,
		# Stesso disegno del vecchio overlay di debug del tasto N (tolto il 2026-10-04) (microcelle bloccate della griglia del pathfinding).
		"map_overlay": preload("res://gameplay/scripts/entities/PathfindingDebugOverlay.gd"),
		"minimap_method": "_draw_walkability_minimap",
	},
	{
		"id": "work_areas", "name_key": "map_layer_work_areas", "icon": "🛠", "available": true,
		# Zone di lavoro (2026-09-27, work areas passo 1a): rettangoli colorati con il nome, vedi WorkAreaOverlay.
		"map_overlay": preload("res://gameplay/scripts/map_layers/WorkAreaOverlay.gd"),
		"minimap_method": "_draw_work_areas_minimap",
	},
	{"id": "territory", "name_key": "map_layer_territory", "icon": "🚩", "available": false, "map_overlay": null, "minimap_method": ""},
	{"id": "known_zone", "name_key": "map_layer_known_zone", "icon": "👁", "available": false, "map_overlay": null, "minimap_method": ""},
	{"id": "resources", "name_key": "map_layer_resources", "icon": "🪨", "available": false, "map_overlay": null, "minimap_method": ""},
	{"id": "fauna", "name_key": "map_layer_fauna", "icon": "🦌", "available": false, "map_overlay": null, "minimap_method": ""},
	# Layer di influenza (2026-10-02): un solo overlay (InfluenceLayerOverlay) parametrizzato dal tipo. Niente minimappa.
	{
		"id": "cultural_influence", "name_key": "map_layer_cultural_influence", "icon": "🎭", "available": true,
		"map_overlay": preload("res://gameplay/scripts/map_layers/InfluenceLayerOverlay.gd"),
		"overlay_params": {"influence_type": InfluenceService.InfluenceType.CULTURAL},
		"minimap_method": "",
	},
	{
		"id": "political_influence", "name_key": "map_layer_political_influence", "icon": "👑", "available": true,
		"map_overlay": preload("res://gameplay/scripts/map_layers/InfluenceLayerOverlay.gd"),
		"overlay_params": {"influence_type": InfluenceService.InfluenceType.POLITICAL},
		"minimap_method": "",
	},
	{
		"id": "religious_influence", "name_key": "map_layer_religious_influence", "icon": "🌙", "available": true,
		"map_overlay": preload("res://gameplay/scripts/map_layers/InfluenceLayerOverlay.gd"),
		"overlay_params": {"influence_type": InfluenceService.InfluenceType.RELIGIOUS},
		"minimap_method": "",
	},
]

# Colore delle macrocelle non percorribili (acqua) sulla minimappa, layer Percorribilità — stesso rosso
# dell'overlay sulla mappa (PathfindingDebugOverlay.BLOCKED_COLOR).
const WALKABILITY_MINIMAP_BLOCKED_COLOR := Color(1.0, 0.0, 0.0, 0.45)


# Voce del registro con questo id, {} se non esiste.
static func get_layer(layer_id: String) -> Dictionary:
	for layer in LAYERS:
		if String(layer["id"]) == layer_id:
			return layer
	return {}


static func is_available(layer_id: String) -> bool:
	return bool(get_layer(layer_id).get("available", false))


# Id dei layer disponibili, nell'ordine del registro, preceduti da NONE_ID ("Nessuno"): l'ordine del tasto L.
static func get_cycle_ids() -> Array[String]:
	var ids: Array[String] = [NONE_ID]
	for layer in LAYERS:
		if bool(layer["available"]):
			ids.append(String(layer["id"]))
	return ids


# Nuovo overlay per la mappa del layer (non ancora aggiunto all'albero), null se il layer non ne ha.
static func create_map_overlay(layer_id: String) -> Node2D:
	var layer := get_layer(layer_id)
	var overlay_script: Variant = layer.get("map_overlay", null)
	if overlay_script == null:
		return null
	var overlay := (overlay_script as Script).new() as Node2D
	var params: Dictionary = layer.get("overlay_params", {})
	for property_name in params.keys():
		overlay.set(property_name, params[property_name])
	return overlay


# true se il layer disegna qualcosa sulla minimappa.
static func has_minimap_drawing(layer_id: String) -> bool:
	return String(get_layer(layer_id).get("minimap_method", "")) != ""


# Disegna il layer sulla minimappa (vedi "minimap_method" sopra). No-op se il layer non ne ha.
static func draw_minimap(layer_id: String, canvas: Control, cell_px: float, world: World, visible_cells: Dictionary) -> void:
	var method := String(get_layer(layer_id).get("minimap_method", ""))
	if method == "":
		return
	_dispatcher().call(method, canvas, cell_px, world, visible_cells)


# Istanza usata solo per invocare per nome i metodi di disegno (stesso schema di DepositStorageIcons).
static var _dispatcher_instance: MapLayerRegistry = null


static func _dispatcher() -> MapLayerRegistry:
	if _dispatcher_instance == null:
		_dispatcher_instance = MapLayerRegistry.new()
	return _dispatcher_instance


# Aree di lavoro sulla minimappa (2026-09-27): le macrocelle che contengono almeno una zona, nel colore della prima
# zona, tra quelle visibili.
const WORK_AREAS_MINIMAP_ALPHA: float = 0.6

static func _draw_work_areas_minimap(canvas: Control, cell_px: float, world: World, visible_cells: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	var drawn: Dictionary = {}
	for area in game_data.work_areas:
		if drawn.has(area.macro_coords) or not visible_cells.has(area.macro_coords):
			continue
		drawn[area.macro_coords] = true
		var color := area.color
		color.a = WORK_AREAS_MINIMAP_ALPHA
		canvas.draw_rect(Rect2(Vector2(area.macro_coords) * cell_px, Vector2(cell_px, cell_px)), color)


# Percorribilità sulla minimappa: in rosso le macrocelle d'acqua (non percorribili), solo tra quelle visibili — le
# celle nere (non ancora esplorate) restano nere.
static func _draw_walkability_minimap(canvas: Control, cell_px: float, world: World, visible_cells: Dictionary) -> void:
	if world == null:
		return
	for coords in visible_cells.keys():
		var cell := world.get_cell_at(coords.x, coords.y)
		if cell != null and cell.terrain_base == GameTypes.TerrainBase.WATER:
			canvas.draw_rect(Rect2(Vector2(coords) * cell_px, Vector2(cell_px, cell_px)), WALKABILITY_MINIMAP_BLOCKED_COLOR)
