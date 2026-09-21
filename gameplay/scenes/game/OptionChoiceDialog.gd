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

# resource_name -> quantità disponibile, salvato da open_dialog (2026-09-12) — usato SOLO per
# chiarire il tetto massimo dello SpinBox quando la selezione cambia, mai per una nuova query a
# Building/al mondo: stesso principio "mute panel" del commento sopra.
var _available_quantities: Dictionary = {}

# Risorsa attualmente selezionata (2026-09-18) — "" solo se open_dialog non ha ancora ricevuto
# candidati (mai il caso reale: il chiamante apre questo dialog solo con 2+ candidati).
var _selected_resource_name: String = ""

# resource_name -> Button della riga corrispondente (2026-09-18) — serve SOLO per aggiornare lo
# stato "pressed" (evidenziazione "selezionato", stile radio-button via toggle_mode) quando la
# selezione cambia, senza dover riattraversare resource_list_container.get_children() ogni volta.
var _resource_row_buttons: Dictionary = {}


func _ready() -> void:
	# confirm_button/cancel_button (2026-09-17) — testo GENERICO ("Conferma"/"Annulla", vedi
	# strings.csv) già riusabile as-is per qualunque scelta, nonostante il prefisso storico
	# "transport_" nella chiave di traduzione — invariate per non toccare il CSV per un rinominare
	# puramente cosmetico, nessuna differenza di testo visibile tra i due usi.
	quantity_label.text = tr("transport_dialog_quantity_label")
	repeat_check_box.text = tr("task_repeat_checkbox").format({"count": TaskRepeatRules.MAX_REPEATS})
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
	_available_quantities = available_quantities
	title = dialog_title
	message_label.text = message
	repeat_check_box.button_pressed = repeat_default

	for child in resource_list_container.get_children():
		child.queue_free()
	_resource_row_buttons.clear()
	_selected_resource_name = ""

	for resource_name: String in available_quantities.keys():
		var quantity: int = int(available_quantities[resource_name])
		resource_list_container.add_child(_build_resource_row(resource_name, quantity))
		if _selected_resource_name == "":
			_select_resource(resource_name)

	exclusive = true
	var height: float = DIALOG_BASE_HEIGHT + float(available_quantities.size()) * RESOURCE_ROW_HEIGHT
	popup_centered(Vector2i(280, int(height)))


# Una riga: icona (disegnata/emoji/iniziale, STESSO schema a 3 livelli già in uso da
# BuildingInfoPanel._build_missing_material_chip — coerenza visiva con ogni altro punto del
# progetto che mostra un'icona risorsa) + Button che riempie il resto della riga, testo "Nome
# (quantità)". toggle_mode=true SOLO per lo stile "pressed" quando selezionato (vedi _select_
# resource sotto) — non un vero comportamento toggle-indipendente, ogni pressione lo riporta
# comunque a true tramite _select_resource, mai lasciato libero di spegnersi da solo.
func _build_resource_row(resource_name: String, quantity: int) -> Control:
	var row := HBoxContainer.new()

	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(RESOURCE_ROW_ICON_SIZE, RESOURCE_ROW_ICON_SIZE)
	var icon_node: Control = IconRegistry.get_resource_icon_node(resource_name)
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
		var icon_text: String = IconRegistry.get_resource_icon(resource_name)
		fallback_label.text = icon_text if icon_text != "" else resource_name.substr(0, 1).to_upper()
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.anchor_right = 1.0
		fallback_label.anchor_bottom = 1.0
		icon_box.add_child(fallback_label)
	row.add_child(icon_box)

	var resource_button := Button.new()
	resource_button.text = "%s (%d)" % [IconRegistry.get_resource_display_name(resource_name), quantity]
	resource_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_button.toggle_mode = true
	_apply_selected_style(resource_button)
	resource_button.pressed.connect(_select_resource.bind(resource_name))
	row.add_child(resource_button)
	_resource_row_buttons[resource_name] = resource_button

	return row


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


# Marca `resource_name` come selezionato: aggiorna lo stile "pressed" di ogni riga (radio-button-
# like, mai più di una selezionata) e il tetto/valore dell'UNICA riga quantità condivisa.
func _select_resource(resource_name: String) -> void:
	_selected_resource_name = resource_name
	for other_resource_name in _resource_row_buttons.keys():
		_resource_row_buttons[other_resource_name].button_pressed = other_resource_name == resource_name
	var max_quantity: int = int(_available_quantities.get(resource_name, 0))
	quantity_spin_box.max_value = max_quantity
	quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
	quantity_spin_box.value = max_quantity


# _selected_resource_name == "" (nessun candidato, mai il caso reale) -> no-op difensivo, mai un
# segnale con un resource_name vuoto.
func _on_confirm_pressed() -> void:
	if _selected_resource_name == "":
		return
	var resource_name := _selected_resource_name
	var quantity: int = int(quantity_spin_box.value)
	hide()
	resource_chosen.emit(resource_name, quantity, repeat_check_box.button_pressed)


# Nessun segnale emesso all'annullamento (stesso principio di DemolishConfirmationDialog._on_
# canceled: "nessuna sorgente viene impostata, come se non avesse cliccato nulla" — richiesta
# esplicita utente) — il chiamante non ha nulla da disfare perché non ha ancora impostato niente.
func _on_cancel_pressed() -> void:
	hide()
