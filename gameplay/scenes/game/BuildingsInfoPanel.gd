class_name BuildingsInfoPanel
extends VBoxContainer

# Corpo del pannello edifici dentro GameInfoTabs.buildings_tab (2026-09-12, richiesta utente — "un
# info panel edifici, concettualmente simile a quella population, in cui elenchi tutti gli
# edifici, il tipo e magari lo stato, con il bottoncino di vai lì come per le persone") — stesso
# principio "muto"/stessa struttura di HumanPopulationInfoPanel: riceve solo dati già risolti
# (Array[Building], GameScene già ha macro_world.buildings a portata di mano), un bottone "🎯" per
# riga che emette solo un segnale (mai selezione/camera decise qui dentro), nessuno scroll/
# paginazione (stesso numero ridotto di edifici per cui la lista popolazione già non ne aveva
# bisogno).
#
# A differenza di HumanPopulationInfoPanel (popolato una volta sola dopo il seeding, mai
# aggiornato — gap noto, mai chiuso, non toccato qui): questo pannello VA aggiornato ogni volta
# che un edificio cambia stato (piazzato/completato) o al tick giornaliero, perché "in
# costruzione"/"completo" è per natura un dato che cambia nel tempo — vedi GameScene per i punti
# esatti da cui show_buildings viene richiamato.

const CENTER_BUTTON_TEXT := "🎯"

# Stesso principio "muto" di HumanPopulationInfoPanel.individual_center_requested — questo
# pannello non decide MAI da sé selezione/camera, si limita a segnalare "l'utente ha chiesto
# questo edificio".
signal building_center_requested(building: Building)

@onready var summary_label: Label = $SummaryRow/SummaryLabel
@onready var expand_button: Button = $SummaryRow/ExpandButton
@onready var list_container: VBoxContainer = $ListContainer

var _expanded: bool = false


func _ready() -> void:
	expand_button.text = "+"
	expand_button.pressed.connect(_on_expand_pressed)
	list_container.visible = false


# buildings già risolto dal chiamante (GameScene) come Array[Building] — stesso principio "dati
# già pronti" del resto della famiglia di pannelli. Ricostruita per intero ad ogni chiamata (stesso
# principio "rebuild da zero" già in uso ovunque nel progetto per contenuto derivato, es.
# HumanPopulationInfoPanel.show_population) — nessun aggiornamento incrementale riga-per-riga, il
# costo resta trascurabile per il numero di edifici in gioco oggi.
func show_buildings(buildings: Array[Building]) -> void:
	var complete_count := 0
	for building in buildings:
		if building.is_complete:
			complete_count += 1
	summary_label.text = tr("buildings_panel_summary_label").format({
		"total": buildings.size(),
		"complete": complete_count,
		"under_construction": buildings.size() - complete_count,
	})

	for child in list_container.get_children():
		child.queue_free()
	for building in buildings:
		var row := HBoxContainer.new()
		# Bottone "vai lì" per riga, ora a SINISTRA (2026-09-12, richiesta utente — "per coerenza
		# anche nel pannello edifici metti il centra a sx", stesso ordine appena adottato in
		# HumanPopulationInfoPanel) — STESSO trattamento compatto (flat, font ridotto, larghezza
		# minima) di prima, solo spostato prima della label nell'ordine di aggiunta.
		var center_button := Button.new()
		center_button.text = CENTER_BUTTON_TEXT
		center_button.tooltip_text = tr("buildings_panel_center_button_tooltip")
		center_button.flat = true
		center_button.add_theme_font_size_override("font_size", 10)
		center_button.custom_minimum_size = Vector2(20, 0)
		center_button.pressed.connect(_on_center_button_pressed.bind(building))
		row.add_child(center_button)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Stessa formula tipo/stato già in uso in BuildingInfoPanel.show_building — coerenza tra i
		# due pannelli (elenco vs dettaglio) per lo stesso concetto.
		var type_name: String = tr(building.rules.building_name) if building.rules != null else building.building_type_name
		var status_text: String = (
			tr("building_status_complete") if building.is_complete else tr("building_status_under_construction")
		)
		label.text = "%s #%d — %s" % [type_name, building.id, status_text]
		row.add_child(label)

		list_container.add_child(row)


func _on_center_button_pressed(building: Building) -> void:
	building_center_requested.emit(building)


func _on_expand_pressed() -> void:
	_expanded = not _expanded
	list_container.visible = _expanded
	expand_button.text = "-" if _expanded else "+"
