class_name MovementStaminaDebugLog
extends RefCounted

# Log di diagnostica TEMPORANEO per la stamina del movimento (2026-09-19, richiesta utente) — dietro
# DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS (default false), limitato a UN SOLO individuo
# (DebugLogging.MOVEMENT_STAMINA_LOG_INDIVIDUAL_ID). Serve a verificare il moltiplicatore di stamina
# del terreno (MovementTerrainService): quale microcella viene attraversata, che moltiplicatore
# viene applicato, quanto costa la quota base e quanto carico+utensili.
#
# Aggrega PER MICROCELLA ATTRAVERSATA, non per frame: record() accumula distanza e costi finché la
# microcella (individual.terrain_cache_key, aggiornata da advance_movement a fine passo) resta la
# stessa, e stampa UNA riga quando cambia — più una riga finale da flush() quando lo step di
# movimento si conclude (WalkAction/RunAction.on_complete). Un'interruzione senza on_complete lascia
# l'ultima microcella non stampata finché lo stesso individuo non registra un nuovo costo.
# Nessun effetto sulla simulazione: solo print.

# individual.id -> {"key": Vector4i, "action": String, "distance": float, "terrain": float,
# "base": float, "extra": float}
static var _accumulators: Dictionary = {}


static func _is_tracked(individual: Variant) -> bool:
	return DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS \
		and int(individual.id) == DebugLogging.MOVEMENT_STAMINA_LOG_INDIVIDUAL_ID


# `base_per_microcell` = quota base per microcella PRIMA del moltiplicatore del terreno (Walk: la
# costante base, Run: base × RUN_INTENSITY_MULTIPLIER); `extra_per_microcell` = carico + utensili
# (mai scalati dal terreno). Chiamata dopo aver calcolato `distance` percorsa in questo frame.
static func record(
	individual: Variant, action_label: String, distance: float, terrain_multiplier: float,
	base_per_microcell: float, extra_per_microcell: float
) -> void:
	if not _is_tracked(individual):
		return
	var key: Vector4i = individual.terrain_cache_key
	var accumulator: Dictionary = _accumulators.get(int(individual.id), {})
	if not accumulator.is_empty() and accumulator["key"] != key:
		_print_accumulator(int(individual.id), accumulator)
		accumulator = {}
	if accumulator.is_empty():
		accumulator = {"key": key, "action": action_label, "distance": 0.0, "terrain": terrain_multiplier, "base": 0.0, "extra": 0.0}
	accumulator["distance"] += distance
	accumulator["terrain"] = terrain_multiplier
	accumulator["base"] += distance * base_per_microcell * terrain_multiplier
	accumulator["extra"] += distance * extra_per_microcell
	_accumulators[int(individual.id)] = accumulator


# Stampa e azzera l'accumulo dell'individuo (se tracciato e non vuoto).
static func flush(individual: Variant) -> void:
	if not _is_tracked(individual):
		return
	var accumulator: Dictionary = _accumulators.get(int(individual.id), {})
	if accumulator.is_empty():
		return
	_print_accumulator(int(individual.id), accumulator)
	_accumulators.erase(int(individual.id))


static func _print_accumulator(individual_id: int, accumulator: Dictionary) -> void:
	var key: Vector4i = accumulator["key"]
	print("[MOVE STAMINA DEBUG] #%d %s macro=(%d,%d) micro=(%d,%d) dist=%.3f terreno=x%.3f base=%.3f carico+utensili=%.3f totale=%.3f" % [
		individual_id, accumulator["action"], key.x, key.y, key.z, key.w, accumulator["distance"], accumulator["terrain"],
		accumulator["base"], accumulator["extra"], float(accumulator["base"]) + float(accumulator["extra"])
	])
