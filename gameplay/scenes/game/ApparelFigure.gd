class_name ApparelFigure
extends Control

# Slot del vestiario nel pannello dell'individuo (2026-10-11, richiesta utente — dal suo schizzo): una sagoma umana
# piena e semitrasparente, con sopra i 6 riquadri di HumanIndividual.ApparelSlot — il vestito grande su spalle e busto, la
# collana sovrapposta in alto al vestito, i bracciali sulle mani a cavallo dei bordi del vestito, i calzari in un riquadro
# largo sotto i piedi, il copricapo sopra la testa. Nessuna etichetta: il nome dello slot è nel tooltip. Un capo indossato mostra la sua icona
# (IconRegistry) e la barra del consumo (giorni residui / max_uses, come la barra degli usi della cintura). Nessuno
# stato di gioco qui: update_from legge l'individuo, i click escono con slot_input e li gestisce
# HumanIndividualInfoPanel.
#
# Geometria in uno spazio di disegno fisso DESIGN_SIZE, centrata nel riquadro reale e mai ingrandita oltre la scala 1
# (_layout): resta piccola anche in un pannello largo.

signal slot_input(slot: int, event: InputEvent)

const DESIGN_SIZE := Vector2(120.0, 150.0)
const MIN_WIDTH: float = 70.0
const SILHOUETTE_COLOR := Color(0.85, 0.87, 0.92, 0.18)
const USES_BAR_HEIGHT_FRACTION: float = 0.14
const USES_BAR_BACKGROUND := Color(0, 0, 0, 0.55)

# Testa: centro e raggio nello spazio di disegno, appoggiata sul collo della sagoma (nessuna sovrapposizione, così
# la trasparenza resta uniforme).
const HEAD_CENTER := Vector2(60.0, 17.0)
const HEAD_RADIUS: float = 11.0
# Sagoma del corpo (collo, spalle, braccia, busto, gambe) come UN solo poligono, in senso orario dal collo.
const BODY_OUTLINE := [
	Vector2(55.0, 28.0), Vector2(65.0, 28.0), Vector2(66.0, 33.0), Vector2(80.0, 36.0), Vector2(88.0, 42.0),
	Vector2(97.0, 74.0), Vector2(99.0, 84.0), Vector2(92.0, 86.0), Vector2(85.0, 60.0), Vector2(81.0, 52.0),
	Vector2(80.0, 94.0), Vector2(77.0, 98.0), Vector2(75.0, 132.0), Vector2(64.0, 132.0), Vector2(61.0, 102.0),
	Vector2(59.0, 102.0), Vector2(56.0, 132.0), Vector2(45.0, 132.0), Vector2(43.0, 98.0), Vector2(40.0, 94.0),
	Vector2(39.0, 52.0), Vector2(35.0, 60.0), Vector2(28.0, 86.0), Vector2(21.0, 84.0), Vector2(23.0, 74.0),
	Vector2(32.0, 42.0), Vector2(40.0, 36.0), Vector2(54.0, 33.0),
]
# Riquadro di ogni slot nello spazio di disegno: centro e dimensione.
const SLOT_RECTS := {
	# Vestito grande (2026-10-11, richiesta utente): copre spalle e busto, dal collo fin sopra le ginocchia.
	HumanIndividual.ApparelSlot.BODY: [Vector2(60.0, 74.0), Vector2(56.0, 78.0)],
	# Collana sovrapposta in alto al vestito, all'altezza del petto.
	HumanIndividual.ApparelSlot.NECK: [Vector2(60.0, 44.0), Vector2(16.0, 14.0)],
	# Bracciali sulle mani, a cavallo del bordo del vestito.
	HumanIndividual.ApparelSlot.WRIST_LEFT: [Vector2(25.0, 86.0), Vector2(18.0, 18.0)],
	HumanIndividual.ApparelSlot.WRIST_RIGHT: [Vector2(95.0, 86.0), Vector2(18.0, 18.0)],
	HumanIndividual.ApparelSlot.FEET: [Vector2(60.0, 140.0), Vector2(34.0, 14.0)],
	# Copricapo SOPRA la testa (sommità a y 6), non sul viso.
	HumanIndividual.ApparelSlot.HEAD: [Vector2(60.0, 6.0), Vector2(22.0, 12.0)],
}
# Ordine dei figli: la tunica sotto, collana e bracciali sopra (si sovrappongono in parte alla tunica).
const SLOT_ORDER := [
	HumanIndividual.ApparelSlot.BODY, HumanIndividual.ApparelSlot.FEET, HumanIndividual.ApparelSlot.NECK,
	HumanIndividual.ApparelSlot.WRIST_LEFT, HumanIndividual.ApparelSlot.WRIST_RIGHT, HumanIndividual.ApparelSlot.HEAD,
]
const SLOT_NAME_KEYS := {
	HumanIndividual.ApparelSlot.BODY: "apparel_slot_body",
	HumanIndividual.ApparelSlot.FEET: "apparel_slot_feet",
	HumanIndividual.ApparelSlot.NECK: "apparel_slot_neck",
	HumanIndividual.ApparelSlot.WRIST_LEFT: "apparel_slot_wrist_left",
	HumanIndividual.ApparelSlot.WRIST_RIGHT: "apparel_slot_wrist_right",
	HumanIndividual.ApparelSlot.HEAD: "apparel_slot_head",
}

var _slot_boxes: Dictionary = {}
var _slot_icons: Dictionary = {}
var _slot_bars: Dictionary = {}
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Nessuna altezza minima: la figura prende l'altezza della riga in cui sta (accanto a zaino e cintura, vedi
	# HumanIndividualInfoPanel._build_apparel_section) e si rimpicciolisce per starci.
	custom_minimum_size = Vector2(MIN_WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.20, 0.22, 0.75)
	style.set_border_width_all(1)
	style.border_color = Color(0.6, 0.6, 0.6, 0.7)
	style.set_corner_radius_all(3)
	for slot in SLOT_ORDER:
		var box := Panel.new()
		box.name = "ApparelSlot%d" % slot
		box.add_theme_stylebox_override("panel", style)
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.gui_input.connect(func(event: InputEvent) -> void: slot_input.emit(slot, event))
		add_child(box)
		_slot_boxes[slot] = box
		_slot_icons[slot] = null
		_slot_bars[slot] = null
	resized.connect(_layout)
	_layout()
	update_from(null)


# Figura attenuata per i bambini (2026-10-11, richiesta utente — HumanIndividual.is_apparel_age_band): vestiti di
# recupero, slot non cliccabili, un tooltip che lo spiega.
const INACTIVE_MODULATE := Color(1, 1, 1, 0.35)


# Riempie i riquadri dagli slot dell'individuo (null = tutti vuoti). `active` false = bambino: figura attenuata e slot
# non cliccabili.
func update_from(individual: HumanIndividual, active: bool = true) -> void:
	modulate = Color.WHITE if active else INACTIVE_MODULATE
	tooltip_text = "" if active else tr("apparel_children_tooltip")
	for slot in _slot_boxes:
		(_slot_boxes[slot] as Control).mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
		var box: Panel = _slot_boxes[slot]
		if _slot_icons[slot] != null:
			_slot_icons[slot].queue_free()
			_slot_icons[slot] = null
		var apparel_name: String = individual.get_equipped_apparel(slot) if individual != null else ""
		var slot_name: String = tr(String(SLOT_NAME_KEYS[slot]))
		if apparel_name == "":
			box.tooltip_text = tr("apparel_slot_empty_tooltip").format({"slot": slot_name})
			_update_uses_bar(slot, 0, 0)
			continue
		var display_name := IconRegistry.get_resource_display_name(apparel_name)
		box.tooltip_text = tr("apparel_slot_full_tooltip").format({"slot": slot_name, "apparel": display_name})
		var instance: Dictionary = individual.get_equipped_apparel_instance(slot)
		var max_days: int = ToolInstance.get_max_uses(apparel_name)
		var remaining_days: int = ToolInstance.get_remaining_uses(instance)
		if max_days > 0:
			box.tooltip_text += "\n" + tr("apparel_slot_days_line").format({"days": remaining_days, "max": max_days})
		var decay_fraction: float = ToolInstance.get_decay_fraction(instance)
		if decay_fraction > 0.0:
			box.tooltip_text += "\n" + tr("apparel_slot_decay_line").format({"percent": int(roundf(decay_fraction * 100.0))})
		var icon_node: Control = IconRegistry.get_resource_icon_node(apparel_name)
		if icon_node != null:
			icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(icon_node)
			icon_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_slot_icons[slot] = icon_node
		_update_uses_bar(slot, remaining_days, max_days)


# Barra del consumo in fondo al riquadro (stesso aspetto della barra degli usi della cintura): verde pieno, rosso
# quasi consumato; nascosta per slot vuoti e capi che non si consumano (max_uses <= 0).
func _update_uses_bar(slot: int, remaining: int, maximum: int) -> void:
	var bar: ColorRect = _slot_bars[slot]
	if maximum <= 0:
		if bar != null:
			bar.visible = false
		return
	if bar == null:
		bar = ColorRect.new()
		bar.color = USES_BAR_BACKGROUND
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 1.0 - USES_BAR_HEIGHT_FRACTION
		bar.anchor_bottom = 1.0
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_bottom = 1.0
		bar.add_child(fill)
		_slot_boxes[slot].add_child(bar)
		_slot_bars[slot] = bar
	var ratio: float = clampf(float(remaining) / float(maximum), 0.0, 1.0)
	var fill_rect := bar.get_node("Fill") as ColorRect
	fill_rect.anchor_right = ratio
	fill_rect.color = Color.RED.lerp(Color.GREEN, ratio)
	bar.visible = true
	# L'icona aggiunta dopo la barra la coprirebbe: la barra torna sopra.
	_slot_boxes[slot].move_child(bar, -1)


func _layout() -> void:
	_scale = 1.0
	if size.x > 0.0 and size.y > 0.0:
		_scale = minf(1.0, minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y))
	_origin = ((size - DESIGN_SIZE * _scale) * 0.5).floor()
	for slot in _slot_boxes:
		var box_size: Vector2 = SLOT_RECTS[slot][1] * _scale
		var box: Panel = _slot_boxes[slot]
		box.size = box_size
		box.position = _to_local(SLOT_RECTS[slot][0]) - box_size * 0.5
	queue_redraw()


func _to_local(design_point: Vector2) -> Vector2:
	return _origin + design_point * _scale


# Sagoma piena e semitrasparente: un solo poligono per il corpo più la testa, senza sovrapposizioni.
func _draw() -> void:
	var outline := PackedVector2Array()
	for point in BODY_OUTLINE:
		outline.append(_to_local(point))
	draw_colored_polygon(outline, SILHOUETTE_COLOR)
	draw_circle(_to_local(HEAD_CENTER), HEAD_RADIUS * _scale, SILHOUETTE_COLOR, true, -1.0, true)
