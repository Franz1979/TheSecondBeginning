class_name SystemMenuDialog
extends Window

signal action_selected(action_id: StringName)

@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

func _ready() -> void:
	title = tr("menu")
	close_button.text = tr("close")
	close_button.pressed.connect(hide)
	close_requested.connect(hide)


func open_menu() -> void:
	exclusive = true
	popup_centered(Vector2i(220, 160))


func add_action(label_text: String, action_id: StringName) -> void:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(func() -> void:
		hide()
		action_selected.emit(action_id)
	)
	actions_container.add_child(button)
