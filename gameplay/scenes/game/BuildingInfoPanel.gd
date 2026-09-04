class_name BuildingInfoPanel
extends VBoxContainer

# Corpo del pannello edificio dentro GameInfoTabs.selection_content — Step 5 del piano "centra
# generalizzato + selezione edifici" (richiesta utente, 2026-09-04), stesso principio "muto" di
# VegetationInfoPanel/HumanIndividualInfoPanel: istanziato dinamicamente da GameScene, riceve solo
# l'oggetto Building già risolto (stesso schema di HumanIndividualInfoPanel.show_individual, che
# prende l'HumanIndividual intero) — non conosce GameScene/selezione/BuildingCalculator. Nessun
# tr() per le etichette strutturali (stesso trattamento hardcoded degli altri pannelli di
# ispezione), TRANNE building.rules.building_name: quel campo è esplicitamente documentato come
# chiave tr() in BuildingRules stessa. Nascosto di default (nessuna selezione all'apertura della
# scena). Solo consultazione, nessuna interazione (a differenza di VegetationInfoPanel.
# cut_requested) — non esiste ancora alcuna azione giocatore su un edificio già piazzato.
#
# TypeLabel (Step 6, richiesta utente 2026-09-04): mai esistita qui come nodo separato dall'inizio
# — sollevata direttamente dentro GameInfoTabs.title_label, sulla STESSA riga del bottone "🎯".
# GameScene la imposta (game_info_tabs.set_selection_title) subito insieme a show_building, con la
# stessa formula tr(building.rules.building_name)/building_type_name che sarebbe finita qui.

@onready var status_label: Label = $StatusLabel
@onready var durability_label: Label = $DurabilityLabel
@onready var built_year_label: Label = $BuiltYearLabel
@onready var stored_resources_label: Label = $StoredResourcesLabel
@onready var id_label: Label = $IdLabel


func _ready() -> void:
	clear()


func show_building(building: Building) -> void:
	visible = true
	status_label.text = "Status: " + ("Complete" if building.is_complete else "Under construction")

	var max_durability: int = building.rules.max_durability if building.rules != null else 0
	durability_label.text = "Durability: %d/%d" % [building.current_durability, max_durability]

	built_year_label.text = "Built: year %d" % building.built_year if building.built_year >= 0 else "Not yet built"

	if building.stored_resources.is_empty():
		stored_resources_label.visible = false
	else:
		stored_resources_label.visible = true
		var entries: Array[String] = []
		for resource_name in building.stored_resources:
			entries.append("%s %d" % [resource_name, building.stored_resources[resource_name]])
		stored_resources_label.text = "Stored: " + ", ".join(entries)

	id_label.text = "ID: %d" % building.id


func clear() -> void:
	visible = false
