class_name Outline3D
extends RefCounted

# Contorno bianco caldo sui modelli degli edifici (outline.gdshader come material_overlay): pieno sul selezionato,
# più sottile e trasparente su quello sotto il mouse. Stesso colore dell'alone a terra (SelectionFrame3D).

# Spento il 2026-11-19 (richiesta utente: colorava tutto il modello; basta l'anello a terra di SelectionFrame3D).
# true per riaccenderlo.
const ENABLED := false
const SELECTED_GROW := 0.05
const HOVER_GROW := 0.03
const HOVER_ALPHA := 0.55

static var _selected: ShaderMaterial
static var _hover: ShaderMaterial


# Mette (o toglie) il contorno sui nodi di un livello con il meta "building_id".
static func apply(layer: Node, selected_id: int, hovered_id: int) -> void:
	if layer == null:
		return
	for child in layer.get_children():
		var instance := child as MeshInstance3D
		if instance == null or not instance.has_meta("building_id"):
			continue
		var building_id: int = instance.get_meta("building_id")
		if not ENABLED:
			instance.material_overlay = null
		elif building_id == selected_id:
			instance.material_overlay = _material(true)
		elif building_id == hovered_id:
			instance.material_overlay = _material(false)
		else:
			instance.material_overlay = null


static func _material(selected: bool) -> ShaderMaterial:
	if selected and _selected != null:
		return _selected
	if not selected and _hover != null:
		return _hover
	var material := ShaderMaterial.new()
	material.shader = preload("res://render3d/overlays/outline.gdshader")
	var color := SelectionFrame3D.COLOR
	material.set_shader_parameter("color", Color(color.r, color.g, color.b, 1.0 if selected else HOVER_ALPHA))
	material.set_shader_parameter("grow", SELECTED_GROW if selected else HOVER_GROW)
	if selected:
		_selected = material
	else:
		_hover = material
	return material
