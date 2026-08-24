class_name CellRichnessCalculator
extends RefCounted

# Valuta quanto e' "ricca" una macrocella, per il criterio di partenza opzionale "Ricchezza
# cella di partenza" di NewGameOptionsMenu (vedi FirstStartMacroCellSelectionService, che ordina
# le celle candidate per questo punteggio e ne ritaglia tre fasce povera/media/ricca). Punteggio
# piu' alto = piu' ricca; nessun range assoluto, solo l'ordinamento relativo conta.
#
# NORMALIZZAZIONE PER ASSE (confermata con l'utente, dopo un calcolo di esempio con i dati reali
# del progetto): le tre componenti hanno scale grezze radicalmente diverse — il vegetale usa
# yield_ratio 30-70x (acorn/fruit/berry) su quantita' gia' nell'ordine delle migliaia, arrivando
# a MILIONI di calorie; l'animale (popolazione x prey_calories, 8-300 per individuo) resta
# nell'ordine delle migliaia anche con un territorio pieno; l'ibrida (fish_meat/bird_meat senza
# yield_ratio, FISH/BIRDS che a inizio partita riempiono solo il 2-6% della capacita' contro il
# 30%+ della vegetazione) resta ancora piu' piccola. Sommare i valori GREZZI pesati (0.5/0.3/0.2,
# schema precedente) rendeva la componente vegetale >99.8% del punteggio — animale e ibrida
# risultavano matematicamente irrilevanti, coerente con quanto osservato in game (RICH sceglieva
# quasi sempre celle con tanta vegetazione e zero animali). Fix: ogni componente viene divisa per
# il MASSIMO della stessa componente osservato nel batch corrente (min-max a 0-1, min implicito
# a 0) PRIMA di applicare i pesi — cosi' i pesi esprimono davvero l'importanza relativa voluta,
# non vengono annullati dalla scala. Se il massimo di un asse e' 0 in tutto il batch (es. nessuna
# cella candidata ha calorie ibride), quell'asse contribuisce 0 per tutte le celle, mai una
# divisione per zero.
const VEGETAL_WEIGHT := 0.4
const ANIMAL_WEIGHT := 0.4
const HYBRID_WEIGHT := 0.2

# Vegetali: SOLO i sottotipi commestibili dall'uomo (wild_fruit/domesticable_fruit su TREE,
# fruit_bearing su SHRUB) — FORAGE (GRASS) escluso di proposito, non consumabile dagli umani
# (confermato con l'utente). Nessun altro sottotipo commestibile esiste oggi nel progetto (GRASS
# resta untracked, ROCK non e' cibo).
const VEGETAL_SOURCES: Array[String] = ["acorn", "fruit", "berry"]

# Ibride: fish_meat/bird_meat (placeholder — nessuna fonte calorica esisteva per loro prima
# d'ora, valori provvisori da ritarare, vedi fish_meat.tres/bird_meat.tres — stesso schema di
# FORAGE: consuming_depletes_primary=true, nessuno stock/sottotipo, non ancora una risorsa
# secondaria gestibile dal giocatore) + eggs (gia' definita, quella si' a stock).
const HYBRID_SOURCES: Array[String] = ["fish_meat", "bird_meat", "eggs"]

# Risorsa primaria da cui ciascuna fonte calorica deriva — CaloricSourceRules non lo dichiara da
# sola (lo sa solo il chiamante, stesso schema gia' in uso in WorldTimeService._SECONDARY_SOURCES
# per il checkpoint stagionale), quindi la mappatura e' ripetuta qui.
const _SOURCE_PRIMARY_TYPE := {
	"acorn": GameTypes.WorldObjectType.TREE,
	"fruit": GameTypes.WorldObjectType.TREE,
	"berry": GameTypes.WorldObjectType.SHRUB,
	"fish_meat": GameTypes.WorldObjectType.FISH,
	"bird_meat": GameTypes.WorldObjectType.BIRDS,
	"eggs": GameTypes.WorldObjectType.BIRDS,
}


# Valuta un intero gruppo di celle in un colpo solo (invece di una evaluate_richness(world, pos)
# per cella): sia la componente animale (territori) sia le regole delle fonti caloriche
# (CaloricSourceRules, altrimenti ricaricate ad ogni singola cella x stagione — su ~10.000
# candidate diventa rapidamente il collo di bottiglia dominante) vengono preparate UNA volta sola
# per l'intero batch, non ripetute per ogni candidata — stesso principio gia' seguito da
# FirstStartMacroCellSelectionService._collect_predator_territory_cells.
func evaluate_richness_batch(world: World, positions: Array[Vector2i]) -> Dictionary:
	var animal_calories_by_cell := _collect_animal_calories_by_cell(world, positions)
	var vegetal_rules := _load_source_rules(VEGETAL_SOURCES)
	var hybrid_rules := _load_source_rules(HYBRID_SOURCES)

	# Passata 1: raccogli le tre componenti GREZZE per ogni candidata, e il massimo di ciascuna
	# nell'intero batch (serve per la normalizzazione nella passata 2 sotto).
	var vegetal_by_cell: Dictionary = {}
	var hybrid_by_cell: Dictionary = {}
	var max_vegetal := 0.0
	var max_animal := 0.0
	var max_hybrid := 0.0

	for pos in positions:
		var cell := world.get_cell_at(pos.x, pos.y)
		var state := world.get_cell_state_at(pos.x, pos.y)
		if cell == null or state == null:
			vegetal_by_cell[pos] = 0.0
			hybrid_by_cell[pos] = 0.0
			continue

		var vegetal_calories := _sum_max_seasonal_calories(vegetal_rules, cell, state)
		var hybrid_calories := _sum_max_seasonal_calories(hybrid_rules, cell, state)
		vegetal_by_cell[pos] = vegetal_calories
		hybrid_by_cell[pos] = hybrid_calories

		max_vegetal = maxf(max_vegetal, vegetal_calories)
		max_hybrid = maxf(max_hybrid, hybrid_calories)
	for pos in positions:
		max_animal = maxf(max_animal, float(animal_calories_by_cell.get(pos, 0.0)))

	# Passata 2: normalizza ciascuna componente sul proprio massimo di batch (0 se il massimo di
	# quell'asse e' 0 — nessuna divisione per zero, l'asse resta semplicemente muto per tutte le
	# celle), poi applica i pesi.
	var scores: Dictionary = {}
	for pos in positions:
		var vegetal_norm: float = float(vegetal_by_cell[pos]) / max_vegetal if max_vegetal > 0.0 else 0.0
		var animal_norm: float = float(animal_calories_by_cell.get(pos, 0.0)) / max_animal if max_animal > 0.0 else 0.0
		var hybrid_norm: float = float(hybrid_by_cell[pos]) / max_hybrid if max_hybrid > 0.0 else 0.0

		scores[pos] = VEGETAL_WEIGHT * vegetal_norm + ANIMAL_WEIGHT * animal_norm + HYBRID_WEIGHT * hybrid_norm

	return scores


# source_name -> CaloricSourceRules gia' risolta, per evitare che get_caloric_source_rules
# (ResourceLoader.exists + load ad ogni chiamata) venga rifatto per ogni singola combinazione
# cella x stagione — con centinaia/migliaia di candidate sarebbe altrimenti l'operazione
# dominante dell'intero calcolo.
func _load_source_rules(source_names: Array[String]) -> Dictionary:
	var rules_by_source: Dictionary = {}
	for source_name in source_names:
		var rules := CaloricCalculator.get_caloric_source_rules(source_name)
		if rules != null:
			rules_by_source[source_name] = rules
	return rules_by_source


# Somma, su tutte le fonti in "rules_by_source", le calorie massime raggiungibili indipendenti
# dalla stagione attuale: MAX su tutte e 4 le stagioni di CaloricCalculator.get_available_calories
# (il tetto teorico, non lo stock persistente attuale — per fonti stateless come fish/bird_meat/
# forage coincide comunque con l'unico valore possibile, dato che il loro moltiplicatore
# stagionale e' 1.0 su tutto l'anno). Salto rapido se la risorsa primaria collegata e' assente
# nella cella (resource_quantity <= 0): nessun sottotipo puo' produrre calorie senza di essa.
func _sum_max_seasonal_calories(rules_by_source: Dictionary, cell: MacroCellData, state: MacroCellState) -> float:
	var total := 0.0
	for source_name in rules_by_source:
		var rules: CaloricSourceRules = rules_by_source[source_name]
		var primary_type: GameTypes.WorldObjectType = _SOURCE_PRIMARY_TYPE[source_name]
		if state.get_resource_quantity(primary_type) <= 0:
			continue

		var best := 0.0
		for season in range(GameTypes.Season.size()):
			var calories := CaloricCalculator.get_available_calories(rules, cell, state, primary_type, season)
			if calories > best:
				best = calories
		total += best
	return total


# Calorie-animali per cella: solo popolazioni ERBIVORE (rules is NOT PredatorRules — un branco
# predatore presente non e' "cibo disponibile", e' gia' gestito a parte dal toggle "escludi
# territori predatori", confermato con l'utente). Per ciascun gruppo idoneo, per ciascuna cella
# del suo territorio in "positions": popolazione della cella per fascia d'eta' (
# get_age_composition_in_cell) x AnimalRules.prey_calories x size_multiplier_by_age[fascia] —
# stessa scalatura per eta' gia' documentata su AnimalRules.prey_calories per il futuro
# PredationService, qui riusata identica.
func _collect_animal_calories_by_cell(world: World, positions: Array[Vector2i]) -> Dictionary:
	var positions_set: Dictionary = {}
	for pos in positions:
		positions_set[pos] = true

	var calories_by_cell: Dictionary = {}
	for group in world.population_groups:
		if group.territory == null:
			continue
		var rules := AnimalCalculator.get_animal_rules(group.species_name)
		if rules == null or rules is PredatorRules:
			continue

		for coords in group.territory.occupied_macrocells:
			if not positions_set.has(coords):
				continue

			var age_composition := group.get_age_composition_in_cell(coords)
			var cell_calories := 0.0
			for age_band in age_composition:
				var count := int(age_composition[age_band])
				var size_mult := 1.0
				if age_band >= 0 and age_band < rules.size_multiplier_by_age.size():
					size_mult = rules.size_multiplier_by_age[age_band]
				cell_calories += count * rules.prey_calories * size_mult

			calories_by_cell[coords] = float(calories_by_cell.get(coords, 0.0)) + cell_calories

	return calories_by_cell
