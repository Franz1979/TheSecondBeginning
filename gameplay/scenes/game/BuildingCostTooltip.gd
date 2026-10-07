class_name BuildingCostTooltip
extends RefCounted

# Tooltip unico di un edificio da costruire (2026-10-07, richiesta utente): stesso formato per i bottoni della barra
# degli edifici (BuildBar, prima costruzione) e per "Migliora" (BuildingInfoPanel, miglioramento):
#   1. nome (per il miglioramento "Migliora in <edificio>");
#   2. descrizione breve dell'edificio ("build_bar_<tipo>_description"), saltata se il tipo non ce l'ha;
#   3. materiali su una riga: icona della risorsa (stessa del magazzino) + quantità, senza nome;
#   4. lavoro ("Lavoro: 2400");
#   poi le eventuali righe extra (perché il bottone è spento).
# Costruito al passaggio del mouse (TooltipButton.tooltip_builder), quindi sempre aggiornato.
# Quantità sempre del colore normale: non esiste un calcolo riutilizzabile della disponibilità dei materiali.

const ICON_SIZE: float = 16.0
const ICON_FONT_SIZE: int = 10
const QUANTITY_FONT_SIZE: int = 12
const DESCRIPTION_FONT_SIZE: int = 11
const DESCRIPTION_WIDTH: float = 240.0
const MATERIAL_SEPARATION: int = 10
const ICON_QUANTITY_SEPARATION: int = 3


static func build(title: String, building_type_name: String, materials: Dictionary, labor: int, extra_lines: Array[String] = []) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var title_label := Label.new()
	title_label.text = title
	box.add_child(title_label)
	var description := get_short_description(building_type_name)
	if description != "":
		var description_label := Label.new()
		description_label.text = description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.custom_minimum_size.x = DESCRIPTION_WIDTH
		description_label.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
		description_label.modulate = Color(1, 1, 1, 0.75)
		box.add_child(description_label)
	if not materials.is_empty():
		box.add_child(_build_materials_row(materials))
	var labor_label := Label.new()
	labor_label.text = TranslationServer.translate("building_upgrade_labor").format({"labor": labor})
	box.add_child(labor_label)
	for line in extra_lines:
		if line == "":
			continue
		var extra_label := Label.new()
		extra_label.text = line
		box.add_child(extra_label)
	return box


# Descrizione breve del tipo ("build_bar_<tipo>_description"); "" se non esiste.
static func get_short_description(building_type_name: String) -> String:
	var key := "build_bar_%s_description" % building_type_name
	var text := String(TranslationServer.translate(key))
	return "" if text == key else text


# Materiali di una costruzione nuova: allestimento del cantiere (setup_site_material_per_cell × required_space) più
# required_materials, sommati se è la stessa risorsa.
static func get_build_materials(rules: BuildingRules) -> Dictionary:
	var materials: Dictionary = {}
	if rules == null:
		return materials
	var setup_required: int = rules.setup_site_material_per_cell * rules.required_space
	if rules.setup_site_material_name != "" and setup_required > 0:
		materials[rules.setup_site_material_name] = setup_required
	for material_name in rules.required_materials.keys():
		var quantity: int = int(rules.required_materials[material_name])
		if quantity > 0:
			materials[String(material_name)] = int(materials.get(String(material_name), 0)) + quantity
	return materials


static func _build_materials_row(materials: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MATERIAL_SEPARATION)
	var names: Array = materials.keys()
	names.sort()
	for material_name in names:
		var quantity: int = int(materials[material_name])
		if quantity <= 0:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", ICON_QUANTITY_SEPARATION)
		item.add_child(_build_resource_icon(String(material_name)))
		var quantity_label := Label.new()
		quantity_label.text = str(quantity)
		quantity_label.add_theme_font_size_override("font_size", QUANTITY_FONT_SIZE)
		quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(quantity_label)
		row.add_child(item)
	return row


# Icona della risorsa come negli slot del magazzino (BuildingInfoPanel._build_storage_slot): fondo del colore della
# risorsa, icona vera, altrimenti emoji, altrimenti iniziale.
static func _build_resource_icon(resource_name: String) -> Control:
	var box := ColorRect.new()
	box.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.color = IconRegistry.get_resource_color(resource_name)
	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		box.add_child(icon_node)
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		var initial_label := Label.new()
		var icon_text: String = IconRegistry.get_resource_icon(resource_name)
		initial_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		initial_label.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
		initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial_label.anchor_right = 1.0
		initial_label.anchor_bottom = 1.0
		box.add_child(initial_label)
	return box
