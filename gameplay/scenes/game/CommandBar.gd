class_name CommandBar
extends HBoxContainer

# Comandi del pipottino (2026-09-27, richiesta utente — work areas passo 3b; dal 2026-09-28 al 2026-10-01 dentro la
# BuildBar, ora di nuovo un pannello a sé). Costruito in codice e messo da GameScene._setup_command_bar in un suo
# PanelContainer centrato in basso, sopra la BuildBar. GameScene lo mostra quando c'è almeno un pipottino selezionato e
# l'idea delle zone di lavoro è completata, e lo nasconde con la BuildBar aperta sugli edifici, col fantasma di
# costruzione e durante il disegno delle zone (_sync_command_bar); applica ogni comando a TUTTI i pipottini
# selezionati: questo componente non sa chi sono, emette solo il comando.
#
# Dal 2026-10-03 anche il pulsante della destinazione dei prodotti della caccia (set_butcher_destination), visibile solo
# con una destinazione di lavorazione oltre al focolare.
# Comandi: Raccogli (tasto GATHER_KEY), Caccia nelle zone (HUNT_KEY, accesa con almeno una zona con la caccia attiva), interruttore "Scegli zona in automatico"
# (AUTO_ZONE_KEY, icona AutoZoneIcon), impostazione unica salvata in UserOptions.work_area_auto_zone. Stato acceso/spento
# e motivi li decide GameScene (set_action_available), come per gli slot della BuildBar. Dal 2026-10-05 anche Estrai

# Un comando del gruppo "Azioni" (2026-10-05: prima un segnale per comando, gather_requested/hunt_requested): l'id della
# voce di ACTIONS. GameScene._on_command_bar_action_requested smista.
signal action_requested(action_id: StringName)
signal auto_zone_changed(enabled: bool)
# Destinazione dei prodotti della caccia scelta dal pulsante (2026-10-03, ButcherDestinationService): GameScene la
# scrive in GameData.last_butcher_destination.
signal butcher_destination_chosen(destination: String)

const GATHER_ACTION := &"command_gather"
const HUNT_ACTION := &"command_hunt"
const QUARRY_ACTION := &"command_quarry"
const CUT_ACTION := &"command_cut"
# Azioni del gruppo "Azioni" (2026-10-04, richiesta utente): UNICA fonte per la barra e per i pulsanti sulle righe della
# lista degli abitanti (HumanPopulationInfoPanel) — un'azione aggiunta qui compare in entrambi i posti. Indice = slot
# della barra. "icon" = chiave di IconRegistry.get_command_button_icon_node; "tooltip_key" = nome del comando.
# Attrezzi richiesti (2026-10-05, regola unica per i comandi che li richiedono — GameScene._command_tool_rejection, usato
# da barra e lista): "tool_categories" = categorie che il pipottino deve possedere (vuoto/assente = nessun attrezzo),
# "tool_belt_only" = conta solo la cintura (altrimenti cintura o zaino, ToolGateService.has_tool_for),
# "tool_missing_tooltip_key" = testo proprio del motivo (altrimenti quello generico con gli attrezzi che coprono le
# categorie mancanti). Un nuovo comando con attrezzo (taglio: CHOPPING, estrazione: DIGGING) basta dichiararlo qui.
# Zona e sblocco (2026-10-05): "job" = lavoro della zona (WorkAreaTypes.JOBS) che il comando usa — il suo sblocco
# (WorkAreaTypes.is_job_unlocked) e l'esistenza di una zona con quel lavoro decidono se il bottone è acceso; senza una
# zona il tooltip è "no_zone_tooltip_key". I posti della barra e i bottoni delle righe degli abitanti nascono da questo
# elenco, nell'ordine: un comando nuovo si aggiunge solo qui (più il suo smistamento in GameScene).
# Ordine (2026-10-06, richiesta utente): Raccogli, Caccia, Taglia, Estrai.
const ACTIONS: Array[Dictionary] = [
	{
		"id": GATHER_ACTION, "icon": "pickup", "tooltip_key": "command_bar_gather_tooltip", "key": GATHER_KEY,
		"job": "haul", "no_zone_tooltip_key": "command_bar_gather_no_zone_tooltip",
	},
	{
		"id": HUNT_ACTION, "icon": "hunt", "tooltip_key": "command_bar_hunt_tooltip", "key": HUNT_KEY,
		"job": "hunt", "no_zone_tooltip_key": "command_bar_hunt_no_zone_tooltip",
		# Coltello in cintura per la macellazione, come HuntZoneService.get_hunt_rejection (stesso testo).
		"tool_categories": [TaskTypes.ToolCategory.BUTCHERING], "tool_belt_only": true,
		"tool_missing_tooltip_key": "work_area_hunt_needs_knife",
	},
	# Taglio nelle zone (2026-10-06, passo 2): accetta (CHOPPING), lavoro "cut".
	{
		"id": CUT_ACTION, "icon": "cut", "tooltip_key": "command_bar_cut_tooltip", "key": CUT_KEY,
		"job": "cut", "no_zone_tooltip_key": "command_bar_cut_no_zone_tooltip",
		"tool_categories": [TaskTypes.ToolCategory.CHOPPING],
	},
	{
		"id": QUARRY_ACTION, "icon": "quarry", "tooltip_key": "command_bar_quarry_tooltip", "key": QUARRY_KEY,
		"job": "quarry", "no_zone_tooltip_key": "command_bar_quarry_no_zone_tooltip",
		"tool_categories": [TaskTypes.ToolCategory.DIGGING],
	},
]


# Voce di ACTIONS con questo id, {} se non c'è.
static func get_action(action_id: StringName) -> Dictionary:
	for action in ACTIONS:
		if action["id"] == action_id:
			return action
	return {}

# Tasti rapidi, liberi nel resto del gioco (2026-09-27).
const GATHER_KEY := KEY_Q
const HUNT_KEY := KEY_C
const QUARRY_KEY := KEY_J
const CUT_KEY := KEY_K
const AUTO_ZONE_KEY := KEY_V

# Stesso lato degli slot di IconButtonRow.
const TOGGLE_BUTTON_SIZE := Vector2(32, 32)

# Aspetto (2026-10-03, richiesta utente — comandi e opzioni distinguibili; ripristinato il 2026-10-04): prima il gruppo
# "Azioni" (Raccogli, Caccia), poi un separatore verticale con un po' di spazio, poi il gruppo "Opzioni" (interruttore
# zona automatica, destinazione della caccia). Le opzioni a scelta hanno il triangolino ▾ (DropdownMarker); l'interruttore ha un bordo luminoso da acceso e
# un aspetto neutro da spento. Solo aspetto: i comportamenti non cambiano.
const GROUP_GAP: int = 6
const TOGGLE_ON_BORDER_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const TOGGLE_ON_BG_COLOR := Color(0.32, 0.28, 0.16, 1.0)
const TOGGLE_OFF_BORDER_COLOR := Color(0.45, 0.45, 0.45, 1.0)
const TOGGLE_OFF_BG_COLOR := Color(0.2, 0.2, 0.2, 1.0)

var _row: IconButtonRow = null
var _auto_zone_button: TooltipButton = null
var _auto_zone_icon: AutoZoneIcon = null
# Pulsante della destinazione dei prodotti della caccia (2026-10-03): icona dell'edificio della destinazione attuale; il
# clic apre una piccola scelta tra le destinazioni disponibili. Stato deciso da GameScene (set_butcher_destination).
var _destination_button: TooltipButton = null
var _destination_icon_holder: Control = null
var _destination_popup: PopupPanel = null
var _destination_list: VBoxContainer = null
# Ultimo stato applicato: [attuale, disponibili come "id:nome|..."] — evita di ricostruire icona e scelta a ogni frame.
var _destination_signature: String = ""
var _destination_options: Array[Dictionary] = []
const DESTINATION_ICON_SIDE: float = 22.0
# Gruppi con etichetta (2026-10-04, richiesta utente — torna la disposizione del 2026-10-03 pomeriggio, commit 997e6a9):
# a sinistra "Azioni" (Raccogli, Caccia nelle zone: CommandBar.ACTIONS), un separatore, a destra "Opzioni" (Scegli zona
# in automatico, destinazione dei prodotti della caccia). Tutta la barra compare solo con l'idea delle zone di lavoro
# (GameScene._sync_command_bar); con l'idea, "Azioni" e la zona automatica sono sempre visibili, la destinazione della
# caccia solo con una destinazione di lavorazione oltre al focolare (set_butcher_destination). Nessun separatore interno.
# Stile condiviso con la riga di titolo della BuildBar (2026-10-03), così le due barre hanno la stessa altezza e i
# pulsanti sulla stessa linea.
const GROUP_LABEL_FONT_SIZE: int = 9
const GROUP_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const GROUP_LABEL_SEPARATION: int = 1
var _actions_group: VBoxContainer = null
var _options_group: VBoxContainer = null
var _options_row: HBoxContainer = null
var _group_separator: VSeparator = null
# Comandi delle zone visibili (idea delle zone, set_zone_commands_visible): senza, la barra non si vede comunque.
var _zone_commands_visible: bool = true


func _ready() -> void:
	_actions_group = _build_group("command_bar_group_actions")
	add_child(_actions_group)
	_row = IconButtonRow.new()
	_row.slot_count = ACTIONS.size()
	_actions_group.add_child(_row)
	# Pulsanti dal solo elenco ACTIONS. Tutti configurati ACCESI (2026-10-01, bugfix "Caccia non fa nulla":
	# IconButtonRow.configure_slot con enabled=false non collega mai `pressed`); lo stato vero lo decide GameScene
	# (set_gather_available/set_hunt_available).
	for slot in range(ACTIONS.size()):
		var action: Dictionary = ACTIONS[slot]
		_row.configure_slot(
			slot, "", _with_key(tr(String(action["tooltip_key"])), action["key"]), action["id"], "", true,
			IconRegistry.get_command_button_icon_node(String(action["icon"]))
		)
	# Spenti finché GameScene non decide (come prima la sola Caccia); Raccogli resta acceso come sempre.
	for slot in range(1, ACTIONS.size()):
		_row.set_slot_disabled(slot, true)
	_row.action_pressed.connect(_on_action_pressed)

	# Separatore tra i gruppi (2026-10-03): linea verticale sottile del tema, con spazio ai lati.
	_group_separator = VSeparator.new()
	_group_separator.add_theme_constant_override("separation", GROUP_GAP * 2)
	add_child(_group_separator)
	_options_group = _build_group("command_bar_group_options")
	add_child(_options_group)
	_options_row = HBoxContainer.new()
	_options_group.add_child(_options_row)

	# Interruttore "Scegli zona in automatico": bottone a due stati (toggle_mode) con icona disegnata che cambia con lo
	# stato, oltre allo stile "premuto" del tema.
	_auto_zone_button = TooltipButton.new()
	_auto_zone_button.custom_minimum_size = TOGGLE_BUTTON_SIZE
	_auto_zone_button.toggle_mode = true
	_auto_zone_button.focus_mode = Control.FOCUS_NONE
	_auto_zone_button.tooltip_text = _with_key(tr("command_bar_auto_zone"), AUTO_ZONE_KEY)
	_auto_zone_icon = AutoZoneIcon.new()
	_auto_zone_button.add_child(_auto_zone_icon)
	_auto_zone_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_auto_zone_button.set_pressed_no_signal(UserOptions.work_area_auto_zone)
	_auto_zone_icon.active = UserOptions.work_area_auto_zone
	_auto_zone_button.toggled.connect(_on_auto_zone_toggled)
	_apply_toggle_style(_auto_zone_button)
	_options_row.add_child(_auto_zone_button)

	_destination_button = TooltipButton.new()
	_destination_button.custom_minimum_size = TOGGLE_BUTTON_SIZE
	_destination_button.focus_mode = Control.FOCUS_NONE
	_destination_icon_holder = CenterContainer.new()
	_destination_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_destination_button.add_child(_destination_icon_holder)
	_destination_icon_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destination_button.pressed.connect(_open_destination_popup)
	var dropdown_marker := DropdownMarker.new()
	_destination_button.add_child(dropdown_marker)
	dropdown_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destination_button.visible = false
	_options_row.add_child(_destination_button)
	_destination_popup = PopupPanel.new()
	_destination_list = VBoxContainer.new()
	_destination_popup.add_child(_destination_list)
	add_child(_destination_popup)

	_refresh_groups()
	visible = false


# Colonna di un gruppo: etichetta piccola e discreta (chiave tr) sopra, i pulsanti sotto.
func _build_group(label_key: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", GROUP_LABEL_SEPARATION)
	var label := make_group_label(tr(label_key))
	group.add_child(label)
	return group


# Etichetta piccola e discreta di un gruppo; usata anche dalla riga di titolo della BuildBar (2026-10-03).
static func make_group_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", GROUP_LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", GROUP_LABEL_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Comandi delle zone visibili o no (l'idea delle zone, la decide GameScene). Dal 2026-10-04 senza l'idea la barra intera
# è nascosta (GameScene._sync_command_bar): qui resta solo per i tasti rapidi e per coerenza dei gruppi.
func set_zone_commands_visible(is_shown: bool) -> void:
	if _zone_commands_visible == is_shown:
		return
	_zone_commands_visible = is_shown
	_refresh_groups()


# "Azioni" e "Opzioni" (con la zona automatica sempre presente) seguono l'idea delle zone; separatore tra i due.
func _refresh_groups() -> void:
	if _actions_group == null:
		return
	_actions_group.visible = _zone_commands_visible
	_options_group.visible = _zone_commands_visible
	_group_separator.visible = _zone_commands_visible


# Interruttore a due stati (2026-10-03): bordo luminoso e fondo caldo da acceso (pressed, anche al passaggio del mouse),
# bordo grigio e fondo neutro da spento.
func _apply_toggle_style(button: Button) -> void:
	var off_style := _make_toggle_style(TOGGLE_OFF_BG_COLOR, TOGGLE_OFF_BORDER_COLOR, 1)
	var on_style := _make_toggle_style(TOGGLE_ON_BG_COLOR, TOGGLE_ON_BORDER_COLOR, 2)
	button.add_theme_stylebox_override("normal", off_style)
	button.add_theme_stylebox_override("hover", off_style)
	button.add_theme_stylebox_override("pressed", on_style)
	button.add_theme_stylebox_override("hover_pressed", on_style)


func _make_toggle_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	return style


func set_bar_visible(bar_visible: bool) -> void:
	if visible != bar_visible:
		visible = bar_visible


# Comando `action_id` acceso o spento, con il motivo nel tooltip (stesso schema di BuildBar.set_building_buildable;
# 2026-10-05: prima set_gather_available/set_hunt_available).
func set_action_available(action_id: StringName, is_available: bool, disabled_tooltip: String = "") -> void:
	var slot := _slot_of(action_id)
	if slot != -1:
		_row.set_slot_disabled(slot, not is_available, disabled_tooltip if not is_available else "")


func is_action_available(action_id: StringName) -> bool:
	var slot := _slot_of(action_id)
	var button := _row.get_slot_button(slot) as BaseButton if slot != -1 else null
	return button != null and not button.disabled


func _slot_of(action_id: StringName) -> int:
	for slot in range(ACTIONS.size()):
		if ACTIONS[slot]["id"] == action_id:
			return slot
	return -1


# Pulsante della destinazione (2026-10-03): `is_shown` = mostrarlo; `current` = destinazione che la caccia userebbe
# adesso; `options` = [{"id", "name", "building_type"}] delle sole destinazioni disponibili. Chiamata a ogni frame da
# GameScene._sync_command_bar: ricostruisce icona, tooltip e scelta solo quando qualcosa cambia.
func set_butcher_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> void:
	if _destination_button.visible != is_shown:
		_destination_button.visible = is_shown
		_refresh_groups()
	if not is_shown:
		if _destination_popup.visible:
			_destination_popup.hide()
		return
	var parts: Array[String] = [String(current.get("id", ""))]
	for option in options:
		parts.append("%s:%s" % [String(option.get("id", "")), String(option.get("name", ""))])
	var signature := "|".join(parts)
	if signature == _destination_signature:
		return
	_destination_signature = signature
	_destination_options = options.duplicate()
	for child in _destination_icon_holder.get_children():
		child.queue_free()
	_destination_icon_holder.add_child(IconRegistry.build_building_icon_box(String(current.get("building_type", "")), DESTINATION_ICON_SIDE))
	_destination_button.tooltip_text = tr("command_bar_butcher_destination_tooltip").format({"name": String(current.get("name", ""))})


func _open_destination_popup() -> void:
	# Tolte subito (non solo queue_free), così la misura del contenuto sotto non conta le righe della volta prima.
	for child in _destination_list.get_children():
		_destination_list.remove_child(child)
		child.queue_free()
	for option in _destination_options:
		var row := HBoxContainer.new()
		row.add_child(IconRegistry.build_building_icon_box(String(option.get("building_type", "")), DESTINATION_ICON_SIDE))
		var choice := Button.new()
		choice.text = String(option.get("name", ""))
		choice.flat = true
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.pressed.connect(_on_destination_option_pressed.bind(String(option.get("id", ""))))
		row.add_child(choice)
		_destination_list.add_child(row)
	_destination_popup.reset_size()
	var content_size := Vector2i(_destination_list.get_combined_minimum_size()) + Vector2i(8, 8)
	var button_rect := _destination_button.get_global_rect()
	# Con le sottofinestre incorporate (default del progetto) la posizione della popup è nelle coordinate della
	# finestra di gioco; altrimenti è sullo schermo.
	var screen_position := Vector2i(button_rect.position)
	if not get_viewport().gui_embed_subwindows:
		screen_position += get_window().position
	_destination_popup.popup(Rect2i(screen_position - Vector2i(0, content_size.y), content_size))


func _on_destination_option_pressed(destination: String) -> void:
	_destination_popup.hide()
	butcher_destination_chosen.emit(destination)


func _on_action_pressed(action_id: StringName) -> void:
	if action_id == HUNT_ACTION:
		HuntZoneService.log_event(null, "bottone Caccia premuto.")
	action_requested.emit(action_id)


func _on_auto_zone_toggled(pressed: bool) -> void:
	_auto_zone_icon.active = pressed
	UserOptions.work_area_auto_zone = pressed
	UserOptions.save_to_disk()
	auto_zone_changed.emit(pressed)


# Tasti rapidi, solo con i comandi visibili. Raccogli e Caccia solo se accesi.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Senza l'idea delle zone (2026-10-03) la barra può mostrare solo la destinazione: i tasti delle zone non valgono.
	if not _zone_commands_visible:
		return
	var keycode := (event as InputEventKey).keycode
	if keycode == AUTO_ZONE_KEY:
		get_viewport().set_input_as_handled()
		_auto_zone_button.button_pressed = not _auto_zone_button.button_pressed
		return
	for action in ACTIONS:
		if keycode != action["key"]:
			continue
		var action_id: StringName = action["id"]
		if action_id == HUNT_ACTION:
			HuntZoneService.log_event(null, "tasto %s premuto (Caccia %s)." % [
				OS.get_keycode_string(HUNT_KEY), "accesa" if is_action_available(action_id) else "spenta: ignorato"
			])
		if is_action_available(action_id):
			get_viewport().set_input_as_handled()
			action_requested.emit(action_id)
		return


func _with_key(text: String, keycode: Key) -> String:
	return "%s (%s)" % [text, OS.get_keycode_string(keycode)]
