extends Node

# TEMPORANEO / DEBUG (2026-11-26, misura FPS della vista 3D): segnalibro della telecamera 3D, per rifare le misure del
# profilatore visivo sempre dalla stessa identica inquadratura, anche dopo un riavvio. Solo nelle build di debug
# (editor, F5), mai nel gioco esportato. Da togliere con la pulizia finale delle misure (insieme a Perf3D), con la riga
# che lo aggiunge in View3D.activate.
# Ins salva punto guardato, zoom e rotazione in SAVE_PATH; Home (inizio) ci torna. Non F7/F8: nell'editor, col gioco
# incorporato, F7 è "Interrompi" del debugger (gioco fermo) e F8 "Ferma il progetto". Una riga "[SEGNALIBRO 3D]" nell'Output.
# Legge e scrive i campi della camera (Camera3DController) per nome, così la camera resta com'è.

const SAVE_PATH := "user://debug_camera_bookmark_3d.cfg"
const SECTION := "camera"

var _camera: Camera3D


func _ready() -> void:
	_camera = get_parent() as Camera3D
	set_process_input(OS.is_debug_build())


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _camera == null:
		return
	if key.keycode == KEY_INSERT:
		_save()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_HOME:
		_load()
		get_viewport().set_input_as_handled()


func _save() -> void:
	var reader: GameStateReader = _camera.get("_reader")
	if reader == null:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "target", reader.camera_position())
	config.set_value(SECTION, "distance", _camera.get("_distance"))
	config.set_value(SECTION, "yaw", _camera.get("_yaw"))
	config.set_value(SECTION, "pitch_offset_deg", _camera.get("_pitch_offset_deg"))
	config.save(SAVE_PATH)
	print("[SEGNALIBRO 3D] salvato: punto %s, distanza %.1f" % [reader.camera_position(), float(_camera.get("_distance"))])


func _load() -> void:
	var reader: GameStateReader = _camera.get("_reader")
	var config := ConfigFile.new()
	if reader == null or config.load(SAVE_PATH) != OK:
		print("[SEGNALIBRO 3D] nessun segnalibro salvato (Ins per salvarlo)")
		return
	var target: Vector2 = config.get_value(SECTION, "target", reader.camera_position())
	reader.move_camera(target - reader.camera_position())
	_camera.set("_distance", float(config.get_value(SECTION, "distance", _camera.get("_distance"))))
	_camera.set("_yaw", float(config.get_value(SECTION, "yaw", _camera.get("_yaw"))))
	_camera.set("_pitch_offset_deg", float(config.get_value(SECTION, "pitch_offset_deg", _camera.get("_pitch_offset_deg"))))
	print("[SEGNALIBRO 3D] ripristinato: punto %s, distanza %.1f" % [target, float(_camera.get("_distance"))])
