class_name HuntTrapStatsPanel
extends CanvasLayer

# Scheda di debug «Caccia grossi animali» (2026-11-15, richiesta utente): tentativi e riuscite di caccia per specie,
# trappole in gioco e catture per trappola e specie, spinte verso le fosse — totale o per anno. Si apre e si chiude dal
# primo bottone a sinistra della DebugBar (🏹). Riquadro compatto nell'angolo in alto a sinistra, sotto la barra, che NON
# ferma il gioco (2026-11-15, richiesta utente: «aperta mentre ci gioco»): a scheda aperta si aggiorna da sé ogni
# REFRESH_INTERVAL_SEC secondi reali, e ricostruisce le righe solo se i dati sono cambiati. Costruita in codice, nessuno
# stato proprio: rilegge GameData (HuntTrapStatsService, placed_traps, broken_traps).
# STRUMENTO DI DEBUG: da togliere prima del player finale.

const HEADER_COLOR := Color(0.85, 0.75, 1.0)
const DIM_COLOR := Color(0.65, 0.62, 0.7)
const FONT_SIZE := 11
const TITLE_FONT_SIZE := 12
const REFRESH_INTERVAL_SEC := 1.0
# Sotto la DebugBar (in alto a sinistra a 10,10, alta ~48).
const PANEL_POSITION := Vector2(10, 66)
# Altezza massima rispetto alla finestra: oltre, si scorre.
const MAX_HEIGHT_FRACTION := 0.7

var _game_data: GameData
var _world: World
var _panel: PanelContainer
var _period_button: OptionButton
var _scroll: ScrollContainer
var _content: VBoxContainer
var _refresh_timer: float = 0.0
var _last_signature: String = ""


func _init() -> void:
	layer = 10
	visible = false


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.position = PANEL_POSITION
	var style := StyleBoxFlat.new()
	# In trasparenza (richiesta utente): la mappa si vede sotto.
	style.bg_color = Color(0.22, 0.12, 0.28, 0.5)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "🏹 Caccia"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_period_button = OptionButton.new()
	_period_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_period_button.item_selected.connect(func(_index: int) -> void: _refresh(true))
	header.add_child(_period_button)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.add_theme_font_size_override("font_size", FONT_SIZE)
	close_button.pressed.connect(hide)
	header.add_child(close_button)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 2)
	_scroll.add_child(_content)


func toggle(game_data: GameData, world: World) -> void:
	if visible:
		hide()
	else:
		open_dialog(game_data, world)


func open_dialog(game_data: GameData, world: World) -> void:
	_game_data = game_data
	_world = world
	_fill_periods()
	show()
	_refresh(true)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL_SEC:
		return
	_refresh_timer = 0.0
	# Anno nuovo nel menu dei periodi appena l'anno rotola.
	if _game_data != null and not _has_period(_game_data.year):
		_fill_periods()
	_refresh(false)


func _has_period(period: int) -> bool:
	for i in range(_period_button.item_count):
		if int(_period_button.get_item_metadata(i)) == period:
			return true
	return false


# "Totale", "Dal caricamento", poi gli anni dal più recente; l'anno in corso c'è sempre. Resta selezionato il periodo di prima.
func _fill_periods() -> void:
	var previous: int = int(_period_button.get_selected_metadata()) if _period_button.selected >= 0 else HuntTrapStatsService.PERIOD_TOTAL
	_period_button.clear()
	_period_button.add_item("Totale")
	_period_button.set_item_metadata(0, HuntTrapStatsService.PERIOD_TOTAL)
	_period_button.add_item("Dal caricamento")
	_period_button.set_item_metadata(1, HuntTrapStatsService.PERIOD_SINCE_LOAD)
	var years := HuntTrapStatsService.years(_game_data)
	if _game_data != null and not years.has(_game_data.year):
		years.append(_game_data.year)
	years.sort()
	years.reverse()
	for year in years:
		_period_button.add_item("Anno %d" % year)
		_period_button.set_item_metadata(_period_button.item_count - 1, year)
	_period_button.select(0)
	for i in range(_period_button.item_count):
		if int(_period_button.get_item_metadata(i)) == previous:
			_period_button.select(i)


# Ricostruisce le righe solo se i dati sono cambiati (o se `force`).
func _refresh(force: bool) -> void:
	if _game_data == null:
		return
	var year: int = int(_period_button.get_selected_metadata()) if _period_button.selected >= 0 else -1
	var stats := HuntTrapStatsService.get_stats(_game_data, year)
	var traps_now := _traps_now()
	var demand := HuntTrapStatsService.hides_demand(_game_data, _world)
	var signature := str(year) + str(stats) + str(traps_now) + str(demand)
	if not force and signature == _last_signature:
		return
	_last_signature = signature
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_add_hunt_section(stats.get("hunt", {}))
	_add_traps_now_section(traps_now)
	_add_trap_catch_section(stats.get("trap_placed", {}), stats.get("trap_catch", {}), stats.get("trap_outcome", {}))
	_add_drive_section(stats.get("drive", {}))
	_add_hides_section(stats.get("hides", {}), demand)
	_fit_size()


# Larghezza del contenuto, altezza fino a MAX_HEIGHT_FRACTION della finestra (oltre si scorre).
func _fit_size() -> void:
	var content_size := _content.get_combined_minimum_size()
	var max_height := get_viewport().get_visible_rect().size.y * MAX_HEIGHT_FRACTION
	_scroll.custom_minimum_size = Vector2(content_size.x, minf(content_size.y, max_height))
	_panel.reset_size()


func _add_hunt_section(hunt: Dictionary) -> void:
	_add_title("Caccia", "Tentativo = un inseguimento iniziato su una preda (i riavvicinamenti sulla stessa preda non contano di nuovo). Tiri = armi partite; A segno = colpi a segno, anche non letali. U/T = uccise su tentativi. Macell. = carcasse di caccia macellate; Marcite = carcasse di caccia marcite a terra prima della macellazione.")
	var counters := [HuntTrapStatsService.HUNT_ATTEMPTS, HuntTrapStatsService.HUNT_THROWS, HuntTrapStatsService.HUNT_HITS,
		HuntTrapStatsService.HUNT_KILLS, HuntTrapStatsService.HUNT_BUTCHERED, HuntTrapStatsService.HUNT_ROTTED]
	var rows: Array = []
	var totals := [0, 0, 0, 0, 0, 0]
	for species in _sorted_keys(hunt):
		var entry: Dictionary = hunt[species]
		var values := []
		for i in range(counters.size()):
			values.append(int(entry.get(counters[i], 0)))
			totals[i] += values[i]
		rows.append([species] + _hunt_cells(values))
	if rows.size() > 1:
		rows.append(["Tutte"] + _hunt_cells(totals))
	_add_table(["Specie", "Tent.", "Tiri", "Segno", "Uccise", "U/T", "Macell.", "Marcite"], rows, "nessun tentativo")


static func _hunt_cells(values: Array) -> Array:
	return [str(values[0]), str(values[1]), str(values[2]), str(values[3]), _percent(values[3], values[0]), str(values[4]), str(values[5])]


# Trappole montate adesso (non dipende dal periodo): per tipo, quante, quante con prede dentro e quante prede, rotte.
func _traps_now() -> Dictionary:
	var by_name := {}
	for trap in _game_data.placed_traps:
		var entry: Dictionary = by_name.get(trap.trap_name, {"placed": 0, "with_catch": 0, "catches": 0, "broken": 0})
		entry["placed"] += 1
		if trap.get_caught() > 0:
			entry["with_catch"] += 1
			entry["catches"] += trap.get_caught()
		by_name[trap.trap_name] = entry
	for broken in _game_data.broken_traps:
		var trap_name := String(broken.get("trap_name", "?"))
		var entry: Dictionary = by_name.get(trap_name, {"placed": 0, "with_catch": 0, "catches": 0, "broken": 0})
		entry["broken"] += 1
		by_name[trap_name] = entry
	return by_name


func _add_traps_now_section(by_name: Dictionary) -> void:
	_add_title("Trappole adesso", "Montate ora (non dipende dal periodo): quante, quante con prede dentro, quante prede, quante rotte a terra.")
	var rows: Array = []
	for trap_name in _sorted_keys(by_name):
		var entry: Dictionary = by_name[trap_name]
		rows.append([_trap_label(trap_name), str(entry["placed"]), str(entry["with_catch"]), str(entry["catches"]), str(entry["broken"])])
	_add_table(["Trappola", "Mont.", "Piene", "Prede", "Rotte"], rows, "nessuna trappola montata")


func _add_trap_catch_section(placed: Dictionary, catches: Dictionary, outcomes: Dictionary) -> void:
	_add_title("Posate e catture", "Catt. = catture, contate quando la preda entra. Recup. = prede tolte allo svuotamento (macellate sul posto o portate vive alla tettoia); Marcite = marcite dentro, o perse con la trappola che si rompe. Una preda entrata prima dell'inizio del periodo può essere recuperata o marcire dentro il periodo. C/P = catture per trappola posata.")
	var names := {}
	for dict in [placed, catches, outcomes]:
		for trap_name in dict:
			names[trap_name] = true
	var rows: Array = []
	for trap_name in _sorted_keys(names):
		var by_species: Dictionary = catches.get(trap_name, {})
		var outcome_by_species: Dictionary = outcomes.get(trap_name, {})
		var species_names := {}
		for dict in [by_species, outcome_by_species]:
			for species in dict:
				species_names[species] = true
		var totals := [0, 0, 0, 0]
		var species_rows: Array = []
		for species in _sorted_keys(species_names):
			var outcome: Dictionary = outcome_by_species.get(species, {})
			var values := [int(by_species.get(species, 0)), int(outcome.get(HuntTrapStatsService.TRAP_RECOVERED, 0)),
				int(outcome.get(HuntTrapStatsService.TRAP_SPOILED, 0)), int(outcome.get(HuntTrapStatsService.TRAP_ESCAPED, 0))]
			for i in range(4):
				totals[i] += values[i]
			species_rows.append(["", "", "  " + String(species), str(values[0]), str(values[1]), str(values[2]), str(values[3]), ""])
		var placed_count := int(placed.get(trap_name, 0))
		var row := [_trap_label(trap_name), str(placed_count), "Tutte", str(totals[0]), str(totals[1]), str(totals[2]),
			str(totals[3]), _ratio(totals[0], placed_count)]
		if species_rows.size() == 1:
			row[2] = String(species_rows[0][2]).strip_edges()
		elif species_rows.is_empty():
			row[2] = "-"
		rows.append(row)
		if species_rows.size() > 1:
			rows.append_array(species_rows)
	_add_table(["Trappola", "Pos.", "Specie", "Catt.", "Recup.", "Marcite", "Scapp.", "C/P"], rows, "nessuna posata né cattura")


func _add_drive_section(drive: Dictionary) -> void:
	if drive.is_empty():
		return
	_add_title("Spinte alle fosse", "Spinte di una mandria verso le fosse e animali partiti.")
	var rows: Array = []
	for species in _sorted_keys(drive):
		var entry: Dictionary = drive[species]
		rows.append([species, str(int(entry.get("drives", 0))), str(int(entry.get("animals", 0)))])
	_add_table(["Specie", "Spinte", "Animali"], rows, "")


func _add_hides_section(produced: Dictionary, demand: Dictionary) -> void:
	_add_title("Pelli", "Prodotte = pelli grezze uscite dalla macellazione nel periodo: di caccia, dallo svuotamento delle trappole, altro (allevamento, carcasse non di caccia). Richieste adesso: Cant. = cantieri, Ripar. = riparazioni degli edifici danneggiati, Prod. = input mancanti alle produzioni in corso sulle postazioni, Ordini = ordini Produci non ancora presi; Mancano = richieste meno scorte del villaggio.")
	var total := 0
	var parts: PackedStringArray = []
	for source in [HuntTrapStatsService.HIDE_SOURCE_HUNT, HuntTrapStatsService.HIDE_SOURCE_TRAPS, HuntTrapStatsService.HIDE_SOURCE_OTHER]:
		var amount := int(produced.get(source, 0))
		total += amount
		parts.append("%s %d" % [source, amount])
	_content.add_child(_cell("Prodotte: %d  (%s)" % [total, ", ".join(parts)], Color.WHITE))
	var rows: Array = []
	for name in HuntTrapStatsService.HIDE_RESOURCES:
		var entry: Dictionary = demand.get(name, {})
		var values := [int(entry.get("construction", 0)), int(entry.get("repair", 0)), int(entry.get("production", 0)),
			int(entry.get("orders", 0)), int(entry.get("stock", 0)), int(entry.get("missing", 0))]
		if name != "hide" and values.max() == 0:
			continue
		var row := [_trap_label(name)]
		for value in values:
			row.append(str(value))
		rows.append(row)
	_add_table(["Richieste adesso", "Cant.", "Ripar.", "Prod.", "Ordini", "Scorte", "Mancano"], rows, "")


func _add_title(text: String, tooltip: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", HEADER_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = TooltipText.wrap(tooltip)
	_content.add_child(label)


func _add_table(headers: Array, rows: Array, empty_text: String) -> void:
	if rows.is_empty():
		_content.add_child(_cell(empty_text, DIM_COLOR))
		return
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	for header in headers:
		grid.add_child(_cell(String(header), DIM_COLOR))
	for row in rows:
		for value in row:
			grid.add_child(_cell(String(value), Color.WHITE))
	_content.add_child(grid)


static func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


static func _trap_label(trap_name: String) -> String:
	var display := IconRegistry.get_resource_display_name(trap_name)
	return trap_name if display == "" else display


static func _percent(part: int, whole: int) -> String:
	return "-" if whole <= 0 else "%.0f%%" % (100.0 * part / whole)


static func _ratio(part: int, whole: int) -> String:
	return "-" if whole <= 0 else "%.2f" % (float(part) / whole)


static func _sorted_keys(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	return keys
