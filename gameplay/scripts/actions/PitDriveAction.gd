class_name PitDriveAction
extends Action

# Spinta verso le fosse (2026-11-14, richiesta utente — PitDriveService, lavoro "Spingi verso le fosse" della lista
# Trappole): il Walk prima porta dietro il gruppetto; qui un momento di grida e braccia agitate, poi la mandria parte verso
# la fossa (PitDriveService.drive). Nessun attrezzo; esperienza di caccia come montare e svuotare le trappole (skill "trap").

const SHOUT_DAYS: float = 0.02
const STAMINA_DRAIN_PER_DAY: float = 150.0
const CONTEXT_AREA_ID := "pit_drive_area_id"
const CONTEXT_SPECIES := "pit_drive_species"
const CONTEXT_POSITION := "pit_drive_position"

var _elapsed: float = 0.0


func _init() -> void:
	target = null
	skill_effect_key = TrapService.SKILL_EFFECT_KEY
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(_individual: Variant, _context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(_individual: Variant, _context: Dictionary) -> bool:
	return _elapsed >= SHOUT_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null:
		return
	var started := PitDriveService.drive(game_data, int(context.get(CONTEXT_AREA_ID, 0)), String(context.get(CONTEXT_SPECIES, "")),
		"#%d %s" % [individual.id, individual.name])
	# Grido (2026-11-14, hunt_shout.wav): solo se la mandria è partita.
	if started > 0 and PitDriveService.shout_sound_emitter.is_valid():
		PitDriveService.shout_sound_emitter.call(individual)


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
