class_name SystemMenuDialog
extends Window

signal action_selected(action_id: StringName)

@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

func _ready() -> void:
	title = tr("menu")
	close_button.text = tr("close_menu")
	close_button.pressed.connect(hide)
	# close_requested NON collegato a hide() (richiesta utente, 2026-09-05): si chiude solo dal
	# CloseButton esplicito qui sotto.
	_hide_native_close_button()


# La X nativa della barra del titolo non ha una proprietà dedicata per nasconderla mantenendo il
# titolo testuale (richiesta utente, 2026-09-05, secondo giro: prima era solo disattivata ma
# restava visibile) — sovrascrivo le icone di tema "close"/"close_pressed" con una texture 1x1
# trasparente, unico modo disponibile per farla sparire senza passare a borderless=true (che
# toglierebbe anche il titolo).
func _hide_native_close_button() -> void:
	var transparent := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override("close", transparent)
	add_theme_icon_override("close_pressed", transparent)


func open_menu() -> void:
	exclusive = true
	# size = get_contents_minimum_size() ESPLICITO prima di popup_centered() (era Vector2i(220, 160)
	# fisso; popup_centered() da solo senza questo passaggio non ridimensionava affatto — richiesta
	# utente, 2026-09-05, secondo giro: con 4 azioni + CloseButton il contenuto non ci stava più,
	# CloseButton finiva fuori dall'area visibile in basso). +20px di margine verticale per respiro
	# visivo, non stretto all'osso.
	size = Vector2i(get_contents_minimum_size()) + Vector2i(0, 20)
	popup_centered()


func add_action(label_text: String, action_id: StringName) -> void:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(func() -> void:
		hide()
		action_selected.emit(action_id)
	)
	actions_container.add_child(button)
