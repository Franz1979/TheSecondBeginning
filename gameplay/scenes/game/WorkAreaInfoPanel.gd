class_name WorkAreaInfoPanel
extends VBoxContainer

# Pannello della zona di lavoro selezionata (2026-09-27, richiesta utente — work areas, passo 1b), dentro
# GameInfoTabs.selection_content come GroundPileInfoPanel. Costruito in codice. Modifica direttamente la WorkArea
# mostrata (nome, colore, lavori, filtri) e segnala ogni modifica con area_changed: GameScene alza la revisione
# (WorkAreaService.notify_changed) così overlay e minimappa si aggiornano. Ridisegna, elimina e centra sono richieste
# a GameScene (redraw_requested/delete_requested/center_requested).
#
# Filtri (WorkArea.filters, per id lavoro), mostrati come albero comprimibile con spunte collegate (2026-09-27, stile
# tabella pivot): radice "Tutto" -> categorie -> risorse per la Raccolta, radice "Tutte le prede" -> specie per la
# Caccia. Spuntare un genitore spunta tutti i figli; un genitore con solo alcuni figli spuntati mostra la spunta
# parziale. Il filtro salvato è sempre la forma normalizzata di ciò che si vede (_save_haul_selection/_save_hunt_selection):
#   - "haul" (Raccolta): {"all": bool, "categories": [int SecondaryResourceTypes.Category] (categorie spuntate per
#     intero), "resources": [String] (risorse spuntate nelle categorie parziali)} — "all" = tutto spuntato, liste vuote;
#   - "hunt" (Caccia): {"all": bool, "species": [String]}.
# La Raccolta propone solo ciò che la PickUpAction raccoglie da terra (TerrainScatteredResourceService.is_pickable:
# lotti del terreno e frutti/uova): niente carni, caccia, pesca, produzione, né "forage" (pascolo aggregato degli
# animali, non raccoglibile). Un lavoro appena abilitato parte con "all": true.

signal area_changed(area: WorkArea)
signal redraw_requested(area: WorkArea)
signal delete_requested(area: WorkArea)
signal center_requested(area: WorkArea)

const FONT_SIZE: int = 10
const CAPTION_FONT_SIZE: int = 11
const SWATCH_SIZE: float = 20.0
const HAUL_JOB := "haul"
const HUNT_JOB := "hunt"
# Albero dei filtri: rientro per livello e larghezza del bottone [+]/[−].
const TREE_INDENT: float = 14.0
const EXPAND_BUTTON_WIDTH: float = 20.0
const HUNT_ROOT_KEY := "hunt:root"

var _area: WorkArea = null
var _delete_confirm_visible: bool = false
# Nodi aperti dell'albero dei filtri ("haul:<categoria>", HUNT_ROOT_KEY): tutti chiusi all'apertura di una zona.
var _expanded: Dictionary = {}
# Icona della spunta parziale, generata una volta dall'icona "unchecked" del tema (_partial_check_icon).
static var _partial_icon: Texture2D = null


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", 4)


func show_area(area: WorkArea) -> void:
	if area != _area:
		_delete_confirm_visible = false
		_expanded.clear()
	_area = area
	visible = area != null
	_rebuild()


func clear() -> void:
	_area = null
	_delete_confirm_visible = false
	_expanded.clear()
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


# Nome modificabile + bottone centra; sotto dimensioni e macrocella, su due righe (una sola veniva tagliata).
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
	add_child(_label(tr("work_area_size_label").format({"w": _area.rect.size.x, "h": _area.rect.size.y})))
	add_child(_label(tr("work_area_macro_label").format({"x": _area.macro_coords.x, "y": _area.macro_coords.y})))


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


# Ricostruisce la zona mostrata con lo stato attuale (2026-10-01): GameScene la chiama al completamento di un'idea,
# così il limite "solo cibo" sparisce dal pannello aperto senza riselezionare la zona.
func refresh() -> void:
	if _area != null:
		_rebuild()


# Lavori abilitati e, per ciascuno abilitato, i suoi filtri. Una spunta per lavoro di WorkAreaTypes.JOBS, nell'ordine,
# solo se sbloccato (WorkAreaTypes.is_job_unlocked, 2026-10-05 — prima la sola caccia, con l'idea "Aree di lavoro");
# senza, il dato salvato resta intatto. Filtri: raccolta (categorie e risorse), caccia (specie); l'estrazione non ne ha.
func _build_jobs() -> void:
	add_child(_label(tr("work_area_jobs_caption"), CAPTION_FONT_SIZE))
	for job_id in WorkAreaTypes.JOBS.keys():
		if not WorkAreaTypes.is_job_unlocked(String(job_id)):
			continue
		add_child(_job_check_box(String(job_id)))
		if not _area.enabled_jobs.has(job_id):
			continue
		match String(job_id):
			HAUL_JOB:
				_build_haul_filters()
			HUNT_JOB:
				_build_hunt_filters()


func _job_check_box(job_id: String) -> CheckBox:
	var check_box := _check_box(tr(WorkAreaTypes.get_job_name_key(job_id)), _area.enabled_jobs.has(job_id))
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


# --- Raccolta: "Tutto" -> categorie -> risorse raccoglibili da terra ---

func _build_haul_filters() -> void:
	var filters := _job_filters(HAUL_JOB)
	var tree := _haul_tree()
	var checked := _haul_checked(filters, tree)
	var box := _indented_box()
	var all_names: Array[String] = []
	for category in tree.keys():
		all_names.append_array(tree[category])
	box.add_child(_tree_row(0, "", tr("work_area_filter_all"), _state_of(all_names, checked), func(pressed: bool) -> void:
		for resource_name in all_names:
			_set_checked(checked, resource_name, pressed)
		_save_haul_selection(filters, tree, checked)
	))
	for category in tree.keys():
		var names: Array[String] = tree[category]
		var expand_key := "haul:%d" % category
		var category_name := tr("category_name_%s" % String(SecondaryResourceTypes.Category.keys()[category]).to_lower())
		var category_text := "%s (%d/%d)" % [category_name, _count_checked(names, checked), names.size()]
		box.add_child(_tree_row(1, expand_key, category_text, _state_of(names, checked), func(pressed: bool) -> void:
			for resource_name in names:
				_set_checked(checked, resource_name, pressed)
			_save_haul_selection(filters, tree, checked)
		))
		if not _expanded.has(expand_key):
			continue
		for resource_name in names:
			var leaf_name: String = resource_name
			box.add_child(_tree_row(2, "", IconRegistry.get_resource_display_name(leaf_name), 2 if checked.has(leaf_name) else 0, func(pressed: bool) -> void:
				_set_checked(checked, leaf_name, pressed)
				_save_haul_selection(filters, tree, checked)
			))
	# Limite "solo cibo" (2026-10-01): l'albero mostra solo il cibo, una riga dice quale idea sblocca il resto.
	if HaulZoneService.is_food_only_limit_active():
		var advanced_idea := IdeaCalculator.get_idea(WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID)
		var idea_name: String = tr(advanced_idea.display_name) if advanced_idea != null else WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID
		var hint := _label(tr("work_area_filter_food_only_hint").format({"idea": idea_name}))
		hint.modulate = Color(1, 1, 1, 0.7)
		box.add_child(hint)


# Categoria (int, nell'ordine di PickUpAction.PRIORITY_CATEGORIES) -> risorse raccoglibili da terra, ordinate per nome
# visibile. Solo categorie con almeno una risorsa; col limite "solo cibo" (HaulZoneService) solo FOOD.
func _haul_tree() -> Dictionary:
	var by_category: Dictionary = {}
	var food_only := HaulZoneService.is_food_only_limit_active()
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null or not TerrainScatteredResourceService.is_pickable(resource_name):
			continue
		if food_only and int(rules.category) != int(SecondaryResourceTypes.Category.FOOD):
			continue
		var category := int(rules.category)
		if not by_category.has(category):
			var names: Array[String] = []
			by_category[category] = names
		(by_category[category] as Array[String]).append(resource_name)
	var tree: Dictionary = {}
	for category in PickUpAction.PRIORITY_CATEGORIES:
		if not by_category.has(int(category)):
			continue
		var names: Array[String] = by_category[int(category)]
		names.sort_custom(func(a: String, b: String) -> bool:
			return IconRegistry.get_resource_display_name(a) < IconRegistry.get_resource_display_name(b)
		)
		tree[int(category)] = names
	return tree


# Risorse dell'albero spuntate secondo il filtro salvato (stessa regola di HaulZoneService.work_area_accepts).
func _haul_checked(filters: Dictionary, tree: Dictionary) -> Dictionary:
	var checked: Dictionary = {}
	var all := bool(filters.get("all", true))
	var categories: Array = filters.get("categories", [])
	var resources: Array = filters.get("resources", [])
	for category in tree.keys():
		for resource_name in tree[category]:
			if all or categories.has(int(category)) or resources.has(resource_name):
				checked[resource_name] = true
	return checked


# Filtro normalizzato da ciò che si vede: tutto spuntato = "all"; altrimenti le categorie spuntate per intero e le
# singole risorse delle categorie parziali.
func _save_haul_selection(filters: Dictionary, tree: Dictionary, checked: Dictionary) -> void:
	var full_categories: Array = []
	var partial_resources: Array = []
	var everything := true
	for category in tree.keys():
		var names: Array[String] = tree[category]
		var count := _count_checked(names, checked)
		if count == names.size():
			full_categories.append(int(category))
			continue
		everything = false
		for resource_name in names:
			if checked.has(resource_name):
				partial_resources.append(resource_name)
	filters["all"] = everything
	filters["categories"] = [] if everything else full_categories
	filters["resources"] = [] if everything else partial_resources
	area_changed.emit(_area)
	_rebuild()


# --- Caccia: "Tutte le prede" -> specie ---

func _build_hunt_filters() -> void:
	var filters := _job_filters(HUNT_JOB)
	var species_names := AnimalCalculator.list_species_names()
	species_names.sort_custom(func(a: String, b: String) -> bool: return tr("animal_species_" + a) < tr("animal_species_" + b))
	var checked: Dictionary = {}
	var all := bool(filters.get("all", true))
	var saved_species: Array = filters.get("species", [])
	for species in species_names:
		if all or saved_species.has(species):
			checked[species] = true
	var box := _indented_box()
	var root_text := "%s (%d/%d)" % [tr("work_area_filter_all_prey"), _count_checked(species_names, checked), species_names.size()]
	box.add_child(_tree_row(0, HUNT_ROOT_KEY, root_text, _state_of(species_names, checked), func(pressed: bool) -> void:
		for species in species_names:
			_set_checked(checked, species, pressed)
		_save_hunt_selection(filters, species_names, checked)
	))
	if not _expanded.has(HUNT_ROOT_KEY):
		return
	for species in species_names:
		var leaf_species: String = species
		box.add_child(_tree_row(1, "", tr("animal_species_" + leaf_species), 2 if checked.has(leaf_species) else 0, func(pressed: bool) -> void:
			_set_checked(checked, leaf_species, pressed)
			_save_hunt_selection(filters, species_names, checked)
		))


func _save_hunt_selection(filters: Dictionary, species_names: Array[String], checked: Dictionary) -> void:
	var everything := _count_checked(species_names, checked) == species_names.size()
	var selected: Array = []
	if not everything:
		for species in species_names:
			if checked.has(species):
				selected.append(species)
	filters["all"] = everything
	filters["species"] = selected
	area_changed.emit(_area)
	_rebuild()


# --- Albero: righe, stati, spunta parziale ---

# Riga dell'albero: rientro per `level`, bottone [+]/[−] se `expand_key` non è vuoto (altrimenti uno spazio della
# stessa larghezza, così le spunte restano allineate), spunta a tre stati (0 nessuna, 1 parziale, 2 piena).
# `on_toggled(pressed)`: da una spunta parziale un clic spunta tutto.
func _tree_row(level: int, expand_key: String, text: String, state: int, on_toggled: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(TREE_INDENT * float(level), 0.0)
	row.add_child(indent)
	if expand_key != "":
		var expand_button := Button.new()
		expand_button.text = "−" if _expanded.has(expand_key) else "+"
		expand_button.custom_minimum_size = Vector2(EXPAND_BUTTON_WIDTH, 0.0)
		expand_button.focus_mode = Control.FOCUS_NONE
		expand_button.add_theme_font_size_override("font_size", FONT_SIZE)
		expand_button.pressed.connect(func() -> void:
			if _expanded.has(expand_key):
				_expanded.erase(expand_key)
			else:
				_expanded[expand_key] = true
			_rebuild()
		)
		row.add_child(expand_button)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(EXPAND_BUTTON_WIDTH, 0.0)
		row.add_child(spacer)
	var check_box := _check_box(text, state == 2)
	if state == 1:
		check_box.add_theme_icon_override("unchecked", _partial_check_icon())
	check_box.toggled.connect(on_toggled)
	row.add_child(check_box)
	return row


# 0 nessuno, 1 alcuni, 2 tutti gli elementi di `names` spuntati.
func _state_of(names: Array[String], checked: Dictionary) -> int:
	var count := _count_checked(names, checked)
	if count == 0:
		return 0
	return 2 if count == names.size() else 1


func _count_checked(names: Array[String], checked: Dictionary) -> int:
	var count := 0
	for item_name in names:
		if checked.has(item_name):
			count += 1
	return count


func _set_checked(checked: Dictionary, item_name: String, pressed: bool) -> void:
	if pressed:
		checked[item_name] = true
	else:
		checked.erase(item_name)


# Spunta parziale: l'icona "unchecked" del tema con una barra orizzontale al centro (CheckBox non ha uno stato
# intermedio). Generata una volta; se l'icona del tema non è leggibile, un quadratino disegnato da zero.
func _partial_check_icon() -> Texture2D:
	if _partial_icon != null:
		return _partial_icon
	var image: Image = null
	var base := get_theme_icon("unchecked", "CheckBox")
	if base != null:
		image = base.get_image()
	if image == null or image.is_empty():
		image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var border := Color(0.8, 0.8, 0.8)
		for i in range(16):
			image.set_pixel(i, 0, border)
			image.set_pixel(i, 15, border)
			image.set_pixel(0, i, border)
			image.set_pixel(15, i, border)
	else:
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var bar_height := maxi(2, int(height * 0.16))
	image.fill_rect(Rect2i(int(width * 0.25), (height - bar_height) / 2, int(width * 0.5), bar_height), Color(0.92, 0.92, 0.92))
	_partial_icon = ImageTexture.create_from_image(image)
	return _partial_icon


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


# Filtri del lavoro (creati con "all": true se mancano), modificati sul posto.
func _job_filters(job_id: String) -> Dictionary:
	if not _area.filters.has(job_id) or not (_area.filters[job_id] is Dictionary):
		_area.filters[job_id] = {"all": true}
	return _area.filters[job_id]


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


# Blocco dei filtri, già aggiunto al pannello: il chiamante aggiunge le righe al VBoxContainer restituito.
func _indented_box() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	margin.add_child(inner)
	add_child(margin)
	return inner
