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
# Priorità (2026-10-08): modo scelto (JobBoardService.PRIORITY_*) e ordine dei tipi per "Personalizzata". Valgono subito:
# GameScene li scrive nella partita (GameData) e riordina le righe.
signal priority_mode_changed(mode: String)
signal kind_order_changed(order: Array[String])
# Soglia della riparazione automatica cambiata (2026-10-10, dato della partita): GameScene la scrive in GameData.
signal auto_repair_percent_changed(percent: int)
# Spunta "Sgombera sempre le macerie" cambiata (2026-10-10, dato della partita): GameScene la scrive in GameData.
signal auto_clear_rubble_changed(enabled: bool)
# Bottone "Produci" (2026-10-09, ordini creati dal cassetto): GameScene risponde con open_produce_overlay (le ricette).
# "Invia in coda" nello strato = produce_orders_submitted: `orders` = [{"recipe", "quantity"}] delle ricette preparate,
# `deliver_to_warehouse` = la spunta "Porta al deposito" al momento dell'invio.
signal produce_order_requested
signal produce_orders_submitted(orders: Array[Dictionary], deliver_to_warehouse: bool)
# Bottoni "Taglia" ed "Estrai" (2026-10-09, ordini del cassetto di zona — `kind` "cut" / "quarry"): GameScene risponde con
# open_zone_order_overlay. Nello strato, "Scegli zona" = zone_pick_requested (scelta sulla mappa, poi set_order_zone);
# "Invia in coda" = zone_order_submitted
# (`zone_id` -1 = zona automatica).
signal zone_order_requested(kind: String)
signal zone_pick_requested
signal zone_order_submitted(kind: String, count: int, zone_id: int)
# Pulsante della destinazione della caccia nello strato "Caccia" (2026-10-09, ButcherDestinationButton condiviso con la
# barra dei comandi): GameScene la scrive subito in GameData.last_butcher_destination.
signal butcher_destination_chosen(destination: String)

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
# Soglia della riparazione automatica (2026-10-10), stessa forma della voce dell'attesa.
var _auto_repair_spin: SpinBox = null
var _auto_repair_percent: int = JobBoardService.AUTO_REPAIR_DEFAULT_PERCENT
var _auto_clear_rubble: bool = false
# Priorità (2026-10-08): valori passati da GameScene prima di _ready (set_priority_settings), elenco dei tipi visibile solo
# con "Personalizzata".
var _priority_mode: String = JobBoardService.DEFAULT_PRIORITY_MODE
var _kind_order: Array[String] = []
var _kind_order_panel: Control = null
var _kind_order_box: VBoxContainer = null
# Bottone "Produci" (2026-10-09): acceso solo se esiste un edificio completo dove si può fare almeno una ricetta
# (set_produce_available, da GameScene; valore tenuto qui se arriva prima di _ready).
var _produce_button: Button = null
var _produce_available: bool = false
# Strato "Produci" (2026-10-09, richiesta utente — al posto del popup a parte): si apre in alto nella zona delle sezioni,
# subito sotto la riga dei cinque bottoni, e scende solo quanto serve (al massimo tutta la zona, poi le ricette
# scorrono); stesso stile dello strato delle regole. Ricette a bottoni per categoria con l'icona a sinistra (come il
# popup "Raccogli nelle zone di lavoro", PickupChoiceMenu). Stesso gesto della griglia delle ricette del pannello
# dell'edificio: clic sinistro +1, destro −1, ma solo per preparare (2026-10-09, richiesta utente: in coda non entra
# niente finché non si invia); ogni ricetta preparata resta evidenziata con la quantità sul bottone ("×3"). In fondo,
# sempre visibile, una riga: "Porta al deposito" a sinistra, "Invia in coda" (spento senza nessuna quantità > 0: crea un
# ordine del cassetto per ricetta preparata, produce_orders_submitted, e chiude) e "Annulla" a destra. Annulla, un
# secondo clic su "Produci", Esc o l'apertura delle regole chiudono senza creare niente; riaprendo, le quantità partono
# da zero (un ordine inviato si toglie solo con la X della sua riga in coda). Ricette passate da GameScene:
# {"name", "category", "max_quantity"}.
var _produce_overlay: PanelContainer = null
var _produce_box: VBoxContainer = null
var _produce_footer: HBoxContainer = null
var _produce_deliver_check: CheckBox = null
var _produce_submit_button: Button = null
var _produce_recipes: Array[Dictionary] = []
var _produce_buttons: Array[Button] = []
# Quantità preparate: ricetta -> pezzi (> 0); azzerate a ogni apertura.
var _produce_quantities: Dictionary = {}
# Strato "Taglia" (2026-10-09, richiesta utente — ordini del cassetto, taglio nelle zone "a chiunque"): stesso stile e
# comportamento dello strato "Produci" (in alto, modale, chiusura con il secondo clic su "Taglia", Annulla, Esc). Dentro:
# piante da tagliare (limiti del popup del comando), zona ("Zona automatica" con l'opzione accesa, altrimenti "Scegli
# zona" sulla mappa e la zona scelta), in fondo "Invia in coda" (spento finché manca la zona, se serve) e "Annulla".
# Strato condiviso da "Taglia" ed "Estrai" (2026-10-09): `_zone_kind` dice quale ordine sta preparando; titolo e voce
# del numero cambiano a ogni apertura. Bottone, stato e motivo per tipo.
const ZONE_KIND_CUT := "cut"
const ZONE_KIND_QUARRY := "quarry"
# "Raccogli" (2026-10-09, quarto tipo): stesso strato, più la scelta di cosa raccogliere (il menu del popup "Raccogli
# nelle zone di lavoro", PickupChoiceMenu) e i viaggi al posto del numero.
const ZONE_KIND_GATHER := "gather"
# "Caccia" (2026-10-09, quinto tipo): carne da portare a casa (5/10/15/20) al posto del numero, e la riga del pulsante
# della destinazione (visibile come quello della barra dei comandi, set_butcher_destination).
const ZONE_KIND_HUNT := "hunt"
var _hunt_button: Button = null
var _hunt_destination_row: HBoxContainer = null
var _hunt_destination_button: ButcherDestinationButton = null
var _hunt_destination_shown: bool = false
var _zone_kind: String = ZONE_KIND_CUT
var _cut_button: Button = null
var _quarry_button: Button = null
var _gather_button: Button = null
var _gather_section: VBoxContainer = null
var _gather_list: VBoxContainer = null
var _gather_menu: PickupChoiceMenu = null
var _gather_chosen: bool = false
var _zone_available: Dictionary = {}  # tipo -> bool
var _zone_unavailable_reason: Dictionary = {}  # tipo -> motivo
var _cut_title_label: Label = null
var _cut_count_label: Label = null
var _cut_overlay: PanelContainer = null
var _cut_box: VBoxContainer = null
var _cut_footer: HBoxContainer = null
var _cut_count_spin: SpinBox = null
var _cut_zone_label: Label = null
var _cut_zone_button: Button = null
# Riga della zona scelta a mano (2026-10-09): sotto "Scegli zona in automatico [interruttore]", visibile a interruttore
# spento — la zona scelta (o "nessuna") a sinistra, "Scegli zona" a destra.
var _cut_zone_pick_row: HBoxContainer = null
# Interruttore della zona automatica (2026-10-09, AutoZoneToggle: lo stesso della barra dei comandi, legato a
# UserOptions.work_area_auto_zone): acceso = zona automatica, niente scelta; spento = "Scegli zona".
var _cut_auto_zone_toggle: AutoZoneToggle = null
var _cut_submit_button: Button = null
var _cut_auto_zone: bool = true
var _cut_zone_id: int = -1
var _cut_zone_name: String = ""
# true mentre il giocatore sceglie la zona sulla mappa (Esc lo annulla lì, non chiude lo strato).
var _cut_zone_picking: bool = false
# Strati modali (2026-10-09, richiesta utente): con "Regole" o "Produci" aperto il resto del cassetto si scurisce e non
# risponde a clic né rotellina — le sezioni sotto un velo (_modal_shade, STOP, tra le sezioni e gli strati), i cinque
# bottoni in alto e la riga "⚙ Regole" attenuati e senza mouse — tranne il bottone che ha aperto lo strato ("Produci" o
# "⚙ Regole"), che lo richiude. Fuori dal cassetto non cambia nulla. _update_modal_state a ogni apertura e chiusura.
var _command_row: HBoxContainer = null
var _modal_shade: ColorRect = null
const MODAL_SHADE_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const MODAL_DIM_MODULATE := Color(0.6, 0.6, 0.6, 1.0)


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
	_command_row = row
	for action in CommandBar.ACTIONS:
		var command_button := _build_command_button(action)
		row.add_child(command_button)
		# "Taglia" ed "Estrai" (2026-10-09): aprono lo strato dell'ordine di zona (ordini del cassetto); un secondo clic sullo
		# stesso bottone lo richiude. Gli altri due restano senza effetto.
		var zone_kind := ""
		if action["id"] == CommandBar.CUT_ACTION:
			zone_kind = ZONE_KIND_CUT
			_cut_button = command_button
		elif action["id"] == CommandBar.QUARRY_ACTION:
			zone_kind = ZONE_KIND_QUARRY
			_quarry_button = command_button
		elif action["id"] == CommandBar.GATHER_ACTION:
			zone_kind = ZONE_KIND_GATHER
			_gather_button = command_button
		elif action["id"] == CommandBar.HUNT_ACTION:
			zone_kind = ZONE_KIND_HUNT
			_hunt_button = command_button
		if zone_kind != "":
			command_button.pressed.connect(func() -> void:
				if _cut_overlay != null and _cut_overlay.visible and _zone_kind == zone_kind:
					close_cut_overlay()
				else:
					zone_order_requested.emit(zone_kind)
			)
	_apply_zone_available(ZONE_KIND_CUT)
	_apply_zone_available(ZONE_KIND_QUARRY)
	_apply_zone_available(ZONE_KIND_GATHER)
	_apply_zone_available(ZONE_KIND_HUNT)
	# Quinto bottone "Produci" (2026-10-09): stessa forma, la riga si divide la larghezza.
	_produce_button = _build_command_button({"icon": "produce", "tooltip_key": "drawer_produce_button"})
	_produce_button.pressed.connect(func() -> void:
		if _produce_overlay != null and _produce_overlay.visible:
			close_produce_overlay()
		else:
			produce_order_requested.emit()
	)
	row.add_child(_produce_button)
	_apply_produce_available()


# Stato del bottone "Taglia" / "Estrai" (2026-10-09, `kind` ZONE_KIND_*): acceso con almeno una zona del lavoro e un
# individuo in età da lavoro con l'attrezzo; spento con il motivo nel tooltip (`reason`).
func set_zone_order_available(kind: String, available: bool, reason: String = "") -> void:
	_zone_available[kind] = available
	_zone_unavailable_reason[kind] = reason
	_apply_zone_available(kind)


func _zone_button(kind: String) -> Button:
	match kind:
		ZONE_KIND_QUARRY:
			return _quarry_button
		ZONE_KIND_GATHER:
			return _gather_button
		ZONE_KIND_HUNT:
			return _hunt_button
	return _cut_button


func _apply_zone_available(kind: String) -> void:
	var button := _zone_button(kind)
	if button == null:
		return
	var available := bool(_zone_available.get(kind, false))
	button.disabled = not available
	var button_tooltip_key: String = String({ZONE_KIND_QUARRY: "drawer_quarry_button_tooltip", ZONE_KIND_GATHER: "drawer_gather_button_tooltip", ZONE_KIND_HUNT: "drawer_hunt_button_tooltip"}.get(kind, "drawer_cut_button_tooltip"))
	button.tooltip_text = tr(button_tooltip_key) if available else String(_zone_unavailable_reason.get(kind, ""))
	if not available and _cut_overlay != null and _cut_overlay.visible and _zone_kind == kind:
		close_cut_overlay()


# Stato del bottone "Produci": spento con il motivo nel tooltip se non c'è un edificio dove produrre.
func set_produce_available(available: bool) -> void:
	_produce_available = available
	_apply_produce_available()


func _apply_produce_available() -> void:
	if _produce_button == null:
		return
	_produce_button.disabled = not _produce_available
	if not _produce_available:
		close_produce_overlay()
	_produce_button.tooltip_text = tr("drawer_produce_button_tooltip") if _produce_available else tr("drawer_produce_no_building")


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
	# Velo degli strati modali: sopra le sezioni, sotto gli strati (aggiunti dopo), nascosto finché nessuno è aperto.
	_modal_shade = ColorRect.new()
	_modal_shade.color = MODAL_SHADE_COLOR
	_modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_shade.visible = false
	area.add_child(_modal_shade)
	_list_box = _build_section(sections, tr("task_assignment_list_section"), QUEUED_STRETCH)
	sections.add_child(HSeparator.new())
	_in_progress_box = _build_section(
		sections, tr("task_assignment_in_progress_section"), IN_PROGRESS_STRETCH, tr("task_assignment_in_progress_tooltip")
	)
	_build_workload_bar()
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
	_build_produce_overlay(area)
	_build_cut_overlay(area)
	_apply_list_entries(_pending_list_entries)
	_apply_in_progress_entries(_pending_in_progress_entries)


# Una sezione dentro `parent`: titolo fuori dallo scorrimento, poi lo scorrimento che riempie l'altezza della sezione.
# Ritorna il contenitore delle righe.
# `title_tooltip` (2026-10-09): tooltip del titolo ("In corso": cosa compare e cosa no).
func _build_section(parent: Control, title: String, stretch: float, title_tooltip: String = "") -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = stretch
	section.add_theme_constant_override("separation", 2)
	parent.add_child(section)
	var title_label := _section_title(title)
	if title_tooltip != "":
		title_label.tooltip_text = title_tooltip
		title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	section.add_child(title_label)
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
			str(entry.get("cancel_disabled", false)), entry.get("cancel_tooltip", "") + "|" + String(entry.get("status_text", "")) + "|" + str(entry.get("direct", false)) + str(entry.get("automatic", false)) + str(entry.get("cargo_return", false)),
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
	if in_progress and bool(entry.get("direct", false)):
		# Comando diretto (2026-10-09): "Diretto" piccolo, non cliccabile, largo quanto "Rimetti in coda" (il bottone resta
		# sotto, invisibile e senza mouse, solo per dare la larghezza).
		state_button.text = tr("task_assignment_requeue")
		state_button.modulate = Color(1, 1, 1, 0)
		state_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state_button.disabled = true
		var direct_holder := MarginContainer.new()
		direct_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		direct_holder.add_child(state_button)
		var direct_label := Label.new()
		# "Automatico" (2026-10-09, "Cerca lavoro"): partito da solo, stesso stile di "Diretto".
		var automatic := bool(entry.get("automatic", false))
		direct_label.text = tr("task_assignment_automatic") if automatic else tr("task_assignment_direct")
		direct_label.tooltip_text = tr("task_assignment_automatic_tooltip") if automatic else tr("task_assignment_direct_tooltip")
		# "Riporta il carico" (2026-10-10): carico della task annullata riportato al magazzino, stesso stile.
		if bool(entry.get("cargo_return", false)):
			direct_label.text = tr("task_assignment_cargo_return")
			direct_label.tooltip_text = tr("task_assignment_cargo_return_tooltip")
		direct_label.mouse_filter = Control.MOUSE_FILTER_STOP
		direct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		direct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		direct_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
		direct_label.modulate = WAITING_MODULATE
		direct_holder.add_child(direct_label)
		row.add_child(direct_holder)
	elif in_progress:
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
	if state_button.get_parent() == null:
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
	# Riga "Automatico" (2026-10-09): niente X — resta solo il suo posto, invisibile, per l'allineamento delle colonne.
	if bool(entry.get("automatic", false)) or bool(entry.get("cargo_return", false)):
		cancel_button.modulate = Color(1, 1, 1, 0)
		cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cancel_button.disabled = true
		cancel_button.tooltip_text = ""
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
	# {"resource": nome} (2026-10-09, ordini di produzione): icona della risorsa sul suo colore, come le chip del pannello
	# edificio; senza icona l'emoji o l'iniziale.
	if icon_spec.has("resource"):
		var resource_name := String(icon_spec["resource"])
		var chip := ColorRect.new()
		chip.color = IconRegistry.get_resource_color(resource_name)
		chip.custom_minimum_size = Vector2(LIST_ICON_SIDE, LIST_ICON_SIDE)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var resource_icon: Control = IconRegistry.get_resource_icon_node(resource_name)
		if resource_icon == null:
			var initial := Label.new()
			var emoji := IconRegistry.get_resource_icon(resource_name)
			initial.text = emoji if emoji != "" else resource_name.substr(0, 1).to_upper()
			initial.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
			initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			resource_icon = initial
		resource_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		resource_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(resource_icon)
		return chip
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
# resto delle due sezioni resta visibile e fermo. Una voce = una riga in _settings_box (attesa, mucchi, priorità). Attesa
# e mucchi in UserOptions, la priorità nella partita (2026-10-08, via GameScene), tutto applicato appena cambia (nessuna
# modifica persa se lo strato si chiude in un altro modo); "Salva e chiudi" applica anche il numero scritto e non
# confermato, poi chiude.
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
	_settings_box.add_child(_build_auto_repair_setting_row())
	_settings_box.add_child(_build_auto_clear_rubble_setting_row())
	_settings_box.add_child(_build_collect_piles_setting_row())
	_settings_box.add_child(_build_empty_outputs_setting_row())
	_build_priority_setting(_settings_box)
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
	if _auto_repair_spin != null:
		_auto_repair_spin.apply()
	_settings_toggle.button_pressed = false


func _on_settings_toggled(pressed: bool) -> void:
	_settings_overlay.visible = pressed
	if pressed:
		# Un solo strato alla volta (2026-10-09): le regole chiudono "Produci" e "Taglia".
		close_produce_overlay()
		close_cut_overlay()
		_fit_settings_overlay()
		# Di nuovo a disposizione assestata: le voci che vanno a capo hanno l'altezza vera solo con la larghezza vera.
		_fit_settings_overlay.call_deferred()
	_update_modal_state()


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


# Riparazione automatica (2026-10-10, JobBoardService.get_auto_repair_percent): "Ripara gli edifici sotto il …%", da 0 a
# 70 a passi di 10, stessa riga della voce dell'attesa. Dato della partita (GameData), come la priorità: il valore arriva
# da GameScene (set_auto_repair_percent, prima di _ready) e ogni cambio esce con auto_repair_percent_changed; GameScene se
# ne accorge al giro successivo della coda e ricontrolla subito gli edifici.
func set_auto_repair_percent(percent: int) -> void:
	_auto_repair_percent = JobBoardService.clamp_auto_repair_percent(percent)


func _build_auto_repair_setting_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = tr("task_assignment_setting_auto_repair")
	label.tooltip_text = tr("task_assignment_setting_auto_repair_tooltip")
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = JobBoardService.AUTO_REPAIR_MIN_PERCENT
	spin.max_value = JobBoardService.AUTO_REPAIR_MAX_PERCENT
	spin.step = JobBoardService.AUTO_REPAIR_STEP_PERCENT
	spin.rounded = true
	spin.suffix = "%"
	spin.value = _auto_repair_percent
	spin.tooltip_text = tr("task_assignment_setting_auto_repair_tooltip")
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spin)
	_auto_repair_spin = spin
	spin.value_changed.connect(func(value: float) -> void: _store_auto_repair_setting(int(value)))
	var line_edit := spin.get_line_edit()
	line_edit.text_submitted.connect(func(_text: String) -> void: spin.apply())
	line_edit.focus_exited.connect(func() -> void: spin.apply())
	return row


func _store_auto_repair_setting(percent: int) -> void:
	var clamped := JobBoardService.clamp_auto_repair_percent(percent)
	if _auto_repair_percent == clamped:
		return
	_auto_repair_percent = clamped
	auto_repair_percent_changed.emit(clamped)


# Regola "Sgombera sempre le macerie" (2026-10-10): spunta, spenta all'inizio. Dato della partita come la soglia della
# riparazione: il valore arriva da GameScene (set_auto_clear_rubble, prima di _ready) e ogni cambio esce con
# auto_clear_rubble_changed, subito (come le altre spunte).
func set_auto_clear_rubble(enabled: bool) -> void:
	_auto_clear_rubble = enabled


func _build_auto_clear_rubble_setting_row() -> Control:
	var check := CheckBox.new()
	check.text = tr("task_assignment_setting_auto_clear_rubble")
	check.tooltip_text = tr("task_assignment_setting_auto_clear_rubble_tooltip")
	check.focus_mode = Control.FOCUS_NONE
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	check.button_pressed = _auto_clear_rubble
	check.toggled.connect(func(pressed: bool) -> void:
		if _auto_clear_rubble == pressed:
			return
		_auto_clear_rubble = pressed
		auto_clear_rubble_changed.emit(pressed)
	)
	return check


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


# Regola "Svuota le uscite piene" (2026-10-08): spunta, accesa all'inizio; salvata in UserOptions appena cambia. Spenta:
# i lavori di consegna dei Prodotti finiti non entrano in coda e le loro righe spariscono (GameScene._output_jobs_collect).
func _build_empty_outputs_setting_row() -> Control:
	var check := CheckBox.new()
	check.text = tr("task_assignment_setting_empty_outputs")
	check.tooltip_text = tr("task_assignment_setting_empty_outputs_tooltip")
	# Testo lungo (2026-10-08): va a capo, il cassetto resta largo 380 px.
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	check.button_pressed = UserOptions.job_board_empty_full_outputs
	check.toggled.connect(func(pressed: bool) -> void:
		if UserOptions.job_board_empty_full_outputs == pressed:
			return
		UserOptions.job_board_empty_full_outputs = pressed
		UserOptions.save_to_disk()
	)
	return check


# Valori della priorità della partita (GameScene, prima di aggiungere il pannello al cassetto).
func set_priority_settings(mode: String, kind_order: Array[String]) -> void:
	_priority_mode = mode
	_kind_order = kind_order.duplicate()


# Sezione "Priorità" (2026-10-08, richiesta utente): i quattro modi di JobBoardService, uno solo attivo (ButtonGroup), con un
# tooltip di una riga ciascuno; sotto, solo con "Personalizzata", l'elenco dei tipi con ▲▼ per spostarli. Ogni scelta vale
# subito (priority_mode_changed / kind_order_changed). Lo strato si adatta da solo all'altezza (minimum_size_changed di
# _settings_box -> _fit_settings_overlay), oltre il massimo scorre.
func _build_priority_setting(parent: VBoxContainer) -> void:
	if _kind_order.is_empty():
		_kind_order = JobBoardService.get_kind_order(null)
	parent.add_child(HSeparator.new())
	parent.add_child(_section_title(tr("task_assignment_priority_section")))
	var group := ButtonGroup.new()
	for mode in JobBoardService.PRIORITY_MODES:
		var name_key := String(JobBoardService.PRIORITY_NAME_KEYS[mode])
		var option := CheckBox.new()
		option.button_group = group
		option.text = tr(name_key)
		option.tooltip_text = tr(name_key + "_tooltip")
		option.focus_mode = Control.FOCUS_NONE
		option.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		option.button_pressed = mode == _priority_mode
		option.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_on_priority_mode_selected(mode)
		)
		parent.add_child(option)
	# Elenco dei tipi, rientrato sotto i modi.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	parent.add_child(margin)
	_kind_order_panel = margin
	_kind_order_box = VBoxContainer.new()
	_kind_order_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_order_box.add_theme_constant_override("separation", 2)
	margin.add_child(_kind_order_box)
	_rebuild_kind_order_rows()
	_kind_order_panel.visible = _priority_mode == JobBoardService.PRIORITY_CUSTOM


func _on_priority_mode_selected(mode: String) -> void:
	if _priority_mode == mode:
		return
	_priority_mode = mode
	_kind_order_panel.visible = mode == JobBoardService.PRIORITY_CUSTOM
	priority_mode_changed.emit(mode)


# Una riga per tipo: "N. nome", poi ▲ (spento sul primo) e ▼ (spento sull'ultimo).
func _rebuild_kind_order_rows() -> void:
	for child in _kind_order_box.get_children():
		_kind_order_box.remove_child(child)
		child.queue_free()
	for index in _kind_order.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var label := Label.new()
		label.text = "%d. %s" % [index + 1, JobBoardService.get_kind_name(_kind_order[index])]
		label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# A capo se il nome non ci sta (2026-10-10, "Demolizioni e sgomberi"): il cassetto resta largo 380 px.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		row.add_child(_build_kind_move_button("▲", tr("task_assignment_kind_move_up"), index, -1))
		row.add_child(_build_kind_move_button("▼", tr("task_assignment_kind_move_down"), index, 1))
		_kind_order_box.add_child(row)


func _build_kind_move_button(text: String, tooltip: String, index: int, direction: int) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
	var target := index + direction
	button.disabled = target < 0 or target >= _kind_order.size()
	button.pressed.connect(func() -> void: _move_kind(index, target))
	return button


# Scambia due tipi e avvisa subito. Le righe si rifanno a fine frame: il bottone premuto è una di quelle.
func _move_kind(from_index: int, to_index: int) -> void:
	if to_index < 0 or to_index >= _kind_order.size():
		return
	var moved := _kind_order[from_index]
	_kind_order[from_index] = _kind_order[to_index]
	_kind_order[to_index] = moved
	_rebuild_kind_order_rows.call_deferred()
	kind_order_changed.emit(_kind_order.duplicate())


func _store_wait_setting(seconds: int) -> void:
	var clamped := clampi(seconds, int(JobBoardService.MANUAL_ASSIGN_WINDOW_MIN_SECONDS), int(JobBoardService.MANUAL_ASSIGN_WINDOW_MAX_SECONDS))
	if UserOptions.job_board_manual_assign_seconds == clamped:
		return
	UserOptions.job_board_manual_assign_seconds = clamped
	UserOptions.save_to_disk()


# --- Strato "Produci" (2026-10-09, vedi _produce_overlay) ---

func _build_produce_overlay(area: Control) -> void:
	_produce_overlay = PanelContainer.new()
	# Ancorato in alto (2026-10-09): scende dalla riga dei cinque bottoni, alto quanto il contenuto (_fit_produce_overlay).
	_produce_overlay.anchor_left = 0.0
	_produce_overlay.anchor_right = 1.0
	_produce_overlay.anchor_top = 0.0
	_produce_overlay.anchor_bottom = 0.0
	_produce_overlay.offset_left = 0.0
	_produce_overlay.offset_right = 0.0
	_produce_overlay.offset_top = 0.0
	_produce_overlay.offset_bottom = 0.0
	_produce_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_produce_overlay.visible = false
	_produce_overlay.add_theme_stylebox_override("panel", _make_settings_overlay_style())
	area.add_child(_produce_overlay)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", SETTINGS_CONTENT_SEPARATION)
	_produce_overlay.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(scroll)
	_produce_box = VBoxContainer.new()
	_produce_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_produce_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_produce_box)
	# Fuori dallo scorrimento, sempre visibile, una riga: spunta a sinistra (va a capo se serve, il cassetto non si
	# allarga), bottoni a destra.
	_produce_footer = HBoxContainer.new()
	_produce_footer.add_theme_constant_override("separation", 6)
	content.add_child(_produce_footer)
	_produce_deliver_check = CheckBox.new()
	_produce_deliver_check.text = tr("produce_deliver_checkbox")
	_produce_deliver_check.focus_mode = Control.FOCUS_NONE
	_produce_deliver_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_produce_deliver_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_produce_deliver_check.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_produce_footer.add_child(_produce_deliver_check)
	_produce_submit_button = Button.new()
	_produce_submit_button.text = tr("drawer_produce_submit")
	_produce_submit_button.focus_mode = Control.FOCUS_NONE
	_produce_submit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_produce_submit_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_produce_submit_button.pressed.connect(_on_produce_submit_pressed)
	_produce_footer.add_child(_produce_submit_button)
	var cancel_button := Button.new()
	cancel_button.text = tr("transport_dialog_cancel")
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	cancel_button.pressed.connect(close_produce_overlay)
	_produce_footer.add_child(cancel_button)
	_sections_area.resized.connect(_fit_produce_overlay)
	_produce_box.minimum_size_changed.connect(_fit_produce_overlay)
	_produce_footer.minimum_size_changed.connect(_fit_produce_overlay)


# Apre lo strato con `recipes` ({"name", "category", "max_quantity"}), quantità tutte a zero e la spunta a
# `deliver_default`. Chiude le regole se aperte.
func open_produce_overlay(recipes: Array[Dictionary], deliver_default: bool) -> void:
	if _produce_overlay == null:
		return
	if _settings_toggle != null and _settings_toggle.button_pressed:
		_settings_toggle.button_pressed = false
	close_cut_overlay()
	_produce_recipes = recipes.duplicate()
	_produce_buttons.clear()
	_produce_quantities.clear()
	for child in _produce_box.get_children():
		_produce_box.remove_child(child)
		child.queue_free()
	_produce_box.add_child(_section_title(tr("drawer_produce_dialog_title")))
	var hint := Label.new()
	hint.text = tr("drawer_produce_overlay_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", LIST_FONT_SIZE - 2)
	hint.modulate = WAITING_MODULATE
	_produce_box.add_child(hint)
	# Per categoria, nell'ordine del popup "Raccogli" (PickUpAction.PRIORITY_CATEGORIES), dentro per nome.
	for category in PickUpAction.PRIORITY_CATEGORIES:
		var indices: Array[int] = []
		for index in range(_produce_recipes.size()):
			if int(_produce_recipes[index].get("category", -1)) == int(category):
				indices.append(index)
		if indices.is_empty():
			continue
		var text_keys: Array = PickupChoiceMenu.CATEGORY_TEXT_KEYS.get(category, ["", ""])
		var header := Label.new()
		header.text = tr(String(text_keys[0])) if String(text_keys[0]) != "" else str(category)
		header.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		header.modulate = WAITING_MODULATE
		_produce_box.add_child(header)
		for index in indices:
			_produce_box.add_child(_build_produce_recipe_row(index))
	_produce_deliver_check.set_pressed_no_signal(deliver_default)
	_refresh_produce_buttons()
	_produce_overlay.visible = true
	_update_modal_state()
	_fit_produce_overlay()
	_fit_produce_overlay.call_deferred()


# Chiude senza creare niente (Annulla, secondo clic su "Produci", Esc, apertura delle regole).
func close_produce_overlay() -> void:
	if _produce_overlay != null:
		_produce_overlay.visible = false
	_produce_quantities.clear()
	_update_modal_state()


# Stato modale del cassetto (vedi _modal_shade): velo sulle sezioni, bottoni in alto e riga delle regole attenuati e
# senza mouse, salvo il bottone dello strato aperto. Nessuno strato aperto: tutto come prima.
func _update_modal_state() -> void:
	var settings_open := _settings_overlay != null and _settings_overlay.visible
	var produce_open := _produce_overlay != null and _produce_overlay.visible
	var cut_open := _cut_overlay != null and _cut_overlay.visible
	var modal := settings_open or produce_open or cut_open
	if _modal_shade != null:
		_modal_shade.visible = modal
	if _command_row != null:
		for child in _command_row.get_children():
			var control := child as Control
			if control == null:
				continue
			var active := not modal or (produce_open and control == _produce_button) or (cut_open and control == _zone_button(_zone_kind))
			control.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
			control.modulate = Color(1, 1, 1, 1) if active else MODAL_DIM_MODULATE
	if _settings_toggle != null:
		var toggle_active := not modal or settings_open
		_settings_toggle.mouse_filter = Control.MOUSE_FILTER_STOP if toggle_active else Control.MOUSE_FILTER_IGNORE
		_settings_toggle.modulate = Color(1, 1, 1, 1) if toggle_active else MODAL_DIM_MODULATE


# Esc con lo strato aperto (2026-10-09): lo chiude senza creare niente, prima che il tasto arrivi al resto del gioco.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _cut_overlay != null and _cut_overlay.visible:
		# Mentre si sceglie la zona sulla mappa, Esc annulla la scelta (GameScene), non lo strato.
		if _cut_zone_picking:
			return
		close_cut_overlay()
		get_viewport().set_input_as_handled()
	elif _produce_overlay != null and _produce_overlay.visible:
		close_produce_overlay()
		get_viewport().set_input_as_handled()
	elif _settings_overlay != null and _settings_overlay.visible:
		# Esc chiude anche le regole (2026-10-09, strati modali): come "Salva e chiudi", applica il numero scritto.
		_on_settings_save_pressed()
		get_viewport().set_input_as_handled()


# Riga di una ricetta: icona a sinistra, poi il bottone a tutta riga con il nome (stile della scelta di PickupChoiceMenu).
# Clic sinistro +1, destro −1 sulla quantità preparata (mai sotto 0, mai sopra il massimo della ricetta).
func _build_produce_recipe_row(index: int) -> Control:
	var recipe_name := String(_produce_recipes[index]["name"])
	var max_quantity := maxi(int(_produce_recipes[index].get("max_quantity", 1)), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_build_entry_icon({"icon": {"resource": recipe_name}}))
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	button.tooltip_text = "%s\n%s" % [IconRegistry.get_resource_display_name(recipe_name), tr("drawer_produce_overlay_hint")]
	_apply_produce_selected_style(button)
	button.set_meta(&"recipe_name", recipe_name)
	# Ricetta che nessuno può fare (2026-10-09: attrezzo che nessun adulto ha e nessuna Attrezzeria copre): spenta, motivo
	# nel tooltip, nessun gesto.
	var disabled_reason := String(_produce_recipes[index].get("disabled_reason", ""))
	if disabled_reason != "":
		button.disabled = true
		button.tooltip_text = "%s\n%s" % [IconRegistry.get_resource_display_name(recipe_name), disabled_reason]
		row.modulate = MODAL_DIM_MODULATE
		_produce_buttons.append(button)
		row.add_child(button)
		return row
	# Il gesto passa da gui_input (il bottone non cambia stato da solo): lo stato "premuto" = quantità preparata > 0.
	button.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not event.pressed:
			return
		var delta := 0
		if event.button_index == MOUSE_BUTTON_LEFT:
			delta = 1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			delta = -1
		else:
			return
		button.accept_event()
		var quantity := clampi(int(_produce_quantities.get(recipe_name, 0)) + delta, 0, max_quantity)
		if quantity > 0:
			_produce_quantities[recipe_name] = quantity
		else:
			_produce_quantities.erase(recipe_name)
		_refresh_produce_buttons()
	)
	_produce_buttons.append(button)
	row.add_child(button)
	return row


# Nome di ogni ricetta, con "×N" ed evidenziato se preparata; "Invia in coda" acceso solo con almeno una quantità > 0.
func _refresh_produce_buttons() -> void:
	for button in _produce_buttons:
		var recipe_name := String(button.get_meta(&"recipe_name", ""))
		var quantity := int(_produce_quantities.get(recipe_name, 0))
		var display_name := IconRegistry.get_resource_display_name(recipe_name)
		button.text = ("%s  ×%d" % [display_name, quantity]) if quantity > 0 else display_name
		button.set_pressed_no_signal(quantity > 0)
	if _produce_submit_button != null:
		_produce_submit_button.disabled = _produce_quantities.is_empty()


# "Invia in coda": un ordine per ricetta preparata, nell'ordine dello strato, con la spunta attuale; poi chiude.
func _on_produce_submit_pressed() -> void:
	if _produce_quantities.is_empty():
		return
	var orders: Array[Dictionary] = []
	for button in _produce_buttons:
		var recipe_name := String(button.get_meta(&"recipe_name", ""))
		var quantity := int(_produce_quantities.get(recipe_name, 0))
		if quantity > 0:
			orders.append({"recipe": recipe_name, "quantity": quantity})
	var deliver := _produce_deliver_check.button_pressed
	close_produce_overlay()
	produce_orders_submitted.emit(orders, deliver)


# Stile "selezionato" della scelta del popup "Raccogli" (PickupChoiceMenu: stessi colori).
func _apply_produce_selected_style(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PickupChoiceMenu.SELECTED_BG_COLOR
	style.border_color = PickupChoiceMenu.SELECTED_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", style)
	button.add_theme_color_override("font_pressed_color", PickupChoiceMenu.SELECTED_FONT_COLOR)
	button.add_theme_color_override("font_hover_pressed_color", PickupChoiceMenu.SELECTED_FONT_COLOR)


# Altezza dello strato: ricette + spunta + margini, al massimo la zona delle due sezioni (oltre, scorrono le ricette).
func _fit_produce_overlay() -> void:
	if _produce_overlay == null or _sections_area == null or not _produce_overlay.visible:
		return
	var style := _produce_overlay.get_theme_stylebox("panel")
	var margins := style.get_minimum_size().y if style != null else 0.0
	var wanted := margins + _produce_box.get_combined_minimum_size().y + float(SETTINGS_CONTENT_SEPARATION) \
		+ _produce_footer.get_combined_minimum_size().y
	var height := minf(wanted, _sections_area.size.y)
	if not is_equal_approx(_produce_overlay.offset_bottom, height):
		_produce_overlay.offset_bottom = height


# --- Strato "Taglia" (2026-10-09, vedi _cut_overlay) ---

func _build_cut_overlay(area: Control) -> void:
	_cut_overlay = PanelContainer.new()
	_cut_overlay.anchor_left = 0.0
	_cut_overlay.anchor_right = 1.0
	_cut_overlay.anchor_top = 0.0
	_cut_overlay.anchor_bottom = 0.0
	_cut_overlay.offset_left = 0.0
	_cut_overlay.offset_right = 0.0
	_cut_overlay.offset_top = 0.0
	_cut_overlay.offset_bottom = 0.0
	_cut_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_cut_overlay.visible = false
	_cut_overlay.add_theme_stylebox_override("panel", _make_settings_overlay_style())
	area.add_child(_cut_overlay)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", SETTINGS_CONTENT_SEPARATION)
	_cut_overlay.add_child(content)
	# Il contenuto scorre (2026-10-09: il menu di "Raccogli" può essere lungo); i bottoni in fondo restano fuori.
	var cut_scroll := ScrollContainer.new()
	cut_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cut_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cut_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(cut_scroll)
	_cut_box = VBoxContainer.new()
	_cut_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cut_box.add_theme_constant_override("separation", 4)
	cut_scroll.add_child(_cut_box)
	_cut_title_label = _section_title(tr("drawer_cut_title"))
	_cut_box.add_child(_cut_title_label)
	# Cosa raccogliere (solo "Raccogli"): lo stesso menu del popup, testi più piccoli e tagliati per stare nel cassetto.
	_gather_section = VBoxContainer.new()
	_gather_section.add_theme_constant_override("separation", 2)
	_gather_section.visible = false
	_cut_box.add_child(_gather_section)
	_gather_list = VBoxContainer.new()
	_gather_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gather_section.add_child(_gather_list)
	_gather_menu = PickupChoiceMenu.new()
	_gather_menu.selection_changed.connect(func(_is_resource: bool, _max_quantity: int) -> void:
		_gather_chosen = true
		_refresh_cut_zone(_cut_zone_name)
	)
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	var count_label := Label.new()
	_cut_count_label = count_label
	count_label.text = tr("cut_order_dialog_count")
	count_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_row.add_child(count_label)
	_cut_count_spin = SpinBox.new()
	_cut_count_spin.step = 1
	_cut_count_spin.rounded = true
	_cut_count_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_row.add_child(_cut_count_spin)
	_cut_box.add_child(count_row)
	# Destinazione dei prodotti (solo "Caccia"): il pulsante della barra dei comandi, stessa impostazione.
	_hunt_destination_row = HBoxContainer.new()
	_hunt_destination_row.add_theme_constant_override("separation", 6)
	_hunt_destination_row.visible = false
	var destination_label := Label.new()
	destination_label.text = tr("hunt_destination_button_label")
	destination_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	destination_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destination_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hunt_destination_row.add_child(destination_label)
	_hunt_destination_button = ButcherDestinationButton.new()
	_hunt_destination_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hunt_destination_button.destination_chosen.connect(func(destination: String) -> void: butcher_destination_chosen.emit(destination))
	_hunt_destination_row.add_child(_hunt_destination_button)
	_cut_box.add_child(_hunt_destination_row)
	# "Scegli zona in automatico" a sinistra e l'interruttore a destra (2026-10-09, come nel popup della caccia).
	var zone_row := HBoxContainer.new()
	zone_row.add_theme_constant_override("separation", 6)
	var auto_zone_label := Label.new()
	auto_zone_label.text = tr("command_bar_auto_zone")
	auto_zone_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	auto_zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_zone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone_row.add_child(auto_zone_label)
	_cut_auto_zone_toggle = AutoZoneToggle.new()
	_cut_auto_zone_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cut_auto_zone_toggle.auto_zone_changed.connect(func(enabled: bool) -> void:
		_cut_auto_zone = enabled
		_cut_zone_pick_row.visible = not enabled
		_refresh_cut_zone(_cut_zone_name)
		_fit_cut_overlay.call_deferred()
	)
	zone_row.add_child(_cut_auto_zone_toggle)
	_cut_box.add_child(zone_row)
	_cut_zone_pick_row = HBoxContainer.new()
	_cut_zone_pick_row.add_theme_constant_override("separation", 6)
	_cut_zone_label = Label.new()
	_cut_zone_label.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_cut_zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cut_zone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cut_zone_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cut_zone_pick_row.add_child(_cut_zone_label)
	_cut_zone_button = Button.new()
	_cut_zone_button.text = tr("drawer_cut_pick_zone")
	_cut_zone_button.focus_mode = Control.FOCUS_NONE
	_cut_zone_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cut_zone_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_cut_zone_button.pressed.connect(func() -> void:
		_cut_zone_picking = true
		zone_pick_requested.emit()
	)
	_cut_zone_pick_row.add_child(_cut_zone_button)
	_cut_box.add_child(_cut_zone_pick_row)
	# Fuori dal contenuto, sempre visibile: "Invia in coda" e "Annulla" a destra.
	_cut_footer = HBoxContainer.new()
	_cut_footer.add_theme_constant_override("separation", 6)
	_cut_footer.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(_cut_footer)
	_cut_submit_button = Button.new()
	_cut_submit_button.text = tr("drawer_produce_submit")
	_cut_submit_button.focus_mode = Control.FOCUS_NONE
	_cut_submit_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	_cut_submit_button.pressed.connect(_on_cut_submit_pressed)
	_cut_footer.add_child(_cut_submit_button)
	var cancel_button := Button.new()
	cancel_button.text = tr("transport_dialog_cancel")
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.add_theme_font_size_override("font_size", LIST_FONT_SIZE)
	cancel_button.pressed.connect(close_cut_overlay)
	_cut_footer.add_child(cancel_button)
	_sections_area.resized.connect(_fit_cut_overlay)
	_cut_box.minimum_size_changed.connect(_fit_cut_overlay)


# Apre lo strato dell'ordine di zona `kind` (ZONE_KIND_CUT "Taglia" / ZONE_KIND_QUARRY "Estrai") con `title` e la voce del
# numero `count_label`: da `min_count` a `max_count` (parte da `default_count`); `auto_zone` = opzione "zona automatica"
# accesa (niente scelta della zona). Chiude gli altri strati.
# `gather_resources` (solo "Raccogli"): le voci del menu, come per il popup ({"resource_name", "category", "quantity",
# "source_kind"}, HaulZoneService.list_work_area_resources); `gather_default` la voce preselezionata, la stessa del popup
# (UserOptions.get_pickup_default_choice, ripiego come lui). `count_step`: passo del numero (5 per la carne della caccia).
func open_zone_order_overlay(kind: String, title: String, count_label: String, min_count: int, max_count: int, default_count: int, auto_zone: bool, gather_resources: Array = [], gather_default: Dictionary = {}, count_step: int = 1) -> void:
	if _cut_overlay == null:
		return
	if _settings_toggle != null and _settings_toggle.button_pressed:
		_settings_toggle.button_pressed = false
	close_produce_overlay()
	_zone_kind = kind
	_gather_section.visible = kind == ZONE_KIND_GATHER
	_gather_chosen = false
	if kind == ZONE_KIND_GATHER:
		_gather_menu.build(_gather_list, gather_resources, gather_default)
		_gather_chosen = not _gather_menu.get_selected().is_empty()
		_compact_gather_rows(_gather_list)
	_cut_title_label.text = title
	_cut_count_label.text = count_label
	_cut_count_spin.step = maxi(count_step, 1)
	_cut_count_spin.min_value = min_count
	_cut_count_spin.max_value = max_count
	_cut_count_spin.value = clampi(default_count, min_count, max_count)
	_hunt_destination_row.visible = kind == ZONE_KIND_HUNT
	# Zona automatica: quella dell'opzione (l'interruttore la mostra e la cambia, anche per gli altri posti).
	_cut_auto_zone = UserOptions.work_area_auto_zone if _cut_auto_zone_toggle != null else auto_zone
	_cut_zone_id = -1
	_cut_zone_name = ""
	_cut_zone_picking = false
	_cut_zone_pick_row.visible = not _cut_auto_zone
	_refresh_cut_zone("")
	_cut_overlay.visible = true
	_update_modal_state()
	_fit_cut_overlay()
	_fit_cut_overlay.call_deferred()


# Stato del pulsante della destinazione nello strato (stessi argomenti di CommandBar.set_butcher_destination): la riga
# compare nella "Caccia", sempre (2026-10-09: anche senza essiccatoio, con le destinazioni non disponibili spente).
func set_butcher_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> void:
	_hunt_destination_shown = is_shown
	if _hunt_destination_button == null:
		return
	_hunt_destination_button.set_destination(is_shown, current, options)


# Zona scelta sulla mappa (GameScene, dopo zone_pick_requested): `zone_id` -1 = nessuna (scelta annullata).
func set_order_zone(zone_id: int, zone_name: String) -> void:
	_cut_zone_picking = false
	if zone_id < 0:
		return
	_cut_zone_id = zone_id
	_cut_zone_name = zone_name
	_refresh_cut_zone(zone_name)


# Fine della scelta sulla mappa senza zona (Esc, clic destro, clic fuori): lo strato resta com'era.
func end_zone_pick() -> void:
	_cut_zone_picking = false


func close_cut_overlay() -> void:
	if _cut_overlay != null:
		_cut_overlay.visible = false
	_cut_zone_picking = false
	_update_modal_state()


# Testi del menu della raccolta a misura di cassetto: carattere della lista e bottoni che si accorciano con i puntini.
func _compact_gather_rows(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			(child as Button).clip_text = true
			(child as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(child as Button).tooltip_text = (child as Button).text
			(child as Control).add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		elif child is Label:
			(child as Control).add_theme_font_size_override("font_size", LIST_FONT_SIZE)
		_compact_gather_rows(child)


# Cosa raccogliere scelto nello strato ({"kind", "category", "resource_name", ...} di PickupChoiceMenu.get_selected();
# {} se nessuna voce).
func get_gather_choice() -> Dictionary:
	if _gather_menu == null or not _gather_chosen:
		return {}
	return _gather_menu.get_selected()


func _refresh_cut_zone(zone_name: String) -> void:
	# Acceso: l'interruttore dice già "zona automatica", nessuna scritta accanto.
	_cut_zone_label.visible = not _cut_auto_zone
	if _cut_auto_zone:
		_cut_zone_label.text = ""
	elif _cut_zone_id >= 0:
		_cut_zone_label.text = tr("drawer_cut_zone_label").format({"zone": zone_name})
	else:
		_cut_zone_label.text = tr("drawer_cut_zone_label").format({"zone": tr("drawer_cut_zone_none")})
	_cut_submit_button.disabled = (not _cut_auto_zone and _cut_zone_id < 0) or (_zone_kind == ZONE_KIND_GATHER and not _gather_chosen)


func _on_cut_submit_pressed() -> void:
	if not _cut_auto_zone and _cut_zone_id < 0:
		return
	if _zone_kind == ZONE_KIND_GATHER and not _gather_chosen:
		return
	_cut_count_spin.apply()
	var count := int(_cut_count_spin.value)
	var zone_id := -1 if _cut_auto_zone else _cut_zone_id
	close_cut_overlay()
	zone_order_submitted.emit(_zone_kind, count, zone_id)


# Altezza dello strato: contenuto + bottoni + margini, al massimo la zona delle due sezioni.
func _fit_cut_overlay() -> void:
	if _cut_overlay == null or _sections_area == null or not _cut_overlay.visible:
		return
	var style := _cut_overlay.get_theme_stylebox("panel")
	var margins := style.get_minimum_size().y if style != null else 0.0
	var wanted := margins + _cut_box.get_combined_minimum_size().y + float(SETTINGS_CONTENT_SEPARATION) \
		+ _cut_footer.get_combined_minimum_size().y
	var height := minf(wanted, _sections_area.size.y)
	if not is_equal_approx(_cut_overlay.offset_bottom, height):
		_cut_overlay.offset_bottom = height


# --- Carico di lavoro sul titolo "In corso" (2026-10-09, richiesta utente) ---
# Riga del titolo "In corso" (2026-10-09, rivista lo stesso giorno: sotto il titolo sembrava una riga divisoria): a
# sinistra "In corso · 3 al lavoro su 6" (mai a capo), a destra la barra nello spazio rimasto e dopo la percentuale al
# lavoro ("50%"). La barra (2026-10-09, rivista: non più a parti colorate) è un riempimento unico della percentuale al
# lavoro sullo sfondo scuro, con bordo sottile e angoli arrotondati; colore secondo il carico: verde sotto
# WORKLOAD_ORANGE_FROM_PERCENT, arancione fino a WORKLOAD_RED_FROM_PERCENT escluso, rosso da lì in su. Senza spazio la
# barra si accorcia fino a WORKLOAD_BAR_MIN_WIDTH; WORKLOAD_BAR_RIGHT_GAP la tiene un po' più corta dello spazio rimasto.
# Stesso tooltip su titolo, barra e percentuale: solo i conteggi (al lavoro, svago, bisogni personali), su tre righe.
# Valori da GameScene (set_workload) a ogni ricalcolo della lista.
const WORKLOAD_BAR_HEIGHT: float = 16.0
const WORKLOAD_BAR_MIN_WIDTH: float = 40.0
const WORKLOAD_BAR_RIGHT_GAP: float = 20.0
const WORKLOAD_BAR_BG_COLOR := Color(0.08, 0.09, 0.11, 1.0)
const WORKLOAD_BAR_BORDER_COLOR := Color(0.75, 0.85, 1.0, 0.45)
# Soglie del colore del riempimento (percentuale al lavoro).
const WORKLOAD_ORANGE_FROM_PERCENT: int = 60
const WORKLOAD_RED_FROM_PERCENT: int = 85
const WORKLOAD_GREEN := Color(0.35, 0.75, 0.35, 1.0)
const WORKLOAD_ORANGE := Color(0.9, 0.6, 0.2, 1.0)
const WORKLOAD_RED := Color(0.85, 0.25, 0.25, 1.0)
var _in_progress_title: Label = null
var _workload_bar: PanelContainer = null
var _workload_percent: Label = null
var _workload_fill: ColorRect = null
var _workload_empty: Control = null
var _pending_workload: Array = []


func _build_workload_bar() -> void:
	var section := _in_progress_box.get_parent().get_parent() as VBoxContainer
	if section == null:
		return
	_in_progress_title = section.get_child(0) as Label
	if _in_progress_title == null:
		return
	# Il titolo passa in una riga orizzontale, al suo posto: titolo, barra, percentuale.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	section.add_child(row)
	section.move_child(row, _in_progress_title.get_index())
	section.remove_child(_in_progress_title)
	_in_progress_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_in_progress_title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_in_progress_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_in_progress_title)
	_workload_bar = PanelContainer.new()
	_workload_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workload_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_workload_bar.custom_minimum_size = Vector2(WORKLOAD_BAR_MIN_WIDTH, WORKLOAD_BAR_HEIGHT)
	_workload_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_workload_bar.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = WORKLOAD_BAR_BG_COLOR
	style.border_color = WORKLOAD_BAR_BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	_workload_bar.add_theme_stylebox_override("panel", style)
	row.add_child(_workload_bar)
	# Riempimento e parte vuota divisi in proporzione alla percentuale (stretch ratio).
	var fill_box := HBoxContainer.new()
	fill_box.add_theme_constant_override("separation", 0)
	fill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_workload_bar.add_child(fill_box)
	_workload_fill = ColorRect.new()
	_workload_fill.color = WORKLOAD_GREEN
	_workload_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workload_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_workload_fill.visible = false
	fill_box.add_child(_workload_fill)
	_workload_empty = Control.new()
	_workload_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workload_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_box.add_child(_workload_empty)
	_workload_percent = Label.new()
	_workload_percent.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_workload_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_workload_percent.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_workload_percent)
	# Barra un po' più corta dello spazio rimasto.
	var right_gap := Control.new()
	right_gap.custom_minimum_size = Vector2(WORKLOAD_BAR_RIGHT_GAP, 0.0)
	right_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right_gap)
	if not _pending_workload.is_empty():
		var pending_extra: Array[Dictionary] = []
		pending_extra.assign(_pending_workload[3])
		set_workload(int(_pending_workload[0]), int(_pending_workload[1]), int(_pending_workload[2]), pending_extra)


# `at_work` + `needs` + `leisure` + le voci di `extra_rows` = individui in età da lavoro. `extra_rows` (2026-10-09):
# [{"key": chiave tr() con {count}, "count": int}] — righe del tooltip subito dopo "Al lavoro" (es. "In cerca di lavoro",
# poi "Coordina"), contate nel totale ma non tra "al lavoro".
func set_workload(at_work: int, needs: int, leisure: int, extra_rows: Array[Dictionary] = []) -> void:
	_pending_workload = [at_work, needs, leisure, extra_rows]
	if _in_progress_title == null or _workload_bar == null:
		return
	var total := at_work + needs + leisure
	for extra in extra_rows:
		total += int(extra.get("count", 0))
	_in_progress_title.text = tr("task_assignment_in_progress_workload").format({"working": at_work, "total": total})
	var percent: int = roundi(100.0 * float(at_work) / float(total)) if total > 0 else 0
	_workload_percent.text = "%d%%" % percent
	var tooltip_lines: Array[String] = [tr("task_assignment_workload_working").format({"count": at_work})]
	for extra in extra_rows:
		tooltip_lines.append(tr(String(extra.get("key", ""))).format({"count": int(extra.get("count", 0))}))
	tooltip_lines.append(tr("task_assignment_workload_leisure").format({"count": leisure}))
	tooltip_lines.append(tr("task_assignment_workload_needs").format({"count": needs}))
	var tooltip := "\n".join(tooltip_lines)
	_in_progress_title.tooltip_text = tooltip
	_workload_bar.tooltip_text = tooltip
	_workload_percent.tooltip_text = tooltip
	_workload_fill.visible = percent > 0
	_workload_empty.visible = percent < 100
	_workload_fill.size_flags_stretch_ratio = maxf(float(percent), 0.001)
	_workload_empty.size_flags_stretch_ratio = maxf(float(100 - percent), 0.001)
	if percent >= WORKLOAD_RED_FROM_PERCENT:
		_workload_fill.color = WORKLOAD_RED
	elif percent >= WORKLOAD_ORANGE_FROM_PERCENT:
		_workload_fill.color = WORKLOAD_ORANGE
	else:
		_workload_fill.color = WORKLOAD_GREEN


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	return label
