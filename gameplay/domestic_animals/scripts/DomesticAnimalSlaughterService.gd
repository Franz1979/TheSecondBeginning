class_name DomesticAnimalSlaughterService
extends RefCounted

# Macella (cane, passo 7, 2026-11-04): ordine del giocatore su un animale domestico, mai automatico. L'animale continua a
# girare finché la persona non lo raggiunge (SlaughterAction).

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


# Toglie l'animale e lascia la carcassa macellabile. Ritorna il riferimento alla carcassa (forma di
# HuntService.CONTEXT_KILL_CARCASS), vuoto se non è stato possibile lasciarla.
static func kill(game_data: GameData, animal: DomesticAnimal) -> Dictionary:
	if kill_sound_emitter.is_valid():
		kill_sound_emitter.call(animal)
	var band := animal.get_age_band(game_data.get_absolute_day(), DomesticAnimalCalculator.get_wild_rules(animal.species))
	var pile := GroundPileService.drop_carcass(game_data, animal.macro_coords, animal.position, animal.species, int(band))
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
