class_name MapScreenLabels
extends CanvasLayer

# Etichette nitide per le scritte della mappa (2026-09-27, richiesta utente — il nome delle zone di lavoro, disegnato
# con draw_string dentro la mappa, veniva ingrandito dallo zoom della camera ed era sfocato). Un CanvasLayer, quindi
# in spazio SCHERMO, figlio del Node2D della mappa che lo usa (overlay, anteprima): muore con lui e si vede solo
# finché lui esiste. Label normali dell'interfaccia (stesso carattere del tema, FONT_SIZE come le etichette del pannello
# laterale) con un contorno scuro per leggerle sopra l'erba.
#
# update_labels, chiamata a ogni frame dal proprietario, posiziona ogni etichetta sull'angolo in alto a sinistra del
# suo rettangolo (in pixel locali del proprietario) convertito in coordinate schermo con la trasformazione corrente
# (camera compresa). Un rettangolo fuori dall'area della mappa nasconde la sua etichetta; altrimenti l'etichetta resta
# dentro l'area della mappa (lo schermo meno il pannello laterale, stesso calcolo di CameraController._get_map_rect).

const FONT_SIZE: int = 11
const OUTLINE_SIZE: int = 4
const TEXT_COLOR := Color(1, 1, 1, 1)
const OUTLINE_COLOR := Color(0, 0, 0, 0.85)
# Distanza dell'etichetta dall'angolo del rettangolo, in pixel schermo.
const CORNER_OFFSET := Vector2(3.0, 1.0)

var _owner_node: Node2D = null
var _labels: Array[Label] = []


func _init(owner_node: Node2D = null) -> void:
	_owner_node = owner_node
	layer = 1


# `items`: [{"text": String, "rect": Rect2 in pixel locali del proprietario}, ...]. Le etichette in più vengono
# nascoste, quelle mancanti create.
func update_labels(items: Array) -> void:
	if _owner_node == null or not is_instance_valid(_owner_node):
		return
	while _labels.size() < items.size():
		_labels.append(_create_label())
	var to_screen: Transform2D = _owner_node.get_global_transform_with_canvas()
	var map_rect := _get_map_rect()
	# Etichette già piazzate in questo giro: una che cadrebbe sopra un'altra scende sotto di lei (2026-09-27 — più zone
	# con il nome nello stesso punto).
	var placed: Array[Rect2] = []
	for i in range(_labels.size()):
		var label := _labels[i]
		if i >= items.size():
			label.visible = false
			continue
		var screen_rect: Rect2 = to_screen * (items[i]["rect"] as Rect2)
		if not map_rect.intersects(screen_rect):
			label.visible = false
			continue
		label.text = String(items[i]["text"])
		label.visible = true
		label.reset_size()
		var label_size := label.get_combined_minimum_size()
		var label_position := screen_rect.position + CORNER_OFFSET
		label_position.x = clampf(label_position.x, map_rect.position.x, maxf(map_rect.end.x - label_size.x, map_rect.position.x))
		label_position.y = clampf(label_position.y, map_rect.position.y, maxf(map_rect.end.y - label_size.y, map_rect.position.y))
		var label_rect := Rect2(label_position, label_size)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if other.intersects(label_rect):
					label_rect.position.y = other.end.y + 1.0
					moved = true
		label.position = label_rect.position
		placed.append(label_rect)


func _create_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(label)
	return label


# Area della mappa sullo schermo: la finestra meno il pannello laterale (CanvasLayer/Sidebar della scena corrente).
func _get_map_rect() -> Rect2:
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var scene := get_tree().current_scene if get_tree() != null else null
	var sidebar := scene.get_node_or_null("CanvasLayer/Sidebar") if scene != null else null
	if sidebar is Control and sidebar.visible:
		rect.size.x = (sidebar as Control).get_global_rect().position.x
	return rect
