class_name GroundPileInfoPanel
extends VBoxContainer

# Pannello informativo di un mucchio a terra (2026-09-26, richiesta utente — ground drop), sibling nella
# SelectionTab come DeadBodyInfoPanel e con lo stesso principio "componente muto": GameScene gli passa i dati
# (_refresh_ground_pile_panel), qui solo testo. Una riga per risorsa (nome, quantità, deperimento, usi residui
# degli attrezzi usati) e i giorni che mancano alla sparizione del mucchio. Sotto, le risorse naturali della
# stessa microcella (2026-09-26): il mucchio non le nasconde, si possono raccogliere anche loro.

@onready var resources_container: VBoxContainer = $ResourcesContainer
@onready var days_remaining_label: Label = $DaysRemainingLabel
@onready var terrain_header_label: Label = $TerrainHeaderLabel
@onready var terrain_container: VBoxContainer = $TerrainContainer


func _ready() -> void:
	clear()


# `terrain_resources`: [{"resource_name", "quantity"}] delle risorse naturali della microcella del mucchio.
# `carcass_lines` (2026-09-26): una riga già formattata per carcassa (specie, età, giorni prima che marcisca),
# mostrata in testa al contenuto.
func show_pile(pile: GroundPile, days_remaining: int, terrain_resources: Array = [], carcass_lines: Array[String] = []) -> void:
	visible = true
	for child in resources_container.get_children():
		child.queue_free()
	for carcass_line in carcass_lines:
		var carcass_label := Label.new()
		carcass_label.text = carcass_line
		carcass_label.add_theme_font_size_override("font_size", 10)
		resources_container.add_child(carcass_label)
	for resource_name in pile.get_resource_names():
		var entry: Dictionary = pile.resources[resource_name]
		var line := tr("ground_pile_resource_line").format({
			"name": IconRegistry.get_resource_display_name(resource_name),
			"quantity": int(entry.get("quantity", 0)),
		})
		var decay_percent := int(round(float(entry.get("decay_fraction", 0.0)) * 100.0))
		if decay_percent > 0:
			line += " " + tr("ground_pile_decay_suffix").format({"percent": decay_percent})
		var used_instances := ToolInstance.get_used_instances(entry)
		if not used_instances.is_empty():
			var uses: PackedStringArray = []
			for instance in used_instances:
				uses.append(str(ToolInstance.get_remaining_uses(instance)))
			line += " " + tr("ground_pile_used_tools_suffix").format({"uses": ", ".join(uses)})
		var label := Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 10)
		resources_container.add_child(label)
	# Durata del mucchio solo se contiene risorse (2026-09-26): con sole carcasse la sua durata è quella delle
	# carcasse (già nelle loro righe) e sparisce quando l'ultima è marcita.
	days_remaining_label.visible = not pile.resources.is_empty()
	days_remaining_label.text = tr("ground_pile_disappears_label").format({"days": days_remaining})
	for child in terrain_container.get_children():
		child.queue_free()
	terrain_header_label.visible = not terrain_resources.is_empty()
	terrain_header_label.text = tr("ground_pile_terrain_header")
	for terrain_entry in terrain_resources:
		var terrain_label := Label.new()
		terrain_label.text = tr("ground_pile_resource_line").format({
			"name": IconRegistry.get_resource_display_name(String(terrain_entry["resource_name"])),
			"quantity": int(terrain_entry["quantity"]),
		})
		terrain_label.add_theme_font_size_override("font_size", 10)
		terrain_container.add_child(terrain_label)


func clear() -> void:
	visible = false
