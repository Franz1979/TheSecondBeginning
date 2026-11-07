class_name ResourceChoiceRows
extends VBoxContainer

# Scelta tra risorse a righe con l'icona, stesso aspetto della raccolta (PickupChoiceMenu), una sempre selezionata
# (2026-11-04, Pietra/Argilla del comando Estrai e dello strato del task assignment). Si costruisce con set_choices.
# Voci: {"id": String, "text": String, "resource_name": String}.

signal selection_changed(id: String)

var _buttons: Dictionary = {}  # id -> Button
var _selected: String = ""


# `selected_id` non tra le voci: la prima. Meno di due voci: nessuna riga.
func set_choices(choices: Array[Dictionary], selected_id: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_selected = ""
	if choices.size() < 2:
		return
	for choice in choices:
		var id := String(choice["id"])
		var row := HBoxContainer.new()
		row.add_child(PickupChoiceMenu.build_resource_icon_box(String(choice["resource_name"])))
		var button := PickupChoiceMenu.build_choice_button(String(choice["text"]))
		button.pressed.connect(_select.bind(id, true))
		row.add_child(button)
		add_child(row)
		_buttons[id] = button
	_select(selected_id if _buttons.has(selected_id) else String(choices[0]["id"]), false)


func has_choices() -> bool:
	return not _buttons.is_empty()


func get_selected() -> String:
	return _selected


func _select(id: String, notify: bool) -> void:
	var changed := id != _selected
	_selected = id
	# toggle_mode solo per lo stile del selezionato: ripremere la voce scelta la lascia scelta.
	for button_id: String in _buttons:
		(_buttons[button_id] as Button).set_pressed_no_signal(button_id == id)
	if notify and changed:
		selection_changed.emit(id)
