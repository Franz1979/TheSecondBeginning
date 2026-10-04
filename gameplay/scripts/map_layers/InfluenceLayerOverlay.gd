class_name InfluenceLayerOverlay
extends Node2D

# Overlay dei layer di influenza (2026-10-02, richiesta utente — voci cultural_influence/political_influence/
# religious_influence di MapLayerRegistry): un solo script, parametrizzato da `influence_type` (impostato dal registro,
# "overlay_params"). Stesso contratto show_cell/get_cell di WorkAreaOverlay: figlio del container della macrocella
# mostrata, coordinate locali. Un solo layer è attivo alla volta, quindi tipi diversi restano aree distinte, ognuna con
# il suo colore (InfluenceFootprintOverlay.COLORS).
#
# AREA UNICA (2026-10-04, richiesta utente — prima un cerchio per edificio, con la zona comune più scura e gli archi di
# contorno anche all'interno): i cerchi di tutti gli edifici con InfluenceService.get_effective_radius > 0 si disegnano
# come un'unica area.
#   - Riempimento: i cerchi si disegnano OPACHI dentro un CanvasGroup (_fill_group), che compone il risultato con una
#     sola trasparenza (self_modulate, InfluenceFootprintOverlay.FILL_ALPHA): colore e trasparenza uniformi anche dove
#     i raggi si sovrappongono, comprese eventuali "isole" vuote al centro di un anello di cerchi.
#   - Contorno: per ogni cerchio, solo i tratti che non cadono dentro un altro cerchio (punto medio del tratto fuori da
#     tutti gli altri): il bordo dell'unione, nessun arco all'interno. Stesso colore e spessore del cerchio singolo.
# Il cerchio del singolo edificio (bottone "Mostra influenza", InfluenceFootprintOverlay) non cambia.
#
# Edifici di TUTTE le macrocelle il cui cerchio tocca quella mostrata (non solo quelli della cella stessa): un cerchio
# che sconfina da una macrocella vicina si vede. get_effective_radius esclude già cantieri e edifici demoliti.
#
# Ricalcolo solo quando cambia GameData.buildings_revision (GameScene._refresh_building_slots_buildable: caricamento,
# piazzamento, completamento, demolizione) o la cella mostrata — in _process si confronta solo un intero.

var influence_type: InfluenceService.InfluenceType = InfluenceService.InfluenceType.POLITICAL

var _cell: LiveMacroCell = null
var _drawn_revision: int = -1
# Cerchi correnti: [centro (px locali), raggio (px)].
var _circles: Array = []
var _fill_group: CanvasGroup = null
var _fill_drawer: Node2D = null
var _outline_drawer: Node2D = null


func _ready() -> void:
	_ensure_drawers()


func _ensure_drawers() -> void:
	if _fill_group != null:
		return
	_fill_group = CanvasGroup.new()
	_fill_group.self_modulate = Color(1.0, 1.0, 1.0, InfluenceFootprintOverlay.FILL_ALPHA)
	add_child(_fill_group)
	_fill_drawer = Node2D.new()
	_fill_drawer.draw.connect(_draw_fill)
	_fill_group.add_child(_fill_drawer)
	_outline_drawer = Node2D.new()
	_outline_drawer.draw.connect(_draw_outline)
	add_child(_outline_drawer)


func show_cell(cell: LiveMacroCell) -> void:
	_cell = cell
	_drawn_revision = -1
	_ensure_drawers()
	_refresh()


func get_cell() -> LiveMacroCell:
	return _cell


func _process(_delta: float) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if _cell == null or game_data == null:
		return
	if game_data.buildings_revision != _drawn_revision:
		_refresh()


func _refresh() -> void:
	var game_data: GameData = GameSettings.active_game_data
	var world: World = GameSettings.active_world
	_circles.clear()
	if _cell != null and game_data != null and world != null:
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
			_circles.append([center, radius])
	if _fill_drawer != null:
		_fill_drawer.queue_redraw()
		_outline_drawer.queue_redraw()


func _color() -> Color:
	return InfluenceFootprintOverlay.COLORS.get(influence_type, Color.WHITE)


# Cerchi opachi: la trasparenza la applica il CanvasGroup una volta sola sull'insieme.
func _draw_fill() -> void:
	var color := _color()
	for circle in _circles:
		_fill_drawer.draw_circle(circle[0], circle[1], Color(color.r, color.g, color.b, 1.0))


# Bordo dell'unione: per ogni cerchio, i tratti (CIRCLE_POINTS per giro) il cui punto medio non è dentro un altro
# cerchio, uniti in polilinee consecutive.
func _draw_outline() -> void:
	var color := _color()
	var points_per_circle: int = InfluenceFootprintOverlay.CIRCLE_POINTS
	for i in range(_circles.size()):
		var center: Vector2 = _circles[i][0]
		var radius: float = _circles[i][1]
		var run := PackedVector2Array()
		var runs: Array[PackedVector2Array] = []
		for k in range(points_per_circle):
			var angle_a: float = TAU * float(k) / float(points_per_circle)
			var angle_b: float = TAU * float(k + 1) / float(points_per_circle)
			var mid := center + Vector2.from_angle((angle_a + angle_b) * 0.5) * radius
			if _is_inside_other(mid, i):
				if run.size() >= 2:
					runs.append(run)
				run = PackedVector2Array()
				continue
			if run.is_empty():
				run.append(center + Vector2.from_angle(angle_a) * radius)
			run.append(center + Vector2.from_angle(angle_b) * radius)
		if run.size() >= 2:
			# Un tratto che chiude il giro si salda al primo, se il primo parte dall'angolo 0.
			if not runs.is_empty() and runs[0][0].is_equal_approx(run[run.size() - 1]):
				run.append_array(runs[0].slice(1))
				runs[0] = run
			else:
				runs.append(run)
		for polyline in runs:
			_outline_drawer.draw_polyline(polyline, color, InfluenceFootprintOverlay.BORDER_WIDTH, true)


func _is_inside_other(point: Vector2, own_index: int) -> bool:
	for j in range(_circles.size()):
		if j == own_index:
			continue
		var other_center: Vector2 = _circles[j][0]
		var other_radius: float = _circles[j][1]
		if point.distance_squared_to(other_center) < other_radius * other_radius:
			return true
	return false
