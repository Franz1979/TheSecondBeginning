class_name AssignHouseService
extends RefCounted

# Assegna individui senza casa (HumanIndividual.house_id == -1) a edifici residenziali con posti
# liberi (2026-09-12, richiesta utente) — stateless, stesso pattern "fabbrica statica"/service già
# in uso da WarehouseSelectionService/BuildingStorageService: nessuna istanza, opera sempre sugli
# argomenti passati. Chiamato da GameScene in tre punti (costruzione completata di un edificio
# residenziale, nascita, morte — vedi lì per i tre call site esatti), mai da un timer/loop proprio:
# questo service non sa QUANDO va richiamato, solo COME assegnare dato lo stato attuale.
#
# DEVIAZIONE dalla firma letterale richiesta (segnalata, come da istruzioni — stesso principio già
# seguito da WarehouseSelectionService.find_best per la propria deviazione): la richiesta originale
# era assign_pending_residents(world) -> void. World (world.gd) possiede `buildings` ma NON possiede
# la lista degli individui (quella vive su GameScene.human_individuals, un Array[HumanIndividual] a
# parte) né l'anno corrente di gioco (GameData.year, anch'esso su GameScene). Aggiunti quindi due
# parametri: `human_individuals` (la STESSA lista che il chiamante già possiede, mai duplicata da
# questo service) e `current_year` (necessario per calcolare l'età — HumanIndividual NON salva un
# campo age proprio, solo birth_year_virtual: età = current_year - birth_year_virtual, stesso calcolo
# al volo già usato ovunque nel progetto, es. HumanCouplingIndividualService/
# HumanConceptionIndividualService — MAI tramite HumanCalculator.get_age_band, che è tutt'altro
# concetto/tutt'altra scala).
#
# CRITERIO UNICO PER ORA (2026-09-12, richiesta utente esplicita — vedi anche il commento su
# BuildingRules.residency_assignment_tier): anzianità DECRESCENTE, i più anziani hanno priorità,
# INDIPENDENTEMENTE dal tier dell'edificio (Stick Tent tier 1 e Hut tier 2 trattati allo STESSO
# modo qui, nessuna lettura di residency_assignment_tier in questo file). Edifici scanditi dal moltiplicatore di
# riposo più alto al più basso, a parità in ordine di costruzione (dal 2026-10-03; prima solo l'ordine di costruzione),
# e il primo posto libero trovato viene occupato — quando in futuro tier
# diversi vorranno criteri diversi (es. "famiglia/nucleo" per i tier più alti), quella logica andrà
# aggiunta QUI, leggendo building.rules.residency_assignment_tier per scegliere quale criterio
# applicare a QUEL building, non prima.
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
	if building.rules == null or building.rules.max_residents <= 0 or not building.is_complete or building.is_marked_for_demolition:
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
	world: World, human_individuals: Array[HumanIndividual], current_year: int
) -> void:
	if world == null:
		return

	# Individui senza casa, ordinati per età DECRESCENTE (più anziani prima) — sort_custom con una
	# lambda di confronto, stesso stile già in uso altrove nel progetto per ordinamenti ad-hoc (es.
	# NotificationPopup). Costruito PRIMA di scandire gli edifici (non dentro il loop sotto): un solo
	# ordinamento vale per l'intera passata, i posti liberi vengono riempiti nell'ordine così fissato.
	var unhoused: Array[HumanIndividual] = []
	for individual in human_individuals:
		if individual.house_id == -1:
			unhoused.append(individual)
	if unhoused.is_empty():
		return
	unhoused.sort_custom(func(a: HumanIndividual, b: HumanIndividual) -> bool:
		return (current_year - a.birth_year_virtual) > (current_year - b.birth_year_virtual)
	)

	# Ordine degli edifici (2026-10-03, richiesta utente — prima l'ordine di costruzione puro): dal moltiplicatore di
	# riposo (BuildingRules.rest_multiplier) più alto al più basso, così i più anziani finiscono nelle abitazioni dove si
	# riposa meglio; a parità, l'ordine di costruzione (posizione in world.buildings, sort stabile per indice). Per
	# ciascun edificio residenziale COMPLETO con posti liberi, riempie finché ne ha o finché la coda `unhoused` si svuota.
	# Chi ha già una casa non viene spostato (solo `unhoused`). residency_assignment_tier resta non letto. Conteggio occupanti per scansione lineare di
	# human_individuals ad ogni edificio (O(edifici × individui), stesso principio "numeri piccoli,
	# costo accettabile" già assunto altrove nel progetto per liste di questa scala, es.
	# TaskPersistenceService._find_building_by_id) — nessun indice/cache mantenuto a parte.
	var ordered_buildings: Array[Building] = world.buildings.duplicate()
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
		var free_slots: int = get_free_slots(building, human_individuals)
		while free_slots > 0 and not unhoused.is_empty():
			var resident: HumanIndividual = unhoused.pop_front()
			resident.house_id = building.id
			free_slots -= 1
			if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[ASSIGN HOUSE] #%d %s -> edificio #%d (%s)" % [
					resident.id, resident.name, building.id,
					building.rules.building_name if building.rules != null else "?"
				])
