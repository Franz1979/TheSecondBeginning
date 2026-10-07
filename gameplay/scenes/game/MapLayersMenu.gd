class_name MapLayersMenu
extends PanelContainer

# Menu a tendina dei layer della mappa (2026-09-27, richiesta utente — rifatto come pannello normale: prima era un
# PopupMenu, cioè una finestra separata con il tema e le misure di default di Godot, enorme e sfocato rispetto al
# resto dell'interfaccia). Un PanelContainer nel CanvasLayer dell'interfaccia, accanto al pannello laterale: stesso
# tema, righe compatte, testo 10 px come le etichette del pannello. Muto: mostra le voci di MapLayerRegistry ("Nessuno"
# in testa) e segnala la scelta; chi decide cosa accendere è GameScene.
#
# Uno alla volta: la voce attiva è evidenziata. Le voci non disponibili sono in grigio, non cliccabili, con il tooltip
# "In arrivo". Si chiude scegliendo una voce o con un clic fuori dal pannello (consumato, come un menu a tendina).

signal layer_chosen(layer_id: String)

const ROW_HEIGHT: float = 20.0
const FONT_SIZE: int = 10
const MENU_WIDTH: float = 190.0
const ACTIVE_ROW_COLOR := Color(0.95, 0.78, 0.2, 0.35)

var _rows: VBoxContainer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 4)
	add_child(margin)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	margin.add_child(_rows)


# Ricostruisce le voci (lingua e layer attivo del momento) e mostra il pannello sotto `anchor_rect` (rettangolo del
# bottone, coordinate del CanvasLayer), dentro `bounds` (il pannello laterale) e dentro lo schermo.
func open(active_layer_id: String, anchor_rect: Rect2, bounds: Rect2, panel_style: StyleBox) -> void:
	if panel_style != null:
		add_theme_stylebox_override("panel", panel_style)
	for child in _rows.get_children():
		child.queue_free()
	_rows.add_child(_build_row(MapLayerRegistry.NONE_ID, tr("map_layer_none"), active_layer_id == MapLayerRegistry.NONE_ID, true))
	for layer in MapLayerRegistry.LAYERS:
		var label := "%s  %s" % [String(layer["icon"]), tr(String(layer["name_key"]))]
		_rows.add_child(_build_row(String(layer["id"]), label, active_layer_id == String(layer["id"]), bool(layer["available"])))
	visible = true
	reset_size()
	var menu_size := get_combined_minimum_size()
	var viewport_size := get_viewport_rect().size
	var x: float = anchor_rect.position.x
	x = minf(x, bounds.end.x - menu_size.x)
	x = maxf(x, bounds.position.x)
	x = clampf(x, 0.0, maxf(viewport_size.x - menu_size.x, 0.0))
	var y: float = anchor_rect.end.y + 2.0
	# Bottone in fondo al pannello (2026-10-07, barra in basso dell'info panel): senza posto sotto si apre sopra.
	if y + menu_size.y > viewport_size.y:
		y = anchor_rect.position.y - menu_size.y - 2.0
	y = clampf(y, 0.0, maxf(viewport_size.y - menu_size.y, 0.0))
	position = Vector2(x, y)
	size = menu_size


func close() -> void:
	visible = false


# Clic fuori dal pannello mentre è aperto: si chiude e il clic non arriva alla mappa.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and not get_global_rect().has_point(event.position):
		close()
		get_viewport().set_input_as_handled()


func _build_row(layer_id: String, text: String, is_active: bool, is_available: bool) -> Control:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	if is_active:
		var active_style := StyleBoxFlat.new()
		active_style.bg_color = ACTIVE_ROW_COLOR
		active_style.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", active_style)
		button.add_theme_stylebox_override("hover", active_style)
	if not is_available:
		button.disabled = true
		button.tooltip_text = tr("map_layer_coming_soon")
		# Il tooltip deve comparire anche sul bottone disabilitato.
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		return button
	button.pressed.connect(func() -> void:
		close()
		layer_chosen.emit(layer_id)
	)
	return button
