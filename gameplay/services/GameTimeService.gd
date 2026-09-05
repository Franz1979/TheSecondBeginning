class_name GameTimeService
extends RefCounted

# Primo consumatore gameplay-side dei checkpoint temporali classificati esposti da
# GameClockController (day_advanced/season_ended/year_rolled_over, propagati da WorldTimeService.
# advance_day senza duplicare i confronti su SeasonCalculator — vedi ricognizione 2026-09-05).
#
# RefCounted come gli altri *Service del progetto, ma a differenza di quelli (stateless,
# "istanzia con .new() e chiama il metodo" — vedi CLAUDE.md) questa istanza deve restare VIVA per
# tutta la durata di GameScene: è la connessione ai segnali stessa a doverle sopravvivere. Il
# chiamante (GameScene) la tiene in un campo (game_time_service), esattamente come tiene clock
# (GameClockController) — se l'unico riferimento uscisse di scope, Godot libererebbe l'istanza e
# le connessioni smetterebbero di scattare senza errore visibile.

# Step 6 (2026-09-05): emesso PRIMA di rimuovere l'individuo da _human_individuals (vedi
# _apply_scheduled_human_deaths sotto), con l'indice che aveva in quell'array in quel momento —
# GameScene.human_individual_views è parallelo per indice a human_individuals (stessa collezione
# di GameScene, vedi il commento lì: "parallelo per indice... la riparentazione richiede di
# trovare la view di un individuo per indice"), quindi GameScene deve rimuovere/liberare la view
# corrispondente ALLO STESSO indice prima che la rimozione qui sotto sfasi tutto ciò che segue.
# age_at_death/partner_freed (sistema notifiche, 2026-09-05): già calcolati qui per il log
# console, passati a GameScene così può comporre il testo del popup di morte senza doverli
# ricalcolare — questa classe non sa nulla di UI/popup, si limita a fornire i dati.
signal individual_died(individual: HumanIndividual, index: int, age_at_death: int, partner_freed: bool)
# Emesso UNA VOLTA a fine giornata, DOPO che tutte le rimozioni/aggiornamenti di total_count del
# giorno sono completati — a differenza di individual_died sopra (emesso PRIMA di ogni singola
# rimozione, con l'indice ancora valido per human_individual_views), questo è il punto giusto per
# rinfrescare pannelli che leggono lo stato AGGIORNATO (es. la scheda 👨‍👩‍👧, che mostra anche
# total_count) — bugfix, richiesta utente, 2026-09-05: collegare il refresh direttamente dentro
# individual_died mostrava ancora i dati vecchi, perché a quel punto la rimozione non era ancora
# avvenuta. Non emesso nei giorni senza morti (nessun refresh inutile).
signal human_population_changed

var _game_data: GameData
# Riferimenti (non copie) allo STESSO Array/Folk/HumanPopulationGroup che GameScene possiede —
# un Array in GDScript è per riferimento, quindi la rimozione reale (Step 6, vedi
# _apply_scheduled_human_deaths sotto) fatta qui resta visibile a GameScene senza dover ripassare
# nulla ad ogni chiamata. _human_folk (non solo human_rules_ref preso una volta sola) perché
# human_rules_ref potrebbe in teoria essere riassegnato più avanti (cambio Era) — leggerlo fresco
# ad ogni anno invece di cachearlo resta corretto in entrambi i casi.
var _human_individuals: Array[HumanIndividual]
var _human_folk: Folk
# Serve SOLO per tenere total_count allineato a _human_individuals.size() dopo una rimozione
# (Step 6) — HumanPopulationInfoPanel.show_population riceve i due dati separatamente, mai
# ricalcolato da _human_individuals.size() al volo.
var _human_population_group: HumanPopulationGroup


# Connessione UNA TANTUM (richiesta utente, 2026-09-05) — chiamata da GameScene._setup_clock
# subito dopo clock.day_advanced.connect(...), stesso punto di inizializzazione, nessun registry
# dedicato esiste ancora nel progetto per questo scopo (vedi ricognizione).
#
# human_individuals/human_folk (Step 5 del piano mortalità): servono per agganciare
# HumanMortalityIndividualService.check_mortality a year_rolled_over — vedi _on_year_rolled_over
# sotto. human_population_group (Step 6): serve per tenere total_count allineato dopo una
# rimozione reale — vedi _apply_scheduled_human_deaths.
func connect_to_clock(
	clock: GameClockController,
	game_data: GameData,
	human_individuals: Array[HumanIndividual],
	human_folk: Folk,
	human_population_group: HumanPopulationGroup
) -> void:
	_game_data = game_data
	_human_individuals = human_individuals
	_human_folk = human_folk
	_human_population_group = human_population_group
	clock.day_advanced.connect(_on_day_advanced)
	clock.year_rolled_over.connect(_on_year_rolled_over)
	clock.season_ended.connect(_on_season_ended)


# Step 6 del piano mortalità (2026-09-05): stesso hook giornaliero già esistente usato da
# GameScene._on_day_advanced per vegetazione/eventi — riusato qui, non un nuovo aggancio, stesso
# principio già seguito per year_rolled_over allo Step 5. checkpoint_ran/animals_changed non
# servono a questa applicazione (le morti programmate non dipendono da nessuno dei due), quindi
# ignorati.
func _on_day_advanced(_checkpoint_ran: bool, _animals_changed: bool) -> void:
	_apply_scheduled_human_deaths()


func _on_year_rolled_over() -> void:
	print("GameTimeService: nuovo anno, year=%d" % _game_data.year)
	_run_annual_human_mortality_determination()


# Step 5 del piano mortalità (2026-09-05): determinazione + assegnazione scheduled_death_day
# annuale sulla popolazione umana REALE — prima di questo step girava solo isolatamente sui dati
# fittizi di res://tools/mortality_test/.
#
# Gira SOLO sulla popolazione a piena simulazione: oggi _human_individuals È già solo quella (un
# solo Folk/insediamento esiste nel progetto, nessuna rappresentazione aggregata "lontana" per gli
# umani ancora — a differenza degli animali non c'è un secondo livello da filtrare qui). Quando in
# futuro esisterà un equivalente umano del LOD animale (popolazioni umane rappresentate solo in
# forma aggregata), questo metodo andrà limitato ai soli individui a piena simulazione, stesso
# principio già seguito da WorldTimeService per gli animali (Livello 2 vs aggregato Livello 1).
func _run_annual_human_mortality_determination() -> void:
	if _human_folk == null or _human_folk.human_rules_ref == null or _human_individuals.is_empty():
		return
	# Durate EFFETTIVE (scalate per Era corrente), non le durate BASE di HumanRules — bugfix,
	# richiesta utente, 2026-09-05: prima il gate age_band e la curva di probabilità leggevano
	# rules.age_band_durations_male/female direttamente, ignorando EraRules.
	# longevity_multiplier_by_age — un individuo poteva risultare ancora FERTILE_ADULT/MATURE_ADULT
	# qui mentre i pannelli (che già usavano game_data.era_effective_age_band_durations_male/female)
	# lo mostravano OLD. Stessa fonte già usata da GameScene per i pannelli, un solo posto di verità.
	var durations_male := _game_data.era_effective_age_band_durations_male
	var durations_female := _game_data.era_effective_age_band_durations_female
	# DIAGNOSTICO TEMPORANEO (richiesta utente, 2026-09-05 — verifica numeri reali invece di
	# continuare a supporre): stampa età/age_band/probabilità calcolata per OGNI individuo (non
	# solo i marcati), PRIMA della determinazione vera e propria. Da rimuovere quando non serve
	# più.
	if DebugLogging.ENABLED:
		for individual in _human_individuals:
			var age := _game_data.year - individual.birth_year_virtual
			var age_band := HumanCalculator.get_age_band(durations_male, durations_female, individual.sex, float(age))
			var probability := HumanCalculator.get_annual_death_probability(
				age, _human_folk.human_rules_ref, durations_male, durations_female
			)
			print("[HUMAN MORTALITY DEBUG] #%d %s eta'=%d age_band=%s probabilita'=%.4f" % [
				individual.id, individual.name, age, HumanTypes.AgeBand.keys()[age_band], probability
			])
	var marked := HumanMortalityIndividualService.check_mortality(
		_human_individuals, _human_folk.human_rules_ref, _game_data.year, durations_male, durations_female
	)
	if not DebugLogging.ENABLED:
		return
	if marked.is_empty():
		print("[HUMAN MORTALITY] anno=%d: nessun individuo marcato per morire" % _game_data.year)
		return
	var details: Array[String] = []
	for individual in marked:
		details.append("#%d %s (giorno %d)" % [individual.id, individual.name, individual.scheduled_death_day])
	print("[HUMAN MORTALITY] anno=%d: %d individui marcati per morire quest'anno -> %s" % [
		_game_data.year, marked.size(), ", ".join(details)
	])


# Step 6 del piano mortalità (2026-09-05): applicazione REALE delle morti programmate dallo
# Step 5 (HumanIndividual.scheduled_death_day) — rimozione da _human_individuals/allineamento
# di total_count, pulizia partner_id del coniuge superstite (vedi _free_partner_if_any sotto).
# Nessuna registrazione per statistiche/life expectancy/death cause qui (Step 7, a parte) e
# nessun nuovo campo oltre a scheduled_death_day/partner_id, già esistenti.
#
# Iterazione ALL'INDIETRO (mai un for in avanti su un Array da cui si rimuove durante lo scorso:
# remove_at farebbe scalare tutto di una posizione, saltando l'elemento successivo) — stesso
# idioma già in uso altrove nel progetto per rimozioni in-place da un Array scorso linearmente.
func _apply_scheduled_human_deaths() -> void:
	if _human_individuals.is_empty():
		return
	var today := _game_data.current_day
	# any_removed è INDIPENDENTE da DebugLogging.ENABLED (bugfix in corso d'opera: prima si
	# decideva se emettere human_population_changed guardando removed_log_lines, popolato SOLO a
	# log abilitati — con ENABLED=false il segnale non sarebbe mai scattato, lasciando la scheda
	# 👨‍👩‍👧 stantia anche a fronte di rimozioni vere).
	var any_removed := false
	var removed_log_lines: Array[String] = []
	var i := _human_individuals.size() - 1
	while i >= 0:
		var individual: HumanIndividual = _human_individuals[i]
		if individual.scheduled_death_day == today:
			var age_at_death := _game_data.year - individual.birth_year_virtual
			# Step 8 (2026-09-05): log grezzo per statistiche future (vedi GameData.death_events) —
			# costruito PRIMA di _free_partner_if_any sotto e PRIMA della rimozione dal roster più
			# in basso, così spouse_id cattura il partner_id del defunto come snapshot ("il coniuge
			# al momento della morte", altrimenti perso). -1 = nessun partner, stessa convenzione
			# di HumanIndividual.partner_id stesso — nessun null/vuoto speciale introdotto solo per
			# questo campo. cause sempre OLD_AGE per ora (unica causa di morte implementata).
			_game_data.death_events.append({
				"individual_id": individual.id,
				"name": individual.name,
				"sex": individual.sex,
				"age_at_death": age_at_death,
				"cause": DeathTypes.DeathCause.OLD_AGE,
				"year": _game_data.year,
				"day": today,
				"spouse_id": individual.partner_id,
			})
			# Log di verifica SEPARATO dal riepilogo "[HUMAN DEATH]" esistente sotto (mai toccato,
			# richiesta esplicita) — conferma che l'evento è stato davvero registrato in
			# game_data.death_events e mostra il conteggio totale accumulato (utile anche per
			# controllare che sopravviva a un save/load, visto che il contatore non riparte da 0).
			if DebugLogging.ENABLED:
				print("[DEATH LOG] registrato: %s (totale eventi finora: %d)" % [
					_game_data.death_events[-1], _game_data.death_events.size()
				])
			var partner_freed := _free_partner_if_any(individual)
			# EMESSO PRIMA della rimozione sotto, con l'indice ancora valido — vedi commento sul
			# signal per il perché (GameScene.human_individual_views parallelo per indice).
			individual_died.emit(individual, i, age_at_death, partner_freed)
			_human_individuals.remove_at(i)
			if _human_population_group != null:
				_human_population_group.total_count = _human_individuals.size()
			any_removed = true
			if DebugLogging.ENABLED:
				removed_log_lines.append("#%d %s (eta'=%d, causa=vecchiaia%s)" % [
					individual.id, individual.name, age_at_death,
					", coniuge liberato" if partner_freed else ""
				])
		i -= 1
	if not any_removed:
		return
	# Nessuna riga se oggi non muore nessuno (a differenza del riepilogo annuale sopra, che
	# stampa sempre) — evita spam giornaliero, richiesta utente.
	if DebugLogging.ENABLED and not removed_log_lines.is_empty():
		print("[HUMAN DEATH] giorno=%d: %s" % [today, ", ".join(removed_log_lines)])
	# Solo ora (dopo TUTTE le rimozioni/total_count del giorno) — vedi commento sul signal.
	human_population_changed.emit()


# Libera partner_id del coniuge superstite di `deceased`, se presente — trovato per scansione
# lineare su _human_individuals (stesso costo già accettato altrove nel progetto per array
# analoghi, es. GameScene._find_building_by_id). MAI mother_id/father_id, di nessuno: restano
# dangling, puramente genealogici (già deciso in sessione precedente). Nessun crash se il
# coniuge non viene trovato (già rimosso in precedenza, o riferimento dangling per altri motivi)
# — skip silenzioso, come richiesto.
func _free_partner_if_any(deceased: HumanIndividual) -> bool:
	if deceased.partner_id == -1:
		return false
	for other in _human_individuals:
		if other.id == deceased.partner_id:
			other.partner_id = -1
			return true
	return false


# Placeholder: nessuna reazione ancora, solo il collegamento richiesto (vedi doc di testa al
# file). Prossimo consumo reale probabilmente qui, quando arriverà una logica per-stagione.
func _on_season_ended(season: GameTypes.Season) -> void:
	pass
