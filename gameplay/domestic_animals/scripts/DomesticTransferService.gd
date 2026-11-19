class_name DomesticTransferService
extends RefCounted

# Domestici dalla tettoia delle gabbie agli edifici d'allevamento (2026-11-16, richiesta utente — conigliera, poi pollaio e
# stalle). Regola: un animale DOMESTICO non resta nella tettoia. Nato lì (cucciolata di madri selvatiche a specie
# addomesticata), aspetta il trasporto solo se in un edificio d'allevamento della sua specie (KeptAnimalService.
# fixed_species) c'è posto per lui, contando tutti quelli che già aspettano; gli altri ricevono subito l'ordine "Macella"
# (DomesticAnimal.slaughter_no_room) con un avviso. Il trasporto: lavoro "Trasferisci animali" (DomesticTransferJobProvider,
# TakeAnimalsAction, KeepAnimalAction con voci "animal_id"). Stateless, statico.

const SKILL_EFFECT_KEY := "husbandry"


# true per un edificio d'allevamento (conigliera, pollaio: specie fissa), false per la tettoia delle gabbie.
static func is_breeding_building(building: Building) -> bool:
	return KeptAnimalService.is_breeding(building)


# Posti liberi per `species` in tutti gli edifici d'allevamento finiti e in servizio (meno i posti prenotati `reserved`).
static func breeding_room(game_data: GameData, world: World, species: String, reserved: Array = []) -> int:
	var room := 0
	if world == null:
		return room
	for building in world.buildings:
		if not is_breeding_building(building) or not building.is_complete or building.is_out_of_service():
			continue
		# Specie fissa o scelta (stalla, 2026-11-19): ammessa, e l'edificio non tiene già un'altra specie.
		if KeptAnimalService.accepts_none(building) or not KeptAnimalService.selectable_species(building).has(species):
			continue
		var current := KeptAnimalService.current_species(game_data, building, reserved)
		if current != "" and current != species:
			continue
		var taken := DomesticAnimalService.get_kept_animals(game_data, building.id).size()
		for entry in reserved:
			if int(entry.get("building_id", -1)) == building.id:
				taken += 1
		room += maxi(KeptAnimalService.capacity(building, species) - taken, 0)
	return room


# Domestici di `species` fuori dagli edifici d'allevamento (nella tettoia delle gabbie) senza ordine di macellazione, in
# ordine di id (scelta deterministica).
static func waiting_animals(game_data: GameData, world: World, species: String) -> Array[DomesticAnimal]:
	var result: Array[DomesticAnimal] = []
	for animal in game_data.domestic_animals:
		if animal.species != species or animal.is_wild or animal.building_id < 0 or animal.slaughter_requested \
				or animal.carried_by >= 0:
			continue
		if is_breeding_building(WarehouseManagerService.find_building(world, animal.building_id)):
			continue
		result.append(animal)
	result.sort_custom(func(a: DomesticAnimal, b: DomesticAnimal) -> bool: return a.id < b.id)
	return result


# Tipo dell'edificio d'allevamento di `species` ("rabbit_hutch"), "" se nessuno.
static func breeding_building_type(species: String) -> String:
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules != null and rules.animal_capacity > 0 and rules.required_domesticated_species == species:
			return type_name
	# Specie scelta (stalla, 2026-11-19): l'edificio d'allevamento a scelta della sua taglia.
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules != null and rules.animal_capacity > 0 and rules.breeding_with_choice \
				and rules.keeps_big_animals == KeptAnimalService.is_big_species(species):
			return type_name
	return ""


# Ogni giorno (DomesticAnimalLifeService.tick_day, dopo le cucciolate): rifà i segni "manca posto". Prima toglie i propri
# segni non ancora presi da nessuno (una conigliera finita nel frattempo li salva), poi per ogni specie tiene in attesa
# quanti ne entrano negli edifici d'allevamento, alternando maschi e femmine, e segna gli altri. Avviso solo per i segni
# nuovi rispetto a ieri.
static func plan_no_room_slaughter(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	release_orphans(game_data, ctx.individuals)
	var before: Dictionary = {}
	for animal in game_data.domestic_animals:
		if animal.slaughter_no_room:
			before[animal.id] = true
			if not DomesticAnimalSlaughterService.has_worker(ctx.individuals, animal.id):
				animal.slaughter_requested = false
				animal.slaughter_no_room = false
	var species_list: Array[String] = []
	for animal in game_data.domestic_animals:
		if not animal.is_wild and animal.building_id >= 0 and not species_list.has(animal.species):
			species_list.append(animal.species)
	var reserved := KeptAnimalService.reservations(ctx.individuals)
	for species in species_list:
		var waiting := waiting_animals(game_data, ctx.world, species)
		var room := breeding_room(game_data, ctx.world, species, reserved)
		if waiting.size() <= room:
			continue
		var excess := _pick_excess(waiting, room)
		var new_marks := 0
		var shelter_id := -1
		for animal in excess:
			animal.slaughter_requested = true
			animal.slaughter_no_room = true
			if not before.has(animal.id):
				new_marks += 1
				shelter_id = animal.building_id
		DebugLogging.print_event("[DOMESTIC] %s: %d in attesa, %d posti d'allevamento, %d da macellare (%d nuovi)" % [
			species, waiting.size(), room, excess.size(), new_marks])
		if new_marks > 0 and effects != null:
			var shelter := WarehouseManagerService.find_building(ctx.world, shelter_id)
			var type_name := breeding_building_type(species)
			effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
				GameContext.tr_text("notification_domestic_no_breeding_room").format({
					"count": new_marks,
					"species": KeptAnimalService.species_display_name(species, false),
					"shelter": shelter.get_display_name() if shelter != null else "",
					"building": GameContext.tr_text("building_" + type_name) if type_name != "" else "",
				}))


# --- Trasferisci animali (2026-11-16) ---

static func age_band_of(animal: DomesticAnimal, today: int) -> int:
	return int(animal.get_age_band(today, DomesticAnimalCalculator.get_wild_rules(animal.species)))


# Spazio libero nello zaino di `worker`, contando gli animali vivi che ha già in braccio.
static func free_space(worker: HumanIndividual) -> float:
	return worker.max_carry_capacity - worker.get_carried_space() - KeptAnimalService.carried_live_space(worker.current_task)


# Domestici in attesa nella tettoia `shelter`: non in trasporto, senza ordine di macellazione, in ordine di id.
static func shelter_waiting(game_data: GameData, shelter: Building) -> Array[DomesticAnimal]:
	var result: Array[DomesticAnimal] = []
	if shelter == null:
		return result
	for animal in game_data.domestic_animals:
		if animal.building_id == shelter.id and not animal.is_wild and not animal.slaughter_requested and animal.carried_by < 0:
			# Specie grosse (2026-11-19, stalla passo 1): in braccio no, si porteranno con la cavezza (passo 2). Intanto
			# restano nel recinto: contano in attesa (waiting_animals), quindi non si macellano se una stalla ha posto.
			if KeptAnimalService.is_big_species(animal.species):
				continue
			result.append(animal)
	result.sort_custom(func(a: DomesticAnimal, b: DomesticAnimal) -> bool: return a.id < b.id)
	return result


# Quelli di shelter_waiting la cui specie ha posto in un edificio d'allevamento (contando i posti prenotati `reserved`).
static func transferable(game_data: GameData, world: World, shelter: Building, reserved: Array) -> Array[DomesticAnimal]:
	var result: Array[DomesticAnimal] = []
	var room := {}
	for animal in shelter_waiting(game_data, shelter):
		if not room.has(animal.species):
			room[animal.species] = breeding_room(game_data, world, animal.species, reserved)
		if int(room[animal.species]) > 0:
			result.append(animal)
	return result


# Edificio d'allevamento con posto per `species` più vicino a `macro_coords`; null se nessuno.
static func nearest_breeding_building(game_data: GameData, world: World, species: String, macro_coords: Vector2i,
		reserved: Array) -> Building:
	var best: Building = null
	var best_distance := INF
	if world == null:
		return best
	for building in world.buildings:
		if not is_breeding_building(building) or not KeptAnimalService.has_room_for(game_data, building, species, reserved):
			continue
		var distance := Vector2(Vector2i(building.macro_x, building.macro_y) - macro_coords).length()
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


# Voce di KeepAnimalAction per un animale già esistente ("animal_id"): stessi campi delle catture vive (prenota il posto in
# `building_id`, pesa `space`).
static func transfer_entry(animal: DomesticAnimal, age_band: int, building_id: int) -> Dictionary:
	return {"animal_id": animal.id, "species": animal.species, "wild_species": animal.species, "is_male": animal.is_male,
		"age_band": age_band, "building_id": building_id, "space": KeptAnimalService.live_space(animal.species, age_band),
		"trap_name": ""}


# Alla tettoia (TakeAnimalsAction): i domestici in attesa che ci stanno nello zaino di `worker`, ognuno verso l'edificio
# d'allevamento con posto più vicino; li segna in trasporto. {building_id: {"building", "entries"}}.
static func pick_for_transfer(game_data: GameData, world: World, individuals: Array[HumanIndividual],
		worker: HumanIndividual, shelter: Building) -> Dictionary:
	var groups := {}
	if game_data == null or shelter == null or worker == null:
		return groups
	var reserved := KeptAnimalService.reservations(individuals)
	var space_left := free_space(worker)
	var today := game_data.get_absolute_day()
	var macro := Vector2i(shelter.macro_x, shelter.macro_y)
	for animal in shelter_waiting(game_data, shelter):
		var band := age_band_of(animal, today)
		var space := KeptAnimalService.live_space(animal.species, band)
		if space > space_left:
			continue
		var target := nearest_breeding_building(game_data, world, animal.species, macro, reserved)
		if target == null:
			continue
		var entry := transfer_entry(animal, band, target.id)
		reserved.append(entry)
		space_left -= space
		animal.carried_by = worker.id
		if not groups.has(target.id):
			groups[target.id] = {"building": target, "entries": []}
		groups[target.id]["entries"].append(entry)
		DebugLogging.print_event("[TRANSFER] #%d %s prende %s #%d dalla tettoia #%d per %s #%d" % [worker.id, worker.name,
			animal.species, animal.id, shelter.id, target.building_type_name, target.id])
	return groups


# Lavoro interrotto (ogni giorno e a Rimetti in coda/Blocca): chi non è più in braccio a nessuno (nessuna tappa
# KeepAnimalAction aperta con il suo id) torna in attesa nella tettoia, dove non si era mai mosso.
static func release_orphans(game_data: GameData, individuals: Array[HumanIndividual]) -> void:
	var held := {}
	for entry in KeptAnimalService.reservations(individuals):
		if entry.has("animal_id"):
			held[int(entry["animal_id"])] = true
	for animal in game_data.domestic_animals:
		if animal.carried_by >= 0 and not held.has(animal.id):
			DebugLogging.print_event("[TRANSFER] %s #%d torna in attesa nella tettoia #%d" % [animal.species, animal.id, animal.building_id])
			animal.carried_by = -1


# Arrivati senza posto in nessun edificio d'allevamento: ucciso sul posto, la carcassa resta davanti a `place` (la
# macella il lavoro Macellazione, col coltello).
static func kill_on_spot(game_data: GameData, animal: DomesticAnimal, place: Building) -> void:
	if place != null:
		animal.building_id = place.id
	animal.carried_by = -1
	animal.slaughter_requested = false
	DomesticAnimalSlaughterService.kill(game_data, animal)


# Quelli di `waiting` che non trovano posto: si tengono `room` animali alternando i sessi (prima il sesso con meno
# tenuti, a parità le femmine), gli altri si macellano.
static func _pick_excess(waiting: Array[DomesticAnimal], room: int) -> Array[DomesticAnimal]:
	var males: Array[DomesticAnimal] = []
	var females: Array[DomesticAnimal] = []
	for animal in waiting:
		if animal.is_male:
			males.append(animal)
		else:
			females.append(animal)
	var kept_males := 0
	var kept_females := 0
	while kept_males + kept_females < room and (kept_males < males.size() or kept_females < females.size()):
		var take_female := kept_females < females.size() and (kept_females <= kept_males or kept_males >= males.size())
		if take_female:
			kept_females += 1
		else:
			kept_males += 1
	var excess: Array[DomesticAnimal] = []
	excess.append_array(males.slice(kept_males))
	excess.append_array(females.slice(kept_females))
	return excess
