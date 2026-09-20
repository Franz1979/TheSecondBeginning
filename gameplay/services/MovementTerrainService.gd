class_name MovementTerrainService
extends RefCounted

# "Cosa c'è in questa microcella e come influisce su chi ci cammina" (2026-09-19, richiesta utente):
# UN SOLO punto che risolve i modificatori di movimento del terreno — oggi stamina e velocità,
# domani modificatori naturali (salite, paludi) e, in una fase a parte, percorribilità. Service
# stateless come gli altri (RefCounted, static), salvo il contatore di versione sotto.
#
# MAPPA SPARSA, non una griglia densa (richiesta utente): LiveMacroCell.movement_modifiers contiene
# SOLO le microcelle che deviano dalla norma — Vector2i -> Vector2(stamina, velocità) — come già
# fanno la memoria della Fog of War e i registri del raccolto; l'assenza significa (1.0, 1.0).
# Costruita da rebuild() quando cambia qualcosa che la influenza (oggi: gli edifici della cella,
# vedi GameScene._refresh_building_visuals, che copre completamento, piazzamento, demolizione,
# riattivazione cella e rinfresco dei vicini di bordo); i moltiplicatori vengono RISOLTI qui, alla
# costruzione, mai riletti dal .tres di BuildingRules a ogni query.
#
# Interrogazione: update_individual(), chiamata da HumanIndividualMovementService.advance_movement
# (nello stesso frame, prima di apply_action) pubblica i due moltiplicatori sull'individuo
# (HumanIndividual.terrain_*_multiplier), come già fa move_speed_multiplier: WalkAction/RunAction
# restano senza dipendenze dal mondo. Un memo sull'individuo (chiave microcella + versione mappa)
# rende la chiamata quasi gratuita nei frame in cui non cambia microcella.

# Versione univoca globale assegnata a ogni rebuild (mai riusata, nemmeno tra celle diverse o dopo
# la disattivazione/ricreazione di una cella): il memo dell'individuo confronta solo (chiave,
# versione). 0 è riservato a "mai costruita" (LiveMacroCell.movement_version di default).
static var _next_version: int = 1

# Sentinella di versione per "cella non viva" nel memo (diversa da ogni versione reale >= 1 e dal
# default -1 dell'individuo).
const VERSION_NOT_LIVE: int = -2


# Ricostruisce la mappa sparsa di UNA cella viva da macro_world.buildings. Solo edifici COMPLETI e
# non demoliti (un cantiere non modifica il cammino), solo i tipi con un moltiplicatore diverso da
# 1.0. Nessuna scansione della griglia 100x100: costo O(edifici del mondo), a eventi rari.
# Fiumi/rocce/pendenze NON sono qui (nessuna percorribilità né modificatori naturali per ora): una
# nuova fonte si aggiunge come un altro blocco di questa funzione, componendo per prodotto.
static func rebuild(cell: LiveMacroCell, macro_world: World) -> void:
	var modifiers: Dictionary = {}
	if macro_world != null:
		for building in macro_world.buildings:
			if building.macro_x != cell.macro_x or building.macro_y != cell.macro_y:
				continue
			if not building.is_complete or building.is_demolished or building.rules == null:
				continue
			var stamina: float = building.rules.movement_stamina_multiplier
			var speed: float = building.rules.movement_speed_multiplier
			if is_equal_approx(stamina, 1.0) and is_equal_approx(speed, 1.0):
				continue
			var key := Vector2i(building.micro_x, building.micro_y)
			var existing: Vector2 = modifiers.get(key, Vector2.ONE)
			modifiers[key] = Vector2(existing.x * stamina, existing.y * speed)
	cell.movement_modifiers = modifiers
	cell.movement_version = _next_version
	_next_version += 1


# Risolve la microcella sotto `individual.position` (coordinate microcella continue, locali a
# home_macro_coords — possono uscire da [0, World.WIDTH) quando cammina in una macrocella vicina,
# da cui la divisione con floor) e aggiorna terrain_stamina_multiplier/terrain_speed_multiplier.
# Memo: se chiave e versione della mappa sono invariate rispetto all'ultima chiamata, non fa nulla.
# Cella non viva o microcella assente dalla mappa -> (1.0, 1.0).
static func update_individual(individual: HumanIndividual, live_cells: Dictionary) -> void:
	var micro_world_x: int = floori(individual.position.x)
	var micro_world_y: int = floori(individual.position.y)
	var macro_offset_x: int = floori(float(micro_world_x) / float(World.WIDTH))
	var macro_offset_y: int = floori(float(micro_world_y) / float(World.HEIGHT))
	var macro_coords := Vector2i(
		individual.home_macro_coords.x + macro_offset_x, individual.home_macro_coords.y + macro_offset_y
	)
	var micro := Vector2i(micro_world_x - macro_offset_x * World.WIDTH, micro_world_y - macro_offset_y * World.HEIGHT)
	var key := Vector4i(macro_coords.x, macro_coords.y, micro.x, micro.y)

	var cell: LiveMacroCell = live_cells.get(macro_coords)
	var version: int = cell.movement_version if cell != null else VERSION_NOT_LIVE
	if key == individual.terrain_cache_key and version == individual.terrain_cache_version:
		return
	individual.terrain_cache_key = key
	individual.terrain_cache_version = version

	var modifier := Vector2.ONE
	if cell != null:
		modifier = cell.movement_modifiers.get(micro, Vector2.ONE)
	individual.terrain_stamina_multiplier = modifier.x
	individual.terrain_speed_multiplier = modifier.y
