class_name ExitConfirmationDialog
extends ConfirmationDialog

func _ready() -> void:
	title = tr("exit_confirmation_title")
	dialog_text = tr("exit_confirmation_text")
	ok_button_text = tr("exit_confirmation_confirm")
	cancel_button_text = tr("exit_confirmation_cancel")
	confirmed.connect(_on_confirmed)


func open_dialog() -> void:
	exclusive = true
	popup_centered()


func _on_confirmed() -> void:
	get_tree().quit()
