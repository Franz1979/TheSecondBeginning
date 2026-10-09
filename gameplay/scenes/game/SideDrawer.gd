class_name SideDrawer
extends PanelContainer

# Cassetto laterale (2026-10-07, richiesta utente): pannello affiancato al fianco sinistro della sidebar, alto quanto
# l'info panel (stesso bordo superiore e inferiore) e largo WIDTH fissi. Contenitore generico: mostra UN contenuto alla
# volta (oggi "Assegnazione delle task", TaskAssignmentPanel; in futuro la gestione dei magazzini), con il suo titolo e
# una X. Non mette in pausa il gioco né blocca il resto dell'interfaccia; i clic sopra di lui non arrivano alla mappa
# (MOUSE_FILTER_STOP). Posizione e dimensione le decide GameScene (place), come lo stile (set_styles).
# Struttura come l'info panel (2026-10-07): cornice sottile azzurra (lo stile della sidebar, sul cassetto stesso) con
# titolo e X nella fascia in alto, poi l'area interna scura (lo stile del pannello dell'info panel) col contenuto.
# Costruito in codice, figlio del CanvasLayer di GameScene: fuori dalla sidebar, non può allargarla.

# Correzione manuale (px, + = più in basso) sommata alla y misurata in align_top_to: per uno scarto residuo.
const TOP_ALIGN_OFFSET_PX := 0

# Contenuto chiuso (X o di nuovo il suo bottone): GameScene spegne l'evidenziazione del bottone.
signal closed(content_id: StringName)
# Bottone della posizione nella barra del titolo (2026-10-09, richiesta utente): il giocatore chiede di passare da
# "Affiancato" a "Sopra" o viceversa (`overlay` = la modalità nuova). GameScene la salva (UserOptions.side_drawer_overlay)
# e rifà place; il bottone si aggiorna con set_overlay_mode.
signal overlay_mode_requested(overlay: bool)
# Icone del bottone: la modalità in cui si passa con un clic.
const OVERLAY_ICON := "⇥"
const SIDE_ICON := "⇤"

const WIDTH: float = 380.0
const TITLE_FONT_SIZE: int = 13

var _title_label: Label = null
var _content_holder: VBoxContainer = null
var _content_panel: PanelContainer = null
var _frame_margin: MarginContainer = null
var _frame_box: VBoxContainer = null
var _header: HBoxContainer = null
# Margine della cornice attorno a fascia del titolo e area scura: quello della sidebar attorno all'info panel.
const FRAME_MARGIN: int = 10
var _content_id: StringName = &""
# Ultimo allineamento chiesto (place): ripetuto quando align_top_to ha misurato il bordo superiore vero.
var _alignment: Dictionary = {}
# Bordo superiore del cassetto misurato da align_top_to (coordinate del CanvasLayer); finché manca, place lo stima.
var _measured_top: float = 0.0
var _has_measured_top: bool = false
# Modalità di posizione mostrata dal bottone (set_overlay_mode): false = "Affiancato", true = "Sopra".
var _overlay_mode: bool = false
var _mode_button: Button = null


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Aperto copre il bordo destro della mappa: lo scorrimento col mouse al bordo destro va lungo il suo fianco sinistro
	# (CameraController._get_map_rect, 2026-10-07).
	# Stesso nome di CameraController.RIGHT_EDGE_COVER_GROUP (lo script della camera non ha class_name).
	add_to_group(&"camera_right_edge_cover")


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, FRAME_MARGIN)
	add_child(margin)
	_frame_margin = margin
	var box := VBoxContainer.new()
	margin.add_child(box)
	_frame_box = box
	var header := HBoxContainer.new()
	box.add_child(header)
	_header = header
	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title_label)
	# Posizione del cassetto (2026-10-09): Affiancato <-> Sopra, accanto alla X.
	_mode_button = Button.new()
	_mode_button.flat = true
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode_button.pressed.connect(func() -> void: overlay_mode_requested.emit(not _overlay_mode))
	header.add_child(_mode_button)
	_apply_mode_button()
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# Area interna scura, come quella dell'info panel.
	_content_panel = PanelContainer.new()
	_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_content_panel)
	var content_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		content_margin.add_theme_constant_override(side, 6)
	_content_panel.add_child(content_margin)
	_content_holder = VBoxContainer.new()
	_content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(_content_holder)


# `frame`: cornice e fascia del titolo (lo stile della sidebar); `content`: l'area interna (lo stile del pannello
# dell'info panel). La cornice riceve un bordo scuro sul lato destro, lo stacco netto dalla sidebar accanto.
const SEPARATION_BORDER_WIDTH: int = 2
const SEPARATION_BORDER_COLOR := Color(0.06, 0.1, 0.16, 1.0)


func set_styles(frame: StyleBox, content: StyleBox) -> void:
	if frame != null:
		var frame_style := frame.duplicate() as StyleBox
		if frame_style is StyleBoxFlat:
			(frame_style as StyleBoxFlat).border_width_right = SEPARATION_BORDER_WIDTH
			(frame_style as StyleBoxFlat).border_color = SEPARATION_BORDER_COLOR
		add_theme_stylebox_override("panel", frame_style)
	if content != null and _content_panel != null:
		_content_panel.add_theme_stylebox_override("panel", content)


# Mostra `content` (sostituisce quello di prima, liberandolo) con il suo titolo.
func show_content(content_id: StringName, title: String, content: Control) -> void:
	if _content_id != content_id:
		var previous := _content_id
		_clear_content()
		_content_holder.add_child(content)
		_content_id = content_id
		if previous != &"":
			closed.emit(previous)
	elif content != null and content.get_parent() == null:
		content.queue_free()
	_title_label.text = title
	visible = true


# Modalità di posizione mostrata dal bottone (la posizione vera la decide GameScene con place).
func set_overlay_mode(overlay: bool) -> void:
	_overlay_mode = overlay
	_apply_mode_button()


func _apply_mode_button() -> void:
	if _mode_button == null:
		return
	_mode_button.text = SIDE_ICON if _overlay_mode else OVERLAY_ICON
	_mode_button.tooltip_text = tr("side_drawer_mode_side_tooltip") if _overlay_mode else tr("side_drawer_mode_overlay_tooltip")


func close() -> void:
	if not visible:
		return
	var previous := _content_id
	visible = false
	_clear_content()
	_content_id = &""
	closed.emit(previous)


func is_showing(content_id: StringName) -> bool:
	return visible and _content_id == content_id


# Allineamento all'info panel (2026-10-07, coordinate del CanvasLayer): il bordo inferiore dell'area scura è
# `content_bottom` (quello dell'area scura dell'info panel); la cornice finisce in basso a `frame_bottom` (il bordo della
# sidebar), con lo stesso margine. Il cassetto sta accanto al bordo sinistro `left_edge_x` (il suo lato destro lì): in
# modalità "Affiancato" GameScene passa il fianco sinistro della sidebar, in "Sopra" il bordo destro dello schermo. Il bordo superiore è quello
# misurato da align_top_to; prima della misura è stimato da `content_top` e dalle dimensioni minime della fascia del titolo.
func place(left_edge_x: float, content_top: float, content_bottom: float, frame_bottom: float) -> void:
	_alignment = {"left": left_edge_x, "content_top": content_top, "content_bottom": content_bottom, "frame_bottom": frame_bottom}
	var bottom_margin := int(round(maxf(0.0, frame_bottom - content_bottom)))
	if _frame_margin != null and _frame_margin.get_theme_constant("margin_bottom") != bottom_margin:
		_frame_margin.add_theme_constant_override("margin_bottom", bottom_margin)
	var top := _measured_top if _has_measured_top else content_top - _estimated_content_top_offset()
	var target_position := Vector2(left_edge_x - WIDTH, top)
	var target_size := Vector2(WIDTH, frame_bottom - top)
	if not position.is_equal_approx(target_position):
		position = target_position
	if not size.is_equal_approx(target_size):
		size = target_size


# Allineamento in alto per misura (2026-10-07, richiesta utente): un frame dopo l'apertura, a disposizione assestata,
# legge la y reale del bordo superiore di `reference` (il nodo che disegna la fascia scura in alto dell'info panel) e
# quella dell'area scura del cassetto, e sposta il cassetto perché coincidano (+ TOP_ALIGN_OFFSET_PX). Il bordo inferiore
# resta su `frame_bottom` (place). Basta all'apertura: quella fascia non si sposta.
func align_top_to(reference: Control) -> void:
	await get_tree().process_frame
	if not visible or reference == null or not is_instance_valid(reference) or _alignment.is_empty():
		return
	var inner_offset := _content_panel.global_position.y - global_position.y
	_measured_top = reference.global_position.y + float(TOP_ALIGN_OFFSET_PX) - inner_offset
	_has_measured_top = true
	place(float(_alignment["left"]), float(_alignment["content_top"]), float(_alignment["content_bottom"]), float(_alignment["frame_bottom"]))


# Stima (prima della misura) della distanza tra il bordo superiore del cassetto e quello dell'area scura.
func _estimated_content_top_offset() -> float:
	var header_height := 0.0
	if _header != null and _frame_box != null:
		header_height = _header.get_combined_minimum_size().y + float(_frame_box.get_theme_constant("separation"))
	return float(FRAME_MARGIN) + header_height


func _clear_content() -> void:
	if _content_holder == null:
		return
	for child in _content_holder.get_children():
		_content_holder.remove_child(child)
		child.queue_free()
