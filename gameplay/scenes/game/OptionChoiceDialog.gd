class_name OptionChoiceDialog
extends Window

# Popup GENERICO "scegli una risorsa e una quantità tra più candidate" — nato (2026-09-12,
# richiesta utente) come TransportSourceDialog, poi GENERALIZZATO (2026-09-17, richiesta utente:
# "usiamo OptionChoiceDialog per tutti i casi") per essere riusato ANCHE dal comando di raccolta
# manuale (destro-click su una cella con più risorse raccoglibili). DAL 2026-09-20 (zaino multi-risorsa, passo 3)
# la raccolta ha un dialog proprio, PickupChoiceDialog (menu gerarchico Tutto/categoria/risorsa): questa classe
# serve di nuovo solo alla Transport (GameScene ne instanzia un nodo, TransportSourceDialog).
#
# Lista SEMPRE VISIBILE, non più un OptionButton a tendina (2026-09-18, richiesta utente — "invece
# di un menu a tendina, fammi un elenco sempre visibile delle risorse, con icona, e le etichette
# siano dei button"): una riga per risorsa (icona + Button "Nome (quantità)"). Cliccare una riga la
# SELEZIONA (radio-style, mai più di una insieme) e aggiorna il tetto/valore dell'UNICA riga
# quantità condivisa sotto la lista — poi Conferma applica la scelta.
#
# UNA sola riga quantità condivisa, non una per risorsa (2026-09-18, richiesta utente — bugfix "con
# 2+ risorse non si vede il tasto quantità": un primo tentativo aveva dato ad OGNI risorsa il
# proprio SpinBox indipendente — corretto ma "inutile", una riga ripetuta N volte per scegliere la
# stessa identica cosa una sola volta per apertura del dialog). Ora sia il Transport sia il Pickup
# passano SEMPRE da qui: anche la raccolta da terreno lascia scegliere quanto raccogliere (Pickup
# Action.quantity_requested, 2026-09-18), non solo la Transport Task — nessun parametro
# show_quantity più necessario, la riga quantità è sempre presente.
#
# "Pannello muto" (stesso principio già seguito da BuildBar/GameInfoPanel/DemolishConfirmation
# Dialog): open_dialog riceve titolo/messaggio/Dictionary resource_name->quantità GIÀ RISOLTI dal
# chiamante — non legge mai Building/BuildingStorageService/TerrainScatteredResourceService da sé.
# Un solo scene/script per entrambi gli usi (richiesta esplicita utente, anche per motivi estetici:
# un fix visivo qui vale per ogni istanza) — GameScene ne instanzia DUE nodi separati
# (TransportSourceDialog/PickupChoiceDialog), mai un'istanza condivisa tra i due flussi: nessuno
# stato "a quale scopo sto servendo ora" da tracciare dentro questa classe, resta ignara di chi la
# usa, stesso principio "pannello muto" sopra.
#
# NESSUN visibility_changed collegato a GameScene._on_blocking_dialog_visibility_changed (2026-09-18,
# richiesta utente: "il tempo non si ferma con questo popup aperto, a differenza di idea/
# statistiche/opzioni") — il collegamento vive/non vive in GameScene._ready, non qui: questa
# classe non sa nulla del clock, resta "pannello muto" anche su questo.
# repeat (2026-09-20): stato della casella "Ripeti fino a N volte" (TaskRepeatRules), indipendente da risorsa/quantita'.
signal resource_chosen(resource_name: String, quantity: int, repeat: bool)
# Opzioni sotto una voce (2026-10-05, popup del click destro su piante e rocce — vedi open_choice_only_dialog,
# `row_options`): mouse sopra / fuori da una riga di un elenco (item_key "" = mouse uscito) e cambio della riga scelta
# o della voce (item_key "" = voce senza elenco).
# Il valore confermato si legge con get_option_value dopo resource_chosen.
signal option_hovered(row_key: String, item_key: String)
signal option_selected(row_key: String, item_key: String)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var resource_list_container: VBoxContainer = $MarginContainer/VBoxContainer/ResourceListContainer
@onready var repeat_check_box: CheckBox = $MarginContainer/VBoxContainer/RepeatCheckBox
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $MarginContainer/VBoxContainer/QuantityRow/QuantitySpinBox
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton

# Lato del riquadro icona di ogni riga (2026-09-18) — STESSA taglia di BuildingInfoPanel.
# MISSING_MATERIAL_CHIP_SIZE, un'indicazione secondaria in una lista, non la griglia principale di
# un pannello: non serve la taglia STORAGE_SLOT_SIZE più grande.
const RESOURCE_ROW_ICON_SIZE: float = 24.0

# Altezza stimata (2026-09-18) usata da open_dialog per dimensionare il popup GIÀ dalla prima
# apertura, in base al numero REALE di candidati (richiesta esplicita utente: "il popup si deve
# aprire già delle dimensioni per contenere tutto, anche riga quantità") — GENEROSA di proposito
# (meglio un po' di spazio vuoto in fondo che un controllo tagliato fuori dalla finestra, il bug
# appena segnalato dall'utente con la versione precedente). DIALOG_BASE_HEIGHT include GIÀ la riga
# quantità/separatore/riga bottoni (sempre presenti ora, mai condizionali) — solo la lista risorse
# cresce con RESOURCE_ROW_HEIGHT per candidato.
const DIALOG_BASE_HEIGHT: float = 224.0
const RESOURCE_ROW_HEIGHT: float = 34.0
# Altezza di un'intestazione di gruppo (2026-09-24, open_grouped_dialog).
const GROUP_HEADER_HEIGHT: float = 22.0

# Righe del dialog (2026-09-12, chiave per riga dal 2026-09-24): chiave di riga -> {"resource_name",
# "quantity"}. La chiave coincide col resource_name in open_dialog; in open_grouped_dialog è
# prefissata dal gruppo ("products:"/"delivered:"), perché la stessa risorsa può comparire in
# entrambi i gruppi. Usato SOLO per il tetto dello SpinBox e per il segnale, mai per una nuova query
# a Building/al mondo: stesso principio "mute panel" del commento sopra.
var _row_entries: Dictionary = {}
# Testo/icona sostitutivi per riga (vedi open_choice_only_dialog), azzerati a ogni apertura.
var _row_overrides: Dictionary = {}

# Chiave della riga selezionata (2026-09-18) — "" solo se non ci sono candidati.
var _selected_key: String = ""

# Opzioni per voce (2026-10-05): chiave di riga -> descrizione (vedi open_choice_only_dialog), pannello costruito
# (Control, visibile solo sotto la voce selezionata), sua altezza stimata e valore corrente (item_key per un elenco,
# bool per una spunta). Azzerati a ogni apertura.
var _row_options: Dictionary = {}
var _option_panels: Dictionary = {}
var _option_panel_heights: Dictionary = {}
var _option_values: Dictionary = {}
# Pulsanti delle righe di un elenco: chiave di riga -> {item_key -> Button}.
var _option_item_buttons: Dictionary = {}
# Altezza del popup senza pannelli di opzioni (vedi _popup_with_height/_fit_height).
var _base_height: float = 0.0
const OPTION_LIST_ROW_HEIGHT: float = 34.0
const OPTION_LIST_MAX_VISIBLE_ROWS: int = 10
const OPTION_CHECK_HEIGHT: float = 34.0
# Impaginazione delle opzioni (2026-10-05) sul modello di PickupChoiceDialog: stesso rientro per livello, stessa larghezza
# minima del popup, icona della risorsa a sinistra di ogni riga dell'elenco; spazio sotto il pannello (prima della riga
# di Conferma) e tra le righe e la barra di scorrimento quando l'elenco scorre.
const OPTION_LIST_INDENT: float = 16.0
const OPTION_PANEL_TOP_GAP: int = 2
const OPTION_PANEL_BOTTOM_GAP: int = 8
const OPTION_SCROLLBAR_GAP: int = 8
const OPTIONS_MIN_DIALOG_WIDTH: int = 320
# Elenchi costruiti: chiave di riga -> {"scroll": ScrollContainer, "list": VBoxContainer, "rows": int}. L'altezza dello
# scroll si misura dopo il primo layout (_fit_to_options_content), per mostrare sempre righe intere.
var _option_lists: Dictionary = {}
# Pannelli "pickup" (2026-10-05, voce "Raccogli" del popup del click destro con l'accetta): chiave di riga ->
# {"menu": PickupChoiceMenu, "quantity_row": HBoxContainer, "quantity": SpinBox, "repeat": CheckBox}.
var _pickup_panels: Dictionary = {}
# Azioni affiancate (2026-10-05, popup del click destro su piante e rocce — open_choice_only_dialog con
# `actions_layout`): le voci su una riga sola in alto (larghe uguali, _actions_row), sotto un'unica area con il pannello
# della voce selezionata (_options_area), contenuto a filo senza rientro, pulsante di conferma col nome della voce.
# Falso per ogni altro uso: voci in verticale e "Conferma", come sempre.
var _actions_layout: bool = false
var _actions_row: HBoxContainer = null
var _options_area: VBoxContainer = null
# Aspetto delle azioni affiancate (2026-10-05): pulsanti con icona e testo centrati insieme, testo in grassetto, un po'
# più alti delle righe sotto; l'azione scelta col giallo del pulsante attivo della velocità (GameScene.tscn,
# StyleBoxFlat_speed_selected — stessi valori, quello stile vive nella scena di gioco e non si può riusare da qui),
# testo scuro. Il contenuto dell'azione scelta sta in un riquadro attaccato sotto (_options_frame), nascosto se
# l'azione non ha contenuto. Testo di ogni azione senza icona, per il pulsante di conferma (_action_texts).
const ACTION_BUTTON_HEIGHT: float = 40.0
const ACTION_SELECTED_BG_COLOR := Color(0.95, 0.78, 0.2, 1.0)
const ACTION_SELECTED_BORDER_COLOR := Color(0.55, 0.4, 0.05, 1.0)
const ACTION_SELECTED_FONT_COLOR := Color(0.15, 0.1, 0.02, 1.0)
const ACTION_FONT_EMBOLDEN: float = 0.6
const OPTIONS_FRAME_BG_COLOR := Color(1.0, 1.0, 1.0, 0.06)
const OPTIONS_FRAME_BORDER_COLOR := Color(0.95, 0.78, 0.2, 0.55)
const OPTIONS_FRAME_MARGIN: float = 8.0
var _options_frame: PanelContainer = null
var _action_texts: Dictionary = {}
# Contenuto dei pulsanti delle azioni (icona su fondo scuro + testo, centrati insieme): chiave -> HBoxContainer, per
# misurarne la larghezza (il minimo di un Button non conta i figli).
var _action_contents: Dictionary = {}
const ACTION_CONTENT_PADDING: float = 24.0
# Fondo scuro dietro l'icona dell'azione (2026-10-05): le emoji a colori non prendono colore né contorno dal carattere,
# così l'icona resta leggibile sia sul giallo della selezionata sia sullo scuro delle altre.
const ACTION_ICON_BADGE_COLOR := Color(0.12, 0.10, 0.06, 0.9)
# Larghezza fissa del popup con le azioni affiancate (2026-10-05): calcolata alla prima misura dopo l'apertura sul
# contenuto più largo tra tutte le azioni, poi tenuta finché il popup resta aperto. 0 = non ancora calcolata.
var _fixed_width: int = 0
# Posizione del popup con le azioni affiancate già fissata dopo l'apertura (vedi _fit_to_options_content).
var _actions_position_locked: bool = false
# Margini sinistro + destro del MarginContainer della scena (10 + 10).
const DIALOG_SIDE_MARGINS: float = 20.0

# Chiave di riga -> Button della riga corrispondente (2026-09-18) — serve SOLO per aggiornare lo
# stato "pressed" (evidenziazione "selezionato", stile radio-button via toggle_mode) quando la
# selezione cambia, senza dover riattraversare resource_list_container.get_children() ogni volta.
var _resource_row_buttons: Dictionary = {}


func _ready() -> void:
	# confirm_button/cancel_button (2026-09-17) — testo GENERICO ("Conferma"/"Annulla", vedi
	# strings.csv) già riusabile as-is per qualunque scelta, nonostante il prefisso storico
	# "transport_" nella chiave di traduzione — invariate per non toccare il CSV per un rinominare
	# puramente cosmetico, nessuna differenza di testo visibile tra i due usi.
	quantity_label.text = tr("transport_dialog_quantity_label")
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": TaskRepeatRules.MAX_TRIPS})
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)


# GENERALIZZATA (2026-09-17, richiesta utente) — `dialog_title`/`message` arrivano GIÀ RISOLTI dal
# chiamante (tr()+format() già fatti lì): prima questa funzione risolveva da sé transport_dialog_
# title/transport_dialog_message, impossibile da riusare per un messaggio diverso (raccolta da
# terreno, nessun "edificio" a cui riferirsi). Stesso principio "pannello muto" già seguito per
# `available_quantities` sotto, esteso ora anche al testo.
#
# NESSUN parametro show_quantity (2026-09-18, rimosso — vedi doc di testa al file): la riga
# quantità è sempre presente ora, per entrambi gli usi.
# `repeat_default` (2026-09-20): stato iniziale della casella "Ripeti" (UserOptions.repeat_default).
func open_dialog(dialog_title: String, message: String, available_quantities: Dictionary, repeat_default: bool = false) -> void:
	_reset_rows(dialog_title, message, repeat_default)
	for resource_name: String in available_quantities.keys():
		_add_row(resource_name, resource_name, int(available_quantities[resource_name]))
	_popup_with_height(DIALOG_BASE_HEIGHT + float(available_quantities.size()) * RESOURCE_ROW_HEIGHT)


# Variante a gruppi per le workstation (2026-09-24, richiesta utente): intestazione "Prodotti", poi intestazione
# "Materiali consegnati". Le voci funzionano come in open_dialog (una risorsa per viaggio); un gruppo vuoto non
# compare. `product_quantities`/`delivered_quantities`: resource_name -> quantità, già risolti dal chiamante.
func open_grouped_dialog(
	dialog_title: String, message: String, product_quantities: Dictionary, delivered_quantities: Dictionary,
	repeat_default: bool = false
) -> void:
	_reset_rows(dialog_title, message, repeat_default)
	var height: float = DIALOG_BASE_HEIGHT
	if not product_quantities.is_empty():
		resource_list_container.add_child(_build_group_header(tr("transport_dialog_group_products")))
		for resource_name: String in product_quantities.keys():
			_add_row("products:" + resource_name, resource_name, int(product_quantities[resource_name]))
		height += GROUP_HEADER_HEIGHT + float(product_quantities.size()) * RESOURCE_ROW_HEIGHT
	if not delivered_quantities.is_empty():
		resource_list_container.add_child(_build_group_header(tr("transport_dialog_group_delivered")))
		for resource_name: String in delivered_quantities.keys():
			_add_row("delivered:" + resource_name, resource_name, int(delivered_quantities[resource_name]))
		height += GROUP_HEADER_HEIGHT + float(delivered_quantities.size()) * RESOURCE_ROW_HEIGHT
	_popup_with_height(height)


# Variante "scegli solo quale" (2026-09-25, richiesta utente — attrezzo da prendere per uno slot
# della cintura): stessa lista/aspetto di open_dialog, ma senza riga quantità né casella "Ripeti"
# (si prende sempre UNA unità). Il segnale resource_chosen resta lo stesso; la quantità emessa è
# quella della riga (ignorata dal chiamante). open_dialog/open_grouped_dialog le rimostrano.
const QUANTITY_AND_REPEAT_HEIGHT: float = 64.0


# `row_overrides` (2026-10-02, scelta del rito): chiave -> {"text": String, "icon": String} per righe che non sono
# risorse (testo del pulsante e icona emoji al posto di nome, quantità e icona della risorsa). Vuoto = come sempre.
# `row_options` (2026-10-05, popup del click destro su piante e rocce): chiave -> pannello di opzioni mostrato SOLO
# sotto la voce selezionata (cambiando voce si chiude quello vecchio e si apre il nuovo; una voce senza chiave qui non
# mostra niente). Due forme:
#   {"type": "list", "items": [{"key": String, "text": String, "enabled": bool, "icon": resource_name o
#     "icon_node": Control}], "selected": String} — elenco a
#     selezione singola, righe spente non selezionabili, scorre oltre OPTION_LIST_MAX_VISIBLE_ROWS righe;
#   {"type": "check", "text": String, "value": bool} — una spunta;
#   {"type": "pickup", "resources": Array, "default_choice": Dictionary, "repeat_default": bool, "repeat_max": int,
#     "single_row": bool} — il menu della raccolta di PickupChoiceDialog (stesso blocco, PickupChoiceMenu: Tutto,
#     categorie, risorse, mucchio/terreno) con la quantità per una risorsa e "Ripeti"; valore = {"kind", "category",
#     "resource_name", "quantity", "repeat", "source_kind"}, gli stessi di PickupChoiceDialog.choice_made.
# Il valore confermato si legge con get_option_value(chiave) dopo resource_chosen; option_hovered/option_selected
# seguono l'elenco mentre il popup è aperto. La larghezza del popup non cambia.
func open_choice_only_dialog(dialog_title: String, message: String, available_quantities: Dictionary, row_overrides: Dictionary = {}, row_options: Dictionary = {}, actions_layout: bool = false) -> void:
	_reset_rows(dialog_title, message, false)
	_row_overrides = row_overrides
	_row_options = row_options
	_set_quantity_and_repeat_visible(false)
	if actions_layout:
		_actions_layout = true
		# Riga delle azioni e riquadro del contenuto uno attaccato all'altro (nessuno spazio tra i due).
		var actions_block := VBoxContainer.new()
		actions_block.add_theme_constant_override("separation", 0)
		resource_list_container.add_child(actions_block)
		_actions_row = HBoxContainer.new()
		actions_block.add_child(_actions_row)
		_options_frame = PanelContainer.new()
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = OPTIONS_FRAME_BG_COLOR
		frame_style.border_color = OPTIONS_FRAME_BORDER_COLOR
		frame_style.set_border_width_all(1)
		frame_style.border_width_top = 0
		frame_style.corner_radius_bottom_left = 3
		frame_style.corner_radius_bottom_right = 3
		frame_style.set_content_margin_all(OPTIONS_FRAME_MARGIN)
		_options_frame.add_theme_stylebox_override("panel", frame_style)
		actions_block.add_child(_options_frame)
		_options_area = VBoxContainer.new()
		_options_frame.add_child(_options_area)
	for resource_name: String in available_quantities.keys():
		_add_row(resource_name, resource_name, int(available_quantities[resource_name]))
	_popup_with_height(DIALOG_BASE_HEIGHT - QUANTITY_AND_REPEAT_HEIGHT + float(available_quantities.size()) * RESOURCE_ROW_HEIGHT)


func _set_quantity_and_repeat_visible(show: bool) -> void:
	repeat_check_box.visible = show
	quantity_label.get_parent().visible = show


func _reset_rows(dialog_title: String, message: String, repeat_default: bool) -> void:
	_set_quantity_and_repeat_visible(true)
	title = dialog_title
	message_label.text = message
	repeat_check_box.button_pressed = repeat_default
	repeat_check_box.disabled = false
	quantity_spin_box.editable = true
	for child in resource_list_container.get_children():
		child.queue_free()
	_actions_layout = false
	_actions_row = null
	_options_area = null
	_options_frame = null
	_action_texts.clear()
	_action_contents.clear()
	_fixed_width = 0
	_actions_position_locked = false
	confirm_button.text = tr("transport_dialog_confirm")
	_resource_row_buttons.clear()
	_row_entries.clear()
	_row_overrides = {}
	_row_options = {}
	_option_panels.clear()
	_option_panel_heights.clear()
	_option_values.clear()
	_option_item_buttons.clear()
	_option_lists.clear()
	_pickup_panels.clear()
	_base_height = 0.0
	_selected_key = ""


# Aggiunge una riga e seleziona la prima aggiunta.
func _add_row(key: String, resource_name: String, quantity: int) -> void:
	_row_entries[key] = {"resource_name": resource_name, "quantity": quantity}
	if _actions_layout:
		# Azione affiancata alle altre, larga uguale (pareggiata in _fit_to_options_content).
		_actions_row.add_child(_build_action_button(key, resource_name))
	else:
		resource_list_container.add_child(_build_resource_row(key, resource_name, quantity))
	if _row_options.has(key):
		var panel := _build_option_panel(key, _row_options[key])
		panel.visible = _selected_key == "" or _selected_key == key
		if _actions_layout:
			_options_area.add_child(panel)
		else:
			resource_list_container.add_child(panel)
		_option_panels[key] = panel
	if _selected_key == "":
		_select_resource(key)


func _popup_with_height(height: float) -> void:
	exclusive = true
	_base_height = height
	if _row_options.is_empty() and not _actions_layout:
		popup_centered(Vector2i(280, int(height + _selected_option_height())))
		return
	# Con opzioni (2026-10-05): larghezza e altezza dal contenuto, come PickupChoiceDialog — righe sempre intere.
	popup_centered(Vector2i(OPTIONS_MIN_DIALOG_WIDTH, int(height + _selected_option_height())))
	_fit_to_options_content.call_deferred()


# Dopo il layout (2026-10-05, solo con opzioni): altezza di ogni elenco = righe intere (fino a
# OPTION_LIST_MAX_VISIBLE_ROWS), poi finestra grande quanto il contenuto — mai più stretta di OPTIONS_MIN_DIALOG_WIDTH,
# mai un testo troncato.
func _fit_to_options_content() -> void:
	await get_tree().process_frame
	if not visible or (_row_options.is_empty() and not _actions_layout):
		return
	# Azioni affiancate: tutte larghe quanto la più larga (testo sempre intero; se non ci stanno, il popup si allarga).
	if _actions_layout and _actions_row != null:
		var widest: float = 0.0
		for content_key in _action_contents.keys():
			widest = maxf(widest, (_action_contents[content_key] as Control).get_combined_minimum_size().x + ACTION_CONTENT_PADDING)
		for action_row in _actions_row.get_children():
			(action_row as Control).custom_minimum_size.x = widest
	for row_key in _option_lists.keys():
		var entry: Dictionary = _option_lists[row_key]
		var list: VBoxContainer = entry["list"]
		var rows: int = int(entry["rows"])
		if rows <= 0 or list.get_child_count() == 0:
			continue
		var row_height: float = (list.get_child(0) as Control).get_combined_minimum_size().y
		var separation: float = float(list.get_theme_constant("separation"))
		var visible_rows: int = mini(rows, OPTION_LIST_MAX_VISIBLE_ROWS)
		(entry["scroll"] as ScrollContainer).custom_minimum_size.y = float(visible_rows) * row_height + float(visible_rows - 1) * separation
	await get_tree().process_frame
	if not visible:
		return
	var content := get_node_or_null("MarginContainer") as Control
	if content == null:
		return
	var min_size := content.get_combined_minimum_size()
	var width: int = maxi(OPTIONS_MIN_DIALOG_WIDTH, ceili(min_size.x))
	# Azioni affiancate: larghezza fissata una volta sola, sul pannello più largo tra tutte le azioni (anche quelli chiusi);
	# poi cambia solo l'altezza.
	if _actions_layout:
		if _fixed_width == 0:
			# Larghezza di ogni pannello (aperto o no) più i margini del riquadro e quelli del popup.
			var horizontal_margins: float = OPTIONS_FRAME_MARGIN * 2.0 + DIALOG_SIDE_MARGINS
			for panel_key in _option_panels.keys():
				var panel_width: float = (_option_panels[panel_key] as Control).get_combined_minimum_size().x
				width = maxi(width, ceili(panel_width + horizontal_margins))
			_fixed_width = width
		width = maxi(_fixed_width, width)
		_fixed_width = width
	var fitted := Vector2i(width, ceili(min_size.y))
	if fitted == size:
		_actions_position_locked = _actions_layout
		return
	size = fitted
	# Azioni affiancate (2026-10-05): centrato solo alla prima misura dopo l'apertura, poi bordo superiore e sinistro
	# fermi — cambiando azione il popup cresce o si accorcia verso il basso, la riga delle azioni non si muove sotto il
	# mouse; sale solo di quanto basta per non uscire dal fondo. Gli altri usi si ricentrano come sempre.
	if not _actions_layout or not _actions_position_locked:
		move_to_center()
		_actions_position_locked = _actions_layout
		return
	var bottom_limit: int = _visible_bottom_limit()
	if position.y + size.y > bottom_limit:
		position.y = maxi(bottom_limit - size.y, 0)


# Fondo dell'area in cui sta il popup, nelle stesse coordinate di `position`: la finestra di gioco con le sottofinestre
# incorporate (default del progetto), altrimenti lo schermo utilizzabile.
func _visible_bottom_limit() -> int:
	var root := get_tree().root
	if root.gui_embed_subwindows:
		return int(root.get_visible_rect().size.y)
	var usable := DisplayServer.screen_get_usable_rect(current_screen)
	return usable.position.y + usable.size.y


# Altezza del pannello di opzioni della voce selezionata (0 senza opzioni).
func _selected_option_height() -> float:
	return float(_option_panel_heights.get(_selected_key, 0.0))


# Ridimensiona il popup aperto al pannello della voce selezionata.
func _fit_height() -> void:
	if not visible or _base_height <= 0.0:
		return
	if not _row_options.is_empty() or _actions_layout:
		_fit_to_options_content()
		return
	size = Vector2i(size.x, int(_base_height + _selected_option_height()))


# Valore confermato delle opzioni della voce `row_key` (item_key per un elenco, bool per una spunta); null se la voce
# non ha opzioni.
func get_option_value(row_key: String) -> Variant:
	if _pickup_panels.has(row_key):
		return _get_pickup_value(row_key)
	return _option_values.get(row_key, null)


# Scelta del pannello "pickup" della voce `row_key`, nella forma di PickupChoiceDialog.choice_made: quantità solo per
# una risorsa (altrimenti -1), "Ripeti" dalla spunta. {} se nessuna voce del menu è selezionata.
func _get_pickup_value(row_key: String) -> Dictionary:
	var panel: Dictionary = _pickup_panels[row_key]
	var choice: Dictionary = (panel["menu"] as PickupChoiceMenu).get_selected()
	if choice.is_empty():
		return {}
	var kind: int = int(choice["kind"])
	return {
		"kind": kind,
		"category": int(choice["category"]),
		"resource_name": String(choice["resource_name"]),
		"quantity": int((panel["quantity"] as SpinBox).value) if kind == PickUpAction.CriterionKind.NAME else -1,
		"repeat": (panel["repeat"] as CheckBox).button_pressed,
		"source_kind": int(choice["source_kind"]),
	}


# Pannello "pickup": stesso contenuto e stesso ordine di PickupChoiceDialog (menu, "Ripeti", quantità), con il menu
# costruito da PickupChoiceMenu. La riga quantità compare solo con una risorsa scelta e ridimensiona il popup.
func _build_pickup_option(row_key: String, options: Dictionary, margin: MarginContainer) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	var repeat := CheckBox.new()
	repeat.text = tr("task_repeat_checkbox").format({"count": int(options.get("repeat_max", TaskRepeatRules.MAX_REPEATS)) + 1})
	repeat.button_pressed = bool(options.get("repeat_default", false))
	box.add_child(repeat)
	var quantity_row := HBoxContainer.new()
	var quantity_caption := Label.new()
	quantity_caption.text = tr("transport_dialog_quantity_label")
	quantity_row.add_child(quantity_caption)
	var quantity := SpinBox.new()
	quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quantity_row.add_child(quantity)
	box.add_child(quantity_row)
	margin.add_child(box)
	var menu := PickupChoiceMenu.new()
	_pickup_panels[row_key] = {"menu": menu, "quantity_row": quantity_row, "quantity": quantity, "repeat": repeat}
	menu.selection_changed.connect(func(is_resource: bool, max_quantity: int) -> void:
		quantity_row.visible = is_resource
		if is_resource:
			quantity.max_value = max_quantity
			quantity.min_value = 1 if max_quantity > 0 else 0
			quantity.value = max_quantity
		_fit_height()
	)
	var row_count := menu.build(list, options.get("resources", []), options.get("default_choice", {}), bool(options.get("single_row", false)))
	# Stima per la prima apertura (poi _fit_to_options_content misura il contenuto vero).
	_option_panel_heights[row_key] = float(row_count + 2) * OPTION_LIST_ROW_HEIGHT


func _build_option_panel(row_key: String, options: Dictionary) -> Control:
	var margin := MarginContainer.new()
	# Rientro sotto la voce solo con le voci in verticale; con le azioni affiancate il contenuto va a filo.
	margin.add_theme_constant_override("margin_left", 0 if _actions_layout else int(OPTION_LIST_INDENT))
	margin.add_theme_constant_override("margin_top", OPTION_PANEL_TOP_GAP)
	margin.add_theme_constant_override("margin_bottom", OPTION_PANEL_BOTTOM_GAP)
	match String(options.get("type", "")):
		"pickup":
			_build_pickup_option(row_key, options, margin)
		"check":
			var check := CheckBox.new()
			check.text = String(options.get("text", ""))
			check.button_pressed = bool(options.get("value", false))
			_option_values[row_key] = check.button_pressed
			check.toggled.connect(func(pressed: bool) -> void: _option_values[row_key] = pressed)
			margin.add_child(check)
			_option_panel_heights[row_key] = OPTION_CHECK_HEIGHT
		"list":
			var items: Array = options.get("items", [])
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var visible_rows: int = mini(items.size(), OPTION_LIST_MAX_VISIBLE_ROWS)
			scroll.custom_minimum_size = Vector2(0.0, float(visible_rows) * OPTION_LIST_ROW_HEIGHT)
			var list := VBoxContainer.new()
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Spazio tra le righe e la barra di scorrimento, solo quando l'elenco scorre.
			var list_margin := MarginContainer.new()
			list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list_margin.add_theme_constant_override("margin_right", OPTION_SCROLLBAR_GAP if items.size() > OPTION_LIST_MAX_VISIBLE_ROWS else 0)
			list_margin.add_child(list)
			scroll.add_child(list_margin)
			margin.add_child(scroll)
			_option_lists[row_key] = {"scroll": scroll, "list": list, "rows": items.size()}
			var buttons: Dictionary = {}
			for item in items:
				var item_key := String(item.get("key", ""))
				# Riga come una risorsa di PickupChoiceDialog: icona + pulsante col testo intero. Icona: "icon_node" (un
				# Control già pronto, es. PlantIcon) se c'è, altrimenti quella della risorsa "icon".
				var item_row := HBoxContainer.new()
				var item_icon: Variant = item.get("icon_node", null)
				if item_icon is Control:
					item_row.add_child(_wrap_icon_node(item_icon as Control))
				else:
					item_row.add_child(_build_icon_box(String(item.get("icon", "")), ""))
				var button := Button.new()
				button.text = String(item.get("text", ""))
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.toggle_mode = true
				button.disabled = not bool(item.get("enabled", true))
				_apply_selected_style(button)
				button.pressed.connect(_select_option_item.bind(row_key, item_key))
				button.mouse_entered.connect(func() -> void: option_hovered.emit(row_key, item_key))
				button.mouse_exited.connect(func() -> void: option_hovered.emit(row_key, ""))
				item_row.add_child(button)
				list.add_child(item_row)
				buttons[item_key] = button
			_option_item_buttons[row_key] = buttons
			_option_values[row_key] = ""
			var selected := String(options.get("selected", ""))
			if buttons.has(selected) and not buttons[selected].disabled:
				_option_values[row_key] = selected
			for item_key in buttons.keys():
				buttons[item_key].button_pressed = item_key == _option_values[row_key]
			_option_panel_heights[row_key] = float(visible_rows) * OPTION_LIST_ROW_HEIGHT + 4.0
	return margin


# Riga `item_key` dell'elenco della voce `row_key` scelta (radio, come le voci).
func _select_option_item(row_key: String, item_key: String) -> void:
	_option_values[row_key] = item_key
	var buttons: Dictionary = _option_item_buttons.get(row_key, {})
	for other_key in buttons.keys():
		buttons[other_key].button_pressed = other_key == item_key
	option_selected.emit(row_key, item_key)


# Intestazione di gruppo (2026-09-24): testo semplice colorato, non selezionabile.
func _build_group_header(text: String) -> Control:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1.0))
	return header


# Una riga: icona (disegnata/emoji/iniziale, STESSO schema a 3 livelli già in uso da
# BuildingInfoPanel._build_missing_material_chip — coerenza visiva con ogni altro punto del
# progetto che mostra un'icona risorsa) + Button che riempie il resto della riga, testo "Nome
# (quantità)". toggle_mode=true SOLO per lo stile "pressed" quando selezionato (vedi _select_
# resource sotto) — non un vero comportamento toggle-indipendente, ogni pressione lo riporta
# comunque a true tramite _select_resource, mai lasciato libero di spegnersi da solo.
func _build_resource_row(key: String, resource_name: String, quantity: int) -> Control:
	var row := HBoxContainer.new()

	var override: Dictionary = _row_overrides.get(key, {})
	row.add_child(_build_icon_box(resource_name, String(override.get("icon", "")) if not override.is_empty() else "", not override.is_empty()))

	var resource_button := Button.new()
	if not override.is_empty():
		resource_button.text = String(override.get("text", resource_name))
	else:
		resource_button.text = "%s (%d)" % [IconRegistry.get_resource_display_name(resource_name), quantity]
	resource_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_button.toggle_mode = true
	_apply_selected_style(resource_button)
	resource_button.pressed.connect(_select_resource.bind(key))
	row.add_child(resource_button)
	_resource_row_buttons[key] = resource_button

	return row


# Riquadro icona di una riga (estratto il 2026-10-05, condiviso con le righe dell'elenco delle opzioni): icona della
# risorsa (disegnata o immagine), altrimenti emoji, altrimenti iniziale. `override_icon`/`use_override`: emoji della
# riga al posto dell'icona della risorsa (row_overrides). resource_name "" senza override = riquadro vuoto.
func _build_icon_box(resource_name: String, override_icon: String, use_override: bool = false) -> Control:
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(RESOURCE_ROW_ICON_SIZE, RESOURCE_ROW_ICON_SIZE)
	if resource_name == "" and not use_override:
		return icon_box
	var icon_node: Control = null if use_override else IconRegistry.get_resource_icon_node(resource_name)
	if icon_node != null:
		icon_box.add_child(icon_node)
		icon_node.anchor_left = 0.0
		icon_node.anchor_top = 0.0
		icon_node.anchor_right = 1.0
		icon_node.anchor_bottom = 1.0
		icon_node.offset_left = 0.0
		icon_node.offset_top = 0.0
		icon_node.offset_right = 0.0
		icon_node.offset_bottom = 0.0
	else:
		var fallback_label := Label.new()
		var icon_text: String = override_icon if use_override else IconRegistry.get_resource_icon(resource_name)
		fallback_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.anchor_right = 1.0
		fallback_label.anchor_bottom = 1.0
		icon_box.add_child(fallback_label)
	return icon_box


# Pulsante di un'azione affiancata: icona (emoji di row_overrides) e testo centrati insieme, grassetto, più alto delle
# righe sotto; selezionata = giallo del pulsante attivo della velocità con testo scuro, non selezionata = tema di sempre.
func _build_action_button(key: String, resource_name: String) -> Button:
	var override: Dictionary = _row_overrides.get(key, {})
	var text := String(override.get("text", IconRegistry.get_resource_display_name(resource_name)))
	var icon_text := String(override.get("icon", ""))
	_action_texts[key] = text
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, ACTION_BUTTON_HEIGHT)
	button.toggle_mode = true
	# Contenuto disegnato dai figli (il Button non ha testo proprio): icona su un fondo scuro e testo in grassetto,
	# centrati insieme; il testo diventa scuro quando l'azione è selezionata, come font_pressed_color.
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if icon_text != "":
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = ACTION_ICON_BADGE_COLOR
		badge_style.set_corner_radius_all(4)
		badge_style.set_content_margin_all(2.0)
		badge.add_theme_stylebox_override("panel", badge_style)
		var icon_label := Label.new()
		icon_label.text = icon_text
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(icon_label)
		content.add_child(badge)
	var text_label := Label.new()
	text_label.text = text
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bold := FontVariation.new()
	bold.base_font = button.get_theme_default_font()
	bold.variation_embolden = ACTION_FONT_EMBOLDEN
	text_label.add_theme_font_override("font", bold)
	content.add_child(text_label)
	button.add_child(content)
	_action_contents[key] = content
	button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			text_label.add_theme_color_override("font_color", ACTION_SELECTED_FONT_COLOR)
		else:
			text_label.remove_theme_color_override("font_color")
	)
	var style := StyleBoxFlat.new()
	style.bg_color = ACTION_SELECTED_BG_COLOR
	style.border_color = ACTION_SELECTED_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", style)
	button.add_theme_color_override("font_pressed_color", ACTION_SELECTED_FONT_COLOR)
	button.add_theme_color_override("font_hover_pressed_color", ACTION_SELECTED_FONT_COLOR)
	button.pressed.connect(_select_resource.bind(key))
	_resource_row_buttons[key] = button
	return button


# Riquadro icona (stessa misura di _build_icon_box) attorno a un Control già pronto, ancorato a tutto il riquadro.
func _wrap_icon_node(icon_node: Control) -> Control:
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(RESOURCE_ROW_ICON_SIZE, RESOURCE_ROW_ICON_SIZE)
	icon_box.add_child(icon_node)
	icon_node.anchor_left = 0.0
	icon_node.anchor_top = 0.0
	icon_node.anchor_right = 1.0
	icon_node.anchor_bottom = 1.0
	icon_node.offset_left = 0.0
	icon_node.offset_top = 0.0
	icon_node.offset_right = 0.0
	icon_node.offset_bottom = 0.0
	return icon_box


# Stile "selezionato" marcato (2026-09-19, richiesta utente — "faccio fatica a distinguerli": lo
# stile "pressed" del tema di default è troppo tenue rispetto a "normal"): sfondo blu pieno, bordo
# chiaro e testo bianco, solo per lo stato pressed/hover_pressed — le righe NON selezionate
# restano col tema di default, così il contrasto è tra "una" e "le altre". Override locali sul
# singolo Button, nessun tema di progetto toccato.
const SELECTED_BG_COLOR := Color(0.20, 0.42, 0.78, 1.0)
const SELECTED_BORDER_COLOR := Color(0.75, 0.87, 1.0, 1.0)
const SELECTED_FONT_COLOR := Color(1.0, 1.0, 1.0, 1.0)


func _apply_selected_style(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = SELECTED_BG_COLOR
	style.border_color = SELECTED_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", style)
	button.add_theme_color_override("font_pressed_color", SELECTED_FONT_COLOR)
	button.add_theme_color_override("font_hover_pressed_color", SELECTED_FONT_COLOR)


# Marca la riga `key` come selezionata: aggiorna lo stile "pressed" di ogni riga (radio-button-
# like, mai più di una selezionata) e il tetto/valore dell'UNICA riga quantità condivisa.
func _select_resource(key: String) -> void:
	_selected_key = key
	for other_key in _resource_row_buttons.keys():
		_resource_row_buttons[other_key].button_pressed = other_key == key
	# Azioni affiancate: il pulsante di conferma prende il nome dell'azione scelta; il riquadro del contenuto compare solo
	# se l'azione ne ha uno.
	if _actions_layout:
		if _action_texts.has(key):
			confirm_button.text = String(_action_texts[key])
		if _options_frame != null:
			_options_frame.visible = _option_panels.has(key)
	# Pannelli di opzioni (2026-10-05): aperto solo quello della voce selezionata.
	for panel_key in _option_panels.keys():
		_option_panels[panel_key].visible = panel_key == key
	_fit_height()
	# Ogni cambio di voce: riga scelta dell'elenco della voce, "" se la voce non ha un elenco.
	option_selected.emit(key, String(_option_values.get(key, "")) if _option_item_buttons.has(key) else "")
	var entry: Dictionary = _row_entries.get(key, {})
	var max_quantity: int = int(entry.get("quantity", 0))
	quantity_spin_box.max_value = max_quantity
	quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
	quantity_spin_box.value = max_quantity


# _selected_key == "" (nessun candidato, mai il caso reale) -> no-op difensivo, mai un segnale con un
# resource_name vuoto.
func _on_confirm_pressed() -> void:
	if _selected_key == "":
		return
	var resource_name: String = String(_row_entries[_selected_key]["resource_name"])
	var quantity: int = int(quantity_spin_box.value)
	hide()
	resource_chosen.emit(resource_name, quantity, repeat_check_box.button_pressed and not repeat_check_box.disabled)


# Nessun segnale emesso all'annullamento (stesso principio di DemolishConfirmationDialog._on_
# canceled: "nessuna sorgente viene impostata, come se non avesse cliccato nulla" — richiesta
# esplicita utente) — il chiamante non ha nulla da disfare perché non ha ancora impostato niente.
func _on_cancel_pressed() -> void:
	hide()
