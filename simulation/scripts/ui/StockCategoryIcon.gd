class_name StockCategoryIcon
extends Control

# Icona disegnata di una categoria di risorse (2026-10-10, richiesta utente — linguette del cassetto "Gestione scorte"):
# il disegno di una risorsa tipica della categoria, preso da IconRegistry (lo stesso del resto del gioco); per i
# Medicinali, che non hanno ancora un'icona disegnata, una foglia verde con una croce chiara. `category` =
# SecondaryResourceTypes.Category.

const REPRESENTATIVE_RESOURCE := {
	SecondaryResourceTypes.Category.FOOD: "fruit",
	SecondaryResourceTypes.Category.RAW_MATERIAL: "stick",
	SecondaryResourceTypes.Category.SEMI_FINISHED: "dried_hide",
	SecondaryResourceTypes.Category.TOOL: "stone_axe",
	SecondaryResourceTypes.Category.APPAREL: "fur_dress",
}
const LEAF_COLOR := Color(0.36, 0.68, 0.32, 1.0)
const LEAF_VEIN_COLOR := Color(0.22, 0.45, 0.20, 1.0)
const CROSS_COLOR := Color(0.95, 0.95, 0.90, 1.0)
const OUTLINE_COLOR := Color(0.14, 0.18, 0.12, 1.0)

var category: int = SecondaryResourceTypes.Category.FOOD


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var resource_name := String(REPRESENTATIVE_RESOURCE.get(category, ""))
	var icon: Control = IconRegistry.get_resource_icon_node(resource_name) if resource_name != "" else null
	if icon != null:
		add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if category != SecondaryResourceTypes.Category.MEDICINAL:
		return
	var w := size.x
	var h := size.y
	var line := minf(w, h) * 0.05
	# Foglia a mandorla inclinata, con la nervatura, e una croce chiara al centro.
	var leaf := PackedVector2Array()
	for i in range(17):
		var t := float(i) / 16.0
		var angle := t * TAU
		leaf.append(Vector2(w * 0.5, h * 0.5) + Vector2(cos(angle) * w * 0.40, sin(angle) * h * 0.24).rotated(-PI / 4.0))
	draw_colored_polygon(leaf, LEAF_COLOR)
	draw_polyline(leaf, OUTLINE_COLOR, line, true)
	draw_line(Vector2(w * 0.22, h * 0.78), Vector2(w * 0.78, h * 0.22), LEAF_VEIN_COLOR, line, true)
	var c := Vector2(w * 0.5, h * 0.5)
	var arm := minf(w, h) * 0.16
	var thick := minf(w, h) * 0.09
	draw_rect(Rect2(c - Vector2(arm, thick * 0.5), Vector2(arm * 2.0, thick)), CROSS_COLOR)
	draw_rect(Rect2(c - Vector2(thick * 0.5, arm), Vector2(thick, arm * 2.0)), CROSS_COLOR)
