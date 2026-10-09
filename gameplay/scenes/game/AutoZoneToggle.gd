class_name AutoZoneToggle
extends TooltipButton

# Interruttore "Scegli zona in automatico" (2026-10-09, estratto dal bottone della barra dei comandi, CommandBar — dove
# poi è stato tolto, resta il tasto V — per riusarlo uguale nello strato degli ordini di zona del cassetto e nei popup di
# Raccogli, Caccia, Taglia ed Estrai):
# stessa icona (AutoZoneIcon), stesso aspetto acceso/spento, stesso tooltip, legato direttamente a
# UserOptions.work_area_auto_zone (salvato a ogni cambio). Tutte le copie aperte restano allineate: cambiandone una, le
# altre si aggiornano (gruppo GROUP) ed emettono anch'esse `auto_zone_changed`, così chi le usa (es. lo strato del
# cassetto) si adegua anche quando il cambio arriva da un'altra parte (barra dei comandi, tasto V).

signal auto_zone_changed(enabled: bool)

const GROUP := &"auto_zone_toggles"
const BUTTON_SIZE := Vector2(32, 32)

var _icon: AutoZoneIcon = null


func _init() -> void:
	custom_minimum_size = BUTTON_SIZE
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "%s (%s)" % [tr("command_bar_auto_zone"), OS.get_keycode_string(CommandBar.AUTO_ZONE_KEY)]
	_icon = AutoZoneIcon.new()
	add_child(_icon)
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_style()
	set_pressed_no_signal(UserOptions.work_area_auto_zone)
	_icon.active = UserOptions.work_area_auto_zone
	toggled.connect(_on_toggled)
	add_to_group(GROUP)


func _enter_tree() -> void:
	# Stato attuale anche se cambiato mentre questa copia non era nell'albero (es. popup riaperto).
	_sync(UserOptions.work_area_auto_zone)


func _on_toggled(pressed: bool) -> void:
	_icon.active = pressed
	if UserOptions.work_area_auto_zone != pressed:
		UserOptions.work_area_auto_zone = pressed
		UserOptions.save_to_disk()
	if is_inside_tree():
		for other in get_tree().get_nodes_in_group(GROUP):
			if other != self and other is AutoZoneToggle:
				(other as AutoZoneToggle)._sync(pressed)
	auto_zone_changed.emit(pressed)


# Cambio dell'opzione senza un interruttore premuto (2026-10-09, tasto V della barra dei comandi, che non ha più il
# suo): salvata, e tutte le copie aperte allineate.
static func set_option(tree: SceneTree, enabled: bool) -> void:
	if UserOptions.work_area_auto_zone != enabled:
		UserOptions.work_area_auto_zone = enabled
		UserOptions.save_to_disk()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(GROUP):
		if node is AutoZoneToggle:
			(node as AutoZoneToggle)._sync(enabled)


# Allinea questa copia senza riscrivere l'opzione; avvisa chi la usa se lo stato è cambiato.
func _sync(pressed: bool) -> void:
	if button_pressed == pressed:
		_icon.active = pressed
		return
	set_pressed_no_signal(pressed)
	_icon.active = pressed
	auto_zone_changed.emit(pressed)


# Stesso aspetto degli interruttori della barra dei comandi (CommandBar.TOGGLE_*): bordo luminoso da acceso.
func _apply_style() -> void:
	var off_style := _make_style(CommandBar.TOGGLE_OFF_BG_COLOR, CommandBar.TOGGLE_OFF_BORDER_COLOR, 1)
	var on_style := _make_style(CommandBar.TOGGLE_ON_BG_COLOR, CommandBar.TOGGLE_ON_BORDER_COLOR, 2)
	add_theme_stylebox_override("normal", off_style)
	add_theme_stylebox_override("hover", off_style)
	add_theme_stylebox_override("pressed", on_style)
	add_theme_stylebox_override("hover_pressed", on_style)


func _make_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	return style
