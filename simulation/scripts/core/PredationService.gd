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

# Malus di selezione preda (repeat_target_malus), soglia di tentativi (attempts_per_efficiency) e
# stanchezza minima (fatigue_floor) sono tutti campi di PredatorRules (stesso refactor già fatto
# per i parametri di movimento cluster rabbit/deer) — non più costanti qui, vedi PredatorRules.gd
# per i default. Il tetto di cattura multipla (vedi _capture_prey) non ha invece un campo dedicato:
# il suo divisore è attempt_count, già calcolato in questo stesso service, non un dato di specie.

const _AGE_BANDS: Array[GameTypes.AgeBand] = [
	GameTypes.AgeBand.YOUNG, GameTypes.AgeBand.ADULT, GameTypes.AgeBand.OLD
]


# Punto di ingresso, chiamato una volta al giorno (vedi WorldTimeService) per OGNI gruppo con
# PredatorRules — group.population <= 0 è già escluso da World.remove_extinct_population_groups a
# fine giornata precedente, il controllo qui è comunque esplicito, stesso stile difensivo di
# AnimalConsumptionService.apply_daily_consumption. rules is PredatorRules (non solo AnimalRules)
# distingue i branchi predatori dagli erbivori: il polimorfismo del loader (vedi PredatorRules.gd)
# garantisce che il downcast sia sempre valido quando il controllo passa.
func apply_daily_predation(world: World, year: int, day: int) -> void:
	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if not (rules is PredatorRules):
			continue
		_process_group(world, group, rules as PredatorRules, year, day)


# Orchestrazione giornaliera per UN branco: punto 1 (gate calorico) -> eventuali tentativi di
# caccia (punti 2-4) -> punto 5 (bookkeeping finale) -> pattugliamento SEMPRE, indipendentemente
# dall'esito della caccia di oggi (anche se il gate del punto 1 esclude la caccia, o se
# max_pack_hunting_efficiency/patrol_route non sono ancora popolati — vedi guard sotto).
func _process_group(world: World, group: PopulationGroup, rules: PredatorRules, year: int, day: int) -> void:
	# Punto 1: fabbisogno di oggi per un branco (hunts_in_pack = true) pesato per età — riusa
	# AnimalRules.caloric_multiplier_by_age, lo stesso campo/pattern già usato per gli erbivori
	# (vedi AnimalConsumptionService._get_total_daily_requirement), qui applicato incondizionatamente
	# (nessun guard su track_age_bands: i branchi predatori tracciano sempre l'età per costruzione,
	# vedi _compute_raw_pack_efficiency sotto, che legge group.get_age_count senza quel guard). Un
	# branco con molti giovani costa quindi meno di uno di soli adulti, non più un flat
	# daily_caloric_requirement × population indipendente dalla composizione. hunts_in_pack stesso
	# resta dichiarato ma DORMIENTE qui: nessuna variante "caccia solitaria" è specificata in questo
	# step, quindi non è implementata — stesso trattamento già riservato ad altri campi non ancora
	# consumati in questo codebase (es. max_density_per_cell per i predatori).
	var daily_requirement_today: float = _compute_daily_requirement(group, rules)
	var residual_requirement: float = (
		daily_requirement_today + group.predation_calorie_debt - group.predation_surplus_carryover
	)

	# Log di apertura giornata (stesso stile/gate di [ANIMAL HUNGER] — vedi AnimalHungerService)
	# incondizionato (non solo sui giorni "eventful"): a differenza della fame erbivora, qui il
	# meccanismo è nuovo e ancora da validare in gioco, quindi ogni giorno processato per un
	# gruppo predatore produce una riga, silenzio compreso.
	if DebugLogging.ENABLED:
		# Finestra di caccia di OGGI (group.patrol_route[patrol_index], la stessa che
		# _run_hunting_attempts leggerà più sotto se la caccia parte) — loggata qui, PRIMA di
		# PredatorPatrolService.advance_patrol a fine funzione, così riflette sempre dove il branco
		# sta pattugliando oggi, non dove si sposterà domani. Guard su patrol_route vuoto (branco
		# appena creato dallo strumento di debug senza territorio, o territorio con BFS esaurita a
		# 0 celle raggiungibili): nessun anchor da mostrare in quel caso.
		var window_info := "nessuna (patrol_route vuoto)"
		if not group.patrol_route.is_empty():
			var window_anchor: Vector2i = group.patrol_route[group.patrol_index]
			window_info = "anchor=(%d,%d) size=%dx%d" % [
				window_anchor.x, window_anchor.y, rules.hunting_window_size, rules.hunting_window_size
			]
		print(
			(
				"[PREDATION] #%d %s pop=%d fabbisogno_oggi=%.1f debito_pregresso=%.1f surplus_pregresso=%.1f "
				+ "residuo=%.1f finestra_oggi=%s"
			) % [
				group.id, group.species_name, group.population,
				daily_requirement_today, group.predation_calorie_debt, group.predation_surplus_carryover,
				residual_requirement, window_info
			]
		)

	var calories_obtained_today := 0.0
	# Catture di oggi per specie (species_name -> {"quantity": int, "calories": float}), popolato
	# da _capture_prey via _run_hunting_attempts — passato per riferimento (Dictionary in GDScript
	# è sempre by-reference) così ogni cattura riuscita si accumula direttamente qui senza dover
	# ricostruire il totale a valle. Resta vuoto se il branco non caccia affatto oggi (gate sotto
	# non entra, o nessun tentativo va a segno) — _record_hunt_log in fondo lo registra comunque,
	# anche vuoto: la tab Fauna 3 mostra "nessuna cattura" per quel giorno invece di un buco nella
	# finestra degli ultimi 5 giorni.
	var captures_today: Dictionary = {}

	# Guard su max_pack_hunting_efficiency <= 0.0: evita la divisione per zero nel calcolo di
	# successo al punto 4c per una specie non ancora tarata (default 0.0, "Nessun default forzato"
	# — vedi PredatorRules.gd). Con max_pack_hunting_efficiency a 0.0, attempts_efficiency =
	# min(qualcosa, 0.0) = 0.0 in ogni caso normale (i pesi di hunting_efficiency_by_age sono
	# sempre >= 0), quindi tentativi_totali sarebbe comunque 0 — questo guard lo rende esplicito e
	# sicuro anche contro un'eventuale configurazione anomala, invece di fare affidamento implicito
	# su quella coincidenza aritmetica.
	if residual_requirement > 0.0 and rules.max_pack_hunting_efficiency > 0.0 and not group.patrol_route.is_empty():
		var pack_efficiency := _compute_raw_pack_efficiency(group, rules)
		# Punto 3: tentativi_totali = round(min(efficacia_branco_grezza, max_pack_hunting_efficiency)
		# / attempts_per_efficiency) — il tetto si applica SOLO qui, non più a pack_efficiency stessa
		# (vedi _compute_raw_pack_efficiency): un branco sopra soglia resta fermo a
		# max_pack_hunting_efficiency ai fini del NUMERO di tentativi, ma pack_efficiency (grezza)
		# passata sotto a _run_hunting_attempts continua a scalare per la probabilità di successo.
		# round() letterale come da formula (non SimulationMath.stochastic_round: la specifica di
		# questo step usa esplicitamente round(), scelta rispettata senza sostituzioni silenziose).
		var attempts_efficiency: float = min(pack_efficiency, rules.max_pack_hunting_efficiency)
		var attempt_count: int = int(round(attempts_efficiency / rules.attempts_per_efficiency))
		if DebugLogging.ENABLED:
			print(
				"[PREDATION] #%d efficacia_branco_grezza=%.2f efficacia_tentativi(cappata)=%.2f tentativi_totali=%d" % [
					group.id, pack_efficiency, attempts_efficiency, attempt_count
				]
			)
		if attempt_count > 0:
			calories_obtained_today = _run_hunting_attempts(
				world, group, rules, pack_efficiency, attempt_count,
				daily_requirement_today, residual_requirement, captures_today
			)
		elif DebugLogging.ENABLED:
			print("[PREDATION] #%d branco troppo debole per cacciare oggi (tentativi_totali=0)" % group.id)
		# Se attempt_count == 0 ("branco troppo debole"): nessuna caccia, calories_obtained_today
		# resta 0.0 — stessa uscita del gate sopra, il bookkeeping sotto gira comunque.
	elif DebugLogging.ENABLED:
		var skip_reason := "residuo già coperto"
		if residual_requirement > 0.0:
			skip_reason = (
				"max_pack_hunting_efficiency non tarato" if rules.max_pack_hunting_efficiency <= 0.0
				else "patrol_route vuoto (territorio non ancora popolato)"
			)
		print("[PREDATION] #%d nessuna caccia oggi (%s)" % [group.id, skip_reason])

	_apply_calorie_bookkeeping(group, daily_requirement_today, calories_obtained_today)
	_record_hunt_log(group, year, day, captures_today)

	# Consuntivo stagionale per la mitigazione della natalità (vedi PopulationGroup.
	# predation_season_calories_obtained/_required) — somma grezza ogni giorno processato, azzerata
	# da TerritoryDynamicsService al checkpoint di birth_season dopo averla letta.
	group.predation_season_calories_obtained += calories_obtained_today
	group.predation_season_calories_required += daily_requirement_today

	if DebugLogging.ENABLED:
		print(
			"[PREDATION] #%d calorie_ottenute_oggi=%.1f -> debito_nuovo=%.1f surplus_nuovo=%.1f" % [
				group.id, calories_obtained_today, group.predation_calorie_debt, group.predation_surplus_carryover
			]
		)

	_apply_starvation_mortality(group, rules, daily_requirement_today)

	# Il pattugliamento avanza SEMPRE, indipendentemente dall'esito della caccia di oggi — vedi
	# PredatorPatrolService.advance_patrol. Va DOPO l'uso di group.patrol_route/patrol_index sopra
	# (la finestra di oggi, letta da _run_hunting_attempts, deve restare quella di OGGI per tutta la
	# durata dei tentativi odierni; avanzare prima l'avrebbe already spostata a domani).
	PredatorPatrolService.new().advance_patrol(group)


# Registra le catture di OGGI (tab Fauna 3, UI — vedi PopulationGroup.recent_hunt_log/
# yearly_prey_totals) — chiamata SEMPRE, anche con captures_today vuoto (nessuna caccia o nessun
# tentativo andato a segno oggi): "gli ultimi 5 giorni" deve restare una vera finestra di 5 giorni
# CONSECUTIVI, non 5 giorni sparsi in cui è successo qualcosa — un giorno senza catture compare
# comunque come entry con captures={}, la UI lo mostra come "nessuna cattura".
func _record_hunt_log(group: PopulationGroup, year: int, day: int, captures_today: Dictionary) -> void:
	group.recent_hunt_log.append({"year": year, "day": day, "captures": captures_today})
	while group.recent_hunt_log.size() > PopulationGroup.RECENT_HUNT_LOG_MAX_DAYS:
		group.recent_hunt_log.pop_front()

	# Totali dell'ANNO DI CALENDARIO corrente (non rolling, vedi PopulationGroup.yearly_prey_totals):
	# azzerati qui stesso al primo giorno di caccia di un anno nuovo (year != yearly_prey_totals_year),
	# senza bisogno di un hook dedicato al cambio anno in WorldTimeService — questo service gira
	# comunque ogni giorno, quindi il confronto qui è sufficiente e sempre aggiornato.
	if group.yearly_prey_totals_year != year:
		group.yearly_prey_totals = {}
		group.yearly_prey_totals_year = year

	for species_name in captures_today.keys():
		var today_entry: Dictionary = captures_today[species_name]
		var yearly_entry: Dictionary = group.yearly_prey_totals.get(species_name, {"quantity": 0, "calories": 0.0})
		yearly_entry["quantity"] = int(yearly_entry["quantity"]) + int(today_entry["quantity"])
		yearly_entry["calories"] = float(yearly_entry["calories"]) + float(today_entry["calories"])
		group.yearly_prey_totals[species_name] = yearly_entry


# Punto 1: daily_requirement_today = Σ [daily_caloric_requirement × caloric_multiplier_by_age[età]
# × popolazione(gruppo, età)] per young/adult/old — stesso schema di _compute_raw_pack_efficiency
# sotto (somma pesata sulle tre fasce d'età del PREDATORE, non della preda). Se il branco non
# traccia età (age_composition vuota) ogni get_age_count ritorna 0, quindi il fabbisogno risulta 0
# — nessun ramo speciale necessario, stessa scelta già fatta per _compute_raw_pack_efficiency.
func _compute_daily_requirement(group: PopulationGroup, rules: PredatorRules) -> float:
	var weighted_count := 0.0
	for age_band in _AGE_BANDS:
		weighted_count += float(rules.caloric_multiplier_by_age[age_band]) * float(group.get_age_count(age_band))
	return weighted_count * rules.daily_caloric_requirement


# Punto 2: efficacia_branco_grezza = Σ hunting_efficiency_by_age[età] × popolazione(gruppo, età).
# Popolazione del PREDATORE stesso (non della preda) per fascia d'età — se il branco non traccia
# età (age_composition vuota) ogni get_age_count ritorna 0, quindi il risultato è 0 e la caccia si
# disattiva da sola, nessun ramo speciale necessario.
#
# NON più clampata a max_pack_hunting_efficiency qui (a differenza di prima): quel tetto ora si
# applica SOLO al calcolo di attempt_count (vedi _process_group), mai al valore usato da
# success_probability in _run_hunting_attempts — un branco sopra la soglia non guadagna più
# tentativi (fermi al tetto), ma continua a guadagnare probabilità di successo per tentativo
# proporzionale alla sua vera taglia, invece di saturare insieme ai tentativi sullo stesso numero.
# Decisione presa col utente: il fabbisogno calorico (_compute_daily_requirement) non ha mai avuto
# un tetto e scala con la popolazione vera, quindi anche la capacità di procacciarsi cibo deve poter
# continuare a scalare oltre la vecchia soglia, non restare bloccata mentre il fabbisogno cresce.
func _compute_raw_pack_efficiency(group: PopulationGroup, rules: PredatorRules) -> float:
	var total := 0.0
	for age_band in _AGE_BANDS:
		total += float(rules.hunting_efficiency_by_age[age_band]) * float(group.get_age_count(age_band))
	return total


# Punto 4, l'intero ciclo di tentativi per la finestra di OGGI (group.patrol_route[patrol_index],
# fissa per tutta la durata di questa funzione). malus_species traccia le specie già bersagliate
# oggi (riuscite o fallite) — dizionario locale a questa singola chiamata, quindi si "resetta" da
# solo ogni giorno per costruzione (mai persistito su group).
func _run_hunting_attempts(
	world: World, group: PopulationGroup, rules: PredatorRules, pack_efficiency: float, attempt_count: int,
	daily_requirement_today: float, residual_requirement: float, captures_today: Dictionary
) -> float:
	var anchor: Vector2i = group.patrol_route[group.patrol_index]
	var window_size: int = rules.hunting_window_size
	var calories_obtained := 0.0
	var malus_species: Dictionary = {}

	# 4a: candidati raccolti UNA SOLA VOLTA per l'intera giornata (non più ad ogni tentativo) —
	# _capture_prey aggiorna in place (stesso Dictionary, per riferimento: nessuna copia) age_totals/
	# convenience del candidato appena colpito dopo una cattura riuscita, così i tentativi
	# successivi vedono comunque la disponibilità aggiornata senza rifare l'intera scansione di
	# tutte le specie preda × tutti i loro gruppi × territorio di ciascuno (world.population_groups
	# nella sua interezza) — prima ripetuta attempt_count volte per branco, e sommata su tutti i
	# branchi attivi quel giorno.
	var candidates := _gather_prey_candidates(world, rules, anchor, window_size)

	for attempt_number in range(1, attempt_count + 1):
		# Punto 4c, moltiplicatore_stanchezza: 1.0 al primo tentativo, decresce linearmente fino a
		# rules.fatigue_floor all'ultimo — formula valida solo per attempt_count > 1 (altrimenti
		# divisione per zero), 1.0 fisso altrimenti come da specifica.
		var fatigue_multiplier := 1.0
		if attempt_count > 1:
			fatigue_multiplier = 1.0 - (1.0 - rules.fatigue_floor) * float(attempt_number - 1) / float(attempt_count - 1)

		if candidates.is_empty():
			if DebugLogging.ENABLED:
				print(
					"[PREDATION ATTEMPT] #%d tentativo %d/%d: nessuna preda disponibile nella finestra oggi" % [
						group.id, attempt_number, attempt_count
					]
				)
			continue # "nessuna preda disponibile nella finestra oggi" -> tentativo fallito

		# Peso di selezione ricalcolato qui ad ogni tentativo (non più memorizzato dentro
		# candidates, vedi _gather_prey_candidates): convenience cambia con le catture di OGGI
		# (aggiornata in place da _capture_prey), il malus da bersaglio-ripetuto cambia con
		# malus_species sotto — nessuno dei due richiede una nuova scansione del mondo, solo
		# S iterazioni (S = specie preda compatibili, tipicamente una manciata).
		var selection_weights: Array[float] = []
		for candidate in candidates:
			var malus: float = rules.repeat_target_malus if malus_species.has(candidate["species_name"]) else 1.0
			selection_weights.append(float(candidate["convenience"]) * malus)
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

		# 4c: successo = prey_compatibility × (efficacia_branco_grezza / max_pack_hunting_efficiency)
		# × moltiplicatore_stanchezza.
		# A differenza di prima, il rapporto efficacia/max qui NON e' piu' garantito <= 1 per
		# costruzione: pack_efficiency e' la versione grezza, mai clampata (vedi
		# _compute_raw_pack_efficiency) — un branco sopra max_pack_hunting_efficiency ottiene quindi
		# un rapporto > 1, che si traduce in probabilita' di successo piu' alta a parita' di
		# compatibilita'/stanchezza (fino al tetto naturale di 1.0×compatibility). Il clamp [0,1]
		# sotto fa ora lavoro REALE (non piu' solo difensivo contro una compatibilita' > 1
		# malconfigurata in un .tres futuro): e' lui a impedire probabilita' > 1.0 per branchi molto
		# sopra soglia.
		var success_probability: float = clamp(
			float(chosen["compatibility"]) * (pack_efficiency / rules.max_pack_hunting_efficiency) * fatigue_multiplier,
			0.0, 1.0
		)
		var success_roll := randf()
		if success_roll >= success_probability:
			if DebugLogging.ENABLED:
				print(
					(
						"[PREDATION ATTEMPT] #%d tentativo %d/%d: bersaglio=%s età=%s stanchezza=%.2f "
						+ "probabilità=%.2f esito=fallito"
					) % [
						group.id, attempt_number, attempt_count, chosen["species_name"],
						GameTypes.AgeBand.keys()[chosen_age], fatigue_multiplier, success_probability
					]
				)
			continue # 4e: fallimento, nessun decremento, nessuna caloria

		# 4d: successo — cattura effettiva. Il log dell'esito positivo (quantità/calorie/gruppo
		# preda reali) vive dentro _capture_prey, l'unico punto che li conosce già calcolati.
		calories_obtained += _capture_prey(
			chosen, chosen_age, daily_requirement_today, residual_requirement, attempt_count,
			group.id, attempt_number, success_probability, captures_today
		)

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
func _capture_prey(
	chosen: Dictionary, chosen_age: int, daily_requirement_today: float, residual_requirement: float,
	attempt_count: int, predator_group_id: int, attempt_number: int, success_probability: float,
	captures_today: Dictionary
) -> float:
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
	# max_catturabili = round(base_per_calcolo / (prey_calories × size_multiplier_by_age[chosen_age]
	# × attempt_count)) — il denominatore usa il valore calorico REALE della fascia d'età già scelta
	# (chosen_age), non il valore adulto puro: altrimenti il tetto assumerebbe implicitamente che
	# ogni individuo catturato valga prey_calories pieno, mentre le calorie ottenute (vedi il return
	# in fondo a questa funzione) sono già scalate per size_multiplier_by_age — un tetto calcolato su
	# young (multiplier < 1) risulterebbe troppo BASSO rispetto al fabbisogno reale da coprire, uno
	# calcolato su old (multiplier > 1) troppo ALTO; solo su adult (multiplier = 1.0) i due erano già
	# coerenti.
	#
	# base_per_calcolo = max(daily_requirement_today, residual_requirement) — non più il solo
	# fabbisogno flat di oggi: residual_requirement (= daily_requirement_today + debito_pregresso -
	# surplus_pregresso, lo stesso valore già usato dal gate caccia sì/no in _process_group) lascia
	# a un branco indebitato la possibilità reale di recuperare l'arretrato in un giorno fortunato
	# ("surplus killing" — un predatore affamato che trova un'occasione buona ne approfitta a
	# pieno), mentre il max() con daily_requirement_today impedisce al tetto di scendere sotto il
	# fabbisogno normale quando il branco è già quasi sazio (surplus_pregresso piccolo,
	# residual_requirement quindi minore di daily_requirement_today) — altrimenti quel branco non
	# potrebbe mai costruire un surplus più consistente in un giorno buono.
	#
	# Divisore attempt_count (non più una costante di specie, vedi PredatorRules.gd): un branco con
	# più tentativi disponibili ha già più occasioni di catturare, quindi un tetto per-tentativo più
	# basso; un branco con pochi tentativi ha un tetto più alto per compensare. round() (non più
	# ceil()): con un numeratore che può già essere generoso di suo grazie al debito, l'arrotondamento
	# matematico standard (>=0.5 sale, <0.5 scende) è meno sistematicamente ottimista — nessun tetto
	# massimo assoluto imposto qui, il tetto resta libero di crescere con il debito accumulato finché
	# non se ne osserva il comportamento in gioco.
	var age_calories: float = prey_calories * float(prey_rules.size_multiplier_by_age[chosen_age])
	var base_per_calcolo: float = max(daily_requirement_today, residual_requirement)
	# Etichetta per il log di successo sotto (base_calc_source): quale dei due termini del max()
	# ha vinto oggi — "fabbisogno" quando il branco non ha debito/ha già un surplus sufficiente a
	# tenere residual_requirement sotto il fabbisogno flat, "residuo" quando il debito pregresso
	# spinge residual_requirement sopra il fabbisogno di oggi. A parità (>=), vince "fabbisogno" —
	# coerente con max(): a debito zero i due termini coincidono esattamente.
	var base_calc_source := "fabbisogno" if daily_requirement_today >= residual_requirement else "residuo"
	var max_catturabili: int = max(1, int(round(base_per_calcolo / (age_calories * float(attempt_count)))))
	# Distribuzione più semplice da implementare tra quelle possibili, come richiesto: uniforme su
	# [1, max_catturabili], nessuna ponderazione verso il basso.
	var quantity: int = randi_range(1, max_catturabili)
	quantity = min(quantity, window_count)

	var removed := target_group.apply_predation_loss(chosen_age, quantity)
	if removed <= 0:
		# Difensivo (vedi commento a group_index sopra): non dovrebbe accadere se chosen_age è
		# stato validato correttamente a monte, ma se capita va comunque in log invece di sparire
		# silenziosamente come un successo senza calorie.
		if DebugLogging.ENABLED:
			print(
				(
					"[PREDATION ATTEMPT] #%d tentativo %d/%d: bersaglio=%s età=%s probabilità=%.2f "
					+ "esito=fallito (nessun individuo rimosso, difensivo)"
				) % [
					predator_group_id, attempt_number, attempt_count, chosen["species_name"],
					GameTypes.AgeBand.keys()[chosen_age], success_probability
				]
			)
		return 0.0

	var gained: float = float(removed) * prey_calories * float(prey_rules.size_multiplier_by_age[chosen_age])

	# Aggiorna in place age_totals/convenience del candidato appena colpito (vedi
	# _run_hunting_attempts: candidates è raccolto una sola volta a inizio giornata, non più ad
	# ogni tentativo) — chosen e la entry dentro chosen["groups"] sono lo STESSO Dictionary di
	# candidates[i]/groups_in_window[j] (per riferimento, non copie), quindi questa modifica è
	# visibile automaticamente al tentativo successivo senza rifare la scansione di
	# _gather_prey_candidates. convenience ricalcolata da zero (non sottratta incrementalmente)
	# per restare sempre bit-per-bit coerente con la stessa formula usata lì.
	chosen["age_totals"][chosen_age] = int(chosen["age_totals"][chosen_age]) - removed
	for entry in chosen["groups"]:
		if entry["group"] == target_group:
			entry["age_totals"][chosen_age] = int(entry["age_totals"][chosen_age]) - removed
			break
	var updated_convenience := 0.0
	for age_band in chosen["age_totals"].keys():
		updated_convenience += (
			prey_rules.prey_calories
			* float(prey_rules.size_multiplier_by_age[age_band])
			* float(chosen["age_totals"][age_band])
		)
	chosen["convenience"] = updated_convenience * float(chosen["compatibility"])

	# Registra la cattura per la tab Fauna 3 (UI) — species_name della PREDA, non del predatore
	# (chosen["species_name"] è già quello). Un dizionario per specie invece di un semplice totale
	# perché un branco può colpire più specie diverse nella stessa giornata (fino a attempt_count
	# tentativi), e la UI deve poterle elencare separatamente ("2 rabbit, 1 bezoar"), non solo un
	# totale calorico indistinto.
	var species_name: String = chosen["species_name"]
	var species_entry: Dictionary = captures_today.get(species_name, {"quantity": 0, "calories": 0.0})
	species_entry["quantity"] = int(species_entry["quantity"]) + removed
	species_entry["calories"] = float(species_entry["calories"]) + gained
	captures_today[species_name] = species_entry

	if DebugLogging.ENABLED:
		print(
			(
				"[PREDATION ATTEMPT] #%d tentativo %d/%d: bersaglio=%s età=%s probabilità=%.2f "
				+ "esito=successo quantità=%d calorie=%.1f gruppo_preda=#%d base_calc=%.1f (%s) max_catturabili=%d"
			) % [
				predator_group_id, attempt_number, attempt_count, chosen["species_name"],
				GameTypes.AgeBand.keys()[chosen_age], success_probability, removed, gained, target_group.id,
				base_per_calcolo, base_calc_source, max_catturabili
			]
		)
	return gained


# Livello 1 (punto 4a): raccoglie, per ogni specie in prey_compatibility con compatibilità > 0 e
# ALMENO un individuo presente nella finestra di oggi, la convenienza e i dati necessari ai livelli
# successivi. Chiamata UNA SOLA VOLTA per l'intera giornata di caccia di un branco (vedi
# _run_hunting_attempts) — non più ad ogni tentativo: _capture_prey aggiorna in place age_totals/
# convenience del candidato colpito dopo una cattura riuscita, quindi i tentativi successivi
# leggono candidates senza bisogno di rifare questa scansione. Nessun indice spaziale: scan
# lineare di world.population_groups per ogni specie preda — accettabile alla scala attuale (poche
# specie preda per branco, poche decine di gruppi totali), e ora pagato una sola volta al giorno
# invece che una volta per tentativo. Nessun campo "selection_weight" nel risultato: il peso di
# selezione (convenience × eventuale malus da bersaglio-ripetuto) è calcolato al momento dell'uso
# in _run_hunting_attempts, non qui — dipende da malus_species, che è per-tentativo/per-branco, non
# un dato della singola specie preda.
func _gather_prey_candidates(
	world: World, rules: PredatorRules, anchor: Vector2i, window_size: int
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

		candidates.append({
			"species_name": prey_species_name,
			"compatibility": compatibility,
			"prey_rules": prey_rules,
			"age_totals": species_age_totals,
			"groups": groups_in_window,
			"convenience": convenience,
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
#   net >= 0 -> debito azzerato, il 90% di net riportato a domani (SURPLUS_CARRYOVER_RATIO,
#     il restante 10% perso). Non più un dimezzamento (50/50): un branco vive davvero di una
#     cattura grossa fino quasi ad esaurirla prima di ricacciare (comportamento reale dei lupi —
#     scorta consumata quasi per intero, non un "credito" che decade di metà ogni giorno anche
#     nei giorni in cui non caccia), la piccola perdita residua modella solo spreco verso
#     spazzini/decomposizione su catture molto abbondanti che richiedono più giorni per essere
#     consumate.
#   net < 0  -> nessun surplus, -net diventa il nuovo debito pregresso per domani ("il residuo non
#     coperto si accumula come nuovo debito pregresso").
# Gira SEMPRE, anche con calories_obtained_today == 0.0 (nessuna caccia oggi, per gate al punto 1 o
# 3): in quel caso il surplus di ieri (predation_surplus_carryover, non ancora "consumato" da
# nessun'altra scrittura prima di qui) copre da solo quanto può, esattamente come se fosse la sola
# fonte di calorie disponibili oggi — nessun ramo speciale necessario.
const SURPLUS_CARRYOVER_RATIO := 0.9

func _apply_calorie_bookkeeping(
	group: PopulationGroup, daily_requirement_today: float, calories_obtained_today: float
) -> void:
	var available: float = group.predation_surplus_carryover + calories_obtained_today
	var owed: float = group.predation_calorie_debt + daily_requirement_today
	var net: float = available - owed

	if net >= 0.0:
		group.predation_calorie_debt = 0.0
		group.predation_surplus_carryover = net * SURPLUS_CARRYOVER_RATIO
	else:
		group.predation_calorie_debt = -net
		group.predation_surplus_carryover = 0.0


# Mortalità da fame prolungata per i predatori (Step 4, confermato con l'utente) — non il sistema
# a bucket-per-individuo degli erbivori (AnimalHungerService), concettualmente incompatibile con
# un branco che caccia a raffiche e vive di una singola cattura per giorni (il modello di
# debito/surplus sopra esiste apposta per questo): predation_calorie_debt è già un accumulo
# scalare di fabbisogno non coperto, quindi debito/fabbisogno_di_oggi è già un equivalente "giorni
# di fame" senza bisogno di un istogramma separato. Soglia = fabbisogno_di_oggi ×
# rules.max_days_without_food (stesso campo di AnimalRules già usato dagli erbivori, nessun nuovo
# dato) — non tarato per questa specie (<=0, default AnimalRules) significa meccanismo non ancora
# configurato, no-op, stesso principio già usato da AnimalOldAgeMortalityService per
# old_duration_years<=0.
#
# Due mitigazioni (osservate nei test: un branco di 8 lupi si è estinto in due soli checkpoint
# consecutivi, il debito non perdonato dopo il primo round di morti lasciava i sopravvissuti
# fragili quanto prima, e un solo giorno di caccia disastrosa bastava a calcolare più morti degli
# individui rimasti):
#   SEVERITY_DIVISOR ammorbidisce quanti individui "vale" l'eccedenza di debito (divisore più alto
#   = serve più debito accumulato per far morire ciascuno) — la pressione da fame resta reale, solo
#   meno brusca.
#   MAX_POPULATION_SHARE è un tetto assoluto indipendente dal divisore sopra: mai più della metà
#   del branco in UN solo checkpoint, qualunque sia il debito accumulato — rete di sicurezza contro
#   un'estinzione istantanea anche in scenari più estremi di quello osservato, dove il solo
#   divisore non basterebbe.
const STARVATION_MORTALITY_SEVERITY_DIVISOR := 5.0
const STARVATION_MORTALITY_MAX_POPULATION_SHARE := 0.5
func _apply_starvation_mortality(group: PopulationGroup, rules: PredatorRules, daily_requirement_today: float) -> void:
	if rules.max_days_without_food <= 0:
		return
	if group.population <= 0 or daily_requirement_today <= 0.0:
		return

	var threshold: float = daily_requirement_today * float(rules.max_days_without_food)
	var excess_debt: float = group.predation_calorie_debt - threshold
	if excess_debt <= 0.0:
		return

	# Divisore = fabbisogno MEDIO per individuo di oggi (non un valore fisso di specie): l'età
	# incide sul fabbisogno reale (AnimalRules.caloric_multiplier_by_age), quindi un giovane "vale"
	# meno di un adulto nel consumare l'eccedenza di debito — quale fascia muoia davvero lo decide
	# comunque apply_hunger_mortality sotto (pesato per mortality_share_by_age), qui serve solo a
	# stimare QUANTI individui l'eccedenza rappresenta. Moltiplicato per SEVERITY_DIVISOR (vedi
	# sopra) prima di dividere: stessa eccedenza, meno morti calcolati.
	var average_requirement_per_individual: float = daily_requirement_today / float(group.population)
	var raw_deaths: int = int(excess_debt / (average_requirement_per_individual * STARVATION_MORTALITY_SEVERITY_DIVISOR))
	var max_deaths_this_checkpoint: int = int(float(group.population) * STARVATION_MORTALITY_MAX_POPULATION_SHARE)
	var deaths: int = min(raw_deaths, max_deaths_this_checkpoint)
	if deaths <= 0:
		return

	var population_before := group.population
	var debt_before := group.predation_calorie_debt
	# Composizione PRIMA della mortalità, per fascia — apply_hunger_mortality sotto ritorna solo il
	# totale rimosso, non la ripartizione per fascia (funzione condivisa con gli erbivori, mai
	# modificata: nessun bisogno del dettaglio per fascia là). Confrontata con quella DOPO per
	# ricavare morti_per_fascia, necessaria sotto per il cannibalismo (stesso pattern già usato
	# altrove nel codebase, es. AnimalAgeBandService, per lo stesso identico problema).
	var age_before: Dictionary = {
		GameTypes.AgeBand.YOUNG: group.get_age_count(GameTypes.AgeBand.YOUNG),
		GameTypes.AgeBand.ADULT: group.get_age_count(GameTypes.AgeBand.ADULT),
		GameTypes.AgeBand.OLD: group.get_age_count(GameTypes.AgeBand.OLD),
	}
	# Riuso diretto della stessa funzione degli erbivori (PopulationGroup.apply_hunger_mortality):
	# generica per qualunque AnimalRules, distribuisce le morti tra le fasce d'età pesando per
	# rules.mortality_share_by_age (già impostato per il lupo) coi tetti reali di disponibilità per
	# fascia — nessun codice nuovo necessario per decidere CHI muore. Non tocca hunger_buckets
	# (sempre vuoto per i predatori, mai popolato — vedi AnimalHungerService, che li esclude).
	var removed := group.apply_hunger_mortality(deaths, rules)
	if removed <= 0:
		return

	# Storno del debito: ogni individuo "portava" una quota uguale del debito totale
	# (debt_before/population_before, non tracciato per singolo individuo) — chi muore se la porta
	# via, i sopravvissuti mantengono la propria quota proporzionale.
	group.predation_calorie_debt = debt_before * (float(group.population) / float(population_before))

	# Cannibalismo (confermato con l'utente): in carestia estrema il branco si nutre dei propri
	# morti — stessa formula già usata per una cattura di predazione vera (prey_calories ×
	# size_multiplier_by_age[fascia] × conteggio), qui applicata ai morti di QUESTO evento invece
	# che a una preda esterna. Gira DOPO lo storno sopra (prima si toglie ai sopravvissuti la quota
	# di debito dei morti, POI si aggiunge il nutrimento ricavato mangiandoli) — ordine causale, non
	# arbitrario. Riusa la stessa riconciliazione debito/surplus di _apply_calorie_bookkeeping
	# (surplus scontato di SURPLUS_CARRYOVER_RATIO, stessa logica di "parte va persa/deperisce"
	# applicata a qualunque eccedenza calorica in questo service, non solo alla caccia vera).
	var cannibalism_calories := 0.0
	for age_band in age_before.keys():
		var died_this_band: int = int(age_before[age_band]) - group.get_age_count(age_band)
		if died_this_band > 0:
			cannibalism_calories += (
				float(died_this_band) * rules.prey_calories * float(rules.size_multiplier_by_age[age_band])
			)
	if cannibalism_calories > 0.0:
		var net_after_cannibalism: float = cannibalism_calories - group.predation_calorie_debt
		if net_after_cannibalism >= 0.0:
			group.predation_calorie_debt = 0.0
			group.predation_surplus_carryover += net_after_cannibalism * SURPLUS_CARRYOVER_RATIO
		else:
			group.predation_calorie_debt = -net_after_cannibalism

	if DebugLogging.ENABLED:
		print(
			(
				"[PREDATION STARVATION] #%d %s debito=%.1f soglia=%.1f (fabbisogno_oggi=%.1f x %dgg) "
				+ "eccedenza=%.1f MORTI=%d pop %d->%d calorie_cannibalismo=%.1f "
				+ "debito_nuovo=%.1f surplus_nuovo=%.1f"
			) % [
				group.id, group.species_name, debt_before, threshold, daily_requirement_today,
				rules.max_days_without_food, excess_debt, removed, population_before, group.population,
				cannibalism_calories, group.predation_calorie_debt, group.predation_surplus_carryover
			]
		)


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
