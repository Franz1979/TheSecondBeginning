class_name PredationService
extends RefCounted

# Meccanismo di caccia dei branchi di predatori (Step 3 del piano predatori) — strutturalmente
# diverso da AnimalConsumptionService: qui il "fabbisogno" non viene coperto da uno stock in
# MacroCellState, ma decrementando direttamente l'age-band di un altro PopulationGroup (la preda).
# Gira una volta al giorno per ogni gruppo con PredatorRules (vedi apply_daily_predation, il punto
# di ingresso), indipendentemente da AnimalConsumptionService/AnimalHungerService (quelle restano
# per gli erbivori, invariate). Nessun dato concreto di specie predatrice esiste ancora (wolf.tres
# arriva allo Step 7): questo service è scritto per funzionare in astratto per qualunque
# PredatorRules, inclusi valori di default/non ancora tarati (vedi guard su
# max_pack_hunting_efficiency sotto).

# Malus applicato al peso di selezione (Livello 1, vedi _gather_prey_candidates) di una specie già
# bersaglio di un tentativo — riuscito O fallito — in un tentativo precedente OGGI STESSO: scoraggia
# senza vietare (una specie molto conveniente può comunque essere ripescata, solo con probabilità
# ridotta), evita che il branco si concentri sempre sull'unica specie più conveniente ignorando le
# altre disponibili nella stessa finestra. Percentuale placeholder (-30%), da tarare in gioco.
const SPECIES_TARGET_MALUS_MULTIPLIER := 0.7

# "prey_calories(specie) × 5" della formula di max_catturabili (punto 4d): un singolo tentativo di
# caccia non può mai fruttare più di questo multiplo del fabbisogno calorico odierno del branco in
# individui di una specie — evita catture abnormi quando il fabbisogno residuo è enorme (branco
# molto affamato) e prey_calories è piccolo (preda minuta). Placeholder, da tarare in gioco.
const MAX_CATCH_CALORIE_MULTIPLIER := 5.0

const _AGE_BANDS: Array[GameTypes.AgeBand] = [
	GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD
]


# Punto di ingresso, chiamato una volta al giorno (vedi WorldTimeService) per OGNI gruppo con
# PredatorRules — group.population <= 0 è già escluso da World.remove_extinct_population_groups a
# fine giornata precedente, il controllo qui è comunque esplicito, stesso stile difensivo di
# AnimalConsumptionService.apply_daily_consumption. rules is PredatorRules (non solo AnimalRules)
# distingue i branchi predatori dagli erbivori: il polimorfismo del loader (vedi PredatorRules.gd)
# garantisce che il downcast sia sempre valido quando il controllo passa.
func apply_daily_predation(world: World) -> void:
	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if not (rules is PredatorRules):
			continue
		_process_group(world, group, rules as PredatorRules)


# Orchestrazione giornaliera per UN branco: punto 1 (gate calorico) -> eventuali tentativi di
# caccia (punti 2-4) -> punto 5 (bookkeeping finale) -> pattugliamento SEMPRE, indipendentemente
# dall'esito della caccia di oggi (anche se il gate del punto 1 esclude la caccia, o se
# max_pack_hunting_efficiency/patrol_route non sono ancora popolati — vedi guard sotto).
func _process_group(world: World, group: PopulationGroup, rules: PredatorRules) -> void:
	# Punto 1: "Il fabbisogno di oggi per un branco (hunts_in_pack = true) è la somma del
	# fabbisogno individuale × popolazione totale del gruppo" — flat, NON age-weighted (a
	# differenza di AnimalConsumptionService._get_total_daily_requirement per gli erbivori): scelta
	# esplicita della specifica di questo step, non un'omissione. hunts_in_pack stesso resta
	# dichiarato ma DORMIENTE qui: nessuna variante "caccia solitaria" è specificata in questo step,
	# quindi non è implementata — stesso trattamento già riservato ad altri campi non ancora
	# consumati in questo codebase (es. max_density_per_cell per i predatori).
	var daily_requirement_today: float = rules.daily_caloric_requirement * float(group.population)
	var residual_requirement: float = (
		daily_requirement_today + group.predation_calorie_debt - group.predation_surplus_carryover
	)

	var calories_obtained_today := 0.0

	# Guard su max_pack_hunting_efficiency <= 0.0: evita la divisione per zero nel calcolo di
	# successo al punto 4c per una specie non ancora tarata (default 0.0, "Nessun default forzato"
	# — vedi PredatorRules.gd). Con efficacia_branco = min(qualcosa, 0.0) = 0.0 in ogni caso normale
	# (i pesi di hunting_efficiency_by_age sono sempre >= 0), tentativi_totali sarebbe comunque 0 —
	# questo guard lo rende esplicito e sicuro anche contro un'eventuale configurazione anomala,
	# invece di fare affidamento implicito su quella coincidenza aritmetica.
	if residual_requirement > 0.0 and rules.max_pack_hunting_efficiency > 0.0 and not group.patrol_route.is_empty():
		var pack_efficiency := _compute_pack_efficiency(group, rules)
		# Punto 3: tentativi_totali = round(efficacia_branco / 2) — round() letterale come da
		# formula (non SimulationMath.stochastic_round: la specifica di questo step usa
		# esplicitamente round(), scelta rispettata senza sostituzioni silenziose).
		var attempt_count: int = int(round(pack_efficiency / 2.0))
		if attempt_count > 0:
			calories_obtained_today = _run_hunting_attempts(
				world, group, rules, pack_efficiency, attempt_count, daily_requirement_today
			)
		# Se attempt_count == 0 ("branco troppo debole"): nessuna caccia, calories_obtained_today
		# resta 0.0 — stessa uscita del gate sopra, il bookkeeping sotto gira comunque.

	_apply_calorie_bookkeeping(group, daily_requirement_today, calories_obtained_today)

	# Il pattugliamento avanza SEMPRE, indipendentemente dall'esito della caccia di oggi — vedi
	# PredatorPatrolService.advance_patrol. Va DOPO l'uso di group.patrol_route/patrol_index sopra
	# (la finestra di oggi, letta da _run_hunting_attempts, deve restare quella di OGGI per tutta la
	# durata dei tentativi odierni; avanzare prima l'avrebbe already spostata a domani).
	PredatorPatrolService.new().advance_patrol(group)


# Punto 2: efficacia_branco = min(Σ hunting_efficiency_by_age[età] × popolazione(gruppo, età),
# max_pack_hunting_efficiency). Popolazione del PREDATORE stesso (non della preda) per fascia d'età
# — se il branco non traccia età (age_composition vuota) ogni get_age_count ritorna 0, quindi il
# risultato è 0 e la caccia si disattiva da sola, nessun ramo speciale necessario.
func _compute_pack_efficiency(group: PopulationGroup, rules: PredatorRules) -> float:
	var total := 0.0
	for age_band in _AGE_BANDS:
		total += float(rules.hunting_efficiency_by_age[age_band]) * float(group.get_age_count(age_band))
	return min(total, rules.max_pack_hunting_efficiency)


# Punto 4, l'intero ciclo di tentativi per la finestra di OGGI (group.patrol_route[patrol_index],
# fissa per tutta la durata di questa funzione). malus_species traccia le specie già bersagliate
# oggi (riuscite o fallite) — dizionario locale a questa singola chiamata, quindi si "resetta" da
# solo ogni giorno per costruzione (mai persistito su group).
func _run_hunting_attempts(
	world: World, group: PopulationGroup, rules: PredatorRules, pack_efficiency: float, attempt_count: int,
	daily_requirement_today: float
) -> float:
	var anchor: Vector2i = group.patrol_route[group.patrol_index]
	var window_size: int = rules.hunting_window_size
	var calories_obtained := 0.0
	var malus_species: Dictionary = {}

	for attempt_number in range(1, attempt_count + 1):
		# Punto 4c, moltiplicatore_stanchezza: 1.0 al primo tentativo, decresce linearmente fino a
		# 0.5 all'ultimo — formula valida solo per attempt_count > 1 (altrimenti divisione per
		# zero), 1.0 fisso altrimenti come da specifica.
		var fatigue_multiplier := 1.0
		if attempt_count > 1:
			fatigue_multiplier = 1.0 - 0.5 * float(attempt_number - 1) / float(attempt_count - 1)

		# 4a: candidati ricalcolati AD OGNI TENTATIVO (non una volta sola per giorno) — una cattura
		# riuscita in un tentativo precedente ha già decrementato la popolazione della preda, quindi
		# la disponibilità reale per i tentativi successivi è diversa da quella di inizio giornata.
		var candidates := _gather_prey_candidates(world, rules, anchor, window_size, malus_species)
		if candidates.is_empty():
			continue # "nessuna preda disponibile nella finestra oggi" -> tentativo fallito

		var selection_weights: Array[float] = []
		for candidate in candidates:
			selection_weights.append(float(candidate["selection_weight"]))
		var species_index := _weighted_random_index(selection_weights)
		if species_index < 0:
			continue
		var chosen: Dictionary = candidates[species_index]
		# Il malus vale per il resto della giornata a prescindere dall'esito di QUESTO tentativo
		# (successo o fallimento, vedi 4c/4e) — marcato subito dopo la selezione, non dopo il tiro
		# di successo sotto: la specie è comunque stata "bersagliata" nel momento in cui è stata
		# scelta, indipendentemente da come va a finire.
		malus_species[chosen["species_name"]] = true

		# 4b: selezione età vittima pesata per mortality_share_by_age della PREDA (young/old più
		# probabili di adult, secondo il pattern già tarato per ciascuna specie) — gated alle sole
		# fasce con popolazione > 0 nella finestra dentro _select_victim_age_band.
		var chosen_age := _select_victim_age_band(chosen)
		if chosen_age < 0:
			continue # difensivo: non dovrebbe accadere, "convenience > 0" implica popolazione > 0 in almeno una fascia

		# 4c: successo = prey_compatibility × (efficacia_branco / max_pack_hunting_efficiency) ×
		# moltiplicatore_stanchezza. Clampato a [0,1] solo per sicurezza contro una compatibilità
		# > 1 in .tres futuri malconfigurati — non altera il risultato per dati ben tarati, dato che
		# il rapporto efficacia/max è già <= 1 per costruzione (efficacia_branco è clampata al
		# punto 2) e fatigue_multiplier <= 1.0 per costruzione.
		var success_probability: float = clamp(
			float(chosen["compatibility"]) * (pack_efficiency / rules.max_pack_hunting_efficiency) * fatigue_multiplier,
			0.0, 1.0
		)
		if randf() >= success_probability:
			continue # 4e: fallimento, nessun decremento, nessuna caloria

		# 4d: successo — cattura effettiva.
		calories_obtained += _capture_prey(chosen, chosen_age, daily_requirement_today)

	return calories_obtained


# Livello 2 (punto 4b): ritorna l'AgeBand scelta, o -1 se nessuna fascia ha peso > 0 (difensivo,
# vedi commento al punto di chiamata). Peso = mortality_share_by_age della PREDA, azzerato per le
# fasce senza popolazione disponibile nella finestra di oggi (non si può scegliere come vittima una
# fascia che non è fisicamente presente, indipendentemente da quanto la specie sia "vulnerabile" lì
# per dato di specie).
func _select_victim_age_band(chosen: Dictionary) -> int:
	var prey_rules: AnimalRules = chosen["prey_rules"]
	var age_totals: Dictionary = chosen["age_totals"]

	var weights: Array[float] = []
	for age_band in _AGE_BANDS:
		var share: float = float(prey_rules.mortality_share_by_age[age_band])
		if int(age_totals[age_band]) <= 0:
			share = 0.0
		weights.append(share)

	var index := _weighted_random_index(weights)
	if index < 0:
		return -1
	return _AGE_BANDS[index]


# Punto 4d: quantità catturata + applicazione della perdita al gruppo preda + calcolo delle
# calorie ottenute. Scelta NON specificata esplicitamente dalla formula originale (che parla di
# "il gruppo preda" al singolare): se più PopulationGroup della stessa specie si sovrappongono alla
# finestra di oggi, la cattura sceglie TRA LORO con selezione random pesata sulla rispettiva
# popolazione della fascia scelta presente nella finestra — stesso principio probabilistico già
# usato per specie/età sopra, non un "prendi sempre dal gruppo più numeroso" deterministico.
func _capture_prey(chosen: Dictionary, chosen_age: int, daily_requirement_today: float) -> float:
	var prey_rules: AnimalRules = chosen["prey_rules"]

	var eligible_groups: Array[PopulationGroup] = []
	var group_weights: Array[float] = []
	for entry in chosen["groups"]:
		var count: int = int(entry["age_totals"][chosen_age])
		if count > 0:
			eligible_groups.append(entry["group"])
			group_weights.append(float(count))

	var group_index := _weighted_random_index(group_weights)
	if group_index < 0:
		return 0.0 # difensivo: non dovrebbe accadere se chosen_age è stato validato sopra

	var target_group: PopulationGroup = eligible_groups[group_index]
	# Tetto = popolazione ATTRIBUITA ALLA FINESTRA per QUESTO gruppo specifico, non il totale
	# dell'intero territorio del gruppo (che può estendersi ben oltre la finestra pattugliata
	# oggi) — non si può catturare più di quanto sia plausibilmente presente nella zona
	# effettivamente battuta oggi. apply_predation_loss sotto applica comunque un secondo clamp
	# (contro la popolazione REALE totale della fascia) come rete di sicurezza puramente difensiva,
	# mai il vincolo vincolante dato questo primo tetto già più stretto.
	var window_count: int = int(group_weights[group_index])

	var prey_calories: float = prey_rules.prey_calories
	var max_catturabili: int = max(1, int(floor(daily_requirement_today / (prey_calories * MAX_CATCH_CALORIE_MULTIPLIER))))
	# Distribuzione più semplice da implementare tra quelle possibili, come richiesto: uniforme su
	# [1, max_catturabili], nessuna ponderazione verso il basso.
	var quantity: int = randi_range(1, max_catturabili)
	quantity = min(quantity, window_count)

	var removed := target_group.apply_predation_loss(chosen_age, quantity)
	if removed <= 0:
		return 0.0

	return float(removed) * prey_calories * float(prey_rules.size_multiplier_by_age[chosen_age])


# Livello 1 (punto 4a): raccoglie, per ogni specie in prey_compatibility con compatibilità > 0 e
# ALMENO un individuo presente nella finestra di oggi, la convenienza e i dati necessari ai livelli
# successivi. Nessun indice spaziale: scan lineare di world.population_groups per ogni specie preda
# (vedi nota di performance nel report) — accettabile alla scala attuale (poche specie preda per
# branco, poche decine di gruppi totali, pochi tentativi al giorno).
func _gather_prey_candidates(
	world: World, rules: PredatorRules, anchor: Vector2i, window_size: int, malus_species: Dictionary
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	for prey_species_name in rules.prey_compatibility.keys():
		var compatibility: float = float(rules.prey_compatibility[prey_species_name])
		if compatibility <= 0.0:
			continue

		var prey_rules := AnimalCalculator.get_animal_rules(prey_species_name)
		if prey_rules == null:
			continue

		var species_age_totals: Dictionary = {
			GameTypes.AgeBand.YOUNG: 0, GameTypes.AgeBand.ADULT: 0, GameTypes.AgeBand.OLD: 0,
		}
		var groups_in_window: Array[Dictionary] = []

		for prey_group in world.population_groups:
			if prey_group.species_name != prey_species_name or prey_group.population <= 0:
				continue
			var age_totals_in_window := _collect_prey_age_totals_in_window(prey_group, anchor, window_size)
			var group_total := 0
			for age_band in age_totals_in_window.keys():
				group_total += int(age_totals_in_window[age_band])
			if group_total <= 0:
				continue
			groups_in_window.append({"group": prey_group, "age_totals": age_totals_in_window})
			for age_band in age_totals_in_window.keys():
				species_age_totals[age_band] = int(species_age_totals[age_band]) + int(age_totals_in_window[age_band])

		if groups_in_window.is_empty():
			continue

		# convenienza(specie) = prey_compatibility × Σ [prey_calories × size_multiplier_by_age[età]
		# × popolazione(specie, età)] — popolazione qui è già ristretta alla sola finestra di oggi
		# (species_age_totals sopra), non l'intera popolazione della specie sulla mappa.
		var convenience := 0.0
		for age_band in species_age_totals.keys():
			convenience += (
				prey_rules.prey_calories
				* float(prey_rules.size_multiplier_by_age[age_band])
				* float(species_age_totals[age_band])
			)
		convenience *= compatibility
		if convenience <= 0.0:
			continue

		var malus: float = SPECIES_TARGET_MALUS_MULTIPLIER if malus_species.has(prey_species_name) else 1.0

		candidates.append({
			"species_name": prey_species_name,
			"compatibility": compatibility,
			"prey_rules": prey_rules,
			"age_totals": species_age_totals,
			"groups": groups_in_window,
			"convenience": convenience,
			"selection_weight": convenience * malus,
		})

	return candidates


# Popolazione per fascia d'età di UN gruppo preda, ristretta alle sole celle del suo territorio che
# ricadono dentro la finestra di oggi — riusa PopulationGroup.get_age_composition_in_cell (già
# esistente, pensato per la UI/rendering: distribuisce proporzionalmente perché il modello non
# traccia età per cella, solo a livello di gruppo). Riuso deliberato di un dato approssimato: è
# comunque l'unica stima di "quanti individui di che età sono FISICAMENTE in questa zona" già
# disponibile nel codebase, non ne esiste una più precisa.
func _collect_prey_age_totals_in_window(group: PopulationGroup, anchor: Vector2i, window_size: int) -> Dictionary:
	var totals: Dictionary = {
		GameTypes.AgeBand.YOUNG: 0, GameTypes.AgeBand.ADULT: 0, GameTypes.AgeBand.OLD: 0,
	}
	if group.territory == null:
		return totals

	for coords in group.territory.occupied_macrocells:
		if not _cell_in_window(coords, anchor, window_size):
			continue
		var cell_ages := group.get_age_composition_in_cell(coords)
		for age_band in cell_ages.keys():
			totals[age_band] = int(totals[age_band]) + int(cell_ages[age_band])

	return totals


func _cell_in_window(coords: Vector2i, anchor: Vector2i, window_size: int) -> bool:
	return (
		coords.x >= anchor.x and coords.x < anchor.x + window_size
		and coords.y >= anchor.y and coords.y < anchor.y + window_size
	)


# Punto 5: bookkeeping calorico finale. Formulazione a "pool netto" invece dei due passi separati
# della specifica ("copre prima il debito pregresso, poi il fabbisogno di oggi") — matematicamente
# equivalente: pagare due importi (debito, poi fabbisogno) da un'unica somma disponibile produce
# esattamente lo stesso debito residuo/surplus finale che nettare debito+fabbisogno contro
# carryover+catturato in un colpo solo, dato che qui non c'è alcuna conseguenza diversa legata a
# QUALE dei due importi viene coperto per primo (nessun interesse, nessuna priorità con effetti
# collaterali propri) — è solo un'unica sottrazione riorganizzata. net = disponibile - dovuto:
#   net >= 0 -> debito azzerato, metà di net riportata a domani (l'altra metà persa, come da
#     specifica "se avanza surplus... metà si riporta, l'altra metà si perde").
#   net < 0  -> nessun surplus, -net diventa il nuovo debito pregresso per domani ("il residuo non
#     coperto si accumula come nuovo debito pregresso").
# Gira SEMPRE, anche con calories_obtained_today == 0.0 (nessuna caccia oggi, per gate al punto 1 o
# 3): in quel caso il surplus di ieri (predation_surplus_carryover, non ancora "consumato" da
# nessun'altra scrittura prima di qui) copre da solo quanto può, esattamente come se fosse la sola
# fonte di calorie disponibili oggi — nessun ramo speciale necessario.
func _apply_calorie_bookkeeping(
	group: PopulationGroup, daily_requirement_today: float, calories_obtained_today: float
) -> void:
	var available: float = group.predation_surplus_carryover + calories_obtained_today
	var owed: float = group.predation_calorie_debt + daily_requirement_today
	var net: float = available - owed

	if net >= 0.0:
		group.predation_calorie_debt = 0.0
		group.predation_surplus_carryover = net * 0.5
	else:
		group.predation_calorie_debt = -net
		group.predation_surplus_carryover = 0.0


# Selezione random pesata generica (usata per specie, età, gruppo-istanza — Livelli 1/2 e scelta
# del gruppo in _capture_prey): ritorna l'indice scelto con probabilità proporzionale al peso, o -1
# se il peso totale è <= 0 (nessun candidato valido, mai un candidato scelto a peso zero).
func _weighted_random_index(weights: Array[float]) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1

	var roll: float = randf() * total
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return weights.size() - 1 # difesa da arrotondamento in virgola mobile sull'ultimo elemento
