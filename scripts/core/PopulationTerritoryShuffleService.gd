class_name PopulationTerritoryShuffleService
extends RefCounted

# ± questa frazione attorno al peso neutro 1.0 per ogni cella (es. 0.35 = tra 0.65 e 1.35) — non
# serve normalizzare a mano: MacroCellState._split_by_weight normalizza già internamente sul
# totale dei pesi, quindi questi valori grezzi vanno bene così come sono.
const WEIGHT_VARIATION: float = 0.35


# Rimescola la ripartizione visiva della popolazione tra le celle del territorio (Step 6 del
# refactoring fauna) — puramente estetico: dà l'impressione di un branco che si sposta nel
# proprio areale nel tempo, invece di un contatore diviso meccanicamente in parti sempre uguali.
# NESSUN impatto su consumo/nascite/mortalità/invecchiamento, che restano ancorati al totale
# PopulationGroup.population, indifferenti a come è distribuito tra le celle. Chiamata una volta
# a ogni checkpoint di inizio stagione (vedi WorldTimeService), per OGNI gruppo multi-cella —
# a differenza di AnimalBirthMitigationService non è filtrata per AnimalRules.birth_season: qui
# la stagione è solo il ritmo del rimescolamento, non legata al ciclo riproduttivo di una specie.
# Territori a 1 sola cella (rabbit oggi) sono saltati: non c'è nulla da variare tra celle diverse,
# e get_population_by_cell() degrada comunque a "tutto in quella cella" senza pesi scritti qui.
func shuffle_distribution(world: World, _season: GameTypes.Season) -> void:
	for group in world.population_groups:
		if group.territory == null or group.territory.get_cell_count() <= 1:
			continue

		var weights: Dictionary = {}
		for coords in group.territory.occupied_macrocells:
			weights[coords] = randf_range(1.0 - WEIGHT_VARIATION, 1.0 + WEIGHT_VARIATION)
		group.set_territory_distribution_weights(weights)
