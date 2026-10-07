class_name TaskAssignmentPanel
extends VBoxContainer

# Contenuto "Assegnazione delle task" del cassetto laterale (SideDrawer, 2026-10-07, richiesta utente — bottone
# "Assegnazione" della riga del governo del villaggio di GameInfoPanel). Il titolo lo mostra il cassetto.
#
# Prima bozza della disposizione (2026-10-07): NESSUN bottone ha effetto per ora.
#   - in alto, subito sotto il titolo del cassetto (senza titolo di sezione): un bottone per comando della barra dei
#     comandi (CommandBar.ACTIONS, stesso ordine e stesse icone disegnate, CommandButtonIcon), larghi uguali, icona e
#     nome sotto; tooltip provvisorio "In arrivo";
#   - separatore;
#   - "In coda" (era "In lista") e, sotto, "In corso" (2026-10-07: lavori con almeno un lavoratore, con i loro nomi):
#     occupano il resto dell'altezza, dentro uno scroll; ogni riga ha anche la X che cancella il lavoro;
#   - in fondo "⚙ Regole di assegnazione", chiusa all'apertura: si apre come uno strato sopra le due sezioni
#     (_build_settings_section).
#   Storia di "In coda": i lavori in lista (passo A, 2026-10-07 —
#     JobBoardService, oggi i cantieri di edifici nuovi) passati da GameScene (set_listed_entries) una volta al secondo,
#     come la scheda "In sospeso": una riga per lavoro senza nessuno assegnato, attivo o bloccato, con icona e nome
#     dell'edificio. Attivo: bottone "Blocca" (lock_requested). Bloccato: riga attenuata, "Bloccato" accanto al nome,
#     bottone "Sblocca" (unlock_requested). Clic sulla riga = centra la visuale (entry_activated). Vuota: "Nessun
#     compito in lista". Righe rifatte solo quando l'elenco cambia davvero.

# Idea che sblocca il bottone (GameScene._is_task_assignment_available) e voce tra i suoi sblocchi nell'albero
# (IdeaUnlocksService.TOOLS).
const REQUIRED_IDEA_ID := "task_assignment"
# Id del contenuto nel cassetto (SideDrawer.show_content).
const DRAWER_CONTENT_ID := &"task_assignment"

const SECTION_FONT_SIZE: int = 12
const BUTTON_LABEL_FONT_SIZE: int = 10
const BUTTON_HEIGHT: float = 58.0
const BUTTON_ICON_SIDE: float = 30.0
const BUTTON_SEPARATION: int = 4

# Clic su una riga della lista (centra la visuale) e bottoni "Blocca" / "Sblocca": GameScene decide cosa fare.
signal entry_activated(entry: Dictionary)
signal lock_requested(entry: Dictionary)
signal unlock_requested(entry: Dictionary)
# X di una riga (2026-10-07): cancella il lavoro con lo stesso comando del pannello edificio (lo decide GameScene).
signal cancel_requested(entry: Dictionary)
# "Rimetti in coda" di una riga in corso (2026-10-07): toglie il lavoro a chi lo fa, senza bloccarlo (GameScene).
signal requeue_requested(entry: Dictionary)

const LIST_FONT_SIZE: int = 11
const LIST_ICON_SIDE: float = 20.0
const DISABLED_MODULATE := Color(1, 1, 1, 0.45)
const LOCKED_MODULATE := Color(1, 1, 1, 0.55)
const WAITING_MODULATE := Color(1, 1, 1, 0.7)
# Stacco tra "Blocca"/"Sblocca" e la X della riga.
const CANCEL_BUTTON_GAP: float = 10.0
# Parti dello spazio libero delle due sezioni (circa 60% "In coda", 40% "In corso").
const QUEUED_STRETCH: float = 3.0
const IN_PROGRESS_STRETCH: float = 2.0
# Fondo dello strato delle regole se il colore del cassetto non si può leggere.
const SETTINGS_OVERLAY_FALLBACK_COLOR := Color(0.12, 0.14, 0.18, 1.0)
# Spazio tra le voci e "Salva e chiudi" nello strato.
const SETTINGS_CONTENT_SEPARATION: int = 6
# Bordo del riquadro dello strato, che lo stacca dalle sezioni sotto.
const SETTINGS_OVERLAY_BORDER_WIDTH: int = 1
# Larghezza minima di "Salva e chiudi" (centrato, non a tutta riga).
const SETTINGS_SAVE_BUTTON_MIN_WIDTH: float = 140.0
const SETTINGS_OVERLAY_BORDER_COLOR := Color(0.75, 0.85, 1.0, 0.6)

var _list_box: VBoxContainer = null
var _list_signature: String = "-"
var _pending_list_entries: Array[Dictionary] = []
var _in_progress_box: VBoxContainer = null
var _in_progress_signature: String = "-"
var _pending_in_progress_entries: Array[Dictionary] = []
var _settings_box: VBoxContainer = null
# Strato delle regole di assegnazione (2026-10-07): copre la zona delle due sezioni, che sotto restano ferme.
var _settings_overlay: PanelContainer = null
# Zona delle due sezioni (limite d'altezza dello strato), riga in basso e sua freccia.
var _sections_area: Control = null
var _settings_toggle: Button = null
# "Salva e chiudi" in fondo allo strato, fuori dallo scorrimento delle voci.
var _settings_save_button: Button = null
# Casella dell'attesa (Salva e chiudi applica anche il numero scritto a mano e non confermato).
var _wait_spin: SpinBox = null


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build_new_task_section()
	add_child(HSeparator.new())
	_build_list_section()
	_build_settings_section()


func _build_new_task_section() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BUTTON_SEPARATION)
	add_child(row)
	for action in CommandBar.ACTIONS:
		row.add_child(_build_command_button(action))


# Bottone di un comando: icona disegnata in alto, nome sotto. Senza effetto per ora (2026-10-07).
func _build_command_button(action: Dictionary) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tr("task_assignment_coming_soon")
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)
	var icon := IconRegistry.get_command_button_icon_node(String(action.get("icon", "")))
	icon.custom_minimum_size = Vector2(BUTTON_ICON_SIDE, BUTTON_ICON_SIDE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := Label.new()
	label.text = tr(String(action.get("tooltip_key", "")))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", BUTTON_LABEL_FONT_SIZE)
	box.add_child(label)
	return button


# "In coda" e "In corso" ad altezza fissa (2026-10-07, richiesta utente): si dividono la zona tra i bottoni in alto e
# "⚙ Regole di assegnazione" in basso in proporzione (QUEUED_STRETCH : IN_PROGRESS_STRETCH, circa 60/40), mai in base al
# numero di righe, separate da una linea. Ognuna ha il titolo sempre visibile e sotto il proprio scorrimento verticale,
# che compare solo se le righe non ci stanno, con lo spazio della barra sempre riservato (SCROLL_MODE_RESERVE: bottoni e
# X non si spostano quando la barra compare). Vuota: stessa altezza, "nessun compito" dentro.
# La zona è un Control semplice (non un contenitore): dentro, le sezioni a tutta zona e, sopra, lo strato delle regole
# di assegnazione, nascosto finché la sua riga non viene aperta.
func _build_list_section() -> void:
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	var sections := VBoxContainer.new()
	sections.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sections.add_theme_constant_override("separation", 6)
	area.add_child(sections)
	_sections_area = area
	_list_box = _build_section(sections, tr("task_assignment_list_section"), QUEUED_STRETCH)
	sections.add_child(HSeparator.new())
	_in_progress_box = _build_section(sections, tr("task_assignment_in_progress_section"), IN_PROGRESS_STRETCH)
	# Strato ancorato in basso, alto quanto il suo contenuto (_fit_settings_overlay).
	_settings_overlay = PanelContainer.new()
	_settings_overlay.anchor_left = 0.0
	_settings_overlay.anchor_right = 1.0
	_settings_overlay.anchor_top = 1.0
	_settings_overlay.anchor_bottom = 1.0
	_settings_overlay.offset_left = 0.0
	_settings_overlay.offset_right = 0.0
	_settings_overlay.offset_bottom = 0.0
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.visible = false
	_settings_overlay.add_theme_stylebox_override("panel", _make_settings_overlay_style())
	area.add_child(_settings_overlay)
	_apply_list_entries(_pending_list_entries)
	_apply_in_progress_entries(_pending_in_progress_entries)


# Una sezione dentro `parent`: titolo fuori dallo scorrimento, poi lo scorrimento che riempie l'altezza della sezione.
# Ritorna il contenitore delle righe.
func _build_section(parent: Control, title: String, stretch: float) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = stretch
	section.add_theme_constant_override("separation", 2)
	parent.add_child(section)
	section.add_child(_section_title(title))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	section.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	scroll.add_child(box)
	return box


# Fondo pieno dello strato, dello stesso colore scuro che si vede nel cassetto: il colore dell'area interna (primo
# PanelContainer sopra questo pannello) composto sopra quello della cornice (il secondo, il cassetto), se è trasparente.
func _make_settings_overlay_style() -> StyleBoxFlat:
	var panels: Array[PanelContainer] = []
	var node := get_parent()
	while node != null and panels.size() < 2:
		if node is PanelContainer:
			panels.append(node as PanelContainer)
		node = node.get_parent()
	var style := StyleBoxFlat.new()
	style.bg_color = SETTINGS_OVERLAY_FALLBACK_COLOR
	if not panels.is_empty():
		var content_style := panels[0].get_theme_stylebox("panel") as StyleBoxFlat
		if content_style != null:
			var color := content_style.bg_color
			if color.a < 1.0 and panels.size() > 1:
				var frame_style := panels[1].get_theme_stylebox("panel") as StyleBoxFlat
				if frame_style != null:
					color = Color(frame_style.bg_color.r, frame_style.bg_color.g, frame_style.bg_color.b, 1.0).lerp(
						Color(color.r, color.g, color.b, 1.0), color.a
					)
			color.a = 1.0
			style.bg_color = color
	# Riquadro (2026-10-07, richiesta utente): bordo chiaro e angoli arrotondati, così si capisce che è un pannello a sé
	# sopra le sezioni.
	style.set_border_width_all(SETTINGS_OVERLAY_BORDER_WIDTH)
	style.border_color = SETTINGS_OVERLAY_BORDER_COLOR
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


# Lavori in coda: {"key", "text", "enabled", "disabled_reason", "icon", "building_name", "locked", "waiting",
# "wait_seconds", "cancel_disabled", "cancel_tooltip", ...} (voci di GameScene._pending_entry). Prima di _ready restano
# da parte e vengono mostrati appena l'elenco esiste.
func set_listed_entries(entries: Array[Dictionary]) -> void:
	_pending_list_entries = entries
	if _list_box != null:
		_apply_list_entries(entries)


# Lavori in corso (2026-10-07): come quelli in coda, più "workers" (nomi di chi li fa, separati da virgola).
func set_in_progress_entries(entries: Array[Dictionary]) -> void:
	_pending_in_progress_entries = entries
	if _in_progress_box != null:
		_apply_in_progress_entries(entries)


func _apply_list_entries(entries: Array[Dictionary]) -> void:
	var signature := _entries_signature(entries)
	if signature == _list_signature:
		return
	_list_signature = signature
	_fill_box(_list_box, entries, false, tr("task_assignment_list_empty"))


func _apply_in_progress_entries(entries: Array[Dictionary]) -> void:
	var signature := _entries_signature(entries)
	if signature == _in_progress_signature:
		return
	_in_progress_signature = signature
	_fill_box(_in_progress_box, entries, true, tr("task_assignment_in_progress_empty"))


# Righe rifatte solo quando qualcosa di ciò che mostrano cambia davvero.
func _entries_signature(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry in entries:
		parts.append("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
			entry["key"], entry.get("building_name", ""), entry.get("name_detail", ""), str(entry.get("icon", {})), str(entry.get("enabled", true)), str(entry.get("locked", false)),
			str(entry.get("waiting", false)), str(entry.get("wait_seconds", 0)), entry.get("workers", ""),
			str(entry.get("cancel_disabled", false)), entry.get("cancel_tooltip", "") + "|" + String(entry.get("status_text", "")),
		])
	return "\n".join(parts)


func _fill_box(box: VBoxContainer, entries: Array[Dictionary], in_progress: bool, empty_text: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = empty_text
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		empty_label.modulate = Color(1, 1, 1, 0.7)
		box.add_child(empty_label)
		return
	for entry in entries:
		box.add_child(_build_list_row(entry, in_progress))


# Riga: icona (dell'edificio; per una demolizione la dinamite del bottone "Demolisci"), nome (troncato con i puntini,
# intero nel tooltip) con sotto una seconda riga più piccola, "Bloccato" se lo è, poi "Blocca"/"Sblocca" (testo sempre
# intero) e, staccata, la X piccola che cancella il lavoro (cancel_requested; spenta con il motivo nel tooltip).
# Seconda riga: in coda "In attesa di assegnazione" (col conto alla rovescia durante l'attesa per l'assegnazione a
# mano), in corso i nomi di chi lo fa. In corso, al posto di Blocca/Sblocca, "Rimetti in coda" (requeue_requested).
# Clic su tutta la riga (non sui bottoni) = centra la visuale; voce che non si può centrare: nome spento, spiegazione
# nel tooltip. Bloccato:
# icona, nome e scritta attenuati, i bottoni no.
func _build_list_row(entry: Dictionary, in_progress: bool) -> Control:
	var enabled := bool(entry.get("enabled", true))
	var locked := bool(entry.get("locked", false)) and not in_progress
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := _build_entry_icon(entry)
	if locked:
		icon.modulate = LOCKED_MODULATE
	row.add_child(icon)
	var label := Label.new()
	label.text = String(entry.get("building_name", entry.get("text", "")))
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# PASS (2026-10-07): il tooltip resta, il clic arriva alla riga intera (ClickableRow in fondo).
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = String(entry.get("text", "")) if enabled else "%s\n%s" % [entry.get("text", ""), entry.get("disabled_reason", "")]
	if not enabled:
		label.modulate = DISABLED_MODULATE
	if locked and enabled:
		label.modulate = LOCKED_MODULATE
	# Seconda riga più piccola sotto il nome, così la riga resta nella larghezza del cassetto.
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_theme_constant_override("separation", 0)
	# Testo piccolo accanto al nome (2026-10-07, "name_detail", es. i giorni rimasti di un corpo): sulla stessa riga; se
	# manca lo spazio si accorcia lui con i puntini, non il nome.
	var name_detail := String(entry.get("name_detail", ""))
	if name_detail != "":
		# Il nome non si accorcia mai (2026-10-07, bugfix: con i puntini ancora attivi la sua larghezza minima era quella
		# dei soli puntini e il nome spariva).
		label.size_flags_horizontal = Control.SIZE_FILL
		label.clip_text = false
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		var name_line := HBoxContainer.new()
		name_line.add_theme_constant_override("separation", 4)
		name_line.add_child(label)
		var detail_label := Label.new()
		detail_label.text = name_detail
		detail_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
		detail_label.clip_text = true
		detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		detail_label.modulate = label.modulate
		name_line.add_child(detail_label)
		name_box.add_child(name_line)
	else:
		name_box.add_child(label)
	var status_text := ""
	if in_progress:
		status_text = String(entry.get("workers", ""))
	elif not locked and String(entry.get("status_text", "")) != "":
		# Lavoro impossibile per ora (2026-10-07, es. "Nessun magazzino lo accetta"): il motivo, senza conto alla rovescia.
		status_text = String(entry["status_text"])
	elif not locked and bool(entry.get("waiting", false)):
		var wait_seconds := int(entry.get("wait_seconds", 0))
		status_text = tr("task_assignment_waiting") + ((" (%d)" % wait_seconds) if wait_seconds > 0 else "")
	if status_text != "":
		var status_label := Label.new()
		status_label.text = status_text
		status_label.tooltip_text = status_text
		status_label.mouse_filter = Control.MOUSE_FILTER_PASS
		status_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
		status_label.clip_text = true
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status_label.modulate = WAITING_MODULATE
		name_box.add_child(status_label)
	row.add_child(name_box)
	if locked:
		var locked_label := Label.new()
		locked_label.text = tr("task_assignment_locked")
		locked_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
		locked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		locked_label.modulate = LOCKED_MODULATE
		row.add_child(locked_label)
	# In coda: Blocca/Sblocca. In corso (2026-10-07): "Rimetti in coda" — larghezza intera, è il nome a accorciarsi.
	var state_button := Button.new()
	state_button.focus_mode = Control.FOCUS_NONE
	state_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 1)
	if in_progress:
		state_button.text = tr("task_assignment_requeue")
		state_button.tooltip_text = tr("task_assignment_requeue_tooltip")
		state_button.pressed.connect(func() -> void: requeue_requested.emit(entry))
	else:
		state_button.text = tr("task_assignment_unlock") if locked else tr("task_assignment_lock")
		state_button.pressed.connect(func() -> void:
			if locked:
				unlock_requested.emit(entry)
			else:
				lock_requested.emit(entry)
		)
	row.add_child(state_button)
	# Stacco tra "Blocca" e la X, per non premerla per sbaglio.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(CANCEL_BUTTON_GAP, 0.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var cancel_button := Button.new()
	cancel_button.text = "✕"
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_button.disabled = bool(entry.get("cancel_disabled", false))
	cancel_button.tooltip_text = String(entry.get("cancel_tooltip", ""))
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit(entry))
	row.add_child(cancel_button)
	# Riga intera cliccabile (2026-10-07, prima solo il nome): centra e seleziona (entry_activated), illuminata al
	# passaggio del mouse; i bottoni tengono il loro clic. Spenta se la voce non si può centrare.
	var clickable_row := ClickableRow.new()
	clickable_row.clickable = enabled
	clickable_row.add_child(row)
	clickable_row.clicked.connect(func() -> void: entry_activated.emit(entry))
	return clickable_row


# Icona della riga, decisa dal tipo di lavoro (2026-10-07, generica — GameScene._job_board_drawer_entry, chiave "icon"):
# {"building_command": BuildingCommandIcon.KIND_*} = icona disegnata del pannello edificio (la dinamite per la
# demolizione); {"command": chiave di IconRegistry.COMMAND_ICON_NODES} = icona di comando; altrimenti
# {"building_type": tipo} = l'edificio.
func _build_entry_icon(entry: Dictionary) -> Control:
	var icon_spec: Dictionary = entry.get("icon", {})
	# {"text": emoji} (2026-10-07, es. il 💀 dei corpi): il simbolo centrato nel riquadro dell'icona.
	if icon_spec.has("text"):
		var symbol := Label.new()
		symbol.text = String(icon_spec["text"])
		symbol.add_theme_font_size_override("font_size", LIST_FONT_SIZE + 1)
		symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		symbol.custom_minimum_size = Vector2(LIST_ICON_SIDE, LIST_ICON_SIDE)
		symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return symbol
	if icon_spec.has("building_command"):
		var command_icon := BuildingCommandIcon.new()
		command_icon.kind = String(icon_spec["building_command"])
		command_icon.custom_minimum_size = Vector2(LIST_ICON_SIDE, LIST_ICON_SIDE)
		command_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return command_icon
	if icon_spec.has("command"):
		var icon := IconRegistry.get_command_button_icon_node(String(icon_spec["command"]))
		icon.custom_minimum_size = Vector2(LIST_ICON_SIDE, LIST_ICON_SIDE)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return icon
	return IconRegistry.build_building_icon_box(String(icon_spec.get("building_type", "")), LIST_ICON_SIDE)


# Regole di assegnazione (2026-10-07, richiesta utente — era "Impostazioni"): riga "⚙ Regole di assegnazione" in fondo
# al cassetto, chiusa all'apertura del cassetto; un clic apre lo strato (_settings_overlay), un secondo lo richiude. Lo
# strato parte dalla riga in basso e sale solo quanto serve al suo contenuto (le voci, poi "Salva e chiudi"), al massimo
# fino alla zona delle due sezioni: oltre, scorrono solo le voci e il bottone resta sempre visibile in fondo. Sopra, il
# resto delle due sezioni resta visibile e fermo. Una voce = una riga in _settings_box (oggi solo l'attesa prima
# dell'assegnazione automatica). Valori in UserOptions, applicati e salvati appena cambiano (nessuna modifica persa se lo
# strato si chiude in un altro modo); "Salva e chiudi" applica anche il numero scritto e non confermato, poi chiude.
func _build_settings_section() -> void:
	add_child(HSeparator.new())
	var toggle := Button.new()
	toggle.text = tr("task_assignment_settings")
	toggle.flat = true
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	add_child(toggle)
	_settings_toggle = toggle
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", SETTINGS_CONTENT_SEPARATION)
	_settings_overlay.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(scroll)
	_settings_box = VBoxContainer.new()
	_settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_settings_box)
	_settings_box.add_child(_build_wait_setting_row())
	_settings_box.add_child(_build_collect_piles_setting_row())
	# Bottone di conferma come quelli dei dialog (CountChoiceDialog): fuori dallo scorrimento, sempre visibile.
	_settings_save_button = Button.new()
	_settings_save_button.text = tr("task_assignment_rules_save_close")
	_settings_save_button.focus_mode = Control.FOCUS_NONE
	# Non a tutta riga (2026-10-07, richiesta utente): largo quanto il testo più un po' di margine, centrato.
	_settings_save_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_save_button.custom_minimum_size.x = SETTINGS_SAVE_BUTTON_MIN_WIDTH
	_settings_save_button.pressed.connect(_on_settings_save_pressed)
	content.add_child(_settings_save_button)
	toggle.toggled.connect(_on_settings_toggled)
	_sections_area.resized.connect(_fit_settings_overlay)
	_settings_box.minimum_size_changed.connect(_fit_settings_overlay)


# Salva e chiudi: applica anche il numero scritto a mano e non ancora confermato (apply(), come Invio — il salvataggio
# avviene in value_changed, _store_wait_setting), poi chiude lo strato come un clic sulla riga in basso.
func _on_settings_save_pressed() -> void:
	if _wait_spin != null:
		_wait_spin.apply()
	_settings_toggle.button_pressed = false


func _on_settings_toggled(pressed: bool) -> void:
	_settings_overlay.visible = pressed
	if pressed:
		_fit_settings_overlay()
		# Di nuovo a disposizione assestata: le voci che vanno a capo hanno l'altezza vera solo con la larghezza vera.
		_fit_settings_overlay.call_deferred()


# Altezza dello strato: voci + "Salva e chiudi" + margini del fondo, al massimo l'altezza della zona delle due sezioni.
func _fit_settings_overlay() -> void:
	if _settings_overlay == null or _sections_area == null or not _settings_overlay.visible:
		return
	var style := _settings_overlay.get_theme_stylebox("panel")
	var margins := style.get_minimum_size().y if style != null else 0.0
	var wanted := margins + _settings_box.get_combined_minimum_size().y + float(SETTINGS_CONTENT_SEPARATION) \
		+ _settings_save_button.get_combined_minimum_size().y
	var height := minf(wanted, _sections_area.size.y)
	if not is_equal_approx(_settings_overlay.offset_top, -height):
		_settings_overlay.offset_top = -height


# Attesa prima dell'assegnazione automatica (JobBoardService.get_manual_assign_window_seconds): secondi 0..30, passo 1.
# Applicata e salvata appena cambia (value_changed): con le frecce e la rotella subito; il numero scritto a mano quando si
# preme Invio o si esce dalla casella (apply(), stesso accorgimento di CountChoiceDialog). Chiudere lo strato non salva
# nulla di suo.
func _build_wait_setting_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = tr("task_assignment_setting_wait")
	label.tooltip_text = tr("task_assignment_setting_wait_tooltip")
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = JobBoardService.MANUAL_ASSIGN_WINDOW_MIN_SECONDS
	spin.max_value = JobBoardService.MANUAL_ASSIGN_WINDOW_MAX_SECONDS
	spin.step = 1
	spin.rounded = true
	spin.value = JobBoardService.get_manual_assign_window_seconds()
	spin.tooltip_text = tr("task_assignment_setting_wait_tooltip")
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spin)
	_wait_spin = spin
	spin.value_changed.connect(func(value: float) -> void: _store_wait_setting(int(value)))
	var line_edit := spin.get_line_edit()
	line_edit.text_submitted.connect(func(_text: String) -> void: spin.apply())
	line_edit.focus_exited.connect(func() -> void: spin.apply())
	return row


# Regola "Ritira i mucchi abbandonati" (2026-10-07): spunta, accesa all'inizio; salvata in UserOptions appena cambia.
# Spenta: i mucchi non entrano in coda e le loro righe spariscono (GameScene._pile_jobs_collect).
func _build_collect_piles_setting_row() -> Control:
	var check := CheckBox.new()
	check.text = tr("task_assignment_setting_collect_piles")
	check.tooltip_text = tr("task_assignment_setting_collect_piles_tooltip")
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	check.button_pressed = UserOptions.job_board_collect_piles
	check.toggled.connect(func(pressed: bool) -> void:
		if UserOptions.job_board_collect_piles == pressed:
			return
		UserOptions.job_board_collect_piles = pressed
		UserOptions.save_to_disk()
	)
	return check


func _store_wait_setting(seconds: int) -> void:
	var clamped := clampi(seconds, int(JobBoardService.MANUAL_ASSIGN_WINDOW_MIN_SECONDS), int(JobBoardService.MANUAL_ASSIGN_WINDOW_MAX_SECONDS))
	if UserOptions.job_board_manual_assign_seconds == clamped:
		return
	UserOptions.job_board_manual_assign_seconds = clamped
	UserOptions.save_to_disk()


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	return label
