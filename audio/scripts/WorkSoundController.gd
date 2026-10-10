class_name WorkSoundController
extends Node

# Suoni del villaggio in GameScene (2026-10-09, richiesta utente), dal banco audio/banks/sfx_world.tres. Figlio di
# GameScene, istanziato accanto ad AmbienceController e MusicController da GameScene._setup_clock, che chiama
# start(game_scene, clock). Tutto in tempo REALE (nodo PROCESS_MODE_ALWAYS, delta reale): cadenza indipendente dalla
# velocità di gioco.
#
# Ogni suono ha la sua regola in SOUND_RULES (in cima al file):
#   - "repeat" (cut, quarry, kids): una sorgente per individuo riconosciuto ("detect"); suona la registrazione dalla sua
#     posizione, poi una pausa casuale ("pause_min_sec"–"pause_max_sec") e di nuovo; prima partenza con un ritardo
#     casuale fino a FIRST_START_MAX_DELAY_SEC. Le sorgenti attive di un gruppo ("group", limite in GROUP_MAX_SOURCES)
#     sono le più vicine al centro dello schermo dentro l'area visibile allargata (cut e quarry dividono il gruppo
#     "work": 4 in tutto, come prima);
#   - "oneshot" (hunt, fino al 2026-10-10 "horn"): una volta sola, quando un individuo passa da "non in caccia" a "in
#     caccia" (HuntService.is_hunt_task sulla task corrente), nella sua posizione e solo se è nell'area udibile; un suono
#     di caccia alla volta e almeno HUNT_MIN_INTERVAL_SEC tra due. Dura al massimo "max_duration_sec": dissolvenza di
#     "end_fade_sec" che finisce lì. Varianti hunt_2, hunt_3… nel banco. La prima scansione registra lo stato senza
#     suonare;
#   - "loop" (crowd): sorgente fissa sul centro del villaggio (VisitorService.find_village_center), in loop (import
#     con loop), con dissolvenza in entrata e in uscita; solo con almeno CROWD_MIN_PEOPLE persone entro
#     CROWD_RADIUS_MICROCELLS dal centro, e con il centro nell'area visibile. Senza centro, nessun suono.
#
# Regole comuni: sorgente fuori (action finita, uscita dalle attive) o gioco in pausa = il suono sfuma ("fade_out_sec");
# volume che cala dal centro dello schermo verso i bordi, con la distanza udibile (max_distance) che segue l'area
# visibile, quindi lo zoom; volume pieno da ZOOM_FULL_VOLUME in su, lineare fino a zero a ZOOM_SILENT (un fattore sul
# volume della sorgente, mai sui volumi utente di UserOptions); uscendo dalla scena le sorgenti, figlie di questo nodo,
# si fermano con lui.

const KIND_REPEAT := "repeat"
const KIND_ONESHOT := "oneshot"
const KIND_LOOP := "loop"

# id del suono (banco sfx_world) -> regola. "detect": metodo di questo nodo, (HumanIndividual, Task) -> bool, per i
# suoni "repeat".
const SOUND_RULES := {
	&"cut": {"kind": KIND_REPEAT, "detect": "_detect_cut", "group": "work", "pause_min_sec": 2.0, "pause_max_sec": 6.0,
		"fade_out_sec": 0.3},
	&"quarry": {"kind": KIND_REPEAT, "detect": "_detect_quarry", "group": "work", "pause_min_sec": 2.0,
		"pause_max_sec": 6.0, "fade_out_sec": 0.3},
	&"knapping": {"kind": KIND_REPEAT, "detect": "_detect_knapping", "group": "work", "pause_min_sec": 2.0,
		"pause_max_sec": 6.0, "fade_out_sec": 0.3},
	&"build": {"kind": KIND_REPEAT, "detect": "_detect_build", "group": "work", "pause_min_sec": 2.0, "pause_max_sec": 6.0,
		"fade_out_sec": 0.3},
	# Kids meno invadente (2026-10-10): pausa 30–60 s, una sorgente, volume ridotto nel banco (volume_db -6).
	# "sound_pause": la pausa vale per tutto il suono, non per sorgente (2026-10-10): dopo una riproduzione nessuna
	# sorgente di quel suono riparte prima della pausa, anche se nel frattempo cambia il bambino.
	&"kids": {"kind": KIND_REPEAT, "detect": "_detect_kids", "group": "kids", "pause_min_sec": 30.0, "pause_max_sec": 60.0,
		"fade_out_sec": 0.3, "sound_pause": true, "no_cut": true, "random_variant": true},
	# Durata limitata (2026-10-10): parte normalmente, a max_duration_sec − end_fade_sec sfuma, a max_duration_sec è finito.
	&"hunt": {"kind": KIND_ONESHOT, "group": "hunt", "fade_out_sec": 0.3, "max_duration_sec": 3.0, "end_fade_sec": 0.5},
	&"crowd": {"kind": KIND_LOOP, "group": "crowd", "fade_in_sec": 1.0, "fade_out_sec": 1.0},
}
# Sorgenti attive al massimo per gruppo (cut e quarry insieme: "work").
const GROUP_MAX_SOURCES := {"work": 4, "kids": 1, "hunt": 1, "crowd": 1}

# Cadenza della ricerca delle sorgenti (secondi reali).
const SCAN_INTERVAL_SEC: float = 0.5
# Margine dell'area visibile in cui contano le sorgenti (frazione della sua larghezza/altezza).
const VISIBLE_MARGIN_RATIO: float = 0.2
# Ritardo casuale della prima partenza di una sorgente "repeat" (secondi reali).
const FIRST_START_MAX_DELAY_SEC: float = 2.0
# Hunt: almeno questo tempo tra un suono di caccia e il successivo (secondi reali).
const HUNT_MIN_INTERVAL_SEC: float = 15.0
# Crowd: persone minime entro il raggio (microcelle) dal centro del villaggio.
const CROWD_MIN_PEOPLE: int = 3
const CROWD_RADIUS_MICROCELLS: float = 8.0
# Attenuazione con la distanza dal centro dello schermo (AudioStreamPlayer2D.attenuation: 1.0 = lineare).
const DISTANCE_ATTENUATION: float = 1.0
# Zoom della camera: volume pieno da ZOOM_FULL_VOLUME in su, zero a ZOOM_SILENT e sotto, lineare in mezzo.
const ZOOM_FULL_VOLUME: float = 6.0
const ZOOM_SILENT: float = 1.0
# Volume di "silenzio" (dB), come AudioManager.SILENT_DB.
const SILENT_DB: float = -80.0

const CROWD_KEY := "crowd"

var _game_scene: Node = null
var _clock: GameClockController = null
var _scan_elapsed: float = 0.0
# Chiave -> sorgente {"sound_id", "rule", "player": AudioStreamPlayer2D, "def": SoundDef, "position": Vector2,
# "playing": bool, "wait_left": float, "gain": float}. Chiave: "<suono>:<id individuo>", "hunt:<id>", "crowd".
var _sources: Dictionary = {}
# Hunt: chi era in caccia alla scansione precedente (id -> true), prima scansione fatta, ultimo suono (ms reali).
var _hunting_ids: Dictionary = {}
var _hunt_initialized: bool = false
var _last_hunt_msec: int = -1000000
# Suoni con la pausa per tutto il suono ("sound_pause"): id -> Time.get_ticks_msec() prima del quale nessuna sorgente
# di quel suono può partire (durante una riproduzione: bloccato finché non finisce).
var _sound_blocked_until_msec: Dictionary = {}
# Riproduzioni lasciate finire ("no_cut", 2026-10-10): sorgenti tolte dalle attive mentre suonavano; il player arriva in
# fondo e poi si libera. Si fermano solo in pausa o uscendo dalla scena.
var _detached_sources: Array[Dictionary] = []
const SOUND_PLAYING_BLOCK_MSEC: int = 1 << 62


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# `game_scene`: la GameScene (individui, celle vive, mondo); `clock`: per sapere se il gioco è in pausa.
func start(game_scene: Node, clock: GameClockController) -> void:
	_game_scene = game_scene
	_clock = clock


func _process(delta: float) -> void:
	if _game_scene == null or not is_instance_valid(_game_scene):
		return
	# In pausa tutto tace.
	if _clock == null or not _clock.is_playing:
		if not _sources.is_empty():
			for key in _sources.keys():
				_fade_out_source(key)
		for detached in _detached_sources.duplicate():
			_fade_out_detached(detached)
		_scan_elapsed = SCAN_INTERVAL_SEC
		return
	_scan_elapsed += delta
	if _scan_elapsed >= SCAN_INTERVAL_SEC:
		_scan_elapsed = 0.0
		_rescan()
	var zoom_factor := _zoom_volume_factor()
	var hearing_distance := _hearing_distance()
	for key in _sources.keys():
		var source: Dictionary = _sources[key]
		var rule: Dictionary = source["rule"]
		var player: AudioStreamPlayer2D = source["player"]
		player.max_distance = hearing_distance
		# Dissolvenza in entrata (crowd).
		if float(source["gain"]) < 1.0:
			var fade_in := float(rule.get("fade_in_sec", 0.0))
			source["gain"] = 1.0 if fade_in <= 0.0 else minf(float(source["gain"]) + delta / fade_in, 1.0)
		var linear := zoom_factor * float(source["gain"])
		var def: SoundDef = source["def"]
		player.volume_db = def.volume_db + _linear_to_db_safe(linear) if linear > 0.0 else SILENT_DB
		if String(rule["kind"]) != KIND_REPEAT or bool(source["playing"]):
			continue
		source["wait_left"] = float(source["wait_left"]) - delta
		if float(source["wait_left"]) <= 0.0 and Time.get_ticks_msec() >= int(_sound_blocked_until_msec.get(source["sound_id"], 0)):
			_play_source(source)


# Una scansione: sorgenti "repeat" per gruppo, hunt, crowd.
func _rescan() -> void:
	var visible := _visible_world_rect()
	var center := visible.get_center()
	var individuals: Array = _game_scene.get("human_individuals")
	var live_cells: Dictionary = _game_scene.get("live_cells")
	var wanted: Dictionary = {}
	var by_group: Dictionary = {}
	for member in individuals:
		var task: Task = member.current_task
		if task == null or task.is_finished():
			continue
		for sound_id in SOUND_RULES.keys():
			var rule: Dictionary = SOUND_RULES[sound_id]
			if String(rule["kind"]) != KIND_REPEAT or not bool(call(String(rule["detect"]), member, task)):
				continue
			var world_position: Variant = _world_position_of(member, live_cells)
			if world_position == null or not visible.has_point(world_position):
				break
			var group := String(rule["group"])
			if not by_group.has(group):
				by_group[group] = []
			(by_group[group] as Array).append({
				"key": "%s:%d" % [sound_id, member.id], "sound_id": sound_id, "position": world_position,
				"distance": (world_position as Vector2).distance_squared_to(center),
			})
			break
	for group in by_group.keys():
		var candidates: Array = by_group[group]
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
		for candidate in candidates.slice(0, int(GROUP_MAX_SOURCES.get(group, 1))):
			wanted[String(candidate["key"])] = candidate
	# Sorgenti "repeat" uscite: sfumano. Rimaste: posizione aggiornata. Nuove: create.
	for key in _sources.keys():
		var source: Dictionary = _sources[key]
		if String((source["rule"] as Dictionary)["kind"]) == KIND_REPEAT and not wanted.has(key):
			# "no_cut" (kids): una riproduzione partita arriva sempre in fondo.
			if bool((source["rule"] as Dictionary).get("no_cut", false)) and bool(source["playing"]):
				_sources.erase(key)
				_detached_sources.append(source)
			else:
				_fade_out_source(key)
	for key in wanted.keys():
		var candidate: Dictionary = wanted[key]
		if _sources.has(key):
			var source: Dictionary = _sources[key]
			source["position"] = candidate["position"]
			(source["player"] as AudioStreamPlayer2D).global_position = candidate["position"]
		else:
			_add_source(key, StringName(candidate["sound_id"]), candidate["position"], randf_range(0.0, FIRST_START_MAX_DELAY_SEC))
	_scan_hunt(individuals, live_cells, visible)
	_scan_crowd(individuals, live_cells, visible)


# Hunt: chi passa da "non in caccia" a "in caccia" (la prima scansione registra senza suonare).
func _scan_hunt(individuals: Array, live_cells: Dictionary, visible: Rect2) -> void:
	var now_hunting: Dictionary = {}
	var started: Array = []
	for member in individuals:
		if not HuntService.is_hunt_task(member.current_task) or member.current_task.is_finished():
			continue
		now_hunting[member.id] = true
		if not _hunting_ids.has(member.id):
			started.append(member)
	_hunting_ids = now_hunting
	if not _hunt_initialized:
		_hunt_initialized = true
		return
	for member in started:
		if _has_group_source("hunt") or Time.get_ticks_msec() - _last_hunt_msec < int(HUNT_MIN_INTERVAL_SEC * 1000.0):
			return
		var world_position: Variant = _world_position_of(member, live_cells)
		if world_position == null or not visible.has_point(world_position):
			continue
		var key := "hunt:%d" % member.id
		if _add_source(key, &"hunt", world_position, 0.0):
			_play_source(_sources[key])
			_last_hunt_msec = Time.get_ticks_msec()
			_limit_duration(key)


# Crowd: sorgente fissa sul centro del villaggio, con abbastanza persone vicine e il centro nell'area visibile.
func _scan_crowd(individuals: Array, live_cells: Dictionary, visible: Rect2) -> void:
	var world: World = _game_scene.get("macro_world")
	var village_center: Building = VisitorService.find_village_center(world) if world != null else null
	var center_position: Variant = null
	if village_center != null:
		var cell: Variant = live_cells.get(Vector2i(village_center.macro_x, village_center.macro_y))
		if cell != null:
			center_position = (cell.container as Node2D).to_global(
				(Vector2(village_center.micro_x, village_center.micro_y) + Vector2(0.5, 0.5)) * MicroCellRenderer.CELL_SIZE
			)
	var active := false
	if center_position != null and visible.has_point(center_position):
		var people := 0
		for member in individuals:
			var center_local := SpatialSelectionService._position_relative_to(village_center, member.home_macro_coords) + Vector2(0.5, 0.5)
			if member.position.distance_to(center_local) <= CROWD_RADIUS_MICROCELLS:
				people += 1
		active = people >= CROWD_MIN_PEOPLE
	if active and not _sources.has(CROWD_KEY):
		if _add_source(CROWD_KEY, &"crowd", center_position, 0.0):
			var source: Dictionary = _sources[CROWD_KEY]
			source["gain"] = 0.0
			_play_source(source)
	elif not active and _sources.has(CROWD_KEY):
		_fade_out_source(CROWD_KEY)


# --- Riconoscimento delle sorgenti "repeat" (SOUND_RULES "detect") ---

func _detect_cut(_member: HumanIndividual, task: Task) -> bool:
	return task.get_current_action() is CutAction


func _detect_quarry(_member: HumanIndividual, task: Task) -> bool:
	return task.get_current_action() is QuarryAction


# Scheggiatura (2026-10-10): la ProduceAction vera e propria presso un focolare — non il cammino né il rifornimento di
# materiali (sono altri step), e non quando la produzione è ferma (materiali o attrezzi mancanti, Prodotti finiti pieni).
func _detect_knapping(_member: HumanIndividual, task: Task) -> bool:
	var action := task.get_current_action() as ProduceAction
	if action == null or action.target_building == null or action.target_building.building_type_name != "campfire":
		return false
	return not action.is_blocked_by_materials() and not action.is_waiting_for_tools() 		and not ProductionService.is_output_blocking(action.target_building)


# Costruzione (2026-10-10): la BuildAction vera e propria — non il rifornimento dei materiali (altri step), e non quando
# è ferma perché al cantiere manca materiale. Riparazione (2026-10-10): la RepairAction usa lo stesso suono.
func _detect_build(_member: HumanIndividual, task: Task) -> bool:
	if task.get_current_action() is RepairAction:
		return true
	var action := task.get_current_action() as BuildAction
	return action != null and action.get_missing_materials().is_empty()


# Bambino (fascia CHILD) che gioca (task_play_name).
func _detect_kids(member: HumanIndividual, task: Task) -> bool:
	return task.task_name == "task_play_name" and int(_game_scene.call("_resolve_age_band", member)) == HumanTypes.AgeBand.CHILD


# --- Sorgenti ---

func _add_source(key: String, sound_id: StringName, world_position: Vector2, first_delay: float) -> bool:
	var def := AudioManager.get_sound_def(sound_id)
	if def == null or def.streams.is_empty():
		return false
	var player := AudioStreamPlayer2D.new()
	player.bus = def.bus
	player.attenuation = DISTANCE_ATTENUATION
	add_child(player)
	player.global_position = world_position
	var rule: Dictionary = SOUND_RULES[sound_id]
	var source := {
		"sound_id": sound_id, "rule": rule, "player": player, "def": def, "position": world_position, "playing": false,
		"wait_left": first_delay, "gain": 1.0,
	}
	player.finished.connect(func() -> void:
		source["playing"] = false
		match String(rule["kind"]):
			KIND_REPEAT:
				source["wait_left"] = randf_range(float(rule["pause_min_sec"]), float(rule["pause_max_sec"]))
				_start_sound_pause(source)
				# Riproduzione lasciata finire: ora il player si libera.
				if _detached_sources.has(source):
					_detached_sources.erase(source)
					player.queue_free()
			KIND_ONESHOT:
				if _sources.get(key) == source:
					_sources.erase(key)
				player.queue_free()
	)
	_sources[key] = source
	return true


func _play_source(source: Dictionary) -> void:
	var def: SoundDef = source["def"]
	var player: AudioStreamPlayer2D = source["player"]
	# Variante della voce (2026-10-10): lo stesso sacchetto casuale di AudioManager (mai la stessa due volte di fila con
	# più varianti); "random_variant" (kids): scelta puramente casuale. Con una sola variante, sempre quella.
	if bool((source["rule"] as Dictionary).get("random_variant", false)):
		player.stream = def.streams[randi() % def.streams.size()]
	else:
		player.stream = AudioManager._next_variant(StringName(source["sound_id"]), def)
	player.pitch_scale = randf_range(minf(def.pitch_min, def.pitch_max), maxf(def.pitch_min, def.pitch_max))
	player.global_position = source["position"]
	source["playing"] = true
	if bool((source["rule"] as Dictionary).get("sound_pause", false)):
		_sound_blocked_until_msec[source["sound_id"]] = SOUND_PLAYING_BLOCK_MSEC
	player.play()


# Fine di una riproduzione (o sorgente tolta mentre suonava) di un suono con "sound_pause": nessuna sorgente di quel
# suono riparte prima di una pausa casuale della sua regola.
func _start_sound_pause(source: Dictionary) -> void:
	var rule: Dictionary = source["rule"]
	if not bool(rule.get("sound_pause", false)):
		return
	var pause_sec := randf_range(float(rule["pause_min_sec"]), float(rule["pause_max_sec"]))
	_sound_blocked_until_msec[source["sound_id"]] = Time.get_ticks_msec() + int(pause_sec * 1000.0)


# Riproduzione lasciata finire, fermata dalla pausa: sfuma come le altre.
func _fade_out_detached(source: Dictionary) -> void:
	_detached_sources.erase(source)
	var player: AudioStreamPlayer2D = source["player"]
	if not is_instance_valid(player):
		return
	_start_sound_pause(source)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, float((source["rule"] as Dictionary).get("fade_out_sec", 0.3)))
	tween.tween_callback(player.queue_free)


# Sorgente fuori: il suono sfuma nel "fade_out_sec" della sua regola, poi il player viene liberato.
func _fade_out_source(key: String, fade_override_sec: float = -1.0) -> void:
	var source: Dictionary = _sources.get(key, {})
	_sources.erase(key)
	if source.is_empty():
		return
	var player: AudioStreamPlayer2D = source["player"]
	if not is_instance_valid(player):
		return
	if not player.playing:
		player.queue_free()
		return
	_start_sound_pause(source)
	var tween := create_tween()
	var fade := fade_override_sec if fade_override_sec >= 0.0 else float((source["rule"] as Dictionary).get("fade_out_sec", 0.3))
	tween.tween_property(player, "volume_db", SILENT_DB, fade)
	tween.tween_callback(player.queue_free)


# Durata massima della regola ("max_duration_sec", "end_fade_sec"): a max − fade la sorgente sfuma in "end_fade_sec",
# a max è finita (tempo reale). Nessun effetto se la sorgente è già finita o tolta.
func _limit_duration(key: String) -> void:
	var source: Dictionary = _sources.get(key, {})
	if source.is_empty():
		return
	var rule: Dictionary = source["rule"]
	var max_duration := float(rule.get("max_duration_sec", -1.0))
	if max_duration <= 0.0:
		return
	var end_fade := clampf(float(rule.get("end_fade_sec", 0.0)), 0.0, max_duration)
	var timer := get_tree().create_timer(max_duration - end_fade, true, false, true)
	timer.timeout.connect(func() -> void:
		if _sources.get(key) == source:
			_fade_out_source(key, end_fade)
	)


func _has_group_source(group: String) -> bool:
	for source in _sources.values():
		if String((source["rule"] as Dictionary)["group"]) == group:
			return true
	return false


# Posizione nel mondo di un individuo (come idea_bulb_shown); null se la sua macrocella non è attiva.
func _world_position_of(member: HumanIndividual, live_cells: Dictionary) -> Variant:
	var cell: Variant = live_cells.get(member.home_macro_coords)
	if cell == null:
		return null
	return (cell.container as Node2D).to_global(member.position * MicroCellRenderer.CELL_SIZE)


# Area visibile in coordinate del mondo (camera compresa), allargata di VISIBLE_MARGIN_RATIO per lato.
func _visible_world_rect() -> Rect2:
	var viewport := get_viewport()
	var screen := viewport.get_visible_rect()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var rect := Rect2(to_world * screen.position, Vector2.ZERO).expand(to_world * screen.end)
	return rect.grow_individual(
		rect.size.x * VISIBLE_MARGIN_RATIO, rect.size.y * VISIBLE_MARGIN_RATIO,
		rect.size.x * VISIBLE_MARGIN_RATIO, rect.size.y * VISIBLE_MARGIN_RATIO
	)


# Distanza udibile dal centro dello schermo: metà diagonale dell'area visibile allargata (segue lo zoom).
func _hearing_distance() -> float:
	return maxf(_visible_world_rect().size.length() * 0.5, 1.0)


func _zoom_volume_factor() -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return 1.0
	return clampf((camera.zoom.x - ZOOM_SILENT) / (ZOOM_FULL_VOLUME - ZOOM_SILENT), 0.0, 1.0)


func _linear_to_db_safe(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))
