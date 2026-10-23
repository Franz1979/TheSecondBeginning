class_name AssignHouseService
extends RefCounted

# Assegna individui senza casa (HumanIndividual.house_id == -1) a edifici residenziali con posti
# liberi (2026-09-12, richiesta utente) — stateless, stesso pattern "fabbrica statica"/service già
# in uso da WarehouseSelectionService/BuildingStorageService: nessuna istanza, opera sempre sugli
# argomenti passati. Chiamato a eventi (casa completata, demolita o migliorata, nascita, morte, visitatori accolti) e
# una volta al giorno (BuildingLifecycleService.evict_damaged_house_overflow): questo service non sa QUANDO va
# richiamato, solo COME assegnare dato lo stato attuale.
#
# `human_individuals` è la STESSA lista del chiamante (World non possiede gli individui) e `current_year` serve per
# l'età (current_year - birth_year_virtual).
#
# TRE PASSATE (2026-10-22, richiesta utente — Hut per nucleo famigliare):
#   1. CASE DI NUCLEO (residency_assignment_tier >= NUCLEUS_HOUSE_TIER, oggi la Hut): ognuna è di UN SOLO nucleo
#      famigliare (FamilyNucleusService); i posti in più restano vuoti. Proprietario = il nucleo con almeno un capo dentro
#      e più membri: escono tutti gli altri; poi dentro i capi, i figli minori e i figli adulti dal più giovane fino ai
#      posti (i figli adulti più vecchi escono per primi: nucleo troppo grande, neonato, danni che dimezzano i posti),
#      rientrando anche chi del nucleo vive altrove. Le case vuote vanno ai nuclei senza casa di nucleo: prima quello con
#      la precedenza del miglioramento (priority_by_building), poi il più numeroso (a parità, il membro più anziano); se
#      restano nuclei in attesa si riprendono le case senza nucleo (passata 3), dalla meno abitata. Uscite e ingressi sono
#      traslochi: nessuna penalità di casa persa.
#   2. CASE COMUNI (tier più basso, le tende): invariate — chi è senza casa, dal più anziano, nelle case dal
#      moltiplicatore di riposo più alto; niente nuclei. Senza case di nucleo nel mondo il gioco va come prima.
#   3. RESIDENTI SENZA NUCLEO: chi è ancora senza casa dopo le tende entra, dal più anziano, nelle case di nucleo che nessun nucleo usa,
#      convivendo con altri residenti; un nucleo in attesa li fa uscire (passata 1). Hanno il bonus della casa come tutti.
const NUCLEUS_HOUSE_TIER: int = HouseWardrobeService.NUCLEUS_HOUSE_TIER


# Casa riservata a un nucleo famigliare (oggi la Hut). La regola vive in simulation/ (HouseWardrobeService).
static func is_nucleus_house(building: Building) -> bool:
	return HouseWardrobeService.is_nucleus_house(building)


# Posti effettivi di un edificio (2026-10-10, effetti dello stato "Danneggiato" — passo 5): rules.max_residents, a metà
# (per difetto, mai sotto 1) se la casa è danneggiata. Punto unico per tutti i conteggi dei posti; i controlli "è
# residenziale" (max_residents > 0) restano sul dato del tipo.
static func get_max_residents(building: Building) -> int:
	if building == null or building.rules == null:
		return 0
	return building.get_effective_capacity(building.rules.max_residents)


# Moltiplicatore del riposo effettivo (2026-10-10, passo 5): 1 se la casa è danneggiata.
static func get_rest_multiplier(building: Building) -> float:
	if building == null or building.rules == null:
		return 1.0
	return building.get_effective_multiplier(building.rules.rest_multiplier)


# Posti liberi di un edificio (2026-09-27, estratto da assign_pending_residents per condividerlo con il
# conteggio dei posti del villaggio): rules.max_residents meno i residenti assegnati (house_id == building.id).
# 0 per un edificio non residenziale (max_residents <= 0), non completo o "da demolire" (2026-09-27), mai negativo.
static func get_free_slots(building: Building, human_individuals: Array[HumanIndividual]) -> int:
	if building.rules == null or building.rules.max_residents <= 0 or not building.is_complete or building.is_out_of_service():
		return 0
	var occupied_count := 0
	for individual in human_individuals:
		if individual.house_id == building.id:
			occupied_count += 1
	return maxi(get_max_residents(building) - occupied_count, 0)


# Posti liberi nelle abitazioni di tutto il villaggio: somma di get_free_slots sugli edifici del mondo (2026-09-27 —
# usato dal moltiplicatore di probabilità dell'arrivo di visitatori, FamilyArrivalEvent).
static func count_free_slots(world: World, human_individuals: Array[HumanIndividual]) -> int:
	if world == null:
		return 0
	var free_slots := 0
	for building in world.buildings:
		free_slots += get_free_slots(building, human_individuals)
	return free_slots


static func assign_pending_residents(
	world: World, human_individuals: Array[HumanIndividual], current_year: int, priority_by_building: Dictionary = {}
) -> void:
	if world == null:
		return
	_assign_nucleus_houses(world, human_individuals, current_year, priority_by_building)
	_assign_common_houses(world, human_individuals, current_year)
	_assign_guest_houses(world, human_individuals, current_year)


# Case di nucleo complete e in servizio.
static func _nucleus_houses(world: World) -> Array[Building]:
	var houses: Array[Building] = []
	for building in world.buildings:
		if is_nucleus_house(building) and building.is_complete and not building.is_out_of_service():
			houses.append(building)
	return houses


# Passata 1: case di nucleo (vedi TRE PASSATE in testa). `priority_by_building`: id edificio -> id dei residenti di prima
# del miglioramento; il loro nucleo prende quella casa per primo.
static func _assign_nucleus_houses(
	world: World, human_individuals: Array[HumanIndividual], current_year: int, priority_by_building: Dictionary
) -> void:
	var houses := _nucleus_houses(world)
	if houses.is_empty():
		return
	var nuclei := FamilyNucleusService.compute_nuclei(human_individuals)
	var by_member: Dictionary = nuclei["by_member"]
	var occupants := _residents_by_house(human_individuals)
	var housed: Dictionary = {}
	var free_houses: Array[Building] = []
	# Case senza nucleo: id edificio -> residenti rimasti (Array di HumanIndividual).
	var guest_houses: Dictionary = {}
	for house in houses:
		# Solo chi vive ancora qui: una casa vista prima può aver già richiamato un suo membro (_fit_nucleus).
		var residents: Array = (occupants.get(house.id, []) as Array).filter(
			func(resident: HumanIndividual) -> bool: return resident.house_id == house.id
		)
		if residents.is_empty():
			free_houses.append(house)
			continue
		var owner := _owner_nucleus(residents, nuclei, housed)
		if owner == "":
			# Nessun nucleo: casa senza nucleo. Restano, fino ai posti (escono i più giovani).
			residents.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool: return a.birth_year_virtual < b.birth_year_virtual)
			var capacity := get_max_residents(house)
			while residents.size() > capacity:
				_move_out(residents.pop_back(), house, "esce: residente in più nella hut danneggiata, il più giovane")
			guest_houses[house.id] = residents
			continue
		for resident in residents:
			if String(by_member.get((resident as HumanIndividual).id, "")) != owner:
				_move_out(resident, house, "esce: non è del nucleo della casa")
		housed[owner] = house
		_fit_nucleus(house, owner, nuclei, current_year)
	var waiting: Array = []
	for nucleus_key in nuclei["members"].keys():
		if not housed.has(nucleus_key):
			waiting.append(nucleus_key)
	if waiting.is_empty():
		return
	waiting.sort_custom(func(a: String, b: String) -> bool:
		var size_a: int = (nuclei["members"][a] as Array).size()
		var size_b: int = (nuclei["members"][b] as Array).size()
		if size_a != size_b:
			return size_a > size_b
		return FamilyNucleusService.oldest_birth_year(nuclei["members"][a]) < FamilyNucleusService.oldest_birth_year(nuclei["members"][b])
	)
	for house in free_houses:
		if waiting.is_empty():
			return
		var chosen := ""
		for resident_id in priority_by_building.get(house.id, []):
			var key := String(by_member.get(int(resident_id), ""))
			if key != "" and waiting.has(key):
				chosen = key
				break
		if chosen == "":
			chosen = String(waiting[0])
		waiting.erase(chosen)
		housed[chosen] = house
		_fit_nucleus(house, chosen, nuclei, current_year)
	# Nuclei ancora in attesa: si riprendono le case senza nucleo, dalla meno abitata.
	var reclaimable: Array[Building] = []
	for house in houses:
		if guest_houses.has(house.id):
			reclaimable.append(house)
	reclaimable.sort_custom(func(a: Building, b: Building) -> bool:
		return (guest_houses[a.id] as Array).size() < (guest_houses[b.id] as Array).size()
	)
	for house in reclaimable:
		if waiting.is_empty():
			return
		var chosen := String(waiting.pop_front())
		for guest in guest_houses[house.id]:
			if (guest as HumanIndividual).house_id == house.id:
				_move_out(guest, house, "esce: la hut serve a un nucleo")
		housed[chosen] = house
		_fit_nucleus(house, chosen, nuclei, current_year)


# Nucleo proprietario di una casa di nucleo: tra i nuclei con almeno un CAPO che ci vive (un figlio da solo non porta lì il
# nucleo dei genitori), quello con più membri dentro (a parità, il membro più anziano), mai uno che ha già un'altra casa
# di nucleo. "" se nessuno: la casa è senza nucleo.
static func _owner_nucleus(residents: Array, nuclei: Dictionary, housed: Dictionary) -> String:
	var counts: Dictionary = {}
	var with_head: Dictionary = {}
	for resident in residents:
		var individual: HumanIndividual = resident
		var key := String(nuclei["by_member"].get(individual.id, ""))
		if key == "" or housed.has(key):
			continue
		counts[key] = int(counts.get(key, 0)) + 1
		if FamilyNucleusService.is_head(nuclei, key, individual):
			with_head[key] = true
	var best := ""
	for key in with_head.keys():
		if best == "" or int(counts[key]) > int(counts[best]) or (int(counts[key]) == int(counts[best]) \
				and FamilyNucleusService.oldest_birth_year(nuclei["members"][key]) < FamilyNucleusService.oldest_birth_year(nuclei["members"][best])):
			best = String(key)
	return best


# Passata 3: residenti senza nucleo (vedi TRE PASSATE in testa). Chi è ancora senza casa dopo le tende, dal più anziano, nelle case di
# nucleo che nessun nucleo usa (vuote o già abitate senza nucleo), fino ai posti.
static func _assign_guest_houses(world: World, human_individuals: Array[HumanIndividual], current_year: int) -> void:
	var unhoused: Array[HumanIndividual] = []
	for individual in human_individuals:
		if individual.house_id == -1:
			unhoused.append(individual)
	if unhoused.is_empty():
		return
	var houses := _nucleus_houses(world)
	if houses.is_empty():
		return
	var nuclei := FamilyNucleusService.compute_nuclei(human_individuals)
	var occupants := _residents_by_house(human_individuals)
	unhoused.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool:
		return (current_year - a.birth_year_virtual) > (current_year - b.birth_year_virtual)
	)
	for house in houses:
		if unhoused.is_empty():
			return
		var residents: Array = occupants.get(house.id, [])
		if _owner_nucleus(residents, nuclei, {}) != "":
			continue
		var free_slots: int = maxi(get_max_residents(house) - residents.size(), 0)
		while free_slots > 0 and not unhoused.is_empty():
			var guest: HumanIndividual = unhoused.pop_front()
			guest.house_id = house.id
			free_slots -= 1
			_log_house(guest, -1, house, "residente: nessun nucleo la usa")


# Il nucleo `nucleus_key` nella casa `house`, fino ai posti: restano sempre i capi e i figli minori già dentro; poi, finché
# c'è posto, capi e minori che vivono altrove, poi i figli adulti dal più giovane. Chi del nucleo è dentro ma non ci sta
# esce; chi ci sta e vive altrove entra (lascia la sua casa).
static func _fit_nucleus(house: Building, nucleus_key: String, nuclei: Dictionary, current_year: int) -> void:
	var capacity := get_max_residents(house)
	var chosen: Array[HumanIndividual] = []
	var candidates: Array[HumanIndividual] = []
	var adults: Array[HumanIndividual] = []
	for member in nuclei["members"][nucleus_key]:
		var individual: HumanIndividual = member
		var essential := FamilyNucleusService.is_head(nuclei, nucleus_key, individual) or not FamilyNucleusService.is_adult(individual, current_year)
		if not essential:
			adults.append(individual)
		elif individual.house_id == house.id:
			chosen.append(individual)
		else:
			candidates.append(individual)
	adults.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool: return a.birth_year_virtual > b.birth_year_virtual)
	candidates.append_array(adults)
	for candidate in candidates:
		if chosen.size() >= capacity:
			break
		chosen.append(candidate)
	for member in nuclei["members"][nucleus_key]:
		var individual: HumanIndividual = member
		if chosen.has(individual):
			if individual.house_id != house.id:
				var previous_house := individual.house_id
				individual.house_id = house.id
				_log_house(individual, previous_house, house, "entra con il suo nucleo")
		elif individual.house_id == house.id:
			_move_out(individual, house, "esce: casa del nucleo piena, figlio adulto più vecchio")


# Uscita da una casa di nucleo: un trasloco, nessuna penalità di casa persa. La passata delle case comuni lo ricolloca.
static func _move_out(individual: HumanIndividual, house: Building, reason: String) -> void:
	individual.house_id = -1
	_log_house(individual, house.id, null, reason)


# Riga [ASSIGN HOUSE] (2026-10-22, richiesta utente — sempre stampata, come [EVICTION]): solo quando qualcuno cambia
# davvero casa, quindi il controllo giornaliero non scrive nulla se nulla cambia. `to` null = resta senza casa.
static func _log_house(individual: HumanIndividual, from_house_id: int, to: Building, reason: String) -> void:
	var from_text := "senza casa" if from_house_id == -1 else "casa #%d" % from_house_id
	var to_text := "senza casa" if to == null else "%s #%d" % [to.get_display_name(), to.id]
	print("[ASSIGN HOUSE] #%d %s: da %s a %s (%s)." % [individual.id, individual.name, from_text, to_text, reason])


# Residenti per casa in un solo giro: house_id -> Array di HumanIndividual.
static func _residents_by_house(human_individuals: Array[HumanIndividual]) -> Dictionary:
	var result: Dictionary = {}
	for individual in human_individuals:
		if individual.house_id == -1:
			continue
		if not result.has(individual.house_id):
			result[individual.house_id] = []
		(result[individual.house_id] as Array).append(individual)
	return result


# Passata 2: case comuni (le tende), regola di sempre — vedi TRE PASSATE in testa.
static func _assign_common_houses(world: World, human_individuals: Array[HumanIndividual], current_year: int) -> void:
	# Individui senza casa, ordinati per età DECRESCENTE (più anziani prima): un solo ordinamento per l'intera passata.
	var unhoused: Array[HumanIndividual] = []
	for individual in human_individuals:
		if individual.house_id == -1:
			unhoused.append(individual)
	if unhoused.is_empty():
		return
	unhoused.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool:
		return (current_year - a.birth_year_virtual) > (current_year - b.birth_year_virtual)
	)

	# Ordine degli edifici (2026-10-03, richiesta utente): dal moltiplicatore di riposo più alto al più basso, così i più
	# anziani finiscono nelle abitazioni dove si riposa meglio; a parità, l'ordine di costruzione. Le case di nucleo sono
	# escluse (passata 1). Chi ha già una casa non viene spostato. Residenti contati in un solo giro.
	var occupants := _residents_by_house(human_individuals)
	var ordered_buildings: Array[Building] = []
	for building in world.buildings:
		if not is_nucleus_house(building):
			ordered_buildings.append(building)
	var build_order: Dictionary = {}
	for index in world.buildings.size():
		build_order[world.buildings[index]] = index
	ordered_buildings.sort_custom(func(a: Building, b: Building) -> bool:
		var rest_a: float = get_rest_multiplier(a)
		var rest_b: float = get_rest_multiplier(b)
		if rest_a != rest_b:
			return rest_a > rest_b
		return int(build_order[a]) < int(build_order[b])
	)
	for building in ordered_buildings:
		if unhoused.is_empty():
			break
		if building.rules == null or building.rules.max_residents <= 0 or not building.is_complete or building.is_out_of_service():
			continue
		var free_slots: int = maxi(get_max_residents(building) - (occupants.get(building.id, []) as Array).size(), 0)
		while free_slots > 0 and not unhoused.is_empty():
			var resident: HumanIndividual = unhoused.pop_front()
			resident.house_id = building.id
			free_slots -= 1
			_log_house(resident, -1, building, "posto libero, dal più anziano")
