class_name TrialGardenService
extends RefCounted

# Conti dell'orto delle prove (2026-11-15, richiesta utente — ramo piante, passo 1): uguali per ogni specie, numeri nel
# .tres (DomesticPlantRules, gruppo Semina). Solo calcoli, nessuno stato: i lavori di semina e raccolto (passi successivi)
# li usano e assegnano i punti con DomesticationPointsService.add_points.
#   semina (sowing_season): fino a sown_units_per_lot once -> points_per_sown_unit ciascuna;
#   piantine nate: un tiro per oncia sull'avanzamento -> points_per_sprout ciascuna;
#   piante mature (harvest_season): un tiro per piantina sull'avanzamento × fertilità del terreno; i punti
#   (points_per_mature_plant) solo alla Mietitura, per pianta mietuta; marcite: -points_per_rotten_plant ciascuna;
#   raccolto: per pianta matura 1 + (resa - 1) × avanzamento once, resa = yield_per_unit col tetto dell'edificio
#   (BuildingRules.cultivation_yield_cap: orto 3).
# Avanzamento = punti / soglia finché la specie è selvatica, 1 da addomesticata.


static func can_sow(rules: DomesticPlantRules) -> bool:
	return rules != null and rules.sown_units_per_lot > 0 and rules.sowing_season >= 0 and rules.harvest_season >= 0


static func progress(game_data: GameData, species: String) -> float:
	if game_data == null:
		return 0.0
	if game_data.domesticated_species.has(species):
		return 1.0
	var rules := DomesticPlantCalculator.get_rules(species)
	if rules == null or rules.domestication_points_required <= 0:
		return 0.0
	return clampf(float(DomesticationPointsService.get_points(game_data, species)) / float(rules.domestication_points_required), 0.0, 1.0)


# Once da seminare in `lots` microcelle avendone `available` nei magazzini.
static func units_to_sow(rules: DomesticPlantRules, available: int, lots: int = 1) -> int:
	if not can_sow(rules):
		return 0
	return clampi(available, 0, rules.sown_units_per_lot * maxi(lots, 0))


# Quanti di `count` tentativi riescono, ciascuno con probabilità `chance`.
static func roll(count: int, chance: float) -> int:
	if chance >= 1.0:
		return maxi(count, 0)
	var success := 0
	for i in range(maxi(count, 0)):
		if randf() < chance:
			success += 1
	return success


static func roll_sprouts(game_data: GameData, species: String, sown_units: int) -> int:
	return roll(sown_units, progress(game_data, species))


# `soil_multiplier`: fertilità del terreno (CultivationService.soil_fertility), solo su questo tiro.
static func roll_mature(game_data: GameData, species: String, sprouts: int, soil_multiplier: float = 1.0) -> int:
	return roll(sprouts, progress(game_data, species) * clampf(soil_multiplier, 0.0, 1.0))


# Once raccolte da `mature_plants` piante mature.
# `disease_multiplier`: malattie delle piante (CultivationService.disease_yield_multiplier), sulla resa.
static func harvest_units(game_data: GameData, species: String, mature_plants: int, disease_multiplier: float = 1.0,
		yield_cap: float = 0.0) -> int:
	var rules := DomesticPlantCalculator.get_rules(species)
	if rules == null or mature_plants <= 0:
		return 0
	var full_yield := minf(rules.yield_per_unit, yield_cap) if yield_cap > 0.0 else rules.yield_per_unit
	var per_plant := 1.0 + maxf(full_yield - 1.0, 0.0) * progress(game_data, species)
	return int(round(per_plant * mature_plants * maxf(disease_multiplier, 0.0)))


static func sowing_points(rules: DomesticPlantRules, sown_units: int) -> int:
	return rules.points_per_sown_unit * maxi(sown_units, 0) if rules != null else 0


static func sprout_points(rules: DomesticPlantRules, sprouts: int) -> int:
	return rules.points_per_sprout * maxi(sprouts, 0) if rules != null else 0


static func rotten_points(rules: DomesticPlantRules, rotten_plants: int) -> int:
	return -rules.points_per_rotten_plant * maxi(rotten_plants, 0) if rules != null else 0


static func mature_points(rules: DomesticPlantRules, mature_plants: int) -> int:
	return rules.points_per_mature_plant * maxi(mature_plants, 0) if rules != null else 0
