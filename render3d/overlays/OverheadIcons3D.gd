class_name OverheadIcons3D
extends CanvasLayer

# Sovrapposizione 3D: le icone e le animazioni del 2D sulla mappa, "paro paro" (2026-11-20, richiesta utente): lampadina
# dell'idea, icone dei comandi (costruisci, raccogli, caccia, produci...), riti e funerale che salgono dagli edifici,
# fumetto della chiacchiera, icona di salute e icona passeggera sopra le persone (GameStateReader.overhead_icons).
# Sono disegni a codice o emoji del 2D: per ognuna si crea una copia uguale (stessa classe, o Label con lo stesso testo)
# e a ogni fotogramma la si mette sullo schermo sopra il suo punto del mondo 3D, con la trasparenza, i dati e lo
# spostamento dell'originale (i tween del 2D continuano a girare sull'originale nascosto). Quando l'originale sparisce,
# sparisce anche la copia. Mai clic: tutto IGNORE.

# Quota delle icone sulla mappa (edifici, bersagli dei comandi), in microcelle sopra il terreno.
const MAP_LIFT := 0.5
# Grandezza minima sullo schermo, in pixel per pixel del 2D (da lontano non spariscono del tutto).
const MIN_SCALE := 1.5

# id dell'originale -> {"copy": CanvasItem, "anchor": Vector2, "vars": PackedStringArray}
var _mirrors: Dictionary = {}
var _entries: Array = []


func _init() -> void:
	layer = 1


func update(reader: GameStateReader, camera: Camera3D) -> void:
	reader.overhead_icons(_entries)
	var seen := {}
	for entry in _entries:
		var source: CanvasItem = entry["source"]
		var id := source.get_instance_id()
		var mirror: Dictionary = _mirrors.get(id, {})
		if mirror.is_empty():
			var copy := _make_copy(source)
			if copy == null:
				continue
			add_child(copy)
			var anchor: Vector2 = entry["anchor"]
			mirror = {"copy": copy, "anchor": entry["local"] if anchor == Vector2.INF else anchor,
				"vars": _script_vars(source)}
			_mirrors[id] = mirror
		seen[id] = true
		_place(mirror, entry, camera)
	for id in _mirrors.keys():
		if not seen.has(id):
			(_mirrors[id]["copy"] as CanvasItem).queue_free()
			_mirrors.erase(id)


func _place(mirror: Dictionary, entry: Dictionary, camera: Camera3D) -> void:
	var copy: CanvasItem = mirror["copy"]
	var anchor: Vector2 = entry["anchor"]
	if anchor == Vector2.INF:
		anchor = mirror["anchor"]
	var cell_point: Vector2 = anchor / float(MicroCellRenderer.CELL_SIZE)
	var ground: Vector2 = entry["ground"] + cell_point
	var person_size: float = entry["person_size"]
	var lift := People3D.HEIGHT * person_size if person_size > 0.0 else MAP_LIFT
	var origin: Vector2 = entry["origin"]
	var point := Vector3(origin.x + cell_point.x, GroundHeight3D.land_height(ground.x, ground.y) + lift, origin.y + cell_point.y)
	if camera == null or camera.is_position_behind(point):
		copy.visible = false
		return
	var screen := camera.unproject_position(point)
	# Pixel dello schermo per pixel del 2D, lì dove sta l'icona (prospettiva: più piccole da lontano).
	var one_microcell := camera.unproject_position(point + camera.global_transform.basis.x) - screen
	var k := maxf(one_microcell.length() / float(MicroCellRenderer.CELL_SIZE), MIN_SCALE)
	var source: CanvasItem = entry["source"]
	copy.visible = true
	copy.modulate = source.modulate
	copy.self_modulate = source.self_modulate
	var local: Vector2 = entry["local"]
	copy.set("position", (screen + (local - anchor) * k).round())
	copy.set("scale", (entry["scale"] as Vector2) * k)
	# Dati dell'originale (es. stato di malattia e ferita): copiati, e ridisegno solo se cambiano.
	var changed := false
	for name in mirror["vars"]:
		var value: Variant = source.get(name)
		if typeof(value) != typeof(copy.get(name)) or value != copy.get(name):
			copy.set(name, value)
			changed = true
	if changed:
		copy.queue_redraw()


# Copia vuota dell'originale: Label col suo testo e il suo carattere, oppure la stessa classe disegnata a codice.
func _make_copy(source: CanvasItem) -> CanvasItem:
	if source is Label:
		var label := source as Label
		var copy := Label.new()
		copy.text = label.text
		copy.size = label.size
		copy.clip_contents = label.clip_contents
		copy.horizontal_alignment = label.horizontal_alignment
		copy.vertical_alignment = label.vertical_alignment
		copy.add_theme_font_size_override("font_size", label.get_theme_font_size("font_size"))
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return copy
	var script := source.get_script() as Script
	if script == null:
		return null
	return script.new() as CanvasItem


# Variabili dello script dell'originale (lette una volta per icona).
static func _script_vars(source: CanvasItem) -> PackedStringArray:
	var names := PackedStringArray()
	if source is Label:
		return names
	for property in source.get_property_list():
		# Solo dati semplici: riferimenti ad altri nodi o oggetti dell'originale non vanno copiati.
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property["type"]) != TYPE_OBJECT:
			names.append(String(property["name"]))
	return names
