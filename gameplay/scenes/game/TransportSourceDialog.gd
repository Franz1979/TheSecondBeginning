class_name TransportSourceDialog
extends Window

# Popup "scegli risorsa e quantità da prelevare" per la Transport Task (2026-09-12, richiesta
# utente — sostituisce il trigger di debug a valori fissi _DEBUG_TRANSPORT_RESOURCE_NAME/QUANTITY).
# Struttura STESSA di SaveConfirmationDialog (Window custom, MarginContainer>VBoxContainer,
# @onready sui figli, popup_centered(size), exclusive=true, segnale-per-scelta via lambda in
# _ready) — scelta come TEMPLATE invece di DemolishConfirmationDialog perché quest'ultimo estende
# il ConfirmationDialog nativo (solo testo + OK/Annulla), che non ha spazio per una lista +
# spinbox; qui serve un OptionButton (risorsa) + SpinBox (quantità), stesso pattern già in uso in
# WorldScene.gd per lo spawner debug di animali.
#
# "Pannello muto" (stesso principio già seguito da BuildBar/GameInfoPanel/DemolishConfirmation
# Dialog): open_dialog riceve un Dictionary GIÀ RISOLTO resource_name->quantity dal chiamante
# (GameScene, da Building.stored_resources) — non legge mai Building/BuildingStorageService da sé.
signal resource_chosen(resource_name: String, quantity: int)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var resource_option: OptionButton = $MarginContainer/VBoxContainer/ResourceOption
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityRow/QuantityLabel
@onready var quantity_spin_box: SpinBox = $MarginContainer/VBoxContainer/QuantityRow/QuantitySpinBox
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/ButtonsRow/CancelButton

# resource_name -> quantità disponibile, salvato da open_dialog (2026-09-12) — usato SOLO per
# chiarire il tetto massimo dello SpinBox quando la selezione cambia, mai per una nuova query a
# Building: stesso principio "mute panel" del commento sopra.
var _available_quantities: Dictionary = {}


func _ready() -> void:
	title = tr("transport_dialog_title")
	quantity_label.text = tr("transport_dialog_quantity_label")
	confirm_button.text = tr("transport_dialog_confirm")
	cancel_button.text = tr("transport_dialog_cancel")
	resource_option.item_selected.connect(_on_resource_selected)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_requested.connect(_on_cancel_pressed)


# building_display_name già tradotto/risolto dal chiamante (stesso principio di
# DemolishConfirmationDialog.open_dialog) — available_quantities: Dictionary[String, int], mai
# vuoto quando questa funzione viene chiamata (il chiamante gestisce già il caso "nessuna
# risorsa" senza aprire il dialog, vedi GameScene._debug_try_assign_transport_command_on_right_
# click).
func open_dialog(building_display_name: String, available_quantities: Dictionary) -> void:
	_available_quantities = available_quantities
	title = tr("transport_dialog_title")
	message_label.text = tr("transport_dialog_message").format({"building": building_display_name})

	resource_option.clear()
	for resource_name: String in available_quantities.keys():
		var quantity: int = int(available_quantities[resource_name])
		resource_option.add_item("%s (%d)" % [IconRegistry.get_resource_display_name(resource_name), quantity])
		resource_option.set_item_metadata(resource_option.item_count - 1, resource_name)

	resource_option.selected = 0
	_on_resource_selected(0)

	exclusive = true
	popup_centered(Vector2i(280, 200))


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
