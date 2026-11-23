class_name Perf3D
extends RefCounted

# TEMPORANEO (2026-11-21, misura degli FPS della vista 3D): tempi per fotogramma divisi per voce, stampati ogni
# INTERVAL secondi con la riga "[PERF3D]" (anche nel 2D, per il confronto). Da togliere a misura finita, con le sue
# chiamate (cercare "Perf3D." in View3D, Cell3D, GameScene).
# Tasti temporanei: F9 ombre del sole sì/no, F10 occlusione ambientale (SSAO) sì/no, F11 bagliore sì/no, F12 alberi e
# cespugli sì/no, F4 terreno a tinta unita sì/no,
# F3 cose piccole a terra (sassi e rocce, bastoni, frutti caduti, piantine, ciuffi d'erba) sì/no.

const INTERVAL := 3.0
# Interruttore (2026-11-23): false = niente misure, niente righe [PERF3D], tasti F3/F4/F9-F12 inattivi.
const ENABLED := false

static var _last := 0
static var _frame: Dictionary = {} # voce -> usec di questo fotogramma
static var _total: Dictionary = {} # voce -> usec sommati nell'intervallo
static var _max: Dictionary = {} # voce -> fotogramma peggiore nell'intervallo
static var _counts: Dictionary = {} # voce -> quante volte (ricostruzioni)
static var _frames := 0
static var _start := 0
static var _frame_start := 0
static var _frame_usec_total := 0
static var _frame_usec_max := 0
static var _gpu_total := 0.0
static var _gpu_max := 0.0
static var _cpu_render_total := 0.0
static var _draw_calls := 0
static var _objects := 0
static var _primitives := 0
static var _measure_on := false
static var _keys_down: Dictionary = {}
static var shadows_off := false
static var ssao_off := false
static var glow_off := false
static var vegetation_off := false
static var terrain_flat := false
static var far_hide_off := false
static var aniso_off := false
static var one_noise := false
static var ground_off := false


# Ogni partita nuova o caricata parte con tutto acceso: lo stato dei tasti non resta da una partita all'altra.
static func reset_keys() -> void:
	shadows_off = false
	ssao_off = false
	glow_off = false
	vegetation_off = false
	terrain_flat = false
	far_hide_off = false
	aniso_off = false
	one_noise = false
	ground_off = false


# Scrive quali pezzi di un'impronta sono cambiati (stesso confronto di Cell3D.needs_refresh: liste e dizionari per
# riferimento, il resto per valore). Prima costruzione (impronta vecchia vuota): non scrive niente.
static func log_changed_signature(layer: String, old: Array, new: Array, names: Array) -> void:
	if not ENABLED or old.is_empty():
		return
	var changed := PackedStringArray()
	for i in range(new.size()):
		var a: Variant = old[i] if i < old.size() else null
		var b: Variant = new[i]
		var same: bool = is_same(a, b) if (a is Array or a is Dictionary or b is Array or b is Dictionary) else a == b
		if not same:
			changed.append(String(names[i]) if i < names.size() else str(i))
	print("[PERF3D] rifaccio %s: cambiato %s" % [layer, ", ".join(changed)])


static func begin() -> void:
	if not ENABLED:
		return
	_last = Time.get_ticks_usec()


# Somma il tempo passato dall'ultimo begin/mark sotto `name`.
static func mark(name: StringName) -> void:
	if not ENABLED:
		return
	var now := Time.get_ticks_usec()
	_frame[name] = int(_frame.get(name, 0)) + (now - _last)
	_last = now


# Come mark, e conta anche le volte (ricostruzioni).
static func mark_count(name: StringName) -> void:
	mark(name)
	count(name)


static func count(name: StringName) -> void:
	if not ENABLED:
		return
	_counts[name] = int(_counts.get(name, 0)) + 1


# Una volta per fotogramma (fine di GameScene._process): chiude il fotogramma precedente e ogni INTERVAL stampa.
static func tick(viewport: Viewport, view_3d_active: bool) -> void:
	if not ENABLED:
		return
	var now := Time.get_ticks_usec()
	var rid := viewport.get_viewport_rid()
	if not _measure_on:
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_measure_on = true
		_start = now
		_frame_start = now
		_frame.clear()
		return
	_read_keys()
	var frame_usec := now - _frame_start
	_frame_start = now
	_frame_usec_total += frame_usec
	_frame_usec_max = maxi(_frame_usec_max, frame_usec)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_gpu_total += gpu
	_gpu_max = maxf(_gpu_max, gpu)
	_cpu_render_total += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_draw_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_objects += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_primitives += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	for name in _frame:
		var value := int(_frame[name])
		_total[name] = int(_total.get(name, 0)) + value
		_max[name] = maxi(int(_max.get(name, 0)), value)
	_frame.clear()
	_frames += 1
	if now - _start < INTERVAL * 1000000.0:
		return
	var f := float(_frames)
	var lines := PackedStringArray()
	lines.append("[PERF3D] %s | fps %d | fotogramma medio %.1f ms (peggiore %.1f) | GPU %.1f ms (peggiore %.1f) | CPU render %.1f ms | draw call %d | oggetti %d | triangoli %dk | process %.1f ms | physics %.1f ms | ombre %s ssao %s glow %s" % [
		"3D" if view_3d_active else "2D", Engine.get_frames_per_second(), _frame_usec_total / f / 1000.0,
		_frame_usec_max / 1000.0, _gpu_total / f, _gpu_max, _cpu_render_total / f, int(_draw_calls / f), int(_objects / f),
		int(_primitives / f / 1000.0), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"no" if shadows_off else "sì", "no" if ssao_off or not UserOptions.ssao_enabled else "sì",
		"no" if glow_off or not Lighting3D.GLOW_ENABLED else "sì"])
	lines[0] += " vegetazione %s terreno %s piccole da lontano %s anisotropo %s" % ["no" if vegetation_off else "sì", "piatto" if terrain_flat else "texture",
		"disegnate" if far_hide_off else "spente", "no" if aniso_off else "sì"]
	lines[0] += " rumore %s risoluzione3d %d%% cose a terra %s" % ["una lettura" if one_noise else "sette letture", roundi(viewport.scaling_3d_scale * 100.0), "no" if ground_off else "sì"]
	var names := _total.keys()
	names.sort_custom(func(a, b): return int(_total[a]) > int(_total[b]))
	var parts := PackedStringArray()
	for name in names:
		var avg := float(_total[name]) / f / 1000.0
		if avg < 0.02 and int(_max[name]) < 2000:
			continue
		var text := "%s %.2f (max %.1f)" % [name, avg, int(_max[name]) / 1000.0]
		if _counts.has(name):
			text += " x%d" % int(_counts[name])
		parts.append(text)
	for name in _counts:
		if not _total.has(name):
			parts.append("%s x%d" % [name, int(_counts[name])])
	lines.append("[PERF3D]   ms per fotogramma: " + ", ".join(parts))
	print("\n".join(lines))
	_total.clear()
	_max.clear()
	_counts.clear()
	_frames = 0
	_frame_usec_total = 0
	_frame_usec_max = 0
	_gpu_total = 0.0
	_gpu_max = 0.0
	_cpu_render_total = 0.0
	_draw_calls = 0
	_objects = 0
	_primitives = 0
	_start = now


static func _read_keys() -> void:
	if _pressed(KEY_F9):
		shadows_off = not shadows_off
	if _pressed(KEY_F10):
		ssao_off = not ssao_off
	if _pressed(KEY_F11):
		glow_off = not glow_off
	if _pressed(KEY_F4):
		terrain_flat = not terrain_flat
	# F3 ora fa l'anisotropo (2026-11-22: F2 e F8 non arrivavano al gioco); la prova dello spegnimento da lontano è finita.
	# F3 ora nasconde le cose piccole a terra (le prove di anisotropo e rumore sono finite: non costano niente).
	if _pressed(KEY_F3):
		ground_off = not ground_off
		print("[PERF3D] tasto F3: cose a terra %s" % ("nascoste" if ground_off else "visibili"))
	if _pressed(KEY_F12):
		vegetation_off = not vegetation_off


static func _pressed(key: Key) -> bool:
	var down := Input.is_physical_key_pressed(key)
	var was := bool(_keys_down.get(key, false))
	_keys_down[key] = down
	return down and not was
