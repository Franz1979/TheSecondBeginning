class_name JobBoardTimingService
extends RefCounted

# Fase 0 dell'assegnatore (2026-10-24, docs/progetto_assegnatore_unico_lavori.md): solo misura, nessun effetto sul gioco.
# Con DebugLogging.SHOW_JOB_BOARD_TIMING_LOGS:
#   - una riga [JOB BOARD TIMING] per ogni domanda "c'è un lavoro per lui?" calcolata (non in memoria) che supera
#     SLOW_CALL_MSEC, con chi la fa (caller), il tempo totale e le voci dalla più cara;
#   - una riga di riepilogo al massimo ogni SUMMARY_INTERVAL_MSEC: domande per chiamante (totali / calcolate / ms), liste
#     rifatte o in memoria, picco del fotogramma e ms per voce.
# Le voci fuori da una domanda (cassetto al secondo, svago, punto più vicino) contano nel riepilogo e nel fotogramma.

const SLOW_CALL_MSEC := 2.0
const SUMMARY_INTERVAL_MSEC := 1000
# Voci sotto questa soglia (ms) non compaiono nella riga della singola domanda.
const MIN_SECTION_MSEC := 0.5

# Chi sta facendo la domanda: lo scrive chi chiama job_available_checker / job_taker ("partenza", "arrivo",
# "coordinatore: …"), lo legge begin_call. Solo per il log.
static var caller: String = ""

static var _depth: int = 0
static var _call_start: int = 0
static var _call_text: String = ""
static var _call: Dictionary = {}  # voce -> usec della domanda in corso
static var _call_flags: Array[String] = []
static var _second_start: int = -1
static var _sections: Dictionary = {}  # voce -> usec nel periodo
static var _counts: Dictionary = {}  # contatore -> quante volte nel periodo
static var _callers: Dictionary = {}  # chiamante -> [domande, calcolate, usec]
static var _frame: int = -1
static var _frame_usec: int = 0
static var _frame_peak_usec: int = 0


static func is_enabled() -> bool:
	return DebugLogging.ENABLED and DebugLogging.SHOW_JOB_BOARD_TIMING_LOGS


static func now() -> int:
	return Time.get_ticks_usec()


# Tempo della voce `section` da `since` (now() all'inizio).
static func add(section: String, since: int) -> void:
	var usec := Time.get_ticks_usec() - since
	_sections[section] = int(_sections.get(section, 0)) + usec
	if _depth > 0:
		_call[section] = int(_call.get(section, 0)) + usec
	else:
		_add_frame(usec)
		_flush_if_due()


static func count(counter: String) -> void:
	_counts[counter] = int(_counts.get(counter, 0)) + 1
	if _depth > 0:
		_call_flags.append(counter)


# Una domanda di `caller` (cached = risposta in memoria, non calcolata).
static func count_question(cached: bool) -> void:
	var stats: Array = _callers.get(_caller_name(), [0, 0, 0])
	stats[0] += 1
	if not cached:
		stats[1] += 1
	_callers[_caller_name()] = stats


# Inizio e fine di una domanda calcolata (_takeable_jobs_for); annidate = una sola.
static func begin_call(worker: HumanIndividual) -> void:
	_depth += 1
	if _depth > 1:
		return
	_call.clear()
	_call_flags.clear()
	_call_text = "%s #%d %s" % [_caller_name(), worker.id, worker.name] if worker != null else _caller_name()
	_call_start = Time.get_ticks_usec()


static func end_call() -> void:
	_depth = maxi(_depth - 1, 0)
	if _depth > 0:
		return
	var usec := Time.get_ticks_usec() - _call_start
	var stats: Array = _callers.get(_caller_name(), [0, 0, 0])
	stats[2] += usec
	_callers[_caller_name()] = stats
	_add_frame(usec)
	if usec / 1000.0 >= SLOW_CALL_MSEC:
		print("[JOB BOARD TIMING] %s: %.1f ms%s — %s" % [
			_call_text, usec / 1000.0, (" (%s)" % ", ".join(_call_flags)) if not _call_flags.is_empty() else "",
			_sections_text(_call, MIN_SECTION_MSEC),
		])
	_flush_if_due()


static func _caller_name() -> String:
	return caller if caller != "" else "altro"


static func _add_frame(usec: int) -> void:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_frame_usec = 0
	_frame_usec += usec
	_frame_peak_usec = maxi(_frame_peak_usec, _frame_usec)


static func _sections_text(sections: Dictionary, min_msec: float) -> String:
	var names: Array = sections.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(sections[a]) > int(sections[b]))
	var parts: Array[String] = []
	for section_name in names:
		var msec := int(sections[section_name]) / 1000.0
		if msec >= min_msec:
			parts.append("%s %.1f" % [section_name, msec])
	return ", ".join(parts) if not parts.is_empty() else "nessuna voce sopra %.1f ms" % min_msec


static func _flush_if_due() -> void:
	var now_msec := Time.get_ticks_msec()
	if _second_start < 0:
		_second_start = now_msec
		return
	if now_msec - _second_start < SUMMARY_INTERVAL_MSEC:
		return
	var caller_parts: Array[String] = []
	for caller_name in _callers.keys():
		var stats: Array = _callers[caller_name]
		caller_parts.append("%s %d/%d %.1f ms" % [caller_name, int(stats[0]), int(stats[1]), int(stats[2]) / 1000.0])
	var count_parts: Array[String] = []
	for counter in _counts.keys():
		count_parts.append("%s %d" % [counter, int(_counts[counter])])
	print("[JOB BOARD TIMING] ultimi %.1f s — domande (totali/calcolate): %s; %s; picco del fotogramma %.1f ms; voci (ms): %s" % [
		(now_msec - _second_start) / 1000.0, ", ".join(caller_parts) if not caller_parts.is_empty() else "nessuna",
		", ".join(count_parts) if not count_parts.is_empty() else "nessun conteggio", _frame_peak_usec / 1000.0,
		_sections_text(_sections, 0.1),
	])
	_second_start = now_msec
	_sections.clear()
	_counts.clear()
	_callers.clear()
	_frame_peak_usec = 0
