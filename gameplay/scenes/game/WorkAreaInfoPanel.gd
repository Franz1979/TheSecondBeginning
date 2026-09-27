class_name WorkAreaInfoPanel
extends VBoxContainer

# Pannello della zona di lavoro selezionata (2026-09-27, richiesta utente — work areas, passo 1b), dentro
# GameInfoTabs.selection_content come GroundPileInfoPanel. Costruito in codice. Modifica direttamente la WorkArea
# mostrata (nome, colore, lavori, filtri) e segnala ogni modifica con area_changed: GameScene alza la revisione
# (WorkAreaService.notify_changed) così overlay e minimappa si aggiornano. Ridisegna, elimina e centra sono richieste
# a GameScene (redraw_requested/delete_requested/center_requested).
#
# Filtri (WorkArea.filters, per id lavoro):
#   - "haul" (Raccolta): {"all": bool, "categories": [int SecondaryResourceTypes.Category], "resources": [String]};
#   - "hunt" (Caccia): {"all": bool, "species": [String]}.
# Un lavoro appena abilitato parte con "all": true.

signal area_changed(area: WorkArea)
signal redraw_requested(area: WorkArea)
signal delete_requested(area: WorkArea)
signal center_requested(area: WorkArea)

const FONT_SIZE: int = 10
const CAPTION_FONT_SIZE: int = 11
const SWATCH_SIZE: float = 20.0
const HAUL_JOB := "haul"
const HUNT_JOB := "hunt"
# Categorie proposte nei filtri della Raccolta.
const HAUL_FILTER_CATEGORIES: Array[int] = [SecondaryResourceTypes.Category.FOOD, SecondaryResourceTypes.Category.RAW_MATERIAL]

var _area: WorkArea = null
var _delete_confirm_visible: bool = false


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", 4)


func show_area(area: WorkArea) -> void:
	if area != _area:
		_delete_confirm_visible = false
	_area = area
	visible = area != null
	_rebuild()


func clear() -> void:
	_area = null
	_delete_confirm_visible = false
	visible = false
	for child in get_children():
		child.queue_free()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if _area == null:
		return
	_build_header()
	_build_colors()
	add_child(HSeparator.new())
	_build_jobs()
	add_child(HSeparator.new())
	_build_actions()


# Nome modificabile + bottone centra; sotto dimensioni e macrocella.
func _build_header() -> void:
	var row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = _area.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	name_edit.tooltip_text = tr("work_area_name_tooltip")
	var commit_name := func(new_text: String) -> void:
		# focus_exited può arrivare mentre il pannello si svuota (clear/_rebuild): zona già tolta.
		if _area == null:
			return
		var trimmed := new_text.strip_edges()
		if trimmed == "" or trimmed == _area.name:
			return
		_area.name = trimmed
		area_changed.emit(_area)
	name_edit.text_submitted.connect(commit_name)
	name_edit.focus_exited.connect(func() -> void: commit_name.call(name_edit.text))
	row.add_child(name_edit)
	var center_button := Button.new()
	center_button.text = "🎯"
	center_button.tooltip_text = tr("work_area_center_tooltip")
	center_button.add_theme_font_size_override("font_size", FONT_SIZE)
	center_button.pressed.connect(func() -> void: center_requested.emit(_area))
	row.add_child(center_button)
	add_child(row)
	add_child(_label(tr("work_area_size_label").format({
		"w": _area.rect.size.x, "h": _area.rect.size.y, "x": _area.macro_coords.x, "y": _area.macro_coords.y,
	})))


# Tavolozza delle 8: il colore attuale ha il bordo bianco.
func _build_colors() -> void:
	add_child(_label(tr("work_area_color_caption"), CAPTION_FONT_SIZE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for color in WorkAreaTypes.PALETTE:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		swatch.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(3)
		if color.is_equal_approx(_area.color):
			style.border_color = Color.WHITE
			style.set_border_width_all(2)
		for state in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, style)
		var chosen: Color = color
		swatch.pressed.connect(func() -> void:
			_area.color = chosen
			area_changed.emit(_area)
			_rebuild()
		)
		row.add_child(swatch)
	add_child(row)


# Lavori abilitati e, per ciascuno abilitato, i suoi filtri.
func _build_jobs() -> void:
	add_child(_label(tr("work_area_jobs_caption"), CAPTION_FONT_SIZE))
	add_child(_job_check_box(HAUL_JOB))
	if _area.enabled_jobs.has(HAUL_JOB):
		_build_haul_filters()
	add_child(_job_check_box(HUNT_JOB))
	if _area.enabled_jobs.has(HUNT_JOB):
		_build_hunt_filters()


func _job_check_box(job_id: String) -> CheckBox:
	var check_box := _check_box(tr(String(WorkAreaTypes.JOBS[job_id])), _area.enabled_jobs.has(job_id))
	check_box.toggled.connect(func(pressed: bool) -> void:
		if pressed and not _area.enabled_jobs.has(job_id):
			_area.enabled_jobs.append(job_id)
			if not _area.filters.has(job_id):
				_area.filters[job_id] = {"all": true}
		elif not pressed:
			_area.enabled_jobs.erase(job_id)
		area_changed.emit(_area)
		_rebuild()
	)
	return check_box


func _build_haul_filters() -> void:
	var filters := _job_filters(HAUL_JOB)
	var box := _indented_box()
	var all_box := _check_box(tr("work_area_filter_all"), bool(filters.get("all", true)))
	all_box.toggled.connect(func(pressed: bool) -> void:
		filters["all"] = pressed
		area_changed.emit(_area)
		_rebuild()
	)
	box.add_child(all_box)
	if not bool(filters.get("all", true)):
		var flow := _flow()
		for category in HAUL_FILTER_CATEGORIES:
			var category_name := tr("category_name_%s" % String(SecondaryResourceTypes.Category.keys()[category]).to_lower())
			flow.add_child(_list_check_box(filters, "categories", category, category_name))
		box.add_child(flow)
		var resources_flow := _flow()
		for resource_name in _gatherable_resources():
			resources_flow.add_child(_list_check_box(filters, "resources", resource_name, IconRegistry.get_resource_display_name(resource_name)))
		box.add_child(resources_flow)


func _build_hunt_filters() -> void:
	var filters := _job_filters(HUNT_JOB)
	var box := _indented_box()
	var all_box := _check_box(tr("work_area_filter_all_prey"), bool(filters.get("all", true)))
	all_box.toggled.connect(func(pressed: bool) -> void:
		filters["all"] = pressed
		area_changed.emit(_area)
		_rebuild()
	)
	box.add_child(all_box)
	if not bool(filters.get("all", true)):
		var flow := _flow()
		for species in AnimalCalculator.list_species_names():
			flow.add_child(_list_check_box(filters, "species", species, tr("animal_species_" + species)))
		box.add_child(flow)


# Ridisegna ed Elimina; Elimina chiede conferma su una riga ("Eliminare Zona 1?" Sì / No).
func _build_actions() -> void:
	if _delete_confirm_visible:
		var confirm_row := HBoxContainer.new()
		var question := _label(tr("work_area_delete_confirm").format({"name": _area.name}))
		question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm_row.add_child(question)
		var yes_button := _button(tr("work_area_delete_yes"))
		yes_button.pressed.connect(func() -> void: delete_requested.emit(_area))
		confirm_row.add_child(yes_button)
		var no_button := _button(tr("work_area_delete_no"))
		no_button.pressed.connect(func() -> void:
			_delete_confirm_visible = false
			_rebuild()
		)
		confirm_row.add_child(no_button)
		add_child(confirm_row)
		return
	var row := HBoxContainer.new()
	var redraw_button := _button(tr("work_area_redraw_button"))
	redraw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redraw_button.pressed.connect(func() -> void: redraw_requested.emit(_area))
	row.add_child(redraw_button)
	var delete_button := _button(tr("work_area_delete_button"))
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(func() -> void:
		_delete_confirm_visible = true
		_rebuild()
	)
	row.add_child(delete_button)
	add_child(row)


# Risorse raccoglibili proposte nei filtri: raccolte in natura (vegetali o sparse sul terreno), di una delle categorie
# di HAUL_FILTER_CATEGORIES, ordinate per nome visibile.
func _gatherable_resources() -> Array[String]:
	var names: Array[String] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null or not HAUL_FILTER_CATEGORIES.has(int(rules.category)):
			continue
		if rules.generation_source != SecondaryResourceTypes.GenerationSource.PLANT_DERIVED \
				and rules.generation_source != SecondaryResourceTypes.GenerationSource.TERRAIN_SCATTERED:
			continue
		names.append(resource_name)
	names.sort_custom(func(a: String, b: String) -> bool:
		return IconRegistry.get_resource_display_name(a) < IconRegistry.get_resource_display_name(b)
	)
	return names


# Filtri del lavoro (creati con "all": true se mancano), modificati sul posto.
func _job_filters(job_id: String) -> Dictionary:
	if not _area.filters.has(job_id) or not (_area.filters[job_id] is Dictionary):
		_area.filters[job_id] = {"all": true}
	return _area.filters[job_id]


# Spunta di un valore dentro la lista `list_key` dei filtri (categorie, risorse, specie).
func _list_check_box(filters: Dictionary, list_key: String, value: Variant, text: String) -> CheckBox:
	var values: Array = filters.get(list_key, [])
	var check_box := _check_box(text, values.has(value))
	check_box.toggled.connect(func(pressed: bool) -> void:
		var current: Array = filters.get(list_key, [])
		if pressed and not current.has(value):
			current.append(value)
		elif not pressed:
			current.erase(value)
		filters[list_key] = current
		area_changed.emit(_area)
	)
	return check_box


func _check_box(text: String, pressed: bool) -> CheckBox:
	var check_box := CheckBox.new()
	check_box.text = text
	check_box.button_pressed = pressed
	check_box.focus_mode = Control.FOCUS_NONE
	check_box.add_theme_font_size_override("font_size", FONT_SIZE)
	return check_box


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	return button


func _label(text: String, font_size: int = FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 2)
	flow.add_theme_constant_override("v_separation", 0)
	return flow


# Blocco rientrato dei filtri, già aggiunto al pannello: il chiamante aggiunge i figli al VBoxContainer restituito.
func _indented_box() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	margin.add_child(inner)
	add_child(margin)
	return inner
