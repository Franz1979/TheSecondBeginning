class_name InfluenceLayerOverlay
extends Node2D

# Overlay dei layer di influenza (2026-10-02, richiesta utente — voci cultural_influence/political_influence/
# religious_influence di MapLayerRegistry): un solo script, parametrizzato da `influence_type` (impostato dal registro,
# "overlay_params"). Per ogni edificio con InfluenceService.get_effective_radius(edificio, influence_type) > 0 disegna
# lo stesso cerchio del bottone "Mostra influenza" (InfluenceFootprintOverlay.draw_influence_circle), senza
# dissolvenza. Stesso contratto show_cell/get_cell di WorkAreaOverlay: figlio del container della macrocella mostrata,
# coordinate locali.
#
# Edifici di TUTTE le macrocelle il cui cerchio tocca quella mostrata (non solo quelli della cella stessa): un cerchio
# che sconfina da una macrocella vicina si vede. get_effective_radius esclude già cantieri e edifici demoliti.
#
# Ridisegno solo quando cambia GameData.buildings_revision (GameScene._refresh_building_slots_buildable: caricamento,
# piazzamento, completamento, demolizione) o la cella mostrata — in _process si confronta solo un intero.

var influence_type: InfluenceService.InfluenceType = InfluenceService.InfluenceType.POLITICAL

var _cell: LiveMacroCell = null
var _drawn_revision: int = -1


func show_cell(cell: LiveMacroCell) -> void:
	_cell = cell
	_drawn_revision = -1
	queue_redraw()


func get_cell() -> LiveMacroCell:
	return _cell


func _process(_delta: float) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if _cell == null or game_data == null:
		return
	if game_data.buildings_revision != _drawn_revision:
		queue_redraw()


func _draw() -> void:
	var game_data: GameData = GameSettings.active_game_data
	var world: World = GameSettings.active_world
	if _cell == null or game_data == null or world == null:
		return
	_drawn_revision = game_data.buildings_revision
	var origin := Vector2i(_cell.macro_x, _cell.macro_y)
	var cell_px := float(World.WIDTH * MicroCellRenderer.CELL_SIZE)
	var cell_rect := Rect2(Vector2.ZERO, Vector2(cell_px, cell_px))
	for building in world.buildings:
		var radius := InfluenceFootprintOverlay.radius_px(building, influence_type)
		if radius <= 0.0:
			continue
		var center := InfluenceFootprintOverlay.building_center_px(building, origin)
		# Solo i cerchi che toccano la macrocella mostrata: distanza dal centro al punto più vicino del rettangolo.
		var nearest := Vector2(clampf(center.x, cell_rect.position.x, cell_rect.end.x), clampf(center.y, cell_rect.position.y, cell_rect.end.y))
		if center.distance_to(nearest) > radius:
			continue
		InfluenceFootprintOverlay.draw_influence_circle(self, center, radius, influence_type)
