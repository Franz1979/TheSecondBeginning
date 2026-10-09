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

# Icone dei lavori sotto il nome (2026-10-09, zone di lavoro): una fila di icone dei comandi (CommandButtonIcon, le stesse
# della barra) su un fondino scuro semitrasparente, in pixel schermo (leggibili a ogni zoom). Mai clic: tutto IGNORE.
const ICON_SIZE: float = 16.0
const ICON_SEPARATION: int = 2
const ICON_PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const ICON_PANEL_MARGIN: float = 2.0

var _owner_node: Node2D = null
# Una voce per etichetta: {"box": VBoxContainer, "label": Label, "icons_panel": PanelContainer, "icons_row": HBoxContainer,
# "icons_signature": String (icone mostrate, per ricostruirle solo quando cambiano)}.
var _entries: Array[Dictionary] = []


func _init(owner_node: Node2D = null) -> void:
	_owner_node = owner_node
	layer = 1


# `items`: [{"text": String, "rect": Rect2 in pixel locali del proprietario, "icons": Array di chiavi delle icone dei
# comandi (facoltativo)}, ...]. Le voci in più vengono nascoste, quelle mancanti create.
func update_labels(items: Array) -> void:
	if _owner_node == null or not is_instance_valid(_owner_node):
		return
	while _entries.size() < items.size():
		_entries.append(_create_entry())
	var to_screen: Transform2D = _owner_node.get_global_transform_with_canvas()
	var map_rect := _get_map_rect()
	# Etichette già piazzate in questo giro: una che cadrebbe sopra un'altra scende sotto di lei (2026-09-27 — più zone
	# con il nome nello stesso punto).
	var placed: Array[Rect2] = []
	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		var box: VBoxContainer = entry["box"]
		if i >= items.size():
			box.visible = false
			continue
		var screen_rect: Rect2 = to_screen * (items[i]["rect"] as Rect2)
		if not map_rect.intersects(screen_rect):
			box.visible = false
			continue
		(entry["label"] as Label).text = String(items[i]["text"])
		_set_icons(entry, items[i].get("icons", []))
		box.visible = true
		box.reset_size()
		var box_size := box.get_combined_minimum_size()
		var box_position := screen_rect.position + CORNER_OFFSET
		box_position.x = clampf(box_position.x, map_rect.position.x, maxf(map_rect.end.x - box_size.x, map_rect.position.x))
		box_position.y = clampf(box_position.y, map_rect.position.y, maxf(map_rect.end.y - box_size.y, map_rect.position.y))
		var box_rect := Rect2(box_position, box_size)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if other.intersects(box_rect):
					box_rect.position.y = other.end.y + 1.0
					moved = true
		box.position = box_rect.position
		placed.append(box_rect)


func _create_entry() -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	box.add_child(label)
	var icons_panel := PanelContainer.new()
	icons_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = ICON_PANEL_COLOR
	style.set_corner_radius_all(3)
	style.set_content_margin_all(ICON_PANEL_MARGIN)
	icons_panel.add_theme_stylebox_override("panel", style)
	icons_panel.visible = false
	box.add_child(icons_panel)
	var icons_row := HBoxContainer.new()
	icons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons_row.add_theme_constant_override("separation", ICON_SEPARATION)
	icons_panel.add_child(icons_row)
	add_child(box)
	return {"box": box, "label": label, "icons_panel": icons_panel, "icons_row": icons_row, "icons_signature": ""}


# Icone della voce: ricostruite solo quando l'elenco cambia; nessuna icona = niente fondino.
func _set_icons(entry: Dictionary, icon_keys: Array) -> void:
	var signature := ",".join(PackedStringArray(icon_keys))
	if signature == String(entry["icons_signature"]):
		return
	entry["icons_signature"] = signature
	var icons_row: HBoxContainer = entry["icons_row"]
	for child in icons_row.get_children():
		icons_row.remove_child(child)
		child.queue_free()
	for icon_key in icon_keys:
		var icon := IconRegistry.get_command_button_icon_node(String(icon_key))
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons_row.add_child(icon)
	(entry["icons_panel"] as PanelContainer).visible = not icon_keys.is_empty()


# Area della mappa sullo schermo: la finestra meno il pannello laterale (CanvasLayer/Sidebar della scena corrente).
func _get_map_rect() -> Rect2:
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var scene := get_tree().current_scene if get_tree() != null else null
	var sidebar := scene.get_node_or_null("CanvasLayer/Sidebar") if scene != null else null
	if sidebar is Control and sidebar.visible:
		rect.size.x = (sidebar as Control).get_global_rect().position.x
	return rect
