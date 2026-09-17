class_name OptionChoiceDialog
extends Window

# Popup GENERICO "scegli una risorsa (ed eventualmente una quantità) tra più candidate" —
# nato (2026-09-12, richiesta utente) come TransportSourceDialog, specifico per la Transport Task
# ("scegli risorsa e quantità da prelevare" da un edificio), poi GENERALIZZATO (2026-09-17,
# richiesta utente: "usiamo OptionChoiceDialog per tutti i casi... se devo sistemarla, ne sistemo
# una") per essere riusato ANCHE dal comando di raccolta manuale (destro-click su una cella con più
# risorse raccoglibili — stick/plant_fiber sullo stesso lotto, vedi GameScene._try_assign_pickup_
# command_on_right_click), che non ha un concetto di "quantità" da scegliere (PickUpAction risolve
# da sé quanto raccogliere) — da qui `show_quantity` sotto. Struttura invariata (Window custom,
# MarginContainer>VBoxContainer, @onready sui figli, popup_centered(size), exclusive=true,
# segnale-per-scelta via lambda in _ready), stesso pattern di SaveConfirmationDialog.
#
# "Pannello muto" (stesso principio già seguito da BuildBar/GameInfoPanel/DemolishConfirmation
# Dialog): open_dialog riceve titolo/messaggio/Dictionary resource_name->quantità GIÀ RISOLTI dal
# chiamante — non legge mai Building/BuildingStorageService/TerrainScatteredResourceService da sé.
# Un solo scene/script per entrambi gli usi (richiesta esplicita utente, anche per motivi estetici:
# un fix visivo qui vale per ogni istanza) — GameScene ne instanzia DUE nodi separati
# (TransportSourceDialog/PickupChoiceDialog), mai un'istanza condivisa tra i due flussi: nessuno
# stato "a quale scopo sto servendo ora" da tracciare dentro questa classe, resta ignara di chi la
# usa, stesso principio "pannello muto" sopra.
signal resource_chosen(resource_name: String, quantity: int)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var resource_option: OptionButton = $MarginContainer/VBoxContainer/ResourceOption
@onready var quantity_row: HBoxContainer = $MarginContainer/VBoxContainer/QuantityRow
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $MarginContainer/VBoxContainer/QuantityRow/QuantitySpinBox
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton

# resource_name -> quantità disponibile, salvato da open_dialog (2026-09-12) — usato SOLO per
# chiarire il tetto massimo dello SpinBox quando la selezione cambia, mai per una nuova query a
# Building/al mondo: stesso principio "mute panel" del commento sopra.
var _available_quantities: Dictionary = {}


func _ready() -> void:
	# confirm_button/cancel_button (2026-09-17) — testo GENERICO ("Conferma"/"Annulla", vedi
	# strings.csv) già riusabile as-is per qualunque scelta, nonostante il prefisso storico
	# "transport_" nella chiave di traduzione — invariate per non toccare il CSV per un rinominare
	# puramente cosmetico, nessuna differenza di testo visibile tra i due usi.
	quantity_label.text = tr("transport_dialog_quantity_label")
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	resource_option.item_selected.connect(_on_resource_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)


# GENERALIZZATA (2026-09-17, richiesta utente) — `dialog_title`/`message` arrivano GIÀ RISOLTI dal
# chiamante (tr()+format() già fatti lì, vedi GameScene._debug_try_assign_transport_command_on_
# right_click/_try_assign_pickup_command_on_right_click): prima questa funzione risolveva da sé
# transport_dialog_title/transport_dialog_message, impossibile da riusare per un messaggio diverso
# (raccolta da terreno, nessun "edificio" a cui riferirsi). Stesso principio "pannello muto" già
# seguito per `available_quantities` sotto, esteso ora anche al testo.
#
# `show_quantity` (2026-09-17, richiesta utente) — false per la raccolta da terreno (nessuna
# quantità da scegliere, vedi doc di testa al file): nasconde l'intera QuantityRow, il resto del
# dialog (lista risorse, Conferma/Annulla) resta identico. `quantity_spin_box`/`_available_
# quantities` restano comunque valorizzati anche a show_quantity=false (via _on_resource_selected
# sotto, invariata) — innocuo, semplicemente mai mostrato; resource_chosen emette comunque una
# quantity (ignorata dal chiamante lato raccolta, vedi _on_pickup_choice_resource_chosen), nessun
# secondo segnale necessario per non duplicare la logica di selezione dell'OptionButton.
func open_dialog(dialog_title: String, message: String, available_quantities: Dictionary, show_quantity: bool = true) -> void:
	_available_quantities = available_quantities
	title = dialog_title
	message_label.text = message

	resource_option.clear()
	for resource_name: String in available_quantities.keys():
		var quantity: int = int(available_quantities[resource_name])
		resource_option.add_item("%s (%d)" % [IconRegistry.get_resource_display_name(resource_name), quantity])
		resource_option.set_item_metadata(resource_option.item_count - 1, resource_name)

	resource_option.selected = 0
	_on_resource_selected(0)

	quantity_row.visible = show_quantity
	exclusive = true
	popup_centered(Vector2i(280, 200 if show_quantity else 160))


func _on_resource_selected(index: int) -> void:
	var resource_name: String = resource_option.get_item_metadata(index)
	var max_quantity: int = int(_available_quantities.get(resource_name, 0))
	quantity_spin_box.max_value = max_quantity
	quantity_spin_box.min_value = 1 if max_quantity > 0 else 0
	quantity_spin_box.value = max_quantity


func _on_confirm_pressed() -> void:
	var resource_name: String = resource_option.get_item_metadata(resource_option.selected)
	var quantity: int = int(quantity_spin_box.value)
	hide()
	resource_chosen.emit(resource_name, quantity)


# Nessun segnale emesso all'annullamento (stesso principio di DemolishConfirmationDialog._on_
# canceled: "nessuna sorgente viene impostata, come se non avesse cliccato nulla" — richiesta
# esplicita utente) — il chiamante non ha nulla da disfare perché non ha ancora impostato niente.
func _on_cancel_pressed() -> void:
	hide()
