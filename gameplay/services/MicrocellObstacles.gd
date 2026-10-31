class_name MicrocellObstacles
extends RefCounted

# Ostacoli permanenti delle microcelle di UNA macrocella (2026-09-27, pathfinding step 1 — estratto da
# BuildingVerificationService.is_microcell_free, che ora lo usa): acqua, fiume, rocce, edifici, raccolti in INSIEMI
# (Dictionary microcella -> true / id edificio) con UNA passata sui dati, così chi interroga molte microcelle della
# stessa cella (griglia del pathfinding, posa dei mucchi) non rifà scansioni lineari per ognuna.
#
# La regola "microcella libera" (is_free) è quella di sempre dei Criteri 3-6 del piazzamento edifici:
#   3. acqua: la macrocella intera è WATER;
#   4. fiume: la microcella è nella fascia fluviale; ruscello (StreamMicrocellService): blocca il piazzamento ma
#      non il cammino (allow_stream, il pathfinding lo attraversa a costo alto);
#   5. roccia: la microcella è in MacroCellState.stone_positions e la roccia non è esaurita (RockStoneService.is_depleted);
#   6. edificio: un edificio del mondo sta su quella microcella (quelli MOVEMENT, calpestabili, contano o no a scelta).
# Alberi, vegetazione e mucchi a terra non sono ostacoli qui.

# false = macrocella sconosciuta (MacroCellData nullo): nessuna microcella è libera, come prima.
var cell_known: bool = false
var water_cell: bool = false
var river: Dictionary = {}
var stream: Dictionary = {}
var stones: Dictionary = {}
# Edifici che bloccano (tutti tranne i calpestabili, BuildingRules.walkable): microcella -> id edificio.
var blocking_buildings: Dictionary = {}
# Edifici calpestabili (BuildingRules.walkable, es. terra battuta, spiazzo): microcella -> id edificio.
var movement_buildings: Dictionary = {}
# Barriere (2026-10-23, richiesta utente): palizzata, vallo e cancello chiuso, tra quelli che bloccano. Un percorso che
# finisce su una loro microcella si ferma sulla microcella libera prima, dal proprio lato (PathfindingService.find_path):
# sopra una barriera non si arriva, quindi non la si attraversa ripartendo da lì. Microcella -> id edificio.
const BARRIER_TYPES: Array[String] = ["palisade", "gate", "earthwork"]
var barrier_buildings: Dictionary = {}
# Strada sotto il cancello (2026-10-24, richiesta utente): due strati sulla stessa microcella solo tra un edificio di suolo
# (BuildingRules.walkable) e uno che lo ammette sotto di sé (BuildingRules.allows_ground_beneath, il cancello). Solo il
# piazzamento li consulta (is_free con stack_as_host/stack_as_ground). Microcella -> id edificio.
var ground_hosts: Dictionary = {}
var ground_buildings: Dictionary = {}


# `river_positions`: microcelle del fiume (Array o Dictionary con le microcelle come chiavi, o null).
static func build(
	macro_coords: Vector2i, macro_cell: MacroCellData, macro_state: MacroCellState, river_positions: Variant, macro_world: World
) -> MicrocellObstacles:
	var obstacles := MicrocellObstacles.new()
	obstacles.cell_known = macro_cell != null
	if macro_cell == null:
		return obstacles
	obstacles.water_cell = macro_cell.terrain_base == GameTypes.TerrainBase.WATER
	if river_positions is Dictionary:
		obstacles.river = (river_positions as Dictionary).duplicate()
	elif river_positions is Array:
		for position in river_positions:
			obstacles.river[position] = true
	obstacles.stream = StreamMicrocellService.get_positions(macro_world, macro_cell)
	if macro_state != null:
		# Rocce esaurite (2026-10-08): non sono più ostacoli (RockStoneService.is_depleted).
		var depleted := RockStoneService.get_depleted_positions(macro_state)
		for position in macro_state.stone_positions:
			if not depleted.has(position):
				obstacles.stones[position] = true
	obstacles.refresh_buildings(macro_coords, macro_world)
	return obstacles


# Ricalcola SOLO gli insiemi degli edifici (costruzione/demolizione): rocce, fiume e acqua non cambiano. Contano TUTTI
# gli edifici di World.buildings, completi o no: un cantiere blocca la sua microcella dal momento in cui è piazzato
# (i MOVEMENT restano calpestabili anche da cantiere); un edificio demolito esce dall'elenco e la libera.
func refresh_buildings(macro_coords: Vector2i, macro_world: World) -> void:
	blocking_buildings.clear()
	movement_buildings.clear()
	barrier_buildings.clear()
	ground_hosts.clear()
	ground_buildings.clear()
	if macro_world == null:
		return
	for building in macro_world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		# Ingombro (2026-10-17): tutte le microcelle del rettangolo (BuildingFootprint; 1x1 = la sola microcella).
		# Calpestabili (2026-10-17): dal flag BuildingRules.walkable, non più dalla categoria MOVEMENT.
		# Cancello (2026-10-23): calpestabile solo se aperto (Building.is_walkable).
		var is_walkable: bool = building.is_walkable()
		var is_host: bool = building.rules != null and building.rules.allows_ground_beneath
		var is_ground: bool = building.rules != null and building.rules.walkable
		for microcell in BuildingFootprint.cells_of(building):
			if is_host:
				ground_hosts[microcell] = building.id
			if is_ground:
				ground_buildings[microcell] = building.id
			if is_walkable:
				movement_buildings[microcell] = building.id
			else:
				blocking_buildings[microcell] = building.id
				if BARRIER_TYPES.has(building.building_type_name):
					barrier_buildings[microcell] = building.id


# true se sulla microcella c'è una barriera che blocca adesso (palizzata, vallo, cancello chiuso).
func is_barrier(microcell: Vector2i) -> bool:
	return barrier_buildings.has(microcell)


# Regola dei Criteri 3-6 (vedi in testa). I flag allow_* corrispondono a BuildingRules.buildable_on_water/_river/
# _stone; ignore_movement_buildings salta gli edifici calpestabili.
# Sovrapposizione (2026-10-24, solo piazzamento): `stack_as_host` = si piazza un edificio con allows_ground_beneath, che
# può andare sopra una strada ma non sopra un altro ospite; `stack_as_ground` = si piazza un edificio di suolo, che può
# andare sotto un ospite (aperto, chiuso o cantiere) ma non dove c'è già un altro edificio di suolo.
func is_free(
	microcell: Vector2i, allow_water: bool = false, allow_river: bool = false, allow_stone: bool = false,
	ignore_movement_buildings: bool = false, stack_as_host: bool = false, stack_as_ground: bool = false,
	allow_stream: bool = false
) -> bool:
	if not cell_known:
		return false
	if not allow_water and water_cell:
		return false
	if not allow_river and river.has(microcell):
		return false
	if not allow_stream and not allow_river and stream.has(microcell):
		return false
	if not allow_stone and stones.has(microcell):
		return false
	if stack_as_host:
		return not ground_hosts.has(microcell) and not blocking_buildings.has(microcell)
	if stack_as_ground and ground_hosts.has(microcell):
		if ground_buildings.has(microcell):
			return false
		return blocking_buildings.get(microcell, ground_hosts[microcell]) == ground_hosts[microcell]
	if blocking_buildings.has(microcell):
		return false
	if not ignore_movement_buildings and movement_buildings.has(microcell):
		return false
	return true
