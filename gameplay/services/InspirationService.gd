class_name InspirationService
extends RefCounted

# Ispirazione (2026-11-14, richiesta utente — più idee man mano che il villaggio evolve): un evento fa nascere un'idea in
# un individuo, che appena libero parte con un daydream (Walk → Think → deposito al Cerchio dei pensieri), come lo svago.
# Parte comune a tutte le fonti: chi può riceverla, il tiro, il flag HumanIndividual.inspired e la partenza del daydream.
# Ogni fonte decide solo la propria probabilità e chi la riceve:
#   - chiacchierata: TalkService.roll_talk_idea (a fine Talk conclusa);
#   - lezione al Ceppo: TeachingRiteService.apply_lesson (all'insegnante).
# Servizio senza stato.


static func log_event(individual: HumanIndividual, text: String) -> void:
	if DebugLogging.ENABLED and DebugLogging.SHOW_INSPIRATION_LOGS and individual != null:
		print("[ISPIRAZIONE] #%d %s: %s" % [individual.id, individual.name, text])


# Un'idea ha senso solo con un Cerchio dei pensieri finito dove depositarla (stesso controllo dello svago).
static func is_possible() -> bool:
	return ThoughtTargetSelectionService.has_thought_accepting_building(GameSettings.active_world)


# Può ricevere un'idea: fascia d'età ammessa dal daydream, nessun pensiero già in attesa di deposito né idea già ricevuta.
static func can_receive(individual: HumanIndividual) -> bool:
	if individual == null or individual.pending_thought or individual.inspired:
		return false
	var definition := TaskDefinitionCache.get_definition(IdleTaskAssignmentService.DAYDREAM_TASK_DEFINITION_PATH)
	if definition == null:
		return false
	if definition.allowed_age_bands.is_empty():
		return true
	var game_data := GameSettings.active_game_data
	if game_data == null:
		return false
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, individual.get_age(game_data.get_absolute_day())
	)
	return definition.allowed_age_bands.has(age_band)


# Tiro con probabilità `chance` (0-1): se riesce, `individual` riceve l'idea. `source` per il log (es. "dalla lezione").
# Il chiamante ha già verificato is_possible e can_receive. Ritorna true se l'idea è nata.
static func try_inspire(individual: HumanIndividual, chance: float, source: String) -> bool:
	var roll := randf()
	if roll >= chance:
		log_event(individual, "nessuna idea %s (tiro %.2f, serviva sotto %.2f)." % [source, roll, chance])
		return false
	individual.inspired = true
	log_event(individual, "è nata un'idea %s (probabilità %.2f): appena libero va a pensarci." % [source, chance])
	return true


# Daydream dell'individuo ispirato (resolve_idle_individual, dopo i bisogni e prima di coda, lavori e svago). true se partito.
static func start_daydream(individual: HumanIndividual, age_band: HumanTypes.AgeBand, world: World) -> bool:
	if not IdleTaskAssignmentService.assign_daydream(individual, age_band, world):
		log_event(individual, "idea persa: il daydream non è potuto partire.")
		return false
	log_event(individual, "parte a pensare all'idea.")
	return true
