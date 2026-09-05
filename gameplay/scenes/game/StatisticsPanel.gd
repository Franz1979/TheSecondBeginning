class_name StatisticsPanel
extends Window

# Pannello Statistiche di GameScene. Stesso pattern di apertura/chiusura già in uso da HelpDialog/
# OptionsMenu/SystemMenuDialog (Window standalone, popup_centered auto-dimensionato al contenuto
# attuale via get_contents_minimum_size(), X nativa nascosta e resa inerte, CloseButton esplicito,
# trattato come dialogo bloccante da GameScene — visibility_changed collegato a
# _on_blocking_dialog_visibility_changed, stesso schema degli altri: mette in pausa il clock mentre
# è aperto).
#
# TabContainer con una sola tab "Mortalità" per ora (Step A: struttura; Step B: contenuto sotto) —
# predispone la struttura per tab future senza dover ristrutturare il contenitore, stesso principio
# già seguito da MacroCellDetailPanel (TAB_* + set_tab_title, mai toggle di .visible sui figli).
#
# Step B (2026-09-05): tutto ricalcolato AL VOLO da game_data.death_events ogni volta che
# open_dialog() viene chiamato — nessuna cache, nessun aggregato salvato, coerente con GameData.
# death_events restando puro log grezzo (vedi Step 8). Nessuna modifica a death_events/DeathTypes o
# alla logica Step 6/7/8: questo file è puramente di lettura/presentazione. Contenuto hardcoded
# (non tr()) — stessa convenzione già in uso per i pannelli di ispezione dati del progetto
# (VegetationInfoPanel/HumanIndividualInfoPanel/HumanPopulationInfoPanel), a differenza della
# "chrome" del pannello sopra (titolo finestra/tab/CloseButton), che invece resta tr() come il
# resto del sistema di menu/dialog.
const TAB_MORTALITY := 0

@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
@onready var total_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/TotalLabel
@onready var average_age_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/AverageAgeLabel
@onready var cause_distribution_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/CauseDistributionLabel
@onready var deaths_per_year_label: Label = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/DeathsPerYearLabel
@onready var death_list_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/MortalityTab/DeathListScroll/DeathListContainer


func _ready() -> void:
	title = tr("statistics_tooltip")
	tab_container.set_tab_title(TAB_MORTALITY, tr("statistics_tab_mortality"))
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() + X nascosta (stesso motivo/meccanismo di
	# SystemMenuDialog._hide_native_close_button): si chiude solo dal CloseButton esplicito.
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)


func open_dialog(game_data: GameData) -> void:
	_refresh_mortality_tab(game_data.death_events)
	exclusive = true
	size = Vector2i(get_contents_minimum_size()) + Vector2i(0, 20)
	popup_centered()


func _refresh_mortality_tab(death_events: Array[Dictionary]) -> void:
	total_label.text = "Morti totali: %d" % death_events.size()

	if death_events.is_empty():
		average_age_label.text = "Età media alla morte: N/D"
	else:
		var age_sum := 0
		for event in death_events:
			age_sum += int(event["age_at_death"])
		average_age_label.text = "Età media alla morte: %.1f" % (float(age_sum) / death_events.size())

	# Itera l'ENUM (non i soli valori presenti negli eventi) — una causa futura senza eventi
	# registrati compare comunque a 0/0%, invece di sparire silenziosamente dalla lista.
	var cause_counts := {}
	for cause_name in DeathTypes.DeathCause.keys():
		cause_counts[cause_name] = 0
	for event in death_events:
		cause_counts[_cause_name(int(event["cause"]))] += 1
	var cause_lines: Array[String] = []
	for cause_name in DeathTypes.DeathCause.keys():
		var count: int = cause_counts[cause_name]
		var percentage := 100.0 * count / death_events.size() if not death_events.is_empty() else 0.0
		cause_lines.append("%s: %d (%.0f%%)" % [String(cause_name).capitalize(), count, percentage])
	cause_distribution_label.text = "Distribuzione per causa:\n" + "\n".join(cause_lines)

	var deaths_by_year := {}
	for event in death_events:
		var year: int = int(event["year"])
		deaths_by_year[year] = deaths_by_year.get(year, 0) + 1
	var years := deaths_by_year.keys()
	years.sort()
	var year_lines: Array[String] = []
	for year in years:
		year_lines.append("Anno %d: %d" % [year, deaths_by_year[year]])
	deaths_per_year_label.text = "Morti per anno:\n" + ("\n".join(year_lines) if not year_lines.is_empty() else "N/D")

	for child in death_list_container.get_children():
		child.queue_free()
	for event in death_events:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 10)
		label.text = "%s — età %d, %s (anno %d, giorno %d)" % [
			event["name"], event["age_at_death"], String(_cause_name(int(event["cause"]))).capitalize(),
			event["year"], event["day"],
		]
		death_list_container.add_child(label)


func _cause_name(cause: int) -> String:
	return DeathTypes.DeathCause.keys()[cause]
