class_name TaskCompletionEffectService
extends RefCounted

# Applica gli effetti del COMPLETAMENTO di una Task su skill e parametri vitali dell'individuo
# (2026-09-19, richiesta utente). Sostituisce le due funzioni che stavano in
# HumanIndividualActionService (_apply_task_completion_skill_growth/_apply_task_completion_vital_effects):
# quel servizio parla di singole Action, questo di Task intere. I valori sono nel file dati
# res://gameplay/data/task_completion/task_completion_effects.tres (vedi TaskCompletionEffects per il
# formato). Stateless (RefCounted, static), stesso pattern degli altri service.
#
# Chiamato SOLO da HumanIndividualActionService.finish_current_step, nell'esatto frame in cui la Task
# INTERA termina con successo (garanzia "una volta sola": quella istanza di Task non e' piu'
# raggiungibile da nessuna chiamata futura di apply_action).

const EFFECTS_PATH := "res://gameplay/data/task_completion/task_completion_effects.tres"
const TASK_DEFINITIONS_DIR := "res://gameplay/scripts/tasks/definitions/"

# Cache del file dati (i .tres non cambiano a runtime): stesso principio delle altre cache static.
static var _effects: TaskCompletionEffects = null
static var _effects_loaded: bool = false


static func apply_effects(individual: HumanIndividual, task: Task) -> void:
	var effects := _get_effects()
	if effects == null:
		return
	_apply_skill_effects(individual, task, effects.skill_effects_by_task_name.get(task.task_name, {}))
	_apply_vital_effects(individual, task, effects.vital_effects_by_task_name.get(task.task_name, {}))


# Somma l'incremento a ciascuna property skill_* indicata. Nessun tetto (le skill non hanno ancora un
# massimo enforced, a differenza dei parametri vitali). Property inesistente -> push_warning, saltata.
static func _apply_skill_effects(individual: HumanIndividual, task: Task, skill_effects: Dictionary) -> void:
	for property_name in skill_effects.keys():
		var value_before: Variant = individual.get(property_name)
		if value_before == null:
			push_warning("TaskCompletionEffectService: '%s' non e' una property di HumanIndividual (task '%s')." % [property_name, task.task_name])
			continue
		var value_after: float = float(value_before) + float(skill_effects[property_name])
		individual.set(property_name, value_after)
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[SKILL GROWTH] #%d %s: Task '%s' completata -> %s %.1f -> %.1f" % [
				individual.id, individual.name, task.task_name, property_name, float(value_before), value_after
			])


# Somma il delta a ciascuna property current_* indicata: un delta positivo e' limitato al max_*
# corrispondente (senza mai abbassare un valore gia' sopra il max), il risultato non scende sotto 0.
static func _apply_vital_effects(individual: HumanIndividual, task: Task, vital_effects: Dictionary) -> void:
	for property_name in vital_effects.keys():
		var value_variant: Variant = individual.get(property_name)
		if value_variant == null:
			push_warning("TaskCompletionEffectService: '%s' non e' una property di HumanIndividual (task '%s')." % [property_name, task.task_name])
			continue
		var value_before: float = float(value_variant)
		var delta: float = float(vital_effects[property_name])
		var value_after: float = value_before + delta
		if delta > 0.0:
			var max_value: Variant = individual.get(String(property_name).replace("current_", "max_"))
			if max_value != null:
				value_after = minf(value_after, maxf(float(max_value), value_before))
		value_after = maxf(value_after, 0.0)
		individual.set(property_name, value_after)
		if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_LIFECYCLE_LOGS:
			print("[VITAL EFFECT] #%d %s: Task '%s' completata -> %s %.1f -> %.1f" % [
				individual.id, individual.name, task.task_name, property_name, value_before, value_after
			])


static func _get_effects() -> TaskCompletionEffects:
	if _effects_loaded:
		return _effects
	_effects_loaded = true
	if not ResourceLoader.exists(EFFECTS_PATH):
		push_warning("TaskCompletionEffectService: file dati non trovato: %s" % EFFECTS_PATH)
		return null
	_effects = load(EFFECTS_PATH) as TaskCompletionEffects
	if _effects != null:
		_warn_unknown_task_names(_effects)
	return _effects


# Una sola volta al primo uso: segnala (push_warning) le chiavi dei due Dictionary che non
# corrispondono al task_name di nessuna TaskDefinition in TASK_DEFINITIONS_DIR - un refuso non darebbe
# nessun effetto ne' nessun errore.
static func _warn_unknown_task_names(effects: TaskCompletionEffects) -> void:
	var known_names: Array[String] = []
	var dir := DirAccess.open(TASK_DEFINITIONS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres") and not file_name.begins_with("step_"):
			var definition := load(TASK_DEFINITIONS_DIR + file_name) as TaskDefinition
			if definition != null:
				known_names.append(definition.task_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	for dictionary in [effects.skill_effects_by_task_name, effects.vital_effects_by_task_name]:
		for task_name in dictionary.keys():
			if not known_names.has(String(task_name)):
				push_warning("TaskCompletionEffects: task_name '%s' non corrisponde a nessuna TaskDefinition." % task_name)
