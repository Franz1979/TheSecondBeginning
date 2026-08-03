class_name PopulationGroup
extends RefCounted

# Stato runtime di una popolazione animale "vera" (oggi solo rabbit) — non serializzato come
# .tres (i parametri di specie restano su AnimalRules), solo salvato/caricato come dato di
# partita (vedi GameSaveService/GameLoadService). Step 1 del refactoring fauna: sposta la
# ownership da MacroCellState (dizionari per-specie dentro la cella) a World (array di gruppi).
# Step 4: la cella occupata è ora un Territory (vedi Territory.gd) invece di una coppia di
# coordinate semplice — oggi un territorio ha sempre esattamente una macrocella
# (Territory.occupied_macrocells.size() == 1), nessun cambiamento di comportamento osservabile.
var species_name: String = ""
var population: int = 0
var age_composition: Dictionary = {} # AgeBand -> int
var territory: Territory = null
# Moltiplicatore di mitigazione della natalità legato alla disponibilità calorica del territorio
# (vedi AnimalBirthMitigationService), applicato in AnimalBirthService IN AGGIUNTA a
# fertility_multiplier_by_age/base_birth_rate — non li sostituisce. Default 1.0 (nessuna
# penalità): finché non è mai stato calcolato (es. gruppo appena creato prima del primo
# checkpoint a inizio birth_season), il comportamento resta quello di sempre. Non persistito nei
# save: si ricalcola comunque al prossimo checkpoint annuale, non vale la pena salvarlo.
var birth_mitigation_multiplier: float = 1.0
# Pesi (Vector2i -> float, non normalizzati) usati da get_population_by_cell() per ripartire
# population tra le celle del territorio — Step 6 del refactoring fauna: sostituisce la
# ripartizione uniforme fissa con una variazione casuale ricalcolata periodicamente (vedi
# PopulationTerritoryShuffleService), per dare l'impressione visiva di un branco che si sposta
# nel proprio areale nel tempo invece di un contatore diviso meccanicamente in parti sempre
# uguali. Default vuoto: get_population_by_cell() tratta una chiave assente come peso 1.0, quindi
# un gruppo mai rimescolato (o con territorio a 1 sola cella, mai scritto qui) degrada esattamente
# alla vecchia ripartizione uniforme, nessun ramo speciale altrove. Non persistito nei save,
# stesso trattamento di birth_mitigation_multiplier sopra: si ricalcola al prossimo checkpoint
# stagionale, non vale la pena salvarlo.
var territory_distribution_weights: Dictionary = {}

func _init(_species_name: String = "", _territory: Territory = null) -> void:
	species_name = _species_name
	territory = _territory


func set_population(count: int) -> void:
	population = max(count, 0)


func set_birth_mitigation_multiplier(value: float) -> void:
	birth_mitigation_multiplier = clamp(value, 0.0, 1.0)


func set_territory_distribution_weights(weights: Dictionary) -> void:
	territory_distribution_weights = weights


func get_age_count(age_band: GameTypes.AgeBand) -> int:
	return int(age_composition.get(age_band, 0))

func set_age_count(age_band: GameTypes.AgeBand, amount: int) -> void:
	age_composition[age_band] = max(amount, 0)

func get_age_total() -> int:
	var total := 0
	for amount in age_composition.values():
		total += int(amount)
	return total


# Sovrascrive interamente la composizione età ripartendo `total` individui secondo `weights`
# (in genere AnimalRules.initial_age_ratio) — pensata per un chiamante che può risettare il
# totale più volte sullo stesso gruppo (oggi solo il pulsante debug "set rabbit population"),
# quindi resetta prima di ridistribuire invece di sommarsi a quanto già presente. weights
# vuoto/tutto a 0 => pesi uguali tra le tre fasce, stesso fallback di initial_age_ratio altrove.
# Riusa MacroCellState._split_by_weight (stesso algoritmo "largest remainder" già condiviso da
# subtype/age-band vegetali, non duplicato qui).
func set_age_composition(total: int, weights: Dictionary) -> void:
	age_composition = {}
	if total <= 0:
		return
	var source_weights := weights
	if source_weights.is_empty():
		source_weights = {
			GameTypes.AgeBand.YOUNG: 1.0,
			GameTypes.AgeBand.ADULT: 1.0,
			GameTypes.AgeBand.OLD: 1.0,
		}
	var split := MacroCellState._split_by_weight(source_weights, total)
	for age_band in split.keys():
		set_age_count(age_band, get_age_count(age_band) + split[age_band])


# Maturazione annuale: young->adult dopo youth_duration_years, adult->old dopo
# adult_duration_years — durate PROPRIE di ciascuna fascia, indipendenti tra loro (non soglie
# cumulative di età dalla nascita), stessa logica frazionaria già usata per la vegetazione. Un
# individuo avanza al massimo di una fascia per anno, mai due nello stesso ciclo. Nessuna
# modifica al totale: population non va toccato qui (il chiamante, AnimalAgeBandService, gira
# PRIMA delle nascite nello stesso checkpoint stagionale).
func apply_age_band_maturation(youth_duration_years: int, adult_duration_years: int) -> void:
	var young_count := get_age_count(GameTypes.AgeBand.YOUNG)
	var adult_count := get_age_count(GameTypes.AgeBand.ADULT)
	if young_count <= 0 and adult_count <= 0:
		return

	var young_to_adult: int = 0
	if youth_duration_years > 0:
		young_to_adult = min(int(round(float(young_count) / float(youth_duration_years))), young_count)

	var adult_to_old: int = 0
	if adult_duration_years > 0:
		adult_to_old = min(int(round(float(adult_count) / float(adult_duration_years))), adult_count)

	if young_to_adult <= 0 and adult_to_old <= 0:
		return

	set_age_count(GameTypes.AgeBand.YOUNG, young_count - young_to_adult)
	set_age_count(GameTypes.AgeBand.ADULT, adult_count - adult_to_old + young_to_adult)
	set_age_count(GameTypes.AgeBand.OLD, get_age_count(GameTypes.AgeBand.OLD) + adult_to_old)


# Aggiunge `amount` nuovi nati alla fascia YOUNG, incrementando anche population della stessa
# quantità — le due scritture avvengono insieme così l'invariante "somma delle fasce ==
# population" resta valida sia prima che dopo. Il chiamante (AnimalBirthService) garantisce che
# questo giri sempre DOPO la maturazione dello stesso checkpoint, così i nuovi nati non maturano
# mai nello stesso ciclo in cui compaiono.
func apply_births(amount: int) -> void:
	if amount <= 0:
		return
	set_age_count(GameTypes.AgeBand.YOUNG, get_age_count(GameTypes.AgeBand.YOUNG) + amount)
	set_population(population + amount)


# Sottrae `amount` morti per vecchiaia dalla fascia OLD, decrementando anche population della
# stessa quantità — gemella di apply_births ma in sottrazione. set_age_count/set_population
# clampano già a 0, quindi nessun rischio di andare in negativo anche in caso di arrotondamenti
# al limite.
func apply_old_age_mortality(amount: int) -> void:
	if amount <= 0:
		return
	set_age_count(GameTypes.AgeBand.OLD, get_age_count(GameTypes.AgeBand.OLD) - amount)
	set_population(population - amount)


# Ripartisce `population` tra le celle del territorio secondo territory_distribution_weights
# (Step 6: variazione casuale ricalcolata a ogni checkpoint stagionale da
# PopulationTerritoryShuffleService — vedi il campo sopra) — una chiave assente in quel
# dizionario vale peso 1.0, quindi un territorio a 1 sola cella (mai scritto lì, rabbit) o un
# gruppo appena creato prima del primo rimescolamento degradano automaticamente alla vecchia
# ripartizione uniforme, senza bisogno di un ramo a parte qui. Split ricalcolato da zero a ogni
# chiamata (non solo i pesi cambiano raramente, anche `population` stesso può cambiare in
# qualunque momento — es. i pulsanti debug — quindi il risultato resta sempre coerente col
# valore CORRENTE di population, mai una quantità congelata al momento del rimescolamento). Riusa
# lo stesso "largest remainder" (MacroCellState._split_by_weight) già condiviso da subtype/age-band
# vegetali e dalla composizione età sopra. Unica fonte condivisa da AnimalConsumptionService
# (ripartizione del fabbisogno) e dai pannelli UI/renderer (quota animali per cella), così non
# possono mai disallinearsi.
func get_population_by_cell() -> Dictionary:
	var result: Dictionary = {}
	if territory == null or population <= 0:
		return result
	var weights: Dictionary = {}
	for coords in territory.occupied_macrocells:
		weights[coords] = float(territory_distribution_weights.get(coords, 1.0))
	return MacroCellState._split_by_weight(weights, population)


# Composizione età SOLO per la quota di `coords` (vedi get_population_by_cell) — non stato reale,
# derivata a scopo di visualizzazione (nessuna age band è tracciata per cella nel modello, solo a
# livello di gruppo). Ripartisce la quota della cella tra le tre fasce in proporzione alla
# composizione età corrente del gruppo intero (stesso fallback a pesi uguali se age_composition è
# vuota, coerente con set_age_composition), così la somma Y+A+O di questa cella torna sempre
# esattamente uguale alla quota mostrata per la cella.
func get_age_composition_in_cell(coords: Vector2i) -> Dictionary:
	var population_by_cell := get_population_by_cell()
	var cell_population: int = int(population_by_cell.get(coords, 0))
	if cell_population <= 0:
		return {}

	var weights: Dictionary = {}
	for age_band in age_composition.keys():
		var count: float = float(age_composition[age_band])
		if count > 0.0:
			weights[age_band] = count
	if weights.is_empty():
		weights = {
			GameTypes.AgeBand.YOUNG: 1.0,
			GameTypes.AgeBand.ADULT: 1.0,
			GameTypes.AgeBand.OLD: 1.0,
		}

	return MacroCellState._split_by_weight(weights, cell_population)
