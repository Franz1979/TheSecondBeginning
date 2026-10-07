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


# Stesso principio "muto" di HumanPopulationInfoPanel.individual_center_requested — questo
# pannello non decide MAI da sé selezione/camera, si limita a segnalare "l'utente ha chiesto
# questo edificio".
signal building_center_requested(building: Building)

const CENTER_BUTTON_TEXT := "🎯"

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
	# Edifici a pezzi collegati (2026-10-07, richiesta utente — BuildingRules.is_linear: vallo, in futuro mura e strade):
	# una sola riga per tipo, al posto del primo pezzo nell'ordine dell'elenco (_build_linear_group_row). Il conteggio in
	# cima conta comunque ogni pezzo.
	var linear_groups: Dictionary = {}  # building_type_name -> Array di Building
	for building in buildings:
		if building.rules != null and building.rules.is_linear:
			if not linear_groups.has(building.building_type_name):
				linear_groups[building.building_type_name] = []
			(linear_groups[building.building_type_name] as Array).append(building)
	var shown_linear_types: Dictionary = {}
	for building in buildings:
		if building.rules != null and building.rules.is_linear:
			if shown_linear_types.has(building.building_type_name):
				continue
			shown_linear_types[building.building_type_name] = true
			list_container.add_child(_build_linear_group_row(linear_groups[building.building_type_name]))
			continue
		var row := HBoxContainer.new()
		# Bottone "vai lì" per riga, a SINISTRA (2026-09-12, richiesta utente). Tornato il 2026-10-07: la riga cliccabile
		# si è rivelata poco intuitiva.
		row.add_child(_make_center_button(building))

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Stessa formula tipo/stato già in uso in BuildingInfoPanel.show_building — coerenza tra i
		# due pannelli (elenco vs dettaglio) per lo stesso concetto.
		var type_name: String = tr(building.rules.building_name) if building.rules != null else building.building_type_name
		label.text = "%s #%d — %s" % [type_name, building.id, tr(_status_key(building))]
		row.add_child(label)

		list_container.add_child(row)


# Stato di un edificio (chiave tr()): completo / in costruzione; "da demolire" o "in demolizione" (2026-09-27), come nel
# pannello di dettaglio.
func _status_key(building: Building) -> String:
	if building.is_marked_for_demolition:
		var demolition_started: bool = float(building.construction_progress.get(DemolishAction.LABOR_KEY, 0.0)) > 0.0
		return "building_status_demolition_in_progress" if demolition_started else "building_status_marked_for_demolition"
	return "building_status_complete" if building.is_complete else "building_status_under_construction"


# Stato -> chiave tr() del conteggio nel riassunto di una riga a pezzi collegati ("12 completi"), nell'ordine mostrato.
const LINEAR_GROUP_COUNT_KEYS := {
	"building_status_complete": "buildings_panel_group_complete",
	"building_status_under_construction": "buildings_panel_group_under_construction",
	"building_status_marked_for_demolition": "buildings_panel_group_marked_for_demolition",
	"building_status_demolition_in_progress": "buildings_panel_group_demolition_in_progress",
}


# Riga unica di un tipo a pezzi collegati, non espandibile: "Vallo di terra (13) — 12 completi, 1 in costruzione", o con
# un solo stato "Vallo di terra (13) — Completo". Su una riga, troncata con i puntini (testo intero nel tooltip). 🎯:
# seleziona e centra il primo pezzo in costruzione, altrimenti il primo pezzo.
func _build_linear_group_row(pieces: Array) -> Control:
	var first: Building = pieces[0]
	var target: Building = null
	var count_by_status: Dictionary = {}
	for piece in pieces:
		var status_key := _status_key(piece)
		count_by_status[status_key] = int(count_by_status.get(status_key, 0)) + 1
		if target == null and not piece.is_complete and not piece.is_marked_for_demolition:
			target = piece
	if target == null:
		target = first
	var status_text := ""
	if count_by_status.size() == 1:
		status_text = tr(String(count_by_status.keys()[0]))
	else:
		var parts: Array[String] = []
		for status_key in LINEAR_GROUP_COUNT_KEYS.keys():
			if count_by_status.has(status_key):
				parts.append(tr(LINEAR_GROUP_COUNT_KEYS[status_key]).format({"count": count_by_status[status_key]}))
		status_text = ", ".join(parts)
	var type_name: String = tr(first.rules.building_name) if first.rules != null else first.building_type_name
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.text = "%s (%d) — %s" % [type_name, pieces.size(), status_text]
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_child(_make_center_button(target))
	row.add_child(label)
	return row


# 🎯 a sinistra della riga: seleziona e centra `building` (building_center_requested).
func _make_center_button(building: Building) -> Button:
	var center_button := Button.new()
	center_button.text = CENTER_BUTTON_TEXT
	center_button.tooltip_text = tr("buildings_panel_center_button_tooltip")
	center_button.flat = true
	center_button.add_theme_font_size_override("font_size", 10)
	center_button.custom_minimum_size = Vector2(20, 0)
	center_button.pressed.connect(_on_center_button_pressed.bind(building))
	return center_button


func _on_center_button_pressed(building: Building) -> void:
	building_center_requested.emit(building)


func _on_expand_pressed() -> void:
	_expanded = not _expanded
	list_container.visible = _expanded
	expand_button.text = "-" if _expanded else "+"
