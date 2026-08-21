class_name SaveConfirmationDialog
extends Window

signal option_selected(option: StringName)

@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var save_and_leave_button: Button = $MarginContainer/VBoxContainer/SaveAndLeaveButton
@onready var leave_without_saving_button: Button = $MarginContainer/VBoxContainer/LeaveWithoutSavingButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/CancelButton

func _ready() -> void:
	title = tr("save_confirmation_title")
	message_label.text = tr("save_confirmation_text")
	save_and_leave_button.text = tr("save_and_leave")
	leave_without_saving_button.text = tr("leave_without_saving")
	cancel_button.text = tr("cancel")
	save_and_leave_button.pressed.connect(func() -> void:
		hide()
		option_selected.emit(&"save_and_leave")
	)
	leave_without_saving_button.pressed.connect(func() -> void:
		hide()
		option_selected.emit(&"leave_without_saving")
	)
	cancel_button.pressed.connect(_cancel)
	close_requested.connect(_cancel)


func open_dialog() -> void:
	exclusive = true
	popup_centered(Vector2i(260, 150))


func _cancel() -> void:
	hide()
	option_selected.emit(&"cancel")
