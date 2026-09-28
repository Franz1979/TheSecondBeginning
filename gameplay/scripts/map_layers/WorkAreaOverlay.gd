class_name WorkAreaOverlay
extends Node2D

# Overlay del layer "Aree di lavoro" (2026-09-27, richiesta utente — work areas, passo 1a; voce di MapLayerRegistry):
# le zone della macrocella mostrata, con riempimento leggero e bordo nel colore della zona. Figlio del container della
# cella, coordinate locali. Il rettangolo si ridisegna da sé quando le zone cambiano (GameData.work_areas_revision) —
# stesso contratto show_cell/get_cell di PathfindingDebugOverlay.
#
# Il nome della zona non è più disegnato qui (2026-09-27, era sfocato: draw_string nella mappa viene ingrandito dallo
# zoom della camera): è un'etichetta in spazio schermo (MapScreenLabels) sull'angolo in alto a sinistra della zona,
# aggiornata a ogni frame. Esiste solo con l'overlay, quindi solo con il layer attivo.

const FILL_ALPHA: float = 0.18
const BORDER_WIDTH: float = 1.5
# Bordo della zona selezionata (2026-09-27, selezione delle zone).
const SELECTED_BORDER_WIDTH: float = 4.0

# Id della zona selezionata, -1 = nessuna (scritto da GameScene alla selezione): bordo più spesso.
static var selected_area_id: int = -1
# Scelta manuale della zona per la raccolta (2026-09-27, work areas passo 3b): finché pick_mode è attivo si disegnano
# solo le zone in pick_area_ids (valide per il filtro scelto), evidenziate. Scritti da GameScene.
static var pick_mode: bool = false
static var pick_area_ids: Array[int] = []
const PICK_FILL_ALPHA: float = 0.38
const PICK_BORDER_WIDTH: float = 3.0

# true = disegna solo la zona selezionata (2026-09-27): usato da GameScene per tenerla visibile a layer spento.
var only_selected: bool = false

var _cell: LiveMacroCell = null
var _drawn_revision: int = -1
var _drawn_selected_id: int = -1
var _drawn_pick_signature: String = ""
var _screen_labels: MapScreenLabels = null


func _ready() -> void:
	_screen_labels = MapScreenLabels.new(self)
	add_child(_screen_labels)


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
	if game_data.work_areas_revision != _drawn_revision or selected_area_id != _drawn_selected_id or _pick_signature() != _drawn_pick_signature:
		queue_redraw()
	# Nomi in spazio schermo: seguono la camera a ogni frame.
	var items: Array = []
	for area in _areas_to_draw(game_data):
		items.append({"text": area.name, "rect": rect_to_pixels(area.rect)})
	_screen_labels.update_labels(items)


func _draw() -> void:
	var game_data: GameData = GameSettings.active_game_data
	if _cell == null or game_data == null:
		return
	_drawn_revision = game_data.work_areas_revision
	_drawn_selected_id = selected_area_id
	_drawn_pick_signature = _pick_signature()
	for area in _areas_to_draw(game_data):
		if pick_mode:
			draw_work_area_rect(self, area.rect, area.color, PICK_BORDER_WIDTH, PICK_FILL_ALPHA)
		else:
			draw_work_area_rect(self, area.rect, area.color, SELECTED_BORDER_WIDTH if area.id == selected_area_id else BORDER_WIDTH)


func _pick_signature() -> String:
	return str(pick_area_ids) if pick_mode else ""


func _areas_to_draw(game_data: GameData) -> Array[WorkArea]:
	var areas := WorkAreaService.find_in_macro_cell(game_data, Vector2i(_cell.macro_x, _cell.macro_y))
	if not only_selected and not pick_mode:
		return areas
	var selected: Array[WorkArea] = []
	for area in areas:
		if pick_mode:
			# In scelta manuale l'overlay della sola zona selezionata non disegna nulla: vale quello del layer.
			if not only_selected and pick_area_ids.has(area.id):
				selected.append(area)
		elif area.id == selected_area_id:
			selected.append(area)
	return selected


# Rettangolo di una zona (microcelle locali) in pixel locali della cella.
static func rect_to_pixels(rect: Rect2i) -> Rect2:
	var cell_size := float(MicroCellRenderer.CELL_SIZE)
	return Rect2(Vector2(rect.position) * cell_size, Vector2(rect.size) * cell_size)


# Disegno di una zona (condiviso con l'anteprima del trascinamento, WorkAreaDragPreview): riempimento e bordo. Le scritte
# sono etichette in spazio schermo (MapScreenLabels), non disegnate qui.
static func draw_work_area_rect(
	canvas: CanvasItem, rect: Rect2i, color: Color, border_width: float = BORDER_WIDTH, fill_alpha: float = FILL_ALPHA
) -> void:
	var pixel_rect := rect_to_pixels(rect)
	var fill := color
	fill.a = fill_alpha
	canvas.draw_rect(pixel_rect, fill)
	canvas.draw_rect(pixel_rect, color, false, border_width)
