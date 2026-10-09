class_name PickupChoiceDialog
extends Window

# Popup di scelta del comando di raccolta (2026-09-20, zaino multi-risorsa, passo 3) — SOSTITUISCE l'uso di
# OptionChoiceDialog per il pickup (quello resta solo per la Transport, che sceglie sempre UNA risorsa da un
# edificio). Menu GERARCHICO a tre livelli, tutto sempre visibile (righe indentate, stesso stile a bottoni
# "selezionato" di OptionChoiceDialog):
#
#   Tutto                          <- livello 1: criterio ALL (tutto quello che c'e' nella microcella)
#   └ Cibo                         <- livello 2: solo intestazione di categoria, non selezionabile
#      └ Tutto il cibo             <- livello 3: criterio CATEGORY
#      └ funghi                    <- livello 3: criterio NAME (una risorsa, con quantita')
#      └ ghiande
#   └ Materiali
#      └ Tutti i materiali
#      └ rametti
#
# Regole:
#   - compaiono SOLO le risorse realmente presenti (`resources` porta solo quelle con scorta) e solo le
#     categorie che ne hanno almeno una;
#   - scegliendo "Tutto" o il "tutto" di una categoria non si sceglie nessun livello inferiore;
#   - la riga quantita' (SpinBox) e' visibile SOLO con una risorsa specifica selezionata, con "tutto"/categoria
#     sparisce (la quantita' verrebbe ignorata da PickUpAction);
#   - preselezione: `default_choice` (per ora sempre "Tutto", fisso, deciso dal chiamante). Se il nodo di default
#     non e' presente si risale al nodo disponibile piu' vicino: la sua categoria ("tutto" della categoria), poi
#     "Tutto".
#
# "Pannello muto" (stesso principio di OptionChoiceDialog): open_dialog riceve testi e dati GIA' RISOLTI dal
# chiamante e non legge mai il mondo. Il criterio scelto esce dal segnale choice_made con gli stessi valori di
# PickUpAction.CriterionKind (NAME/CATEGORY/ALL), pronti per _assign_pickup_task.
#
# NESSUN visibility_changed collegato a GameScene._on_blocking_dialog_visibility_changed (come
# OptionChoiceDialog): scegliere cosa raccogliere e' un'azione rapida a gioco in corso, l'orologio non si ferma.

# kind: PickUpAction.CriterionKind (NAME = una risorsa, CATEGORY = tutta la categoria, ALL = tutto);
# category: SecondaryResourceTypes.Category come int (solo con CATEGORY, altrimenti -1); resource_name: solo
# con NAME, altrimenti ""; quantity: solo con NAME (quella scelta nello SpinBox), altrimenti -1; repeat: stato
# del flag "Ripeti fino a N volte" (2026-09-20), indipendente dal criterio.
# source_kind (2026-09-26, ground drop): PickUpAction.SourceKind della voce scelta (mucchio a terra o terreno).
signal choice_made(kind: int, category: int, resource_name: String, quantity: int, repeat: bool, source_kind: int)
# Modalità caccia (2026-10-01, comando Caccia nelle zone — open_hunt_dialog): solo il selettore "Carne", nessun elenco.
# `butcher_destination` (2026-10-03): destinazione dei prodotti della macellazione (ButcherDestinationService).
signal hunt_choice_made(meat_target: int, butcher_destination: String)
# Scelta dal pulsante della destinazione (2026-10-09, ButcherDestinationButton: lo stesso della barra dei comandi, stessa
# impostazione condivisa): GameScene la scrive subito in GameData.last_butcher_destination, come dalla barra.
signal butcher_destination_chosen(destination: String)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var choice_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ChoiceScroll/ChoiceListContainer
@onready var choice_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ChoiceScroll
@onready var repeat_check_box: CheckBox = $MarginContainer/VBoxContainer/RepeatCheckBox
@onready var quantity_row: HBoxContainer = $MarginContainer/VBoxContainer/QuantityRow
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $MarginContainer/VBoxContainer/QuantityRow/QuantitySpinBox
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton

# Menu Tutto / categoria / risorsa (2026-10-05): estratto in PickupChoiceMenu, condiviso con la voce "Raccogli" del
# popup del click destro; le chiavi delle categorie (CATEGORY_TEXT_KEYS) vivono lì.

# Dimensionamento del popup (stesso principio di OptionChoiceDialog): base = messaggio + riga quantita' +
# separatore + riga bottoni; poi una riga per voce del menu. Tetto al valore di MAX_DIALOG_HEIGHT, oltre il
# quale la lista scorre (ScrollContainer).
const DIALOG_BASE_HEIGHT: float = 224.0
const ROW_HEIGHT: float = 34.0
const MAX_DIALOG_HEIGHT: float = 640.0
const DIALOG_WIDTH: int = 320

# Menu delle voci (PickupChoiceMenu): costruito in choice_list_container a ogni apertura in modalità raccolta.
var _menu: PickupChoiceMenu = null
# false = nessuna scelta della quantità (2026-09-27, raccolta nelle zone di lavoro: la quantità non si sceglie).
var _quantity_enabled: bool = true
# Selettore "viaggi" (2026-10-01, raccolta nelle zone): al posto della casella delle ripetizioni quando open_dialog riceve
# trips > 0. Riga costruita in codice sotto la casella (_ensure_trips_row). Il valore scelto è in selected_trips al
# momento di choice_made (repeat = selected_trips > 1); 0 = modalità casella (clic su una cella).
var selected_trips: int = 0
var _trips_mode: bool = false
var _trips_row: HBoxContainer = null
var _trips_spin_box: SpinBox = null
# Modalità caccia (open_hunt_dialog): riga "Carne" con i valori ammessi, costruita in codice come la riga dei viaggi.
var _hunt_mode: bool = false
var _meat_row: HBoxContainer = null
var _meat_option: OptionButton = null
var _meat_values: Array[int] = []
# Altezza di partenza in modalità caccia: la finestra poi si adatta al contenuto (_fit_to_content).
const HUNT_DIALOG_HEIGHT: float = 120.0
# Destinazione della caccia (2026-10-09): la vecchia sezione da spuntare è stata tolta; resta il pulsante condiviso
# con la barra e il cassetto (_hunt_destination_button), che vale subito.
# Posizione accanto a un pannello (2026-10-09, richiesta utente — "Raccogli nelle zone di lavoro" e Caccia dalla lista
# degli individui): se prima di open_dialog / open_hunt_dialog il chiamante imposta `popup_anchor` (vedi
# DialogPlacement.place), la finestra resta identica ma compare accanto all'info panel invece che al centro. Vale per
# quell'apertura sola; {} = al centro come sempre.
var popup_anchor: Dictionary = {}
var _anchor: Dictionary = {}
# Interruttore della zona automatica (2026-10-09): visibile in "Raccogli nelle zone di lavoro" (modalità viaggi) e nella
# caccia, non nella raccolta da una cella.
var _auto_zone_row: HBoxContainer = null
# Riga "Destinazione dei prodotti [pulsante]" nella caccia (2026-10-09), sopra quella della zona automatica: il pulsante
# della barra dei comandi, visibile negli stessi casi (set_butcher_destination, da GameScene).
var _hunt_destination_row: HBoxContainer = null
var _hunt_destination_button: ButcherDestinationButton = null
var _hunt_destination_state: Dictionary = {"shown": false, "current": {}, "options": []}


func _ready() -> void:
	_menu = PickupChoiceMenu.new()
	_menu.selection_changed.connect(_on_menu_selection_changed)
	quantity_label.text = tr("transport_dialog_quantity_label")
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": TaskRepeatRules.MAX_TRIPS})
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)
	# Esc chiude senza fare nulla, in entrambe le modalità (2026-10-01).
	window_input.connect(_on_window_input)


# `resources`: Array di Dictionary {"resource_name": String, "category": int, "quantity": int (> 0),
# "source_kind": PickUpAction.SourceKind (facoltativo, default TERRAIN)} — SOLO
# quelle realmente presenti nella microcella. `default_choice`: {"kind": PickUpAction.CriterionKind,
# "category": int, "resource_name": String}; vuoto o senza "kind" = "Tutto" (il default fisso di oggi).
# `repeat_default`: stato iniziale del flag "Ripeti fino a N viaggi" (2026-09-20: UserOptions.repeat_default).
# repeat_max/quantity_enabled (2026-09-27, work areas passo 3a): ripetizioni mostrate nella spunta (3 per il clic su una
# cella, 5 per la raccolta nelle zone) e scelta della quantità (spenta per le zone).
func open_dialog(
	dialog_title: String, message: String, resources: Array, default_choice: Dictionary = {}, repeat_default: bool = false,
	repeat_max: int = TaskRepeatRules.MAX_REPEATS, quantity_enabled: bool = true, trips: int = 0, trips_max: int = 0
) -> void:
	_anchor = popup_anchor
	popup_anchor = {}
	_set_hunt_mode(false)
	title = dialog_title
	message_label.text = message
	repeat_check_box.button_pressed = repeat_default
	# Il testo conta i viaggi in tutto (2026-10-05): il primo più repeat_max ripetizioni.
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": repeat_max + 1})
	_trips_mode = trips > 0
	repeat_check_box.visible = not _trips_mode
	_ensure_trips_row()
	_trips_row.visible = _trips_mode
	_show_auto_zone_row(_trips_mode)
	selected_trips = 0
	if _trips_mode:
		_trips_spin_box.max_value = maxi(trips_max, 1)
		_trips_spin_box.value = clampi(trips, 1, maxi(trips_max, 1))
	_quantity_enabled = quantity_enabled

	# Righe del menu (PickupChoiceMenu: sorgenti, "Tutto", categorie, risorse) e selezione del default.
	var row_count: int = _menu.build(choice_list_container, resources, default_choice)

	exclusive = true
	var height: float = minf(DIALOG_BASE_HEIGHT + float(row_count) * ROW_HEIGHT, MAX_DIALOG_HEIGHT)
	_popup_fitted(height)


# Scelta cambiata nel menu: la riga quantita' e' visibile SOLO per una risorsa specifica, con tetto/valore pari alla
# quantita' disponibile.
func _on_menu_selection_changed(is_resource: bool, max_quantity: int) -> void:
	quantity_row.visible = is_resource and _quantity_enabled
	if is_resource:
		quantity_spin_box.max_value = max_quantity
		quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
		quantity_spin_box.value = max_quantity


# Modalità caccia (2026-10-01, comando Caccia nelle zone): stesso dialog e stesso stile di Raccogli, con titolo e
# messaggio della caccia, senza elenco delle risorse, con il solo selettore "Carne" (`meat_options`, preselezionato
# `default_target` o il primo valore) e Conferma/Annulla. Conferma -> hunt_choice_made(valore); Annulla/Esc -> nulla.
# Ritorna false (dialog NON aperto, nessun pannello lasciato sullo schermo) se la riga non si costruisce o non ci sono
# valori: il chiamante non deve aspettarsi una risposta.
# La destinazione è quella del pulsante (impostazione condivisa, GameScene.set_butcher_destination): hunt_choice_made
# la passa vuota e GameScene usa quella attuale.
func open_hunt_dialog(dialog_title: String, message: String, meat_options: Array[int], default_target: int) -> bool:
	_ensure_meat_row()
	if _meat_option == null or meat_options.is_empty():
		popup_anchor = {}
		push_error("PickupChoiceDialog.open_hunt_dialog: riga \"Carne\" non disponibile o nessun valore — dialog non aperto.")
		hide()
		return false
	_set_hunt_mode(true)
	_show_auto_zone_row(true)
	_show_hunt_destination_row()
	title = dialog_title
	message_label.text = message
	_meat_values = meat_options.duplicate()
	_meat_option.clear()
	var selected_index := 0
	for i in range(_meat_values.size()):
		_meat_option.add_item(str(_meat_values[i]), i)
		if _meat_values[i] == default_target:
			selected_index = i
	_meat_option.select(selected_index)
	_anchor = popup_anchor
	popup_anchor = {}
	exclusive = true
	_popup_fitted(HUNT_DIALOG_HEIGHT)
	return true


# Apre centrato con l'altezza voluta e poi (2026-10-01, bugfix "bottoni tagliati") adatta la finestra al contenuto: il
# messaggio va a capo solo quando conosce la propria larghezza, quindi l'altezza minima vera si legge dopo il primo
# layout. Mai più bassa del contenuto (bottoni sempre interi), mai più stretta di DIALOG_WIDTH; in Raccogli resta
# l'altezza calcolata dalle righe se è maggiore (l'elenco scorre).
func _popup_fitted(desired_height: float) -> void:
	popup_centered(Vector2i(DIALOG_WIDTH, int(desired_height)))
	_place()
	_fit_to_content.call_deferred(desired_height)


# Al centro, oppure accanto al pannello se l'apertura ha una posizione (_anchor, DialogPlacement.place).
func _place() -> void:
	DialogPlacement.place(self, _anchor)


func _fit_to_content(desired_height: float) -> void:
	await get_tree().process_frame
	if not visible:
		return
	var content := get_node_or_null("MarginContainer") as Control
	if content == null:
		return
	var min_size := content.get_combined_minimum_size()
	var fitted := Vector2i(maxi(DIALOG_WIDTH, ceili(min_size.x)), maxi(int(desired_height), ceili(min_size.y)))
	if fitted != size:
		size = fitted
		_place()


# Mostra solo ciò che serve alla modalità: elenco/casella/quantità/viaggi per la raccolta, riga "Carne" per la caccia.
func _set_hunt_mode(enabled: bool) -> void:
	_hunt_mode = enabled
	choice_scroll.visible = not enabled
	if enabled:
		repeat_check_box.visible = false
		quantity_row.visible = false
		if _trips_row != null:
			_trips_row.visible = false
	if _meat_row != null:
		_meat_row.visible = enabled
	if _hunt_destination_row != null and not enabled:
		_hunt_destination_row.visible = false


func _ensure_meat_row() -> void:
	if _meat_row != null:
		return
	# Una frase con il menu dentro (2026-10-01): «Fermati dopo aver portato a casa [10] di carne». La prima parte va a
	# capo se serve, così la finestra resta larga DIALOG_WIDTH.
	_meat_row = HBoxContainer.new()
	_meat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prefix := Label.new()
	prefix.text = tr("hunt_order_dialog_stop_prefix")
	prefix.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prefix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefix.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_meat_row.add_child(prefix)
	_meat_option = OptionButton.new()
	_meat_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meat_row.add_child(_meat_option)
	var suffix := Label.new()
	suffix.text = tr("hunt_order_dialog_stop_suffix")
	_meat_row.add_child(suffix)
	var parent := repeat_check_box.get_parent()
	parent.add_child(_meat_row)
	parent.move_child(_meat_row, repeat_check_box.get_index() + 1)
	_meat_row.visible = false


func _on_window_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		_on_cancel_pressed()


func _on_confirm_pressed() -> void:
	if _hunt_mode:
		var index := _meat_option.selected if _meat_option != null else -1
		hide()
		if index >= 0 and index < _meat_values.size():
			hunt_choice_made.emit(_meat_values[index], "")
		return
	var choice: Dictionary = _menu.get_selected()
	if choice.is_empty():
		return
	var kind: int = int(choice["kind"])
	var category: int = int(choice["category"])
	var resource_name: String = String(choice["resource_name"])
	var quantity: int = int(quantity_spin_box.value) if kind == PickUpAction.CriterionKind.NAME and _quantity_enabled else -1
	selected_trips = int(_trips_spin_box.value) if _trips_mode else 0
	var repeat: bool = selected_trips > 1 if _trips_mode else repeat_check_box.button_pressed
	hide()
	choice_made.emit(kind, category, resource_name, quantity, repeat, int(choice["source_kind"]))


# Riga "Viaggi: [1..N]" sotto la casella delle ripetizioni, creata alla prima apertura in modalità viaggi.
func _ensure_trips_row() -> void:
	if _trips_row != null:
		return
	_trips_row = HBoxContainer.new()
	var label := Label.new()
	label.text = tr("work_area_gather_trips_label")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trips_row.add_child(label)
	_trips_spin_box = SpinBox.new()
	_trips_spin_box.min_value = 1
	_trips_spin_box.step = 1
	_trips_spin_box.rounded = true
	_trips_row.add_child(_trips_spin_box)
	var parent := repeat_check_box.get_parent()
	parent.add_child(_trips_row)
	parent.move_child(_trips_row, repeat_check_box.get_index() + 1)


# Stato del pulsante della destinazione (stessi argomenti di CommandBar.set_butcher_destination), aggiornato da GameScene
# insieme a quello della barra; applicato subito se la riga esiste.
func set_butcher_destination(is_shown: bool, current: Dictionary, options: Array[Dictionary]) -> void:
	_hunt_destination_state = {"shown": is_shown, "current": current, "options": options}
	if _hunt_destination_button != null:
		_hunt_destination_button.set_destination(is_shown, current, options)
		_hunt_destination_row.visible = _hunt_mode and is_shown


func _show_hunt_destination_row() -> void:
	if _hunt_destination_row == null:
		_hunt_destination_row = HBoxContainer.new()
		_hunt_destination_row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.text = tr("hunt_destination_button_label")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hunt_destination_row.add_child(label)
		_hunt_destination_button = ButcherDestinationButton.new()
		_hunt_destination_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hunt_destination_button.destination_chosen.connect(_on_hunt_destination_button_chosen)
		_hunt_destination_row.add_child(_hunt_destination_button)
		var box := _auto_zone_row.get_parent()
		box.add_child(_hunt_destination_row)
		box.move_child(_hunt_destination_row, _auto_zone_row.get_index())
	var options: Array[Dictionary] = []
	options.assign(_hunt_destination_state["options"])
	set_butcher_destination(bool(_hunt_destination_state["shown"]), _hunt_destination_state["current"], options)


# Scelta dal pulsante: impostazione condivisa (GameScene), vale anche per questa caccia.
func _on_hunt_destination_button_chosen(destination: String) -> void:
	butcher_destination_chosen.emit(destination)


func _show_auto_zone_row(shown: bool) -> void:
	if _auto_zone_row == null:
		if not shown:
			return
		var box := $MarginContainer/VBoxContainer as VBoxContainer
		_auto_zone_row = _ensure_auto_zone_row(box, $MarginContainer/VBoxContainer/HSeparator)
	_auto_zone_row.visible = shown


# Riga "Scegli zona in automatico [interruttore]" (2026-10-09, AutoZoneToggle: lo stesso della barra dei comandi, legato a
# UserOptions.work_area_auto_zone, letto alla conferma da GameScene), creata alla prima apertura sopra il separatore dei
# bottoni.
func _ensure_auto_zone_row(box: VBoxContainer, separator: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = tr("command_bar_auto_zone")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := AutoZoneToggle.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)
	box.add_child(row)
	box.move_child(row, separator.get_index())
	return row


# Nessun segnale all'annullamento (stesso principio di OptionChoiceDialog): il chiamante non ha ancora impostato
# nulla.
func _on_cancel_pressed() -> void:
	hide()
