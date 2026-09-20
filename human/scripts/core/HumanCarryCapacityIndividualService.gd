class_name HumanCarryCapacityIndividualService
extends RefCounted

# Ricalcolo di HumanIndividual.max_carry_capacity per un SINGOLO individuo (2026-09-08, richiesta
# utente) — stesso identico principio/pattern di HumanStaminaIndividualService.
# recalculate_max_stamina: un *Service RefCounted stateless, il chiamante (GameTimeService.
# _on_day_advanced) itera l'intera popolazione, questo service opera su un individuo alla volta.
#
# STESSA SOLUZIONE TEMPORANEA di HumanStaminaIndividualService (richiesta utente, 2026-09-08) —
# ricalcolo PERIODICO (una volta al giorno, incondizionato, per ogni individuo) invece che
# event-driven: nessun cambio di stato che influenzi max_carry_capacity (age_band) ha oggi un
# meccanismo di rilevazione generico nel progetto — vedi il commento di testa a
# HumanStaminaIndividualService per la stessa motivazione strutturale, identica qui.
#
# age_band risolto con le durate EFFETTIVE per l'Era corrente (game_data.era_effective_age_band_
# durations_male/female), MAI human_rules.age_band_durations_male/female direttamente — stesso
# principio già fissato ovunque nel dominio umano (vedi HumanStaminaIndividualService).
#
# Fallback HumanIndividual.FALLBACK_MAX_CARRY_CAPACITY quando la catena source_group_ref->
# folk_ref->human_rules_ref non è risolvibile — stesso criterio di HumanStaminaIndividualService/
# HumanIndividual._resolve_initial_max_carry_capacity (mai un secondo fallback diverso).
#
# Nessun clamp su carried_quantity qui (a differenza del clamp su current_stamina in
# HumanStaminaIndividualService): un max_carry_capacity che scende sotto lo spazio già occupato
# oggi non ha ancora una conseguenza definita (nessun sistema di trasporto/PickUp esiste ancora,
# vedi HumanIndividual.carried_resource_name/carried_quantity) — quando arriverà, la policy
# ("l'eccedenza cade a terra"? "non può più raccogliere finché non scarica"?) andrà decisa da chi
# implementerà quel sistema, non anticipata qui senza un consumatore reale.
static func recalculate_max_carry_capacity(individual: HumanIndividual, game_data: GameData) -> void:
	var human_rules: HumanRules = null
	if individual.source_group_ref != null and individual.source_group_ref.folk_ref != null:
		human_rules = individual.source_group_ref.folk_ref.human_rules_ref
	if human_rules == null:
		individual.max_carry_capacity = HumanIndividual.FALLBACK_MAX_CARRY_CAPACITY
		individual.food_space_capacity = HumanIndividual.FALLBACK_MAX_FOOD_SPACE
		HumanFoodPouchService.on_capacity_recalculated(individual, false)
		_recalculate_body_calories_capacity(individual, HumanIndividual.FALLBACK_MAX_BODY_CALORIES, false)
		return
	var age := float(game_data.year - individual.birth_year_virtual)
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, age
	)
	individual.max_carry_capacity = HumanCalculator.get_max_carry_capacity(
		human_rules, age_band, individual.sex, individual.equipped_tool_count
	)
	# Saccoccia del cibo (2026-09-19, richiesta utente - ricalcolo spostato qui da
	# HumanVitalsIndividualService): stessa eta'/regole gia' risolte sopra, stessa cadenza (creazione,
	# ingresso in scena, ogni giorno). Il massimo (food_space_capacity) non e' persistito.
	individual.food_space_capacity = HumanCalculator.get_max_food_space(human_rules, age_band, individual.sex)
	# Contenuto della saccoccia (riempimento alla prima capacita' vera, poi solo clamp) - vedi
	# HumanFoodPouchService.
	HumanFoodPouchService.on_capacity_recalculated(individual, true)
	# Riserva corporea (2026-09-19, richiesta utente): stesso punto e stessa cadenza del massimo delle
	# provviste, stesso clamp verso il basso.
	_recalculate_body_calories_capacity(
		individual, HumanCalculator.get_max_body_calories(human_rules, age_band, individual.sex), true
	)


# Aggiorna body_calories_capacity e riallinea body_calories (2026-09-19, richiesta utente). `from_rules`:
# true se il massimo viene da HumanRules reali, false se dal fallback. Stessa logica di
# HumanFoodPouchService.on_capacity_recalculated: la PRIMA volta che il massimo vero e' noto
# (body_calories_resolved ancora false: individuo appena creato, o caricato da un salvataggio senza la
# chiave) la riserva riparte piena al massimo vero; da allora in poi solo clamp verso il basso (se il
# massimo cresce la riserva non cambia).
static func _recalculate_body_calories_capacity(individual: HumanIndividual, max_value: float, from_rules: bool) -> void:
	individual.body_calories_capacity = max_value
	if from_rules and not individual.body_calories_resolved:
		individual.body_calories = max_value
		individual.body_calories_resolved = true
		return
	individual.body_calories = minf(individual.body_calories, max_value)
