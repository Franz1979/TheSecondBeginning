class_name VillageService
extends RefCounted

# Nascita e centro dei villaggi (2026-10-12, richiesta utente — passo 2 Folk/Village). Stateless, solo static.
# 1 villaggio = 1 village center: il villaggio nasce automaticamente quando un centro viene completato (mai una scelta
# del giocatore); se il centro sparisce il villaggio resta in vita senza centro e il prossimo centro completato lo
# ricollega invece di fondarne un altro.

enum CenterOutcome { NONE, FOUNDED, RECONNECTED }
# Lunghezza massima del nome del villaggio (2026-10-26).
const VILLAGE_NAME_MAX_LENGTH := 16
# Livello di centro minimo per battezzare il villaggio (2026-10-26): il Cerchio del consiglio (Organizzazione tribale).
const NAMING_MIN_CENTER_TIER := 2
# Battesimo (2026-10-26, richiesta utente): una volta sola, coesione al villaggio; la lealtà di chi ci abita parte da 0.
const NAMING_COHESION_GAIN := 2.0


# Candidato centro `center` (BuildingRules.can_be_village_center) completato: lo ricollega al primo villaggio del Folk
# senza centro; se il Folk non ha ancora villaggi ne fonda uno. In entrambi i casi i membri del Folk e gli edifici ancora
# senza villaggio vi entrano. NONE se il centro era già di un villaggio (es. miglioramento, stesso edificio) o se tutti i
# villaggi hanno già un centro (2026-10-26, cerchio del consiglio: resta un candidato, il centro ce lo sposta il giocatore —
# move_center; nessun secondo villaggio per ora). Restituisce {"outcome": CenterOutcome, "village"}.
static func on_village_center_completed(
	folk: Folk, world: World, center: Building, individuals: Array[HumanIndividual]
) -> Dictionary:
	if folk == null or center == null:
		return {"outcome": CenterOutcome.NONE, "village": null}
	var existing := find_village_by_center(folk, center.id)
	if existing != null:
		return {"outcome": CenterOutcome.NONE, "village": existing}
	var outcome := CenterOutcome.RECONNECTED
	var village: Village = null
	for candidate in folk.villages:
		if candidate.center_building_id == -1:
			village = candidate
			break
	if village == null and not folk.villages.is_empty():
		return {"outcome": CenterOutcome.NONE, "village": null}
	if village == null:
		outcome = CenterOutcome.FOUNDED
		village = Village.new()
		village.id = folk.next_village_id
		folk.next_village_id += 1
		village.folk_ref = folk
		folk.villages.append(village)
	village.center_building_id = center.id
	center.village_id = village.id
	for individual in individuals:
		if individual.folk_ref == folk and individual.village_ref == null:
			individual.village_ref = village
	adopt_orphan_buildings(folk, world)
	return {"outcome": outcome, "village": village}


# Centro rimosso (demolito o crollato): il villaggio resta (abitanti, nome, in futuro valori accumulati) ma senza
# centro. Restituisce il villaggio che lo perde, null se il centro non era di nessun villaggio.
static func on_village_center_removed(folk: Folk, center: Building) -> Village:
	if folk == null or center == null:
		return null
	var village := find_village_by_center(folk, center.id)
	if village != null:
		village.center_building_id = -1
	return village


# Apertura della partita (nuova o caricata): collega in silenzio i centri completi che non hanno ancora un villaggio —
# partite salvate prima dei villaggi e, in futuro, partite che iniziano con un centro già costruito — e assegna gli
# edifici rimasti senza villaggio (salvataggi precedenti al campo Building.village_id). Solo se il Folk non ha ancora
# villaggi (2026-10-26): un candidato non-centro (cerchio di sassi dopo lo spostamento) non ricollega nulla in silenzio.
static func sync_with_existing_centers(folk: Folk, world: World, individuals: Array[HumanIndividual]) -> void:
	if folk == null or world == null:
		return
	for building in world.buildings:
		if not folk.villages.is_empty():
			break
		if building.is_complete and not building.is_demolished and building.rules != null and building.rules.can_be_village_center():
			on_village_center_completed(folk, world, building, individuals)
	adopt_orphan_buildings(folk, world)


# Edifici senza villaggio (village_id -1) assegnati al villaggio scelto da find_village_for_building. Oggi, con un solo
# villaggio, vanno tutti a lui; col secondo centro andranno al più vicino. No-op se il Folk non ha villaggi.
static func adopt_orphan_buildings(folk: Folk, world: World) -> void:
	if folk == null or world == null or folk.villages.is_empty():
		return
	for building in world.buildings:
		if building.village_id == -1 and not building.is_demolished:
			var village := find_village_for_building(folk, world, building)
			if village != null:
				building.village_id = village.id


# Villaggio di un edificio appena piazzato o da adottare: quello col centro più vicino; se nessun villaggio ha un
# centro, il primo del Folk; null se il Folk non ha villaggi (l'edificio resta senza finché un centro non lo adotta).
static func find_village_for_building(folk: Folk, world: World, building: Building) -> Village:
	if folk == null or folk.villages.is_empty():
		return null
	var best: Village = null
	var best_distance := INF
	for village in folk.villages:
		var center := _find_building(world, village.center_building_id)
		if center == null:
			continue
		var distance := _absolute_microcell(center).distance_squared_to(_absolute_microcell(building))
		if distance < best_distance:
			best_distance = distance
			best = village
	return best if best != null else folk.villages[0]


# --- Spostamento del centro (2026-10-26, richiesta utente — cerchio del consiglio) ---
# Irreversibile: il centro va solo verso un candidato di livello superiore (BuildingRules.village_center_tier), mai
# indietro né tra pari. Villaggio senza centro (demolito o crollato): recupero libero verso qualunque candidato. Il vecchio
# centro resta in piedi con i suoi raggi, accetta pensieri e resta punto di assegnazione.

# Villaggio di `building` (Building.village_id) a cui può passare il centro; null se lo spostamento non è possibile.
static func get_center_move_village(folk: Folk, world: World, building: Building) -> Village:
	if folk == null or building == null or building.rules == null or not building.rules.can_be_village_center():
		return null
	if not building.is_complete or building.is_demolished or building.is_out_of_service():
		return null
	var village := folk.find_village(building.village_id)
	if village == null or village.center_building_id == building.id:
		return null
	var center := _find_building(world, village.center_building_id)
	if center == null or center.is_demolished or center.rules == null:
		return village
	return village if building.rules.village_center_tier > center.rules.village_center_tier else null


# Sposta il centro di `village` su `building` (già verificato con get_center_move_village). `village_name` non vuoto =
# battesimo del villaggio (solo se non ha ancora un nome).
static func move_center(village: Village, building: Building, village_name: String) -> void:
	if village == null or building == null:
		return
	village.center_building_id = building.id
	building.village_id = village.id
	if building.rules.village_center_tier >= NAMING_MIN_CENTER_TIER:
		name_village(village, village_name)


# --- Nome del villaggio (2026-10-26, richiesta utente) ---
# Si dà una volta sola, allo spostamento del centro o più avanti dal pannello del centro, e solo con un centro di livello
# NAMING_MIN_CENTER_TIER. Per ora non si rinomina mai (in futuro forse sì, perdendo lealtà e coesione).

# Villaggio di cui `building` è il centro e che si può battezzare adesso; null altrimenti.
static func get_nameable_village(folk: Folk, world: World, building: Building) -> Village:
	if folk == null or building == null or building.rules == null:
		return null
	if building.rules.village_center_tier < NAMING_MIN_CENTER_TIER:
		return null
	var village := find_village_by_center(folk, building.id)
	if village == null or village.name != "" or find_center_building(world, village) != building:
		return null
	return village


# Battesimo: solo se il villaggio non ha ancora un nome e `village_name` non è vuoto. true se il nome è stato dato.
static func name_village(village: Village, village_name: String) -> bool:
	var trimmed := village_name.strip_edges().left(VILLAGE_NAME_MAX_LENGTH)
	if village == null or village.name != "" or trimmed == "":
		return false
	village.name = trimmed
	VillageCohesionService.add(village, NAMING_COHESION_GAIN, "battesimo del villaggio")
	for individual in GameSettings.active_human_individuals:
		if individual.village_ref == village:
			individual.current_loyalty = 0.0
	return true


# Lealtà (2026-10-26, richiesta utente): esiste solo verso un villaggio con un nome. Prima del battesimo è ferma, nessuna
# regola la tocca (HumanVitalsInteractionService, PoliticalRiteService), il pannello la mostra grigia e le statistiche la
# saltano.
static func is_loyalty_active(individual: HumanIndividual) -> bool:
	return individual != null and individual.village_ref != null and individual.village_ref.name != ""


# Edificio centro di `village` (completo e non demolito); null se non c'è.
static func find_center_building(world: World, village: Village) -> Building:
	if village == null:
		return null
	var center := _find_building(world, village.center_building_id)
	return center if center != null and center.is_complete and not center.is_demolished else null


static func find_village_by_center(folk: Folk, center_building_id: int) -> Village:
	if folk == null or center_building_id < 0:
		return null
	for village in folk.villages:
		if village.center_building_id == center_building_id:
			return village
	return null


static func _find_building(world: World, building_id: int) -> Building:
	if world == null or building_id < 0:
		return null
	for building in world.buildings:
		if building.id == building_id:
			return building
	return null


# Posizione in microcelle assolute (stessa convenzione di InfluenceService): confronta edifici di macrocelle diverse.
static func _absolute_microcell(building: Building) -> Vector2:
	return Vector2(building.macro_x * World.WIDTH + building.micro_x, building.macro_y * World.HEIGHT + building.micro_y)
