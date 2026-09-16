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
# modo qui, nessuna lettura di residency_assignment_tier in questo file). Nessuna preferenza tra
# tipi di edificio: gli edifici vengono scanditi nell'ordine in cui compaiono in world.buildings
# (ordine di costruzione) e il primo posto libero trovato viene occupato — quando in futuro tier
# diversi vorranno criteri diversi (es. "famiglia/nucleo" per i tier più alti), quella logica andrà
# aggiunta QUI, leggendo building.rules.residency_assignment_tier per scegliere quale criterio
# applicare a QUEL building, non prima.
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

	# Scandisce world.buildings nell'ordine in cui si trovano (ordine di costruzione, nessuna
	# priorità Tent/Hut) — per ciascun edificio residenziale COMPLETO con posti liberi, riempie finché
	# ne ha o finché la coda `unhoused` si svuota. Conteggio occupanti per scansione lineare di
	# human_individuals ad ogni edificio (O(edifici × individui), stesso principio "numeri piccoli,
	# costo accettabile" già assunto altrove nel progetto per liste di questa scala, es.
	# TaskPersistenceService._find_building_by_id) — nessun indice/cache mantenuto a parte.
	for building in world.buildings:
		if unhoused.is_empty():
			break
		if building.rules == null or building.rules.max_residents <= 0:
			continue
		if not building.is_complete:
			continue
		var occupied_count := 0
		for individual in human_individuals:
			if individual.house_id == building.id:
				occupied_count += 1
		var free_slots: int = building.rules.max_residents - occupied_count
		while free_slots > 0 and not unhoused.is_empty():
			var resident: HumanIndividual = unhoused.pop_front()
			resident.house_id = building.id
			free_slots -= 1
			if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[ASSIGN HOUSE] #%d %s -> edificio #%d (%s)" % [
					resident.id, resident.name, building.id,
					building.rules.building_name if building.rules != null else "?"
				])
