class_name TerritoryDynamicsService
extends RefCounted

# Rampa a due tratti del moltiplicatore di densità (vedi _get_density_multiplier sotto). Soglia
# di inizio 0.7 (dopo un giro di test a 0.5, poi tornata a 0.7): frenare troppo presto rischia di
# stabilizzare la popolazione di specie a crescita lenta e territorio ancora espandibile (es.
# deer) in un equilibrio permanente SOTTO la soglia che farebbe scattare l'espansione
# (_update_group_territory.needs_expansion_density, ~ratio > 1.0) — il freno pensato per chi non
# ha via di scampo (rabbit, sempre al massimo territorio) finirebbe per impedire alla via di
# scampo stessa (l'espansione di deer) di attivarsi mai. Stesso discorso varrà in futuro per lo
# split del gruppo (Step 9): la mitigazione non deve MAI essere così aggressiva da impedire alla
# popolazione di accumulare la pressione reale che serve a far scattare il meccanismo successivo.
const DENSITY_RATIO_RAMP_START := 0.7   # sotto: nessuna penalità, moltiplicatore = 1.0
const DENSITY_RATIO_FULL_CAPACITY := 1.0  # qui il moltiplicatore vale il "mid" della specie (vedi sotto)
const DENSITY_RATIO_RAMP_END := 1.5     # da qui in poi: moltiplicatore = 0.0, per tutti

# Il "mid" (valore del moltiplicatore esattamente a ratio=1.0, piena capacità etologica) non è
# un'unica costante: la stessa rampa 0.7->1.0 quadratica, applicata a un floor unico, andava bene
# per specie a riproduzione veloce (rabbit: anche un moltiplicatore basso produce comunque molti
# nascituri) ma soffocava una specie lenta (deer, base_birth_rate=0.4) fino a stabilizzarla in un
# equilibrio PERMANENTE — le nascite (già ridotte al 5%) bastavano solo a pareggiare la mortalità
# per vecchiaia, mai a produrre il surplus necessario a superare la soglia di espansione
# territoriale (osservato nei test: popolazione ferma esatta a 70 per tre cicli di fila). La
# discriminante è il VALORE di AnimalRules.base_birth_rate della specie, non il nome/l'identità
# della specie in sé (nessuna eccezione hardcoded, stesso principio già seguito ovunque in questo
# file) — sopra o uguale a DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD (1.0) è "veloce" (rabbit,
# base_birth_rate=1.5) e usa DENSITY_MULTIPLIER_MID_FAST (0.05, severo, già validato nei test:
# ha fermato un'esplosione da 14000+ individui); sotto è "lenta" (deer, base_birth_rate=0.4) e usa
# DENSITY_MULTIPLIER_MID_SLOW (0.3 — alzato da 0.25 dopo osservazione in gioco: il floor
# precedente lasciava il surplus di nascite troppo debole per accumulare pressione in tempi
# ragionevoli. Se dovesse ripresentarsi lo stesso problema, si può alzare ulteriormente verso 0.5,
# mai oltre: un floor troppo alto vanificherebbe la mitigazione stessa).
#
# La FORMA della curva è invece IDENTICA per entrambe le categorie, nessuna doppia formula da
# mantenere: quadratica (t², frenata debole per la maggior parte del tratto, concentrata negli
# ultimi passi) da 0.7 a 1.0, poi lineare da 1.0 a 1.5 — ciascuna parte scende dal PROPRIO mid
# (0.05 o 0.3) fino a 0.0 esattamente a ratio=1.5, mai un floor piatto fisso uguale per tutte:
# un plateau comune a un valore fisso (es. sempre 0.05 tra 1.0 e 1.5 indipendentemente dal mid di
# partenza) creerebbe una discontinuità a ratio=1.0 per la specie lenta (salto da 0.3 a 0.05) —
# scartato apposta per restare continua in entrambi i punti di rottura, come tutte le altre curve
# di questo sistema.
const DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD := 1.0
const DENSITY_MULTIPLIER_MID_FAST := 0.05   # base_birth_rate >= soglia (oggi: rabbit, boar)
const DENSITY_MULTIPLIER_MID_SLOW := 0.3   # base_birth_rate < soglia E population > soglia piccola sotto

# Seconda distinzione, SOLO all'interno della categoria "lenta" sopra (mai per quella "veloce": un
# tasso base già alto si autoprotegge dal problema — vedi sotto) — osservata per la prima volta sul
# lupo (population piccola per costruzione, max ~15) ma non specifica ai predatori: qualunque
# popolazione lenta può trovarcisi, es. un gruppo erbivoro appena scisso. Con population piccola,
# il mid "normale" (0.3) combinato con un base_birth_rate già basso produce nascite attese quasi
# a zero (verificato: lupo, pesato_fertilita=5 × base_birth_rate=0.4 × mid=0.3 ≈ 0.6/anno,
# facilmente pareggiato o superato dalla sola mortalità per vecchiaia — osservato in gioco: la
# popolazione oscilla per molti cicli attorno allo stesso ratio=1.0 senza mai accumulare un
# surplus stabile) — stesso tipo di equilibrio quasi-permanente già visto per deer con mid=0.25,
# qui riletto come "il problema non è la specie, è la popolazione piccola in valore assoluto".
# DENSITY_MULTIPLIER_MID_SLOW_SMALL (0.5) sostituisce SLOW quando population <= soglia. Nessuna
# distinzione per le specie veloci: un base_birth_rate già alto (rabbit=1.5, boar=1.3) produce
# comunque un valore atteso sano anche con lo stesso mid severo (0.05) a popolazione piccola (es.
# 10×1.5×0.05=0.75), quindi non ha lo stesso rischio di stallo — la distinzione lenta/veloce
# esistente resta il primo filtro, questa si applica solo dopo.
const DENSITY_SMALL_POPULATION_THRESHOLD := 12   # valore di partenza, da tarare osservando i test
const DENSITY_MULTIPLIER_MID_SLOW_SMALL := 0.5

# Interruttore DEDICATO (non DebugLogging, che per contratto non deve mai cambiare comportamento
# di simulazione) per lo spalmamento su più giorni del lavoro Livello 1 (vedi
# update_territories_and_mitigation/process_daily_stagger sotto). A false: comportamento
# IDENTICO a prima di questa modifica — un solo checkpoint annuale, tutti i gruppi con
# rules.birth_season == season elaborati in un colpo solo, process_daily_stagger sempre no-op,
# nessun marcatore letto (group.territory_dynamics_processed_year resta ignorato anche se
# valorizzato da un giro precedente con l'interruttore a true). Pensato per essere spento in
# qualunque momento senza lasciare stato incoerente: la sola differenza col codice pre-modifica è
# un confronto in più, sempre falso quando qui sotto è false.
const STAGGER_LEVEL_1_ENABLED := true

# Espansione/contrazione del territorio di ogni PopulationGroup (Step 8 del refactoring fauna) —
# gira nello STESSO checkpoint di inizio birth_season di ciascuna specie in cui gira già
# AnimalBirthMitigationService, perché i due condividono la stessa identica definizione di
# "scarsità" (AnimalBirthMitigationService.compute_caloric_ratio — stock disponibile snapshot /
# fabbisogno stagionale age-weighted).
#
# Sequenza per ogni gruppo con rules.birth_season == season:
#   1. ratio_iniziale = compute_caloric_ratio() sul territorio ATTUALE
#   2. valuta espansione/contrazione (vedi _update_group_territory)
#   3. ratio_finale = compute_caloric_ratio() sul territorio ORA aggiornato (identico a
#      ratio_iniziale se il territorio non è cambiato — nessun ramo speciale necessario)
#   4. apply_mitigation_multiplier(group, ratio_finale) — mai il ratio_iniziale: la natalità di
#      fine stagione deve vedere l'effetto dell'eventuale aggiustamento territoriale di
#      quest'anno, non lo stato di prima.
#
# Nessuna eccezione hardcoded per specie: rabbit (min_territory_cells == max_territory_cells == 1)
# si autoesclude per pura costruzione matematica — density_cells_needed resta sempre uguale alle
# celle attuali (già 1) e la contrazione è strutturalmente impossibile quando current_cell_count
# non supera già min_territory_cells — senza bisogno di alcun controllo esplicito sul nome specie
# qui sotto. Ogni gruppo è valutato indipendentemente dagli altri per densità/calorie/contrazione;
# l'unico accoppiamento cross-gruppo è l'esclusione territoriale STESSA SPECIE dentro
# TerritoryBuilderService.expand_by_one_cell (vedi _collect_species_occupied_cells lì) — specie
# diverse restano libere di sovrapporsi (competizione per risorse quando coesistono, mai per
# "diritto territoriale"), nessun TerritoryManager cross-specie ancora.
#
# SPALMAMENTO (STAGGER_LEVEL_1_ENABLED, vedi costante sopra): questo checkpoint stagionale resta
# il punto di ingresso principale, ma ora funge anche da RETE DI SICUREZZA — elabora solo i gruppi
# NON ancora marcati come già processati quest'anno (group.territory_dynamics_processed_year !=
# current_year). Con lo spalmamento attivo, la maggior parte dei gruppi Livello 1 arriva qui già
# marcata (elaborata giorno per giorno da process_daily_stagger sotto, durante l'intera finestra
# stagionale precedente) — questo checkpoint quindi rielabora solo: i gruppi Livello 2 (mai
# toccati dal driver giornaliero, sempre pochi), i gruppi nati da split con turno-hash già passato
# nella finestra corrente, e i gruppi che hanno cambiato Livello 1<->2 a metà finestra troppo tardi
# per essere presi dal driver giornaliero (vedi discussione di design — nessuna delle due
# situazioni richiede una regola a parte, la rete di sicurezza le copre entrambe per costruzione).
# Con lo spalmamento disattivato, `current_year` è ignorato (nessun gruppo risulta mai marcato per
# l'anno in corso da process_daily_stagger, che è sempre no-op) e questo checkpoint elabora TUTTI
# i gruppi in un colpo solo, esattamente come il codice originale.
func update_territories_and_mitigation(world: World, season: GameTypes.Season, current_year: int) -> void:
	var mitigation_service := AnimalBirthMitigationService.new()

	for group in world.population_groups:
		if group.population <= 0:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules.birth_season != season:
			continue
		if STAGGER_LEVEL_1_ENABLED and group.territory_dynamics_processed_year == current_year:
			continue
		_process_group(world, group, rules, season, mitigation_service, current_year)

	_print_and_clear_split_summary(world, season)


# Driver giornaliero (spalmamento Livello 1) — chiamato OGNI giorno da WorldTimeService.
# advance_day (mai solo ai confini di stagione, a differenza del checkpoint sopra). No-op
# immediato se STAGGER_LEVEL_1_ENABLED è false (fallback completo, vedi costante) o se nessun
# focus LOD è attivo (world.lod_focus_state vuoto = vista mondo, nessuna lista Livello 1 da cui
# pescare — stesso sentinel già usato ovunque per questo campo).
#
# Per ogni gruppo Livello 1 (world.lod_focus_state["level_1_groups"]): calcola il proprio
# "giorno di turno" deterministico (_get_turn_day, hash(id) modulo la finestra della stagione
# PRECEDENTE al proprio birth_season) e, se oggi è quel giorno e il gruppo non è già marcato come
# elaborato quest'anno, lo elabora SUBITO (mai in una cache per applicazione differita — stesso
# principio già stabilito in altre parti della pipeline: applicare quando si decide, non
# accumulare per dopo). `real_season` è la stagione REALE di oggi (quasi sempre la stagione
# PRECEDENTE al birth_season del gruppo, es. WINTER per un gruppo con birth_season=SPRING) — mai
# rules.birth_season: compute_caloric_ratio usa la stagione passata per il moltiplicatore di
# disponibilità stagionale del foraggio (CaloricCalculator), che deve riflettere la stagione VERA
# di oggi, non quella target del checkpoint di fine finestra.
func process_daily_stagger(world: World, game_data: GameData) -> void:
	if not STAGGER_LEVEL_1_ENABLED:
		return
	if world.lod_focus_state.is_empty():
		return

	var mitigation_service := AnimalBirthMitigationService.new()
	var real_season := SeasonCalculator.get_season_for_day(game_data.current_day)

	for group in world.lod_focus_state["level_1_groups"]:
		if group.population <= 0:
			continue
		if group.territory_dynamics_processed_year == game_data.year:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null:
			continue
		if _get_turn_day(group.id, rules) != game_data.current_day:
			continue
		_process_group(world, group, rules, real_season, mitigation_service, game_data.year)


# Giorno fisso (0-indicizzato, assoluto nell'anno) assegnato a un gruppo all'interno della
# finestra della stagione PRECEDENTE al proprio birth_season — deterministico e stabile finché
# group_id non cambia (mai, per costruzione), nessuno stato aggiuntivo da persistere per
# ricalcolarlo. Caso noto non gestito: una specie con birth_season==WINTER avrebbe una finestra
# precedente (AUTUMN) che attraversa il cambio di GameData.year — nessuna specie lo dichiara oggi
# (vedi commento "Nessun'altra logica gira ancora a fine inverno" in WorldTimeService), quindi
# resta un caso latente, non un bug attivo.
func _get_turn_day(group_id: int, rules: AnimalRules) -> int:
	var previous_season := SeasonCalculator.get_previous_season(rules.birth_season)
	var window := SeasonCalculator.get_season_day_range(previous_season)
	# absi(): hash() non garantisce un risultato non-negativo, e l'operatore % di GDScript su un
	# dividendo negativo restituisce un resto negativo (semantica stile C) — senza absi() qui
	# turn_day potrebbe cadere fuori dall'intervallo [window.x, window.x + window.y).
	return window.x + (absi(hash(group_id)) % window.y)


# Corpo per-gruppo, riusato sia dal checkpoint stagionale (update_territories_and_mitigation)
# sia dal driver giornaliero (process_daily_stagger) — stessa logica esatta indipendentemente da
# CHI la chiama e QUANDO, solo `real_season` cambia (vedi process_daily_stagger sopra per il
# perché). `current_year` marca group.territory_dynamics_processed_year alla fine, solo se lo
# spalmamento è attivo (nessuno stato meaningful da scrivere quando è disattivato — la rete di
# sicurezza in quel caso non legge mai questo campo).
func _process_group(
	world: World, group: PopulationGroup, rules: AnimalRules, real_season: GameTypes.Season,
	mitigation_service: AnimalBirthMitigationService, current_year: int
) -> void:
	# Countdown di recovery post-scissione (Step 10, vedi
	# PopulationGroup.years_since_last_split/_get_post_split_multiplier sotto): incrementato
	# QUI, PRIMA dell'eventuale scissione di quest'anno stesso (_update_group_territory sotto,
	# via PopulationSplitService) — se il gruppo scinde proprio in questo checkpoint, il
	# gruppo di ORIGINE viene riazzerato a 0 SUBITO DOPO, scartando l'incremento di qui sopra:
	# il moltiplicatore calcolato più avanti in questo stesso checkpoint riflette quindi
	# correttamente "anno 0, appena scisso" e non "anno 1". Sentinella -1 = mai scisso (mai
	# incrementata): nessuna specie/gruppo esclusa esplicitamente, si autoesclude per
	# costruzione finché non genera un primo split.
	if group.years_since_last_split >= 0:
		group.years_since_last_split += 1

	# Il ratio calorico è age-weighted (AnimalBirthMitigationService._get_seasonal_requirement):
	# per una specie senza track_age_bands, age_composition resta sempre vuota, quindi il
	# fabbisogno stagionale risulterebbe sempre 0 e il ratio un falso "0.0 = carestia
	# permanente". Nessuna specie erbivora oggi è in questo caso (tutte hanno
	# track_age_bands=true): il criterio calorico resta comunque disattivato (ratio neutro 1.0,
	# nessuna pressione) finché capitasse, il criterio di densità resta invece pienamente
	# specie-agnostico e valido in ogni caso.
	#
	# caloric_criterion_applicable esclude i PredatorRules (wolf) SOLO ai fini del criterio di
	# espansione/contrazione territoriale sotto (_update_group_territory, tramite initial_ratio):
	# quel calcolo legge rules.diet_compatibility (AnimalBirthMitigationService.
	# _get_available_stock), vuoto per design su un predatore puro — non "nessun dato ancora",
	# ma strutturalmente sempre vuoto. Senza questa esclusione il ratio lì risulterebbe sempre
	# 0.0 ("carestia permanente"), con needs_expansion_caloric sempre vero che, con
	# min_territory_cells == max_territory_cells (territorio statico, vedi PredatorRules.gd),
	# fa fallire l'espansione ogni checkpoint e attiva uno split spurio ogni anno, indipendente
	# dalla resa di caccia reale. Il criterio di densità (sotto, _get_density_multiplier/
	# needs_expansion_density) resta invece attivo e specie-agnostico come per gli erbivori —
	# solo la componente calorica del criterio di ESPANSIONE resta neutralizzata. Placeholder
	# fino a quando un vero criterio di espansione/contrazione per predatori (legato alla resa
	# di caccia di PredationService, non ancora progettato) non lo sostituirà.
	#
	# La mitigazione della NATALITÀ (final_ratio_data sotto) è invece un calcolo SEPARATO, non
	# più neutro per i predatori: usa AnimalBirthMitigationService.compute_predator_caloric_ratio
	# (consuntivo di caccia reale accumulato da PredationService, vedi PopulationGroup.
	# predation_season_calories_obtained/_required) invece dello stock territoriale stimato.
	var caloric_criterion_applicable: bool = rules.track_age_bands and not (rules is PredatorRules)
	var initial_ratio_data: Dictionary = {"stock": 0.0, "requirement": 0.0, "ratio": 1.0}
	if caloric_criterion_applicable:
		initial_ratio_data = mitigation_service.compute_caloric_ratio(world, group, rules, real_season)
	var initial_ratio: float = initial_ratio_data["ratio"]

	var territory_result: Dictionary = {}
	if group.territory != null:
		territory_result = _update_group_territory(world, group, rules, initial_ratio)
		if territory_result.get("split_happened", false):
			# Accumulatore su World (non locale): con lo spalmamento attivo questa funzione viene
			# chiamata su giorni diversi per gruppi diversi della stessa finestra, quindi il
			# riepilogo per specie deve sopravvivere tra una chiamata e l'altra fino al checkpoint
			# di fine finestra — vedi World.territory_dynamics_split_counts e
			# _print_and_clear_split_summary sotto. density/caloric/minimum NON sono mutuamente
			# esclusivi (_update_group_territory può avere più criteri veri contemporaneamente per
			# lo stesso split) — la somma dei tre può superare "total" per una specie, non è un
			# errore di conteggio.
			var counts: Dictionary = world.territory_dynamics_split_counts.get(
				group.species_name, {"total": 0, "density": 0, "caloric": 0, "minimum": 0}
			)
			counts["total"] = int(counts["total"]) + 1
			if territory_result["needs_expansion_density"]:
				counts["density"] = int(counts["density"]) + 1
			if territory_result["needs_expansion_caloric"]:
				counts["caloric"] = int(counts["caloric"]) + 1
			if territory_result["needs_expansion_minimum"]:
				counts["minimum"] = int(counts["minimum"]) + 1
			world.territory_dynamics_split_counts[group.species_name] = counts

	if STAGGER_LEVEL_1_ENABLED:
		group.territory_dynamics_processed_year = current_year

	if not rules.track_age_bands:
		return

	var final_ratio_data: Dictionary = {"stock": 0.0, "requirement": 0.0, "ratio": 1.0}
	if rules is PredatorRules:
		final_ratio_data = mitigation_service.compute_predator_caloric_ratio(group)
		# Consuntivo letto: azzerato per il ciclo successivo (dal checkpoint di oggi al
		# prossimo, non l'anno di calendario) — stesso principio di
		# PopulationGroup.yearly_prey_totals, che si azzera da solo al cambio anno.
		group.predation_season_calories_obtained = 0.0
		group.predation_season_calories_required = 0.0
	elif caloric_criterion_applicable:
		final_ratio_data = mitigation_service.compute_caloric_ratio(world, group, rules, real_season)
	var final_ratio: float = final_ratio_data["ratio"]

	# Densità sul territorio DEFINITIVO di quest'anno (dopo _update_group_territory sopra),
	# mai su quello pre-aggiustamento — stesso principio già usato per final_ratio.
	var cell_count_final: int = group.territory.get_cell_count() if group.territory != null else 0
	var density_data := _get_density_multiplier(
		group.population, cell_count_final, rules.max_density_per_cell, rules.base_birth_rate
	)
	var post_split_multiplier := _get_post_split_multiplier(group, rules)

	# log_enabled=false qui: per le specie con min_territory_cells > 1 il log dedicato sotto
	# mostra già ratio_finale/stock/fabbisogno (e ora anche moltiplicatore_post_split/
	# anni_da_split) — aggiungere anche il moltiplicatore lì evita di stampare due righe con
	# la stessa informazione (vedi apply_mitigation_multiplier). Filtro erbivori/predatori:
	# vedi DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS.
	var show_lifecycle_log: bool = (
		DebugLogging.SHOW_PREDATOR_TERRITORY_DYNAMICS_LOGS if rules is PredatorRules
		else DebugLogging.SHOW_HERBIVORE_LIFECYCLE_LOGS
	)
	var multiplier_data := mitigation_service.apply_mitigation_multiplier(
		group, final_ratio, density_data["multiplier"], density_data["ratio"],
		post_split_multiplier, rules.min_territory_cells <= 1 and show_lifecycle_log
	)
	# Solo per il log di AnimalBirthService a fine stagione (vedi PopulationGroup.
	# birth_mitigation_caloric_ratio) — final_ratio grezzo, non clamped_ratio: il valore
	# "come è andata davvero", non quello già tagliato per la curva.
	group.birth_mitigation_caloric_ratio = final_ratio

	if DebugLogging.ENABLED and rules.min_territory_cells > 1 and not territory_result.is_empty() and show_lifecycle_log:
		var years_display: String = (
			"mai scisso" if group.years_since_last_split < 0 else str(group.years_since_last_split)
		)
		print(
			(
				"[TERRITORY DYNAMICS] #%d %s pop=%d celle=%d->%d "
				+ "ratio_iniziale=%.3f (stock=%.1f fabbisogno=%.1f) "
				+ "celle_da_densita=%d occupazione_media=%.2f soglia_contrazione=%.1f "
				+ "azione=%s (%s) "
				+ "ratio_finale=%.3f ratio_clampato=%.3f (stock=%.1f fabbisogno=%.1f) "
				+ "moltiplicatore_calorico=%.3f occupazione_ratio=%.3f moltiplicatore_densita=%.3f "
				+ "anni_da_split=%s moltiplicatore_post_split=%.3f "
				+ "moltiplicatore_finale=%.3f"
			) % [
				group.id, group.species_name, group.population,
				territory_result["cells_before"], territory_result["cells_after"],
				initial_ratio, initial_ratio_data["stock"], initial_ratio_data["requirement"],
				territory_result["density_cells_needed"],
				territory_result["average_occupancy"], territory_result["contraction_threshold"],
				territory_result["action"], territory_result["reason"],
				final_ratio, multiplier_data["clamped_ratio"],
				final_ratio_data["stock"], final_ratio_data["requirement"],
				multiplier_data["caloric_multiplier"], density_data["ratio"], density_data["multiplier"],
				years_display, post_split_multiplier,
				multiplier_data["final_multiplier"]
			]
		)


# Riepilogo split per motivazione — SEMPRE visibile (solo dietro il master switch
# DebugLogging.ENABLED, non dietro SHOW_HERBIVORE_LIFECYCLE_LOGS come il log per-gruppo sopra,
# che per le specie a 1 sola cella come rabbit/partridge non stampa MAI): senza questo, un'ondata
# di centinaia di split per specie a territorio mono-cella resterebbe invisibile per intero.
# Legge/azzera world.territory_dynamics_split_counts (vedi _process_group sopra) invece di un
# accumulatore locale: con lo spalmamento attivo i contributi arrivano da chiamate sparse su ~90
# giorni diversi, quindi l'accumulatore deve sopravvivere tra una chiamata e l'altra di questa
# funzione — con lo spalmamento disattivato tutti i contributi arrivano comunque da un'unica
# chiamata a update_territories_and_mitigation, quindi il comportamento osservabile (una riga di
# riepilogo per specie, stampata una volta a checkpoint) resta identico a prima.
func _print_and_clear_split_summary(world: World, season: GameTypes.Season) -> void:
	var split_counts_by_species: Dictionary = world.territory_dynamics_split_counts
	if DebugLogging.ENABLED and not split_counts_by_species.is_empty():
		for species_name in split_counts_by_species.keys():
			var counts: Dictionary = split_counts_by_species[species_name]
			print(
				(
					"[TERRITORY DYNAMICS SPLIT SUMMARY] stagione=%s specie=%s split_totali=%d "
					+ "per_densita=%d per_calorico=%d per_minimo=%d"
				) % [
					GameTypes.Season.keys()[season], species_name, counts["total"],
					counts["density"], counts["caloric"], counts["minimum"]
				]
			)
	world.territory_dynamics_split_counts = {}

# Un solo controllo per gruppo: prima l'espansione (in OR tra tre criteri indipendenti — densità
# etologica, vincolo calorico, territorio sotto il minimo di specie, vedi sotto), altrimenti la
# contrazione — mutuamente esclusive per costruzione (nessuna condizione può chiedere
# contemporaneamente più celle E meno celle), quindi if/elif, mai entrambe nello stesso checkpoint
# per lo stesso gruppo. Ritorna i dettagli della decisione (per il logging del chiamante), mai
# null/vuoto se raggiunta.
func _update_group_territory(
	world: World, group: PopulationGroup, rules: AnimalRules, caloric_ratio: float
) -> Dictionary:
	var current_cell_count := group.territory.get_cell_count()

	# Criterio 1 di espansione: densità etologica, indipendente dalle risorse (vedi
	# AnimalRules.max_density_per_cell) — nessun clamp qui, è solo il segnale "serve più spazio",
	# non un target di celle da raggiungere in un colpo solo (si espande di una cella alla volta
	# comunque, vedi sotto).
	var density_cells_needed: int = int(ceil(float(group.population) / float(rules.max_density_per_cell)))
	var needs_expansion_density: bool = density_cells_needed > current_cell_count

	# Criterio 2 di espansione: vincolo calorico, sulla stessa soglia RATIO_HIGH_THRESHOLD già
	# usata da AnimalBirthMitigationService per "sopra: nessuna penalità alla natalità" — non un
	# valore dedicato, per non avere due definizioni scoordinate di "questo territorio è in
	# difficoltà" nello stesso sistema.
	var needs_expansion_caloric: bool = caloric_ratio < AnimalBirthMitigationService.RATIO_HIGH_THRESHOLD

	# Criterio 3 di espansione: territorio ancora sotto il minimo etologico di specie
	# (AnimalRules.min_territory_cells), indipendente da densità/calorie — senza questo, un gruppo
	# nato da scissione (PopulationSplitService.attempt_split, che crea SEMPRE un territorio a 1
	# sola cella indipendentemente da min_territory_cells, per design) può restare bloccato ben
	# sotto il minimo della propria specie a tempo indeterminato se cibo e spazio sono già
	# sufficienti per quella popolazione ridotta — nessuno dei primi due criteri si accorgerebbe
	# mai del problema. Un gruppo creato da zero (WorldScene, via TerritoryBuilderService.
	# build_territory con min_territory_cells) parte invece già al minimo, quindi per lui questo
	# criterio è sempre falso fin dal primo checkpoint.
	var needs_expansion_minimum: bool = current_cell_count < rules.min_territory_cells

	# Contrazione: occupazione media (population/celle attuali) confrontata direttamente con METÀ
	# del limite etologico — non un denominatore gonfiato (l'ex fattore ×1.5, concettualmente
	# sbagliato: spostava l'intero limite di riferimento a 27, tollerando densità permanentemente
	# sopra il limite etologico dichiarato di 18 senza mai contrarre). Con la soglia a metà, la
	# "zona morta" di isteresi è [max_density_per_cell/2, max_density_per_cell] — sotto quella
	# banda si contrae, sopra si espande (criterio 1), dentro non si muove nulla: mai una
	# contrazione quando la densità è già pari o sopra il limite etologico normale.
	var average_occupancy: float = float(group.population) / float(current_cell_count)
	var contraction_threshold: float = float(rules.max_density_per_cell) / 2.0
	var needs_contraction: bool = (
		average_occupancy < contraction_threshold and current_cell_count > rules.min_territory_cells
	)

	var action := "nessun cambiamento"
	var reason := "nessun criterio soddisfatto"
	# Per il riepilogo aggregato del chiamante (update_territories_and_mitigation) — vedi il
	# Dictionary di ritorno in fondo: true SOLO se lo split è stato TENTATO e RIUSCITO in questo
	# checkpoint (mai per una semplice espansione riuscita, mai per un tentativo fallito).
	var split_succeeded := false

	if needs_expansion_density or needs_expansion_caloric or needs_expansion_minimum:
		# Stessa cache di AnimalHungerService._attempt_expansion (vedi
		# PopulationGroup.blocked_territory_search_version per la spiegazione completa): se
		# l'ultima ricerca di questo gruppo è fallita e nessun territorio della sua specie si è
		# liberato da allora (World.species_territory_release_version invariato), la ricerca di
		# qui darebbe con certezza lo stesso esito — questo checkpoint gira solo una volta a
		# stagione (non ogni giorno come l'altro chiamante), ma condivide lo stesso campo di
		# cache: senza questo gate ignorerebbe silenziosamente lo stato "bloccato" già accertato
		# nel frattempo dai controlli giornalieri.
		var current_release_version: int = int(
			world.species_territory_release_version.get(group.species_name, 0)
		)
		if group.blocked_territory_search_version == current_release_version:
			reason = "ricerca territorio saltata (nessun rilascio dal precedente fallimento)"
		else:
			var expanded := false
			if current_cell_count >= rules.max_territory_cells:
				reason = "espansione richiesta ma territorio già a max_territory_cells (%d)" % rules.max_territory_cells
			elif rules is PredatorRules:
				# Predatori (Step 8b): salto diretto alla cella-target del criterio di densità,
				# invece del passo ±1 annuale degli erbivori — vedi TerritoryBuilderService.
				# expand_by_n_cells. target_cells incorpora già sia il criterio di densità sia quello
				# di minimo etologico (clamp inferiore a min_territory_cells); il criterio calorico
				# resta strutturalmente neutro per i predatori (vedi caloric_criterion_applicable in
				# update_territories_and_mitigation) quindi non contribuisce qui.
				var target_cells: int = clamp(density_cells_needed, rules.min_territory_cells, rules.max_territory_cells)
				var cells_to_add: int = target_cells - current_cell_count
				var added := TerritoryBuilderService.new().expand_by_n_cells(
					world, group.territory, group.species_name, cells_to_add
				)
				# Territorio DAVVERO cambiato forma (added>0, anche se parziale) -> il patrol_route
				# esistente riflette la forma VECCHIA e va ricalcolato, preservando la posizione
				# attuale del branco invece di un reset a 0 (Step 7, vedi
				# PredatorPatrolService.recompute_route_preserving_position). Nessuna chiamata se
				# added==0: il territorio non è cambiato, il percorso esistente resta valido.
				if added > 0:
					PredatorPatrolService.new().recompute_route_preserving_position(group, rules as PredatorRules)
				# Successo solo se il salto raggiunge ESATTAMENTE il target di quest'anno — un
				# risultato parziale (BFS esaurita prima di cells_to_add, rivali/mare tutt'intorno)
				# cade comunque nel ramo "not expanded" sotto e tenta anche uno split per la
				# pressione residua, invece di considerarsi "abbastanza". Le celle comunque trovate
				# restano acquisite (expand_by_n_cells non fa rollback), mai perse.
				expanded = added == cells_to_add
				if expanded:
					action = "espande di %d celle" % added
					reason = _expansion_reason(needs_expansion_density, needs_expansion_caloric, needs_expansion_minimum)
					group.blocked_territory_search_version = -1
				elif added > 0:
					action = "espande di %d celle (parziale, target %d)" % [added, target_cells]
					reason = "espansione richiesta ma BFS esaurita prima del target (%d/%d)" % [added, cells_to_add]
				else:
					reason = "espansione richiesta ma nessuna cella libera raggiungibile"
			else:
				expanded = TerritoryBuilderService.new().expand_by_one_cell(world, group.territory, group.species_name)
				if expanded:
					action = "espande di 1 cella"
					reason = _expansion_reason(needs_expansion_density, needs_expansion_caloric, needs_expansion_minimum)
					group.blocked_territory_search_version = -1
				else:
					reason = "espansione richiesta ma nessuna cella libera raggiungibile"

			# Espansione fallita, per qualunque motivo (già a max_territory_cells sopra, o BFS satura
			# appena sopra) — un unico segnale (false), non serve distinguere il perché: prova a
			# staccare una porzione della popolazione in un nuovo gruppo altrove (Step 9) PRIMA di
			# lasciare che la sola pressione calorica/fame gestisca la situazione. Surplus = quanti
			# individui eccedono la capacità etologica del territorio ATTUALE — letta FRESCA da
			# group.territory.get_cell_count() qui, non dalla variabile current_cell_count catturata
			# a inizio funzione: per gli erbivori le due coincidono sempre (espansione fallita lì
			# significa sempre zero celle aggiunte), ma per i predatori un'espansione PARZIALE
			# (ramo sopra) ha già fatto crescere il territorio senza far scattare "expanded" — usare
			# il valore stantio sovrastimerebbe la pressione residua ignorando le celle appena
			# guadagnate. Floor MIN_DISPERSAL_SHARE_FRACTION già usato anche dal trigger di fame in
			# AnimalHungerService, stessa costante condivisa per non avere due soglie scoordinate.
			if not expanded:
				var cell_count_after_expansion_attempt: int = group.territory.get_cell_count()
				var surplus: int = int(max(
					0.0,
					float(group.population) - (float(cell_count_after_expansion_attempt) * rules.max_density_per_cell)
				))
				var split_amount: int
				if rules is PredatorRules:
					# Predatori: floor al 50% della popolazione invece del 5% (MIN_DISPERSAL_SHARE_
					# FRACTION) usato dagli erbivori — con popolazioni piccole (branco lupo max ~15) il
					# 5% vale sempre 1 solo individuo, quasi certamente destinato a morire di fame da
					# solo (bassa hunting_efficiency_by_age da giovane, nessuna caccia di gruppo
					# possibile in solitaria) — uno spreco netto per il branco d'origine, non un vero
					# nuovo branco fondatore. Al 50% entrambe le metà restano gruppi credibili, con una
					# composizione d'età rappresentativa (dispersal_share_by_age) invece di un singolo
					# disperso casuale. surplus resta comunque il floor dominante nei casi di
					# sovraffollamento severo (population molto oltre la capacità del territorio
					# attuale), dove metà non basterebbe a riportare il gruppo d'origine sotto la
					# propria capacità — stesso principio "il più esigente dei due criteri vince" già
					# usato per gli erbivori, solo con una soglia diversa.
					split_amount = max(surplus, int(group.population / 2))
				else:
					split_amount = max(
						surplus, int(ceil(float(group.population) * PopulationSplitService.MIN_DISPERSAL_SHARE_FRACTION))
					)
				# Stesso criterio (densità/calorico/minimo) già determinato sopra per il tentativo di
				# espansione fallito — riusato qui solo per il log di PopulationSplitService, non
				# ricalcolato: lo split non ha un "perché" proprio, eredita quello dell'espansione che
				# lo ha preceduto nello stesso checkpoint.
				var split_trigger_reason := _expansion_reason(needs_expansion_density, needs_expansion_caloric, needs_expansion_minimum)
				var new_group := PopulationSplitService.new().attempt_split(world, group, rules, split_amount, split_trigger_reason)
				if new_group != null:
					# FIX classificazione LOD per split da spalmamento giornaliero (vedi
					# LODOrchestrator.register_new_group per il perché): questa stessa funzione è
					# chiamata sia dal checkpoint stagionale (dove _run_lod_focus_refresh_checkpoint
					# ricalcolerà comunque tutto subito dopo — questa chiamata è lì ridondante ma
					# innocua) sia da process_daily_stagger (dove PRIMA di questo fix il nuovo
					# gruppo restava fuori da entrambe le liste fino al checkpoint successivo,
					# trattato per default come Livello 2 — calcolo individuale ogni giorno invece
					# che aggregato stagionale).
					LODOrchestrator.register_new_group(world, new_group)
					action = "scissione di %d individui" % split_amount
					reason += " -> scissione riuscita"
					group.blocked_territory_search_version = -1
					split_succeeded = true
				else:
					group.blocked_territory_search_version = current_release_version
	elif needs_contraction:
		if rules is PredatorRules:
			# Predatori: stesso principio di salto diretto usato per l'espansione sopra, applicato
			# in senso inverso — vedi TerritoryBuilderService.contract_by_n_cells.
			var target_cells: int = clamp(density_cells_needed, rules.min_territory_cells, rules.max_territory_cells)
			var cells_to_release: int = current_cell_count - target_cells
			var released := TerritoryBuilderService.new().contract_by_n_cells(
				world, group.territory, group.species_name, cells_to_release
			)
			action = "contrae di %d celle" % released
			# Stesso motivo del ramo di espansione sopra: territorio cambiato forma -> patrol_route
			# va ricalcolato preservando la posizione attuale (Step 7).
			if released > 0:
				PredatorPatrolService.new().recompute_route_preserving_position(group, rules as PredatorRules)
		else:
			_contract_by_one_cell(world, group)
			action = "contrae di 1 cella"
		reason = "occupazione media sotto soglia isteresi (%.2f < %.1f)" % [average_occupancy, contraction_threshold]

	return {
		"cells_before": current_cell_count,
		"cells_after": group.territory.get_cell_count(),
		"density_cells_needed": density_cells_needed,
		"average_occupancy": average_occupancy,
		"contraction_threshold": contraction_threshold,
		"action": action,
		"reason": reason,
		"split_happened": split_succeeded,
		"needs_expansion_density": needs_expansion_density,
		"needs_expansion_caloric": needs_expansion_caloric,
		"needs_expansion_minimum": needs_expansion_minimum,
	}


# Mitigazione della natalità legata alla densità ETOLOGICA del territorio (AnimalRules.
# max_density_per_cell) — indipendente dalla disponibilità calorica sopra, MOLTIPLICA il
# moltiplicatore calorico già esistente invece di sostituirlo (vedi
# AnimalBirthMitigationService.apply_mitigation_multiplier, unico punto dove i due si combinano).
# occupazione_ratio = population / (celle_attuali del territorio DEFINITIVO di quest'anno ×
# max_density_per_cell) — SEMPRE la capacità dell'INTERO territorio, mai il valore per singola
# cella isolato: stessa formula identica per un territorio a 1 cella (rabbit) o multi-cella (deer).
#
# base_birth_rate sceglie il "mid" (FAST/SLOW), e per le lente population lo raffina ulteriormente
# (SLOW/SLOW_SMALL) — vedi le costanti sopra per il perché di entrambe le distinzioni. Poi la
# stessa forma di curva si applica a tutte e tre le categorie, continua in ogni punto di
# rottura: sotto DENSITY_RATIO_RAMP_START (0.7) nessuna penalità (1.0); da lì a
# DENSITY_RATIO_FULL_CAPACITY (1.0) scende al mid della specie seguendo un easing QUADRATICO (t²,
# non lineare) — la frenata resta debole per la maggior parte del tratto (es. per una specie
# "veloce", a ratio=0.9 il moltiplicatore è ancora ~0.58, non ~0.37 come sarebbe con una rampa
# lineare) e si concentra quasi tutta negli ultimi passi verso 1.0; da lì a DENSITY_RATIO_RAMP_END
# (1.5) scende LINEARMENTE dal proprio mid fino a 0.0 esatto (mai un plateau piatto uguale per
# tutte le specie in questo tratto — vedi commento sopra sul perché). Oltre RAMP_END resta a 0.0
# per tutti — a differenza del solo vincolo calorico che con risorse abbondanti lascia la natalità
# a pieno regime anche a densità già assurde (osservato in test: 14000+ individui in una cella con
# max_density_per_cell=200, prima che fame/espansione avessero modo di intervenire).
func _get_density_multiplier(
	population: int, cell_count: int, max_density_per_cell: float, base_birth_rate: float
) -> Dictionary:
	var capacity: float = cell_count * max_density_per_cell
	if capacity <= 0:
		return {"ratio": 0.0, "multiplier": 1.0}

	var ratio: float = float(population) / float(capacity)
	var mid: float
	if base_birth_rate >= DENSITY_FAST_GROWTH_BIRTH_RATE_THRESHOLD:
		mid = DENSITY_MULTIPLIER_MID_FAST
	elif population <= DENSITY_SMALL_POPULATION_THRESHOLD:
		mid = DENSITY_MULTIPLIER_MID_SLOW_SMALL
	else:
		mid = DENSITY_MULTIPLIER_MID_SLOW
	var multiplier: float

	if ratio < DENSITY_RATIO_RAMP_START:
		multiplier = 1.0
	elif ratio < DENSITY_RATIO_FULL_CAPACITY:
		var t: float = (ratio - DENSITY_RATIO_RAMP_START) / (DENSITY_RATIO_FULL_CAPACITY - DENSITY_RATIO_RAMP_START)
		multiplier = lerp(1.0, mid, t * t)
	elif ratio < DENSITY_RATIO_RAMP_END:
		var t: float = (ratio - DENSITY_RATIO_FULL_CAPACITY) / (DENSITY_RATIO_RAMP_END - DENSITY_RATIO_FULL_CAPACITY)
		multiplier = lerp(mid, 0.0, t)
	else:
		multiplier = 0.0

	return {"ratio": ratio, "multiplier": multiplier}


# Terza mitigazione della natalità (Step 10 del refactoring fauna), indipendente da calorico e
# densità sopra — recovery TEMPORANEO applicato SOLO al gruppo che ha generato uno split come
# ORIGINE (mai al nuovo gruppo scisso, che parte con years_since_last_split=-1, vedi
# PopulationGroup), per rallentare le scissioni ravvicinate anno dopo anno: la natalità del
# gruppo appena alleggerito riparte a metà regime e recupera gradualmente. Rampa LINEARE (non
# quadratica come la densità sopra: qui la richiesta esplicita è un decremento/recupero costante,
# non una frenata concentrata) da 0.5 (anno 0, appena scisso) a 1.0 (recovery completo, raggiunto
# a post_split_recovery_years). Sentinella -1 = mai scisso -> nessuna penalità. Guard su
# post_split_recovery_years <= 0 (specie che non lo dichiara esplicitamente, o lo dichiara a 0):
# trattato come recovery istantaneo, mai una divisione per zero.
func _get_post_split_multiplier(group: PopulationGroup, rules: AnimalRules) -> float:
	if group.years_since_last_split < 0 or rules.post_split_recovery_years <= 0:
		return 1.0
	if group.years_since_last_split >= rules.post_split_recovery_years:
		return 1.0
	return 0.5 + (0.5 / float(rules.post_split_recovery_years)) * float(group.years_since_last_split)


# Generico su un numero qualunque di criteri contemporaneamente veri (prima a due, ora a tre con
# needs_minimum) — invece di enumerare a mano tutte le combinazioni binarie (che raddoppiavano ad
# ogni nuovo criterio aggiunto), costruisce l'elenco delle ragioni vere e le unisce con " e ",
# stesso pattern già usato da AnimalHungerService._format_bucket_summary per unire un Array[String].
func _expansion_reason(needs_density: bool, needs_caloric: bool, needs_minimum: bool) -> String:
	var reasons: Array[String] = []
	if needs_minimum:
		reasons.append("sotto il territorio minimo di specie")
	if needs_density:
		reasons.append("densita etologica")
	if needs_caloric:
		reasons.append("vincolo calorico (ratio < %.1f)" % AnimalBirthMitigationService.RATIO_HIGH_THRESHOLD)
	return " e ".join(reasons)


# Rilascia UNA sola cella per checkpoint — la più lontana dal baricentro — stesso approccio
# incrementale già usato dall'espansione (expand_by_one_cell): un passo alla volta, mai un salto
# diretto a un numero di celle "ottimale" calcolato in anticipo. Mai sotto min_territory_cells:
# già garantito dal chiamante, che valuta needs_contraction solo se current_cell_count >
# min_territory_cells. Eventuali pesi orfani in territory_distribution_weights per la cella
# rilasciata non richiedono pulizia: PopulationGroup.get_population_by_cell() itera solo
# territory.occupied_macrocells corrente (le chiavi in più vengono semplicemente ignorate), e
# PopulationTerritoryShuffleService sovrascrive comunque l'intero dizionario al prossimo cambio
# di stagione. Rilascia davvero una cella per un rivale della stessa specie in cerca di spazio —
# World.release_species_territory va chiamata qui (non nel chiamante, per non poterla dimenticare
# in un futuro secondo punto che rilasci celle), così i gruppi bloccati di questa specie sanno che
# vale la pena riprovare la ricerca (vedi PopulationGroup.blocked_territory_search_version).
func _contract_by_one_cell(world: World, group: PopulationGroup) -> void:
	var cells := group.territory.occupied_macrocells
	if cells.size() <= 1:
		return

	var centroid := group.territory.get_centroid()
	var farthest: Vector2i = cells[0]
	var farthest_distance := _manhattan_distance(farthest, centroid)
	for coords in cells:
		var distance := _manhattan_distance(coords, centroid)
		if distance > farthest_distance:
			farthest = coords
			farthest_distance = distance

	cells.erase(farthest)
	world.release_species_territory(group.species_name)


static func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
