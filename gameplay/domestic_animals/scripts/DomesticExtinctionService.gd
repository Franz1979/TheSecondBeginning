class_name DomesticExtinctionService
extends RefCounted

# Estinzione di una specie domestica (2026-11-17, richiesta utente): un avviso in campanella, con il suggerimento di
# ripartire dai selvatici, quando una specie già addomesticata non ha più niente di vivo o di seminabile.
#   - animale: nessun esemplare domestico (i selvatici in tettoia non contano). Il cane è escluso (nessuna idea richiesta:
#     quelli che mancano arrivano da fuori da soli);
#   - pianta: nessun seme domestico in edifici, zaini e mucchi a terra, e nessun lotto seminato o con piante di quella
#     specie (i prodotti, come la farina, non contano: non si riseminano).
# Ogni giorno (GameSimulation.tick_day) confronta le specie presenti con quelle di ieri (GameData.domestic_species_present,
# salvato): l'avviso esce solo al passaggio da presente ad assente, quindi una volta per estinzione, e di nuovo se la
# specie ricompare e si riestingue. Una specie addomesticata che non ha ancora avuto il primo esemplare non dà avvisi.
# La strada per ripartire c'è già: la specie resta addomesticata (punti fermi), quindi i piccoli delle madri selvatiche in
# tettoia nascono domestici e la mietitura dell'orto delle prove rende il seme domestico. Stateless, statico.


static func check_daily(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	if game_data == null:
		return
	var present_now: Array[String] = []
	var animal_species: Array[String] = []
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules == null or rules.required_idea_id == "" or not game_data.domesticated_species.has(species):
			continue
		animal_species.append(species)
		if _animal_present(game_data, species):
			present_now.append(species)
	for species in DomesticPlantCalculator.list_species():
		var rules := DomesticPlantCalculator.get_rules(species)
		if rules == null or rules.domestic_resource_name == "" or not game_data.domesticated_species.has(species):
			continue
		if _plant_present(ctx, species, rules):
			present_now.append(species)
	for species in game_data.domestic_species_present:
		if present_now.has(species):
			continue
		DebugLogging.print_event("[DOMESTICATION] specie domestica estinta: %s" % species)
		if effects != null:
			effects.notify(NotificationTypes.NotificationPopupType.DOMESTIC_SPECIES_DISCOVERED,
				_animal_text(species) if animal_species.has(species) else _plant_text(species))
	game_data.domestic_species_present = present_now


static func _animal_present(game_data: GameData, species: String) -> bool:
	for animal in game_data.domestic_animals:
		if animal.species == species and not animal.is_wild:
			return true
	return false


static func _plant_present(ctx: GameContext, species: String, rules: DomesticPlantRules) -> bool:
	var seed_name := rules.domestic_resource_name
	if ctx.world != null:
		for building in ctx.world.buildings:
			var stored := int((building.stored_resources.get(seed_name, {}) as Dictionary).get("quantity", 0))
			if stored + int(building.production_output.get(seed_name, 0)) > 0:
				return true
			if CultivationService.is_cultivated(building) and building.crop_species == species:
				for lot in building.crop_lots:
					if lot.sown + lot.sprouts + lot.mature + lot.seeds > 0:
						return true
	for member in ctx.individuals:
		if member.get_carried_quantity(seed_name) > 0:
			return true
	for pile in ctx.game_data.ground_piles:
		if pile.get_quantity(seed_name) > 0:
			return true
	return false


static func _animal_text(species: String) -> String:
	var rules := DomesticAnimalCalculator.get_rules(species)
	return GameContext.tr_text("notification_domestic_animal_extinct").format({
		"domestic": GameContext.tr_text(rules.display_name),
		"wild": GameContext.tr_text("animal_species_" + rules.wild_species_name),
		"shelter": GameContext.tr_text("building_cage_shelter"),
	})


static func _plant_text(species: String) -> String:
	var rules := DomesticPlantCalculator.get_rules(species)
	return GameContext.tr_text("notification_domestic_plant_extinct").format({
		"domestic": GameContext.tr_text(rules.display_name),
		"wild": GameContext.tr_text(rules.wild_display_name),
		"garden": GameContext.tr_text("building_trial_garden"),
	})
