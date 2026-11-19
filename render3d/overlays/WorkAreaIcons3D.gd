class_name WorkAreaIcons3D
extends CanvasLayer

# Sovrapposizione 3D: le icone dei lavori abilitati di ogni zona di lavoro, sotto il suo nome (2026-11-19, richiesta
# utente — come nel 2D, MapScreenLabels). Le icone sono disegni a codice (CommandButtonIcon), non immagini: non si possono
# posare nel 3D come la scritta (Label3D), quindi stanno sullo schermo, su un fondino scuro, e a ogni fotogramma si
# spostano sotto la scritta della loro zona (punto della scritta proiettato dalla camera). Mai clic: tutto IGNORE.

const ICON_SIZE := 20.0
const ICON_SEPARATION := 2
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const PANEL_MARGIN := 2.0
# Altezza di una riga della scritta rispetto alla grandezza del carattere, e spazio tra scritta e icone (pixel schermo).
const LINE_HEIGHT_RATIO := 1.3
const GAP := 1.0

# Una voce per fondino: {"panel": PanelContainer, "row": HBoxContainer, "signature": String}.
var _entries: Array[Dictionary] = []


func _init() -> void:
	layer = 1


# labels: le Label3D delle zone (meta WorkAreas3D.ICON_KEYS_META = icone). Quelle senza icone non hanno fondino.
func update(labels: Array, camera: Camera3D) -> void:
	var count := 0
	if camera != null:
		var text_height := _text_height_px(camera)
		for label in labels:
			var label3d := label as Label3D
			var keys: PackedStringArray = label3d.get_meta(WorkAreas3D.ICON_KEYS_META, PackedStringArray())
			if keys.is_empty() or not label3d.is_visible_in_tree():
				continue
			var anchor := label3d.global_position
			if camera.is_position_behind(anchor):
				continue
			if count >= _entries.size():
				_entries.append(_create_entry())
			var entry: Dictionary = _entries[count]
			count += 1
			_set_icons(entry, keys)
			var panel: PanelContainer = entry["panel"]
			panel.visible = true
			panel.reset_size()
			panel.position = (camera.unproject_position(anchor) + Vector2(0.0, text_height + GAP)).round()
	for i in range(count, _entries.size()):
		(_entries[i]["panel"] as PanelContainer).visible = false


# Altezza sullo schermo della scritta delle zone: Label3D a misura fissa (fixed_size) = font_size × pixel_size per unità
# di profondità, proiettata dalla camera prospettica.
func _text_height_px(camera: Camera3D) -> float:
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	var world_height := WorkAreas3D.LABEL_FONT_SIZE * WorkAreas3D.LABEL_PIXEL_SIZE * LINE_HEIGHT_RATIO
	return world_height / tan(deg_to_rad(camera.fov) / 2.0) * viewport_height / 2.0


func _create_entry() -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(3)
	style.set_content_margin_all(PANEL_MARGIN)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ICON_SEPARATION)
	panel.add_child(row)
	add_child(panel)
	return {"panel": panel, "row": row, "signature": ""}


# Icone rifatte solo quando l'elenco cambia (stesse icone della barra dei comandi e del 2D).
func _set_icons(entry: Dictionary, keys: PackedStringArray) -> void:
	var signature := ",".join(keys)
	if signature == String(entry["signature"]):
		return
	entry["signature"] = signature
	var row: HBoxContainer = entry["row"]
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for key in keys:
		var icon := IconRegistry.get_command_button_icon_node(key)
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
