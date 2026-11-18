class_name DomesticAnimalSlaughterService
extends RefCounted

# Macella (cane, passo 7, 2026-11-04): ordine del giocatore su un animale domestico, mai automatico. L'animale continua a
# girare finché la persona non lo raggiunge (SlaughterAction).

# Carcassa di un animale ucciso dentro un edificio che tiene animali (recinto, tettoia, conigliera, pollaio, stalla;
# 2026-11-18, richiesta utente): la sua macellazione è lavoro di Allevamento (crescita e velocità, ButcherAction). Salvata
# con la carcassa (GroundPileService).
const CARCASS_KEPT_KEY := "kept_in_building"

# Suono dell'uccisione (GameScene): Callable(DomesticAnimal), chiamata prima che il corpo sparisca.
static var kill_sound_emitter: Callable = Callable()


# true se qualcuno ha una task aperta che macella questo animale.
static func has_worker(individuals: Array, animal_id: int) -> bool:
	for member in individuals:
		for task in JobWorkScanService.open_tasks(member):
			if task_slaughters(task, animal_id):
				return true
	return false


static func task_slaughters(task: Task, animal_id: int) -> bool:
	if task == null or task.is_finished():
		return false
	for step in task.steps:
		if step is SlaughterAction and (step as SlaughterAction).animal_id == animal_id:
			return true
	return false


# Dove si macella `animal` (2026-11-14, pezzo 3): un animale in tettoia sta nella sua tettoia (la sua microcella d'origine,
# come KeepAnimalAction.walk_point), uno libero dov'è. {"macro": Vector2i, "position": Vector2}, vuoto se da nessuna parte.
static func spot(world: World, animal: DomesticAnimal) -> Dictionary:
	if animal == null:
		return {}
	if animal.building_id >= 0:
		var shelter := WarehouseManagerService.find_building(world, animal.building_id)
		if shelter == null:
			return {}
		return {"macro": Vector2i(shelter.macro_x, shelter.macro_y),
			"position": Vector2(shelter.micro_x, shelter.micro_y) + Vector2(0.5, 0.5)}
	if animal.macro_coords.x < 0:
		return {}
	return {"macro": animal.macro_coords, "position": animal.position}


# Punti persi macellando `animal` (pezzo 3): solo in tettoia e prima dell'addomesticazione (DomesticAnimalRules.
# slaughter_point_loss); 0 altrimenti.
static func point_loss(game_data: GameData, animal: DomesticAnimal) -> int:
	if animal.building_id < 0 or DomesticAnimalService.is_domesticated(game_data, animal.species):
		return 0
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	return rules.slaughter_point_loss if rules != null else 0


# Toglie l'animale e lascia la carcassa macellabile. Ritorna il riferimento alla carcassa (forma di
# HuntService.CONTEXT_KILL_CARCASS), vuoto se non è stato possibile lasciarla.
static func kill(game_data: GameData, animal: DomesticAnimal) -> Dictionary:
	if kill_sound_emitter.is_valid():
		kill_sound_emitter.call(animal)
	var band := animal.get_age_band(game_data.get_absolute_day(), DomesticAnimalCalculator.get_wild_rules(animal.species))
	# In tettoia (pezzo 3): la carcassa sta alla tettoia; ancora selvatico, è della specie selvatica e ne ha le rese.
	var where := spot(GameSettings.active_world, animal)
	var macro: Vector2i = where.get("macro", animal.macro_coords)
	var position: Vector2 = where.get("position", animal.position)
	var carcass_species := animal.species
	var rules := DomesticAnimalCalculator.get_rules(animal.species)
	if animal.is_wild and rules != null and rules.wild_species_name != "":
		carcass_species = rules.wild_species_name
	var pile := GroundPileService.drop_carcass(game_data, macro, position, carcass_species, int(band))
	if pile != null and animal.building_id >= 0:
		pile.carcasses[-1][CARCASS_KEPT_KEY] = true
	if animal.body_id != 0:
		AnimalGroupRenderer.remove_live_individual(animal.body_id)
	game_data.domestic_animals.erase(animal)
	if pile == null:
		return {}
	return {
		"macro_x": pile.macro_coords.x, "macro_y": pile.macro_coords.y,
		"micro_x": pile.microcell.x, "micro_y": pile.microcell.y,
		"id": int(pile.carcasses[-1]["id"]),
	}
