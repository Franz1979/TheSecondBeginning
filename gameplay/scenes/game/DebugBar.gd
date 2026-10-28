class_name DebugBar
extends PanelContainer

# Barra di debug di GameScene — ancorata in alto a sinistra, colore volutamente diverso dal blu
# usato dal resto della UI (vedi .tscn) per segnalare visivamente che questi controlli sono
# temporanei e spariranno prima della build finale del player (stesso principio gia' scritto nei
# commenti di GameInfoPanel/GameScene per world_debug/macro_cell_debug, solo ora davvero separato
# dalla UI definitiva invece di conviverci dentro). Un solo bottone di controllo (stesso schema
# "un passo indietro" di BuildBar, qui pero' solo due stati — espanso/richiuso, nessuna gerarchia
# di sottomenu: 5 azioni piatte + un'etichetta, non categorie). Muta come GameInfoPanel/BuildBar:
# non conosce World/GameData, si limita a esporre content_row (pubblico, per set_slot_toggled) e
# set_coords() (pubblico) e a inoltrare action_pressed — GameScene resta l'unico posto che decide
# cosa fare. ContentGroup (ContentRow + CoordsLabel) e' il blocco che si nasconde/mostra insieme
# da _apply_state — coords/anno avanzamento sono debug tanto quanto i quattro toggle/salti
# originali (richiesta utente, 2026-09-01: liberare righe nella Sidebar).

@onready var control_button: Button = $MarginContainer/HBoxContainer/ControlButton
@onready var content_group: HBoxContainer = $MarginContainer/HBoxContainer/ContentGroup
@onready var content_row: IconButtonRow = $MarginContainer/HBoxContainer/ContentGroup/ContentRow
@onready var coords_label: Label = $MarginContainer/HBoxContainer/ContentGroup/CoordsLabel
# Celle vive (2026-09-26, richiesta utente — debug): numero nel testo, elenco con i motivi di attivazione
# nel tooltip — vedi set_live_cells e GameScene._refresh_debug_live_cells.
@onready var live_cells_label: Label = $MarginContainer/HBoxContainer/ContentGroup/LiveCellsLabel
# Riepilogo animali della macrocella del giocatore (quota cella / individui istanziati per specie)
# — vedi set_animal_summary sotto e GameScene._refresh_debug_animal_summary.
@onready var animal_summary_label: Label = $MarginContainer/HBoxContainer/ContentGroup/AnimalSummaryLabel
# FPS (Engine.get_frames_per_second, già mediato dal motore sull'ultimo secondo). Unico dato che
# questa barra legge da sé invece di riceverlo da GameScene: è globale del motore, non dello stato
# di gioco — vedi _process.
@onready var fps_label: Label = $MarginContainer/HBoxContainer/ContentGroup/FpsLabel
var _last_fps: int = -1
# Tempo reale di gioco (2026-10-25, richiesta utente): "in partita" e "in play" della partita, da GameScene
# (set_playtime, con i riepiloghi di debug).
@onready var playtime_label: Label = $MarginContainer/HBoxContainer/ContentGroup/PlaytimeLabel
# Eventi casuali (2026-09-26, richiesta utente — gameplay/events/): menu a tendina con tutti gli eventi definiti
# (RandomEventService.list_rules, nome tradotto, id come metadata) e pulsante per scatenare quello scelto.
@onready var random_event_option_button: OptionButton = $MarginContainer/HBoxContainer/ContentGroup/RandomEventOptionButton
@onready var random_event_apply_button: Button = $MarginContainer/HBoxContainer/ContentGroup/RandomEventApplyButton
# Addomesticazione (2026-10-26, passo 1): +100 punti al cane (dal lupo), inoltrato come action_pressed a
# GameScene._on_debug_action_pressed; il testo mostra punti/soglia (set_domestication_progress).
@onready var domestication_button: Button = $MarginContainer/HBoxContainer/ContentGroup/DomesticationButton
# Branco di lupi che frequenta il villaggio (2026-10-26): numero di lupi, dettaglio per lupo nel tooltip
# (set_wolf_pack).
@onready var wolves_label: Label = $MarginContainer/HBoxContainer/ContentGroup/WolvesLabel

signal action_pressed(action_id: StringName)
# Evento casuale da scatenare subito (id di RandomEventRules), dal menu a tendina degli eventi.
signal random_event_trigger_requested(event_id: String)
# Barra aperta o chiusa dal suo pulsante (2026-10-04): GameScene aggiorna i riepiloghi di debug solo a barra aperta e
# subito alla riapertura.
signal expanded_changed(expanded: bool)

var _expanded: bool = true


func is_expanded() -> bool:
	return _expanded


func _ready() -> void:
	content_row.configure_slot(
		0, "🌱", tr("toggle_flora_updates_tooltip"), &"toggle_flora_updates", tr("toggle_flora_updates_description")
	)
	content_row.configure_slot(
		1, "🐇", tr("toggle_animals_visibility_tooltip"), &"toggle_animals_visibility",
		tr("toggle_animals_visibility_description")
	)
	content_row.configure_slot(
		2, "🌍", tr("game_info_world_debug"), &"world_debug", tr("game_info_world_debug_description")
	)
	content_row.configure_slot(
		3, "🔬", tr("game_info_macro_cell_debug"), &"macro_cell_debug", tr("game_info_macro_cell_debug_description")
	)
	# Bottone "+1" (advance_year) e bottone del malato tolti (2026-10-25, richiesta utente — non servono più; per il malato
	# c'è l'evento della malattia nel menu degli eventi): le azioni restano in GameScene._on_debug_action_pressed.
	content_row.action_pressed.connect(func(action_id: StringName) -> void: action_pressed.emit(action_id))
	control_button.pressed.connect(_on_control_button_pressed)
	playtime_label.tooltip_text = TooltipText.wrap("Tempo reale di questa partita: Partita = con la partita aperta, pause comprese; Play = solo con il tempo che scorre")
	animal_summary_label.tooltip_text = TooltipText.wrap("Animali della macrocella del giocatore: quota della cella / individui istanziati (≠ = discrepanza)")
	_fill_random_events()
	# Barra stretta (2026-10-26, richiesta utente): solo "▶", il nome dell'azione nel tooltip.
	random_event_apply_button.text = "▶"
	random_event_apply_button.tooltip_text = TooltipText.wrap(tr("debug_random_event_apply") + ": " + tr("debug_random_event_apply_tooltip"))
	random_event_apply_button.pressed.connect(_on_random_event_apply_pressed)
	domestication_button.pressed.connect(func() -> void: action_pressed.emit(&"domestication_add_wolf"))
	_apply_state()


func _fill_random_events() -> void:
	random_event_option_button.clear()
	for rules in RandomEventService.list_rules():
		random_event_option_button.add_item(tr(rules.display_name))
		random_event_option_button.set_item_metadata(random_event_option_button.item_count - 1, rules.id)
	random_event_apply_button.disabled = random_event_option_button.item_count == 0


func _on_random_event_apply_pressed() -> void:
	var selected := random_event_option_button.selected
	if selected < 0:
		return
	random_event_trigger_requested.emit(String(random_event_option_button.get_item_metadata(selected)))


# Aggiorna l'etichetta FPS solo quando il valore cambia (il motore lo ricalcola una volta al
# secondo) e solo a barra espansa: nessun lavoro per frame oltre a un confronto tra interi.
func _process(_delta: float) -> void:
	if not _expanded:
		return
	var fps := int(Engine.get_frames_per_second())
	if fps == _last_fps:
		return
	_last_fps = fps
	fps_label.text = "FPS: %d" % fps


func _on_control_button_pressed() -> void:
	_expanded = not _expanded
	_apply_state()
	expanded_changed.emit(_expanded)


func _apply_state() -> void:
	content_group.visible = _expanded
	control_button.text = "◀" if _expanded else "▶"
	# Questo nodo e' figlio diretto di CanvasLayer (non di un Container che lo ridimensiona da
	# solo), quindi il suo Rect2 resta quello scritto in .tscn finche' nessuno lo cambia
	# esplicitamente — reset_size() lo riporta alla propria dimensione minima corrente ad ogni
	# cambio di stato, cosi' il pannello si restringe davvero quando content_group si nasconde
	# invece di lasciare uno spazio viola vuoto della stessa larghezza di prima.
	reset_size()


# Inoltrato da GameScene per riflettere lo stato dei due toggle (flora/animali) — stesso schema
# di IconButtonRow.set_slot_toggled, GameScene continua a decidere QUANDO chiamarlo, questo
# metodo esiste solo perche' content_row non e' esposto direttamente al chiamante.
func set_slot_toggled(index: int, is_active: bool) -> void:
	content_row.set_slot_toggled(index, is_active)


# Spostato qui da GameInfoPanel.set_coords (richiesta utente, 2026-09-01) — stesso formato
# testuale di prima ("Coords: x, y"), GameScene chiama questo invece di quello.
func set_coords(x: int, y: int) -> void:
	coords_label.text = "Coords: " + str(x) + ", " + str(y)


# Tempo reale di gioco in secondi, mostrato in ore e minuti; ridimensiona solo se il testo cambia.
func set_playtime(in_game_seconds: float, playing_seconds: float) -> void:
	var text := "Partita %s · Play %s" % [_format_hours_minutes(in_game_seconds), _format_hours_minutes(playing_seconds)]
	if playtime_label.text == text:
		return
	playtime_label.text = text
	reset_size()


# Barra stretta (2026-10-26): il pulsante resta "🐕+100", i punti vanno nel tooltip.
func set_domestication_progress(points: int, required: int) -> void:
	domestication_button.tooltip_text = TooltipText.wrap(
		"Debug: +100 punti addomesticazione al cane (%d/%d)" % [points, required]
	)


# Branco di lupi (debug): `count` < 0 = nessun branco ancora (serve un villaggio con centro); `lines` = una riga per lupo.
func set_wolf_pack(count: int, lines: PackedStringArray) -> void:
	var text := "🐺-" if count < 0 else "🐺%d" % count
	wolves_label.tooltip_text = TooltipText.wrap(
		"Branco di lupi del villaggio: nessuno (serve un villaggio con centro)" if count < 0
		else "Branco di lupi del villaggio:
" + "
".join(lines)
	)
	if wolves_label.text == text:
		return
	wolves_label.text = text
	reset_size()


static func _format_hours_minutes(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%dh %02dm" % [int(minutes / 60.0), minutes % 60]


# Celle vive (2026-09-26, debug): `lines` = una riga per cella, già composta da GameScene ("(87,68):
# giocatore, individuo"). Testo = solo il numero, dettaglio nel tooltip; ridimensiona il pannello solo
# se il numero cambia (il tooltip non occupa spazio).
func set_live_cells(lines: PackedStringArray) -> void:
	var text := "Celle vive: %d" % lines.size()
	live_cells_label.tooltip_text = TooltipText.wrap("Celle vive e motivo di attivazione:\n" + "\n".join(lines))
	if live_cells_label.text == text:
		return
	live_cells_label.text = text
	reset_size()


# Riepilogo animali (debug): `entries` = Array di {"species", "quota", "instanced"}, già filtrato
# da GameScene alle sole specie con quota > 0. Formato "specie quota/istanziati"; una specie in cui
# i due numeri differiscono è marcata con "≠" e l'intera etichetta diventa rossa, così la
# discrepanza salta all'occhio anche con molte specie in riga. Muta come il resto della barra: non
# sa da dove arrivano i numeri, li formatta soltanto.
func set_animal_summary(entries: Array) -> void:
	if entries.is_empty():
		animal_summary_label.text = "Animali: -"
		animal_summary_label.remove_theme_color_override("font_color")
		reset_size()
		return

	var parts: PackedStringArray = []
	var has_mismatch := false
	for entry in entries:
		var quota: int = int(entry["quota"])
		var instanced: int = int(entry["instanced"])
		var part := "%s %d/%d" % [entry["species"], quota, instanced]
		if quota != instanced:
			part += " ≠"
			has_mismatch = true
		parts.append(part)

	animal_summary_label.text = "Animali: " + " | ".join(parts)
	if has_mismatch:
		animal_summary_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		animal_summary_label.remove_theme_color_override("font_color")
	# Stesso motivo di _apply_state: la larghezza del testo cambia, il pannello deve seguirla.
	reset_size()
