class_name HelpDialog
extends Window

# Popup con la lista delle scorciatoie da tastiera di GameScene — stesso pattern di
# SystemMenuDialog/SaveConfirmationDialog (Window, popup_centered, close_requested -> hide),
# trattato come dialogo bloccante da GameScene (visibility_changed collegato a
# _on_blocking_dialog_visibility_changed, stesso schema degli altri due): mette in pausa il
# clock mentre è aperto, non il movimento dell'individuo (indipendente dal clock per design).

@onready var content_label: RichTextLabel = $MarginContainer/VBoxContainer/ContentLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton


func _ready() -> void:
	title = tr("help_dialog_title")
	close_button.text = tr("close")
	close_button.pressed.connect(hide)
	close_requested.connect(hide)

	content_label.bbcode_enabled = true
	content_label.text = _build_shortcuts_text()


func open_dialog() -> void:
	exclusive = true
	popup_centered(Vector2i(340, 240))


func _build_shortcuts_text() -> String:
	var lines: Array[String] = [
		"[b]%s[/b]" % tr("help_shortcuts_title"),
		"",
		"[b]W A S D[/b] / %s — %s" % [tr("help_arrow_keys"), tr("help_pan_camera")],
		"[b]X[/b] — %s" % tr("help_center_camera"),
		"[b]+[/b] — %s" % tr("help_zoom_max"),
		"[b]-[/b] — %s" % tr("help_zoom_min"),
	]
	return "\n".join(lines)
