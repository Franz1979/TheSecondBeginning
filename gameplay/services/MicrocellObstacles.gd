class_name MicrocellObstacles
extends RefCounted

# Ostacoli permanenti delle microcelle di UNA macrocella (2026-09-27, pathfinding step 1 — estratto da
# BuildingVerificationService.is_microcell_free, che ora lo usa): acqua, fiume, rocce, edifici, raccolti in INSIEMI
# (Dictionary microcella -> true / id edificio) con UNA passata sui dati, così chi interroga molte microcelle della
# stessa cella (griglia del pathfinding, posa dei mucchi) non rifà scansioni lineari per ognuna.
#
# La regola "microcella libera" (is_free) è quella di sempre dei Criteri 3-6 del piazzamento edifici:
#   3. acqua: la macrocella intera è WATER;
#   4. fiume: la microcella è nella fascia fluviale;
#   5. roccia: la microcella è in MacroCellState.stone_positions;
#   6. edificio: un edificio del mondo sta su quella microcella (quelli MOVEMENT, calpestabili, contano o no a scelta).
# Alberi, vegetazione e mucchi a terra non sono ostacoli qui.

# false = macrocella sconosciuta (MacroCellData nullo): nessuna microcella è libera, come prima.
var cell_known: bool = false
var water_cell: bool = false
var river: Dictionary = {}
var stones: Dictionary = {}
# Edifici che bloccano (tutti tranne la categoria MOVEMENT): microcella -> id edificio.
var blocking_buildings: Dictionary = {}
# Edifici calpestabili (categoria MOVEMENT, es. terra battuta): microcella -> id edificio.
var movement_buildings: Dictionary = {}


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
	if macro_state != null:
		for position in macro_state.stone_positions:
			obstacles.stones[position] = true
	obstacles.refresh_buildings(macro_coords, macro_world)
	return obstacles


# Ricalcola SOLO gli insiemi degli edifici (costruzione/demolizione): rocce, fiume e acqua non cambiano. Contano TUTTI
# gli edifici di World.buildings, completi o no: un cantiere blocca la sua microcella dal momento in cui è piazzato
# (i MOVEMENT restano calpestabili anche da cantiere); un edificio demolito esce dall'elenco e la libera.
func refresh_buildings(macro_coords: Vector2i, macro_world: World) -> void:
	blocking_buildings.clear()
	movement_buildings.clear()
	if macro_world == null:
		return
	for building in macro_world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		var microcell := Vector2i(building.micro_x, building.micro_y)
		if building.rules != null and building.rules.category == BuildingTypes.Category.MOVEMENT:
			movement_buildings[microcell] = building.id
		else:
			blocking_buildings[microcell] = building.id


# Regola dei Criteri 3-6 (vedi in testa). I flag allow_* corrispondono a BuildingRules.buildable_on_water/_river/
# _stone; ignore_movement_buildings salta gli edifici calpestabili.
func is_free(
	microcell: Vector2i, allow_water: bool = false, allow_river: bool = false, allow_stone: bool = false,
	ignore_movement_buildings: bool = false
) -> bool:
	if not cell_known:
		return false
	if not allow_water and water_cell:
		return false
	if not allow_river and river.has(microcell):
		return false
	if not allow_stone and stones.has(microcell):
		return false
	if blocking_buildings.has(microcell):
		return false
	if not ignore_movement_buildings and movement_buildings.has(microcell):
		return false
	return true
