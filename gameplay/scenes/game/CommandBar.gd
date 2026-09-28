class_name CommandBar
extends HBoxContainer

# Comandi del pipottino (2026-09-27, richiesta utente — work areas passo 3b; dal 2026-09-28 dentro la BuildBar, a destra
# degli strumenti dopo un separatore verticale, non più una barra a sé). Costruito in codice e aggiunto da BuildBar
# (BuildBar.command_bar). GameScene lo mostra quando c'è almeno un pipottino selezionato e l'idea delle zone di lavoro è
# completata (set_bar_visible: la BuildBar, CenterContainer, si allarga e si ricentra da sola) e applica ogni comando a
# TUTTI i pipottini selezionati: questo componente non sa chi sono, emette solo il comando.
#
# Comandi: Raccogli (tasto GATHER_KEY), Caccia (HUNT_KEY, spento: "In arrivo"), interruttore "Scegli zona in automatico"
# (AUTO_ZONE_KEY, icona AutoZoneIcon), impostazione unica salvata in UserOptions.work_area_auto_zone. Stato acceso/spento
# e motivi li decide GameScene (set_gather_available), come per gli slot della BuildBar.

signal gather_requested
signal auto_zone_changed(enabled: bool)

const GATHER_ACTION := &"command_gather"
const HUNT_ACTION := &"command_hunt"
const GATHER_SLOT: int = 0
const HUNT_SLOT: int = 1
const SLOT_COUNT: int = 2

# Tasti rapidi, liberi nel resto del gioco (2026-09-27).
const GATHER_KEY := KEY_Q
const HUNT_KEY := KEY_C
const AUTO_ZONE_KEY := KEY_V

# Stesso lato degli slot di IconButtonRow.
const TOGGLE_BUTTON_SIZE := Vector2(32, 32)

var _row: IconButtonRow = null
var _auto_zone_button: TooltipButton = null
var _auto_zone_icon: AutoZoneIcon = null


func _ready() -> void:
	add_child(VSeparator.new())
	_row = IconButtonRow.new()
	_row.slot_count = SLOT_COUNT
	add_child(_row)
	_row.configure_slot(
		GATHER_SLOT, "", _with_key(tr("command_bar_gather_tooltip"), GATHER_KEY), GATHER_ACTION, "", true,
		IconRegistry.get_command_button_icon_node("pickup")
	)
	_row.configure_slot(
		HUNT_SLOT, "", _with_key(tr("command_bar_hunt_tooltip"), HUNT_KEY), HUNT_ACTION, tr("command_bar_coming_soon"), false,
		IconRegistry.get_command_button_icon_node("hunt")
	)
	_row.action_pressed.connect(_on_action_pressed)

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
	add_child(_auto_zone_button)

	visible = false


func set_bar_visible(bar_visible: bool) -> void:
	if visible != bar_visible:
		visible = bar_visible


# Raccogli acceso o spento, con il motivo nel tooltip (stesso schema di BuildBar.set_building_buildable).
func set_gather_available(is_available: bool, disabled_tooltip: String = "") -> void:
	_row.set_slot_disabled(GATHER_SLOT, not is_available, disabled_tooltip if not is_available else "")


func is_gather_available() -> bool:
	var button := _row.get_slot_button(GATHER_SLOT) as BaseButton
	return button != null and not button.disabled


func _on_action_pressed(action_id: StringName) -> void:
	if action_id == GATHER_ACTION:
		gather_requested.emit()


func _on_auto_zone_toggled(pressed: bool) -> void:
	_auto_zone_icon.active = pressed
	UserOptions.work_area_auto_zone = pressed
	UserOptions.save_to_disk()
	auto_zone_changed.emit(pressed)


# Tasti rapidi, solo con i comandi visibili. Il tasto della Caccia non fa nulla finché il comando è spento.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		GATHER_KEY:
			if is_gather_available():
				get_viewport().set_input_as_handled()
				gather_requested.emit()
		AUTO_ZONE_KEY:
			get_viewport().set_input_as_handled()
			_auto_zone_button.button_pressed = not _auto_zone_button.button_pressed


func _with_key(text: String, keycode: Key) -> String:
	return "%s (%s)" % [text, OS.get_keycode_string(keycode)]
