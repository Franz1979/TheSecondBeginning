class_name VillageService
extends RefCounted

# Nascita e centro dei villaggi (2026-10-12, richiesta utente — passo 2 Folk/Village). Stateless, solo static.
# 1 villaggio = 1 village center: il villaggio nasce automaticamente quando un centro viene completato (mai una scelta
# del giocatore); se il centro sparisce il villaggio resta in vita senza centro e il prossimo centro completato lo
# ricollega invece di fondarne un altro.

enum CenterOutcome { NONE, FOUNDED, RECONNECTED }


# Centro `center` completato: lo ricollega al primo villaggio del Folk senza centro, altrimenti fonda un villaggio
# nuovo. In entrambi i casi i membri del Folk e gli edifici ancora senza villaggio vi entrano. NONE se il centro era
# già di un villaggio (es. miglioramento di un centro, stesso edificio). Restituisce {"outcome": CenterOutcome, "village"}.
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
# edifici rimasti senza villaggio (salvataggi precedenti al campo Building.village_id).
static func sync_with_existing_centers(folk: Folk, world: World, individuals: Array[HumanIndividual]) -> void:
	if folk == null or world == null:
		return
	for building in world.buildings:
		if building.is_complete and not building.is_demolished and building.rules != null and building.rules.is_village_center:
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
