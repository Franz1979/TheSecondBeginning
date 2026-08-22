class_name AnimalHungerService
extends RefCounted

# Mortalità da digiuno prolungato (nuovo meccanismo, indipendente dal checkpoint stagionale di
# birth_season — gira OGNI giorno, come AnimalConsumptionService) applicata alla popolazione
# ESISTENTE di ogni PopulationGroup, mai ai nascituri (quello resta compito di
# AnimalBirthMitigationService). Legge group.daily_caloric_ratio, già calcolato oggi da
# AnimalConsumptionService su TUTTO il territorio del gruppo (mai un dato per singola cella
# isolata) — nessun ricalcolo qui.
#
# Soglia di espansione territoriale DEDICATA e separata da
# AnimalBirthMitigationService.RATIO_HIGH_THRESHOLD (0.8, tarata per il ratio STAGIONALE della
# mitigazione natalità — un contesto diverso): qui qualunque deficit giornaliero, per quanto
# piccolo, deve tentare un'espansione, perché significa che qualcuno nel gruppo sta accumulando
# giorni di digiuno verso la propria soglia di morte — vogliamo agire il prima possibile, non
# aspettare che il deficit sia già ampio.
const DAILY_HUNGER_EXPANSION_THRESHOLD := 1.0
# Tolleranza MINIMA, solo per il rumore di rappresentazione in virgola mobile (somme/divisioni
# concatenate su più celle/fonti in AnimalConsumptionService._consume_group possono restituire
# 0.999999994 invece di esattamente 1.0 anche quando il fabbisogno è coperto per intero) — NON
# serve a mascherare deficit reali: un vero calo stagionale di FORAGE (vedi
# CaloricCalculator.seasonal_availability_multiplier, che cambia di scatto al confine tra due
# stagioni) produce un ratio realmente sotto soglia di ordini di grandezza superiori a questo
# epsilon, e continua a innescare l'espansione come richiesto ("qualunque deficit, anche
# piccolo"). Va nel log daily_calories_consumed/daily_calories_required per distinguere i due casi.
const RATIO_EPSILON := 0.000001


func apply_daily_hunger(world: World, groups_override: Array = []) -> void:
	# Aggregato giornaliero (vedi log di riepilogo in fondo): quanti gruppi hanno evitato la BFS
	# costosa oggi grazie a PopulationGroup.blocked_territory_search_version, contro quanti l'hanno
	# eseguita per davvero — per verificare a colpo d'occhio l'effetto della cache senza dover
	# contare a mano le righe "ricerca_territorio=saltata" nel log per-gruppo sottostante.
	var territory_searches_skipped := 0
	var territory_searches_attempted := 0

	# groups_override (Parte B del LOD, infrastruttura — vedi LODOrchestrator): vuoto (default) =
	# comportamento invariato, itera world.population_groups per intero come sempre. Non ancora
	# collegato da nessun chiamante reale (WorldTimeService continua a non passarlo).
	var groups_to_process: Array = groups_override if not groups_override.is_empty() else world.population_groups

	for group in groups_to_process:
		if group.population <= 0:
			continue

		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null:
			continue
		# I branchi predatori (PredatorRules) non passano mai da AnimalConsumptionService (vedi
		# esclusione lì) quindi group.daily_caloric_ratio non viene mai aggiornato per loro —
		# processarli qui userebbe un ratio residuo/stantio (0.0 di default) e applicherebbe
		# mortalità da fame scollegata dal reale esito delle cacce di PredationService, che ha già
		# il proprio bookkeeping calorico (predation_calorie_debt/predation_surplus_carryover) e la
		# propria logica di conseguenze — nessuna mortalità da fame equivalente ancora implementata
		# lì, deliberatamente fuori scope di questo fix.
		if rules is PredatorRules:
			continue

		var outcome := _process_group_hunger(world, group, rules)
		if outcome["territory_search_skipped"]:
			territory_searches_skipped += 1
		elif outcome["territory_search_attempted"]:
			territory_searches_attempted += 1

	# SHOW_HERBIVORE_LIFECYCLE_LOGS: questo service processa SOLO erbivori (i predatori sono
	# saltati sopra, mai raggiungono questo punto), quindi basta il flag da solo, nessun controllo
	# di specie necessario — stesso flag già usato per silenziare ANIMAL BIRTHS/AGING/OLD AGE
	# DEATHS/TERRITORY DYNAMICS erbivori mentre si valida la sola natalità/mortalità dei lupi.
	if DebugLogging.ENABLED and DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS and (territory_searches_skipped > 0 or territory_searches_attempted > 0):
		print(
			"[ANIMAL HUNGER SUMMARY] ricerche_territorio_evitate=%d ricerche_territorio_eseguite=%d" % [
				territory_searches_skipped, territory_searches_attempted
			]
		)


# Ordine per gruppo: 1) riallinea hunger_buckets a population (rete di sicurezza, vedi
# _reconcile_bucket_total — l'invariante è già mantenuta per costruzione da
# PopulationGroup.set_age_composition/apply_births/apply_old_age_mortality, ma un secondo
# controllo qui costa pochissimo e rende il meccanismo robusto a eventuali futuri punti di
# mutazione della popolazione non ancora aggiornati); 2) calcola quanti individui non sono stati
# nutriti oggi dal ratio già calcolato; 3) fa avanzare/retrocedere i bucket, raccogliendo le morti
# per superamento soglia; 4) applica la mortalità (pesata per età); 5) tenta un'espansione di una
# cella se il ratio odierno segnala ancora deficit. Ritorna {"territory_search_skipped": bool,
# "territory_search_attempted": bool} — solo per l'aggregato giornaliero del chiamante
# (apply_daily_hunger), nessun altro uso.
func _process_group_hunger(world: World, group: PopulationGroup, rules: AnimalRules) -> Dictionary:
	_reconcile_bucket_total(group)

	# Cooldown sullo split da fame (Step 11, vedi PopulationGroup.hunger_split_cooldown_days) —
	# decrementato QUI, incondizionatamente, ogni giorno per ogni gruppo processato: deve scendere
	# anche nei giorni in cui il gruppo non è affamato (ratio >= 1.0, il ramo sotto non gira),
	# altrimenti il countdown si fermerebbe ogni volta che la pressione si allevia anche solo per
	# un giorno, invece di scadere a un numero fisso di giorni dallo split come richiesto.
	if group.hunger_split_cooldown_days > 0:
		group.hunger_split_cooldown_days -= 1

	var ratio: float = group.daily_caloric_ratio
	var population_before := group.population
	var unfed_target: int = clamp(
		int(round(float(population_before) * (1.0 - ratio))), 0, population_before
	)

	var shift_result := _shift_buckets(group, rules, unfed_target)
	var total_deaths: int = shift_result["total_deaths"]
	var deaths_by_origin_day: Dictionary = shift_result["deaths_by_origin_day"]

	if total_deaths > 0:
		group.apply_hunger_mortality(total_deaths, rules)

	var expansion_attempted := false
	var expansion_succeeded := false
	var split_skipped_cooldown := false
	var territory_search_skipped := false
	if ratio < DAILY_HUNGER_EXPANSION_THRESHOLD - RATIO_EPSILON:
		# Cache "ero gia bloccato" (PopulationGroup.blocked_territory_search_version): se
		# l'ultima ricerca di questo gruppo e fallita, e da allora nessun territorio della sua
		# specie si e liberato in nessun punto della mappa (World.species_territory_release_version
		# invariato), la ricerca di oggi darebbe con certezza lo stesso esito - sia
		# expand_by_one_cell che attempt_split chiamano comunque la STESSA BFS
		# (TerritoryBuilderService.find_nearest_free_cell dallo stesso centroide), quindi saltarle
		# entrambe qui elimina anche la doppia ricerca ridondante che il codice faceva gia oggi
		# nello stesso giorno per lo stesso gruppo bloccato.
		var current_release_version: int = int(
			world.species_territory_release_version.get(group.species_name, 0)
		)
		if group.blocked_territory_search_version == current_release_version:
			territory_search_skipped = true
		else:
			expansion_attempted = true
			expansion_succeeded = _attempt_expansion(world, group, rules)
			if expansion_succeeded:
				group.blocked_territory_search_version = -1
			elif group.hunger_split_cooldown_days > 0:
				# Cooldown attivo (Step 11): nessun tentativo oggi, il gruppo resta esposto al solo
				# digiuno prolungato finché il countdown non scade — visibile nel log sotto invece
				# di sparire silenziosamente. L'espansione fallita ha comunque già accertato lo
				# stato reale dello spazio disponibile (stessa BFS che avrebbe usato lo split),
				# quindi la cache si aggiorna comunque qui.
				split_skipped_cooldown = true
				group.blocked_territory_search_version = current_release_version
			else:
				# Espansione fallita (territorio già a max_territory_cells o BFS satura, un unico
				# segnale, non serve distinguere il perché) — prova a staccare una porzione della
				# popolazione in un nuovo gruppo altrove (Step 9) PRIMA di lasciare che il solo
				# digiuno prolungato gestisca la situazione nei giorni successivi. unfed_target
				# (già calcolato sopra, individui non nutriti OGGI) è il surplus naturale per
				# questo trigger, analogo al surplus di densità/calorico stagionale usato da
				# TerritoryDynamicsService — stesso floor MIN_DISPERSAL_SHARE_FRACTION condiviso,
				# non una seconda soglia scoordinata. group.population qui è già post-mortalità di
				# oggi (vedi apply_hunger_mortality sopra): PopulationSplitService.attempt_split
				# clampa comunque requested_amount a population - 1, quindi un unfed_target
				# calcolato su population_before pre-mortalità resta sicuro anche se ora eccede la
				# popolazione attuale.
				var split_amount: int = max(
					unfed_target,
					int(ceil(float(group.population) * PopulationSplitService.MIN_DISPERSAL_SHARE_FRACTION))
				)
				var split_trigger_reason := "fame quotidiana (ratio=%.3f)" % ratio
				# Cooldown (Step 11) impostato SOLO se lo split riesce davvero — un tentativo
				# fallito per mancanza di cella libera raggiungibile non ha "consumato" nulla, non
				# deve bloccare il tentativo di domani.
				if PopulationSplitService.new().attempt_split(world, group, rules, split_amount, split_trigger_reason):
					group.hunger_split_cooldown_days = rules.max_days_without_food
					group.blocked_territory_search_version = -1
				else:
					group.blocked_territory_search_version = current_release_version

	if (
		DebugLogging.ENABLED and DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS
		and (unfed_target > 0 or total_deaths > 0 or expansion_attempted or territory_search_skipped)
	):
		_log_daily_hunger(
			group, ratio, unfed_target, total_deaths, deaths_by_origin_day,
			population_before, expansion_attempted, expansion_succeeded, split_skipped_cooldown,
			territory_search_skipped
		)

	return {
		"territory_search_skipped": territory_search_skipped,
		"territory_search_attempted": expansion_attempted,
	}


# Rete di sicurezza: se population e somma(hunger_buckets) sono comunque disallineati (es. un
# punto di mutazione futuro che dimenticasse di aggiornare hunger_buckets), riallinea qui invece
# di propagare un istogramma inconsistente allo shift giornaliero. Un eccesso di population va nel
# bucket 0 (nessuno storico noto = trattati come sazi, stesso criterio di set_age_composition);
# un eccesso di hunger_buckets si toglie proporzionalmente tra i bucket esistenti (stesso
# "water-filling" capped già usato da apply_old_age_mortality).
func _reconcile_bucket_total(group: PopulationGroup) -> void:
	var diff := group.population - group.get_hunger_bucket_total()
	if diff > 0:
		group.set_hunger_bucket_count(0, group.get_hunger_bucket_count(0) + diff)
	elif diff < 0:
		var loss := -diff
		var split := MacroCellState._split_by_weight_capped(group.hunger_buckets, group.hunger_buckets, loss)
		for days in split.keys():
			group.set_hunger_bucket_count(days, group.get_hunger_bucket_count(days) - split[days])


# Assegna i `unfed_target` individui "non nutriti oggi" partendo dai bucket PIÙ ALTI (i già più
# affamati restano scoperti per primi), poi fa avanzare di un bucket chi non è stato nutrito e
# retrocedere di un bucket (mai sotto 0) chi lo è stato. Chi supererebbe
# rules.max_days_without_food muore invece di entrare in un bucket oltre la soglia. Ritorna
# {"total_deaths": int, "deaths_by_origin_day": Dictionary} — il secondo per il solo logging,
# chiave = bucket di PARTENZA di chi è morto oggi.
func _shift_buckets(group: PopulationGroup, rules: AnimalRules, unfed_target: int) -> Dictionary:
	var days_desc: Array = group.hunger_buckets.keys()
	days_desc.sort()
	days_desc.reverse()

	var remaining_unfed := unfed_target
	var unfed_by_day: Dictionary = {}
	var fed_by_day: Dictionary = {}

	for day in days_desc:
		var count: int = group.get_hunger_bucket_count(day)
		if count <= 0:
			continue
		if remaining_unfed <= 0:
			fed_by_day[day] = count
		elif remaining_unfed >= count:
			unfed_by_day[day] = count
			remaining_unfed -= count
		else:
			unfed_by_day[day] = remaining_unfed
			fed_by_day[day] = count - remaining_unfed
			remaining_unfed = 0

	var new_buckets: Dictionary = {}
	var deaths_by_origin_day: Dictionary = {}
	var total_deaths := 0

	for day in unfed_by_day.keys():
		var c: int = unfed_by_day[day]
		if c <= 0:
			continue
		var next_day: int = int(day) + 1
		if next_day > rules.max_days_without_food:
			deaths_by_origin_day[day] = int(deaths_by_origin_day.get(day, 0)) + c
			total_deaths += c
		else:
			new_buckets[next_day] = int(new_buckets.get(next_day, 0)) + c

	for day in fed_by_day.keys():
		var c: int = fed_by_day[day]
		if c <= 0:
			continue
		var prev_day: int = max(int(day) - 1, 0)
		new_buckets[prev_day] = int(new_buckets.get(prev_day, 0)) + c

	group.hunger_buckets = new_buckets
	return {"total_deaths": total_deaths, "deaths_by_origin_day": deaths_by_origin_day}


# Un solo tentativo al giorno, nessuna finestra di attesa: se fallisce oggi (territorio già a
# max_territory_cells, o BFS satura senza celle libere raggiungibili — vedi
# TerritoryBuilderService.expand_by_one_cell) si ritenta domani se il deficit persiste, la BFS è
# economica. rabbit (min=max=1 territorio) fallisce sempre qui per costruzione, mai un'eccezione
# hardcoded per specie.
func _attempt_expansion(world: World, group: PopulationGroup, rules: AnimalRules) -> bool:
	if group.territory == null:
		return false
	if group.territory.get_cell_count() >= rules.max_territory_cells:
		return false
	return TerritoryBuilderService.new().expand_by_one_cell(world, group.territory, group.species_name)


func _log_daily_hunger(
	group: PopulationGroup, ratio: float, unfed_target: int, total_deaths: int,
	deaths_by_origin_day: Dictionary, population_before: int,
	expansion_attempted: bool, expansion_succeeded: bool, split_skipped_cooldown: bool,
	territory_search_skipped: bool
) -> void:
	# consumate/fabbisogno con 6 decimali (non solo il ratio arrotondato a 3): un ratio stampato
	# "1.000" può nascondere un vero piccolo deficit (es. 0.997, calo stagionale reale di
	# seasonal_availability_multiplier su FORAGE) indistinguibile dal rumore in virgola mobile
	# senza i numeri grezzi.
	var line := "[ANIMAL HUNGER] #%d %s pop=%d consumato=%.6f fabbisogno=%.6f ratio=%.6f non_nutriti_oggi=%d bucket(giorni:conta)=[%s]" % [
		group.id, group.species_name, population_before,
		group.daily_calories_consumed, group.daily_calories_required, ratio,
		unfed_target, _format_bucket_summary(group.hunger_buckets)
	]

	if expansion_attempted:
		line += " espansione=%s" % ("riuscita" if expansion_succeeded else "fallita")
		if not expansion_succeeded:
			# Visibilità sul cooldown (Step 11, PopulationGroup.hunger_split_cooldown_days): se
			# saltato, quanti giorni mancano ancora; se tentato, il valore ORA (0 se il tentativo è
			# fallito per mancanza di cella libera — attempt_split non lo arma in quel caso — o
			# rules.max_days_without_food se è appena stato riarmato da uno split riuscito).
			if split_skipped_cooldown:
				line += " split_fame=saltato(cooldown=%dgg residui)" % group.hunger_split_cooldown_days
			else:
				line += " split_fame=tentato(cooldown_ora=%dgg)" % group.hunger_split_cooldown_days
	elif territory_search_skipped:
		# Nessun tentativo oggi: ricerca saltata perché il gruppo era già accertato bloccato e
		# nessun territorio della sua specie si è liberato da allora (vedi
		# PopulationGroup.blocked_territory_search_version) — nessuna BFS eseguita, a differenza
		# di "espansione=fallita" sopra che invece la esegue e basta fallire.
		line += " ricerca_territorio=saltata (nessun rilascio dal precedente fallimento)"

	if total_deaths > 0:
		line += " MORTI=%d da_bucket(giorni:conta)=[%s] pop %d->%d age(Y=%d,A=%d,O=%d)" % [
			total_deaths, _format_bucket_summary(deaths_by_origin_day),
			population_before, group.population,
			group.get_age_count(GameTypes.AgeBand.YOUNG),
			group.get_age_count(GameTypes.AgeBand.ADULT),
			group.get_age_count(GameTypes.AgeBand.OLD),
		]

	print(line)


func _format_bucket_summary(buckets: Dictionary) -> String:
	var days: Array = []
	for day in buckets.keys():
		if int(buckets[day]) > 0:
			days.append(day)
	days.sort()

	var parts: Array = []
	for day in days:
		parts.append("%d:%d" % [day, int(buckets[day])])
	return " ".join(parts)
