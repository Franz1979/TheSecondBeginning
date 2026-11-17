class_name SlaughterStockService
extends RefCounted

# Macellazione decisa dal gestore scorte (2026-11-14, richiesta utente — pezzo 2c delle soglie "Macella oltre"). A ogni
# Inventario il WM mette il segno "da macellare" (DomesticAnimal.slaughter_requested, lo stesso del 🔪 manuale, con in più
# slaughter_by_wm) sugli animali in tettoia oltre le soglie; il lavoro è quello della lista (SlaughterJobProvider).
# - Prima toglie i propri segni non ancora presi da nessuno (soglia alzata o tolta), poi li rifà: la scelta è
#   deterministica, gli stessi animali tornano segnati. I segni manuali e quelli già presi non si toccano.
# - Soglia della tettoia (Building.slaughter_above): animali non segnati oltre il numero.
# - Soglia della specie (GameData.domestic_slaughter_above): animali non segnati di tutto il villaggio oltre il numero,
#   chiusi e liberi (2026-11-16, richiesta utente: prima solo i chiusi), uno alla volta dall'edificio che ne ha di più; i
#   liberi per ultimi. Il cane non ha soglia (solo le specie da recinto, KeptAnimalService.can_be_kept).
# - Chi: i vecchi (dal più vecchio), poi i maschi adulti oltre il più giovane, poi i giovani maschi (dal più grande), poi le
#   femmine adulte (dalla più vecchia). Le giovani femmine e un maschio adulto per tettoia restano sempre. Vecchi per primi
#   dal 2026-11-17 (richiesta utente): non figliano più e morirebbero presto di vecchiaia, la carne si prende prima.
# Senza stato.


# true se ha cambiato qualche segno.
static func plan(world: World, game_data: GameData, individuals: Array) -> bool:
	if world == null or game_data == null:
		return false
	var before: Dictionary = {}
	for animal in game_data.domestic_animals:
		if animal.slaughter_by_wm:
			before[animal.id] = true
			if not DomesticAnimalSlaughterService.has_worker(individuals, animal.id):
				animal.slaughter_requested = false
				animal.slaughter_by_wm = false
	# Animali in tettoia non segnati, per tettoia.
	var free_by_building: Dictionary = {}
	var shelters: Dictionary = {}
	for building in world.buildings:
		if KeptAnimalService.capacity(building) > 0 and building.is_complete:
			shelters[building.id] = building
			free_by_building[building.id] = []
	for animal in game_data.domestic_animals:
		if animal.building_id >= 0 and free_by_building.has(animal.building_id) and not animal.slaughter_requested:
			(free_by_building[animal.building_id] as Array).append(animal)
	var today := game_data.get_absolute_day()
	# Soglie delle tettoie.
	for building_id in shelters:
		var limit := KeptAnimalService.building_slaughter_above(shelters[building_id])
		var free: Array = free_by_building[building_id]
		while limit > 0 and free.size() > limit:
			if not _mark_one(free, today):
				break
	# Soglie delle specie: anche i liberi, sotto la chiave FREE_KEY (per ultimi in _mark_from_fullest).
	var free_animals: Array = []
	for animal in game_data.domestic_animals:
		if animal.building_id < 0 and not animal.slaughter_requested:
			free_animals.append(animal)
	free_by_building[FREE_KEY] = free_animals
	for species in game_data.domestic_slaughter_above.keys():
		var limit := KeptAnimalService.species_slaughter_above(game_data, String(species))
		if limit <= 0 or not KeptAnimalService.can_be_kept(DomesticAnimalCalculator.get_rules(String(species))):
			continue
		var total := 0
		for building_id in free_by_building:
			total += _count_species(free_by_building[building_id], String(species))
		while total > limit:
			if not _mark_from_fullest(free_by_building, String(species), today):
				break
			total -= 1
	var changed := false
	for animal in game_data.domestic_animals:
		if animal.slaughter_by_wm != before.has(animal.id):
			changed = true
			break
	return changed


# Chiave dei liberi (non in un edificio) in free_by_building.
const FREE_KEY := -1


static func _count_species(animals: Array, species: String) -> int:
	var count := 0
	for animal: DomesticAnimal in animals:
		if animal.species == species:
			count += 1
	return count


# Uno della specie dall'edificio che ne ha di più (non segnati) e ha qualcuno da macellare; i liberi (FREE_KEY) per
# ultimi. false se nessuno.
static func _mark_from_fullest(free_by_building: Dictionary, species: String, today: int) -> bool:
	var order: Array = free_by_building.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		if (a == FREE_KEY) != (b == FREE_KEY):
			return b == FREE_KEY
		var count_a := _count_species(free_by_building[a], species)
		var count_b := _count_species(free_by_building[b], species)
		return count_a > count_b if count_a != count_b else a < b)
	for building_id in order:
		# Solo la specie: tra i liberi ce ne sono di più specie.
		var all_free: Array = free_by_building[building_id]
		var of_species := all_free.filter(func(animal: DomesticAnimal) -> bool: return animal.species == species)
		if not of_species.is_empty() and _mark_one(of_species, today):
			free_by_building[building_id] = all_free.filter(func(animal: DomesticAnimal) -> bool: return not animal.slaughter_requested)
			return true
	return false


# Segna il prossimo da macellare di `free` (una tettoia, una specie) e lo toglie dalla lista. false se restano solo i
# protetti.
static func _mark_one(free: Array, today: int) -> bool:
	var chosen := _pick(free, today)
	if chosen == null:
		return false
	chosen.slaughter_requested = true
	chosen.slaughter_by_wm = true
	free.erase(chosen)
	DebugLogging.print_event("[WM] macellazione: %s %d (tettoia %d)" % [chosen.species, chosen.id, chosen.building_id])
	return true


static func _pick(animals: Array, today: int) -> DomesticAnimal:
	if animals.is_empty():
		return null
	var wild_rules := DomesticAnimalCalculator.get_wild_rules((animals[0] as DomesticAnimal).species)
	var adult_males: Array[DomesticAnimal] = []
	var old: Array[DomesticAnimal] = []
	var young_males: Array[DomesticAnimal] = []
	var adult_females: Array[DomesticAnimal] = []
	for animal: DomesticAnimal in animals:
		var band := int(animal.get_age_band(today, wild_rules)) if wild_rules != null else int(GameTypes.AgeBand.ADULT)
		if band == GameTypes.AgeBand.OLD:
			old.append(animal)
		elif band == GameTypes.AgeBand.YOUNG:
			if animal.is_male:
				young_males.append(animal)
		elif animal.is_male:
			adult_males.append(animal)
		else:
			adult_females.append(animal)
	# Dal più vecchio (nascita più lontana); tra i maschi adulti resta il più giovane.
	var oldest_first := func(a: DomesticAnimal, b: DomesticAnimal) -> bool:
		return a.birth_day < b.birth_day if a.birth_day != b.birth_day else a.id < b.id
	for group in [adult_males, old, young_males, adult_females]:
		(group as Array).sort_custom(oldest_first)
	if not old.is_empty():
		return old[0]
	if adult_males.size() > 1:
		return adult_males[0]
	if not young_males.is_empty():
		return young_males[0]
	if not adult_females.is_empty():
		return adult_females[0]
	return null
