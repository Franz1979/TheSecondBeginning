class_name View3DToggleButton
extends Button

# Pulsante di debug che passa dalla vista 2D alla 3D e ritorno. Parla solo con View3D (trovata per gruppo).

const LABEL_TO_3D := "3D"
const LABEL_TO_2D := "2D"

var _view: View3D


func _ready() -> void:
	text = LABEL_TO_3D
	tooltip_text = "Vista 3D di prova (solo da guardare)"
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if _view == null:
		_view = get_tree().get_first_node_in_group(View3D.GROUP) as View3D
		if _view == null:
			push_warning("View3DToggleButton: nessuna View3D nella scena.")
			return
		_view.active_changed.connect(_on_active_changed)
	_view.toggle()


func _on_active_changed(is_active: bool) -> void:
	text = LABEL_TO_2D if is_active else LABEL_TO_3D
