class_name BuildingVerificationService
extends RefCounted

# Verifica se una posizione mondo è edificabile — RICOSTRUITA da zero passo per passo (2026-08-30,
# richiesta esplicita dell'utente: aggiungere un criterio alla volta, testando prima di passare al
# successivo, invece di scrivere tutto insieme — stesso principio già seguito per il LOD0, vedi
# memoria [[feedback_incremental_implementation]]). Stesso principio "un solo Service stateless
# per compito" già in uso ovunque nel progetto (RefCounted, .new() per uso, nessun autoload).
#
# NOTA MULTI-MICROCELLA (2026-08-30, promemoria per il futuro): oggi ogni edificio occupa UN solo
# punto (world_position -> una cella/microcella, vedi _resolve_cell_and_microcell). Un futuro
# edificio con un'impronta più grande di una microcella richiederà: (1) una forma/dimensione su
# Building/BuildingRules (required_space oggi è solo un conteggio, non basta — serve la FORMA),
# (2) far scorrere _is_position_clear su OGNI microcella dell'impronta invece che su una sola, (3)
# decidere quale bordo dell'impronta porta la porta per i Criteri 7/8. Il resto dell'architettura
# (un service stateless, criteri separati in blocchi) regge già: è un'estensione, non un rifacimento.
#
# Ogni criterio è un blocco separato e commentato qui sotto, in successione, deliberatamente non
# accorpato in un'unica condizione — richiesta esplicita dell'utente (2026-08-30): così restano
# ben individuabili singolarmente nel codice, facili da testare/rimuovere/riordinare uno alla
# volta man mano che se ne aggiungono altri in futuro.
#
# Criterio 1 (infrastruttura, non un vero criterio): il punto deve ricadere dentro una cella viva
# — prerequisito per poterne valutare qualunque altro, non qualcosa che l'utente possa "vedere"
# cambiare. UNIVERSALE (mai una preferenza di tipo edificio).
# Criterio 2: la microcella deve essere almeno "terrain fresh" nella fog of war
# (FogOfWarMemory.is_terrain_fresh — il tier più permissivo dei tre, quello che decade più
# lentamente: copre sia il visibile ORA sia un ricordo vecchio ma non ancora scaduto) — sul nero
# pieno (terrain scaduto o mai vista) non si può mai costruire. UNIVERSALE.
# Criterio 3: la macrocella non dev'essere acqua (SEA o LAKE — entrambe hanno terrain_base=WATER,
# a differenza del fiume che vive su terrain_base=PLAIN, vedi criterio 4) — controllo di MACROCELLA
# intera, non di singola microcella: un mare/lago copre sempre l'intera macrocella per come il
# mondo viene generato. SPECIFICO DEL TIPO: saltato se rules.buildable_on_water (es. un futuro
# molo).
# Criterio 4: la microcella non dev'essere parte del letto di un fiume (cell.river_positions,
# calcolate da RiverMicrocellService) — a differenza dell'acqua sopra, il fiume occupa solo
# ALCUNE microcelle di una macrocella PLAIN, non l'intera cella. SPECIFICO DEL TIPO: saltato se
# rules.buildable_on_river.
# Criterio 5: la microcella non dev'essere occupata da una roccia (cell.macro_state.
# stone_positions) — ostacolo permanente finché non viene esaurita dall'estrazione (2026-10-08, vedi
# RockStoneService.is_depleted e MicrocellObstacles), mai rimovibile altrimenti (a differenza della vegetazione, che può
# essere tagliata per far posto — vedi BuildingSiteClearingService, mai consultato qui). SPECIFICO
# DEL TIPO: saltato se rules.buildable_on_stone (es. una futura cava).
# Criterio 6: la microcella non dev'essere già occupata da un altro edificio (macro_world.
# buildings, filtrato per macro_x/macro_y/micro_x/micro_y) — stesso ostacolo permanente del
# criterio 5, ma per costruzioni invece che per roccia naturale. UNIVERSALE.
#
# I criteri 1-6 sono raggruppati in _is_position_clear sotto ("questo punto è noto e libero da
# ostacoli permanenti/di tipo", presi in base a `rules`) — riusata TALE E QUALE per il
# Criterio 7 (2026-08-30): la porta non può affacciarsi su una microcella ostacolata o ignota
# (stessa domanda "questo punto è libero?", posta sulla microcella adiacente nella direzione della
# porta invece che sulla capanna stessa) — richiesta esplicita dell'utente: non ha senso costruire
# con la porta bloccata da roccia/altro edificio/acqua/fiume (a meno che quel tipo non li permetta
# comunque, vedi sopra), o rivolta verso territorio mai scoperto (non sapendo cosa c'è, per
# coerenza è trattato come ostacolato). Il loop che risolve "quale cella viva contiene questo
# punto" gestisce da solo l'attraversamento di un confine di macrocella (se il vicino è vivo, lo
# trova; se non lo è, il punto risulta "ignoto" tramite lo stesso Criterio 1 — nessun caso
# speciale scritto per il bordo). SPECIFICO DEL TIPO: saltato per intero se not rules.has_door (un
# edificio senza porta non ha nulla da tenere sgombro davanti a sé).
#
# Criterio 8 (2026-08-30, caso "opposto" del Criterio 7): non si può piazzare un edificio esattamente
# sulla microcella verso cui punta la porta di un edificio ESISTENTE — altrimenti la porta di quello
# esistente risulterebbe bloccata dal nuovo edificio, anche se la posizione del nuovo edificio di
# per sé è libera (Criteri 1-6 passerebbero). Calcolo puramente aritmetico su macro_x/macro_y/
# micro_x/micro_y (stesso attraversamento di bordo del Criterio 7, qui in coordinate invece che in
# pixel — vedi BuildingFootprint.door_front): non richiede che la macrocella dell'edificio
# esistente sia viva, l'edificio è comunque un dato reale in macro_world.buildings. UNIVERSALE
# rispetto al NUOVO edificio (SEMPRE attivo, anche se il NUOVO edificio non ha porta propria —
# has_door riguarda solo se l'edificio che si sta piazzando ha una porta da tenere sgombra, non se
# può bloccare quella di un altro) — ma NON rispetto all'edificio ESISTENTE: se quello non ha porta
# (rules.has_door = false, es. Pebble Circle/Deposit Site) non c'è nulla da proteggere, va saltato
# (BUGFIX 2026-09-08, richiesta utente: un Deposit Site bloccava la costruzione sul lato sud, la sua
# `rotation` di default/SOUTH veniva letta come se fosse una porta vera anche con has_door=false).

#
# Criterio 10 (2026-09-28, richiesta utente; dal 2026-10-04 sempre attivo nel piazzamento della Build Task — le piante
# vive si abbattono solo con la task Cut): alberi e cespugli VIVI sulla microcella dell'edificio
# (BuildingSiteClearingService.has_woody_vegetation; ceppi e piante morte non contano) la rendono non edificabile con
# can_cut = false, che GameScene passa sempre per anteprima e conferma. Erba e microcelle vuote restano edificabili. Solo la microcella dell'edificio, non quella davanti
# alla porta (la pulizia del cantiere non la tocca). Default true = criterio disattivato. Per sapere se il rifiuto
# dipende SOLO da questo criterio basta richiamare con can_cut = true (vedi GameScene._report_woody_vegetation_block).

static func is_position_buildable(
	live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2,
	current_absolute_day: int, macro_world: World, direction: GameTypes.Direction, rules: BuildingRules,
	can_cut: bool = true, ignore_ground_pile: bool = false
) -> bool:
	# Ingombro (2026-10-17): i criteri 2-6 e 9-12 valgono per ogni microcella del rettangolo, il bordo di macrocella è
	# dentro resolve_placement (un 1x1 ha la sola microcella sotto il mouse, come prima).
	var placement := resolve_placement(live_cells, macro_cell_pixels, cell_size, world_position, direction, rules)
	if placement.is_empty():
		return false
	var cell: LiveMacroCell = placement["cell"]
	var macro_coords := Vector2i(cell.macro_x, cell.macro_y)
	for microcell: Vector2i in placement["cells"]:
		if not _is_position_clear(cell, microcell, current_absolute_day, macro_world, rules):
			return false

		# Criterio 10
		if not can_cut and BuildingSiteClearingService.has_woody_vegetation(cell.macro_state, microcell):
			return false

		# Criterio 11 (2026-10-16, Ceppo dell'insegnamento): serve almeno un ceppo d'albero sulla microcella.
		if rules.requires_tree_stump and not has_required_tree_stump(cell.macro_state, microcell):
			return false

		# Criterio 9 (2026-09-26, ground drop): non si costruisce sopra un mucchio a terra. Vale solo per la
		# microcella dell'edificio: davanti alla porta un mucchio non è un ostacolo (ci si cammina sopra).
		# `ignore_ground_pile` (2026-10-07): solo per sapere se il rifiuto dipende da piante e mucchio (messaggio al giocatore,
		# GameScene._is_placement_buildable_or_report); il piazzamento lo passa sempre false.
		if not ignore_ground_pile and GroundPileService.find_at(GameSettings.active_game_data, macro_coords, microcell) != null:
			return false
		# Criterio 12 (2026-10-17): roccia esaurita con ancora sassi di scarto, da raccogliere prima (come un mucchio).
		if not ignore_ground_pile and RockStoneService.has_waste_pebbles(cell.macro_state, microcell):
			return false

		# Criterio 8 — un edificio MOVEMENT (calpestabile, es. terra battuta) può stare davanti alla porta
		# di un edificio esistente: non la blocca, ci si cammina sopra (2026-09-19, richiesta utente).
		if not rules.walkable and _blocks_existing_building_door(
			cell.macro_x, cell.macro_y, microcell, macro_world
		):
			return false

	# Criterio 7
	if is_door_blocked(live_cells, macro_cell_pixels, cell_size, world_position, current_absolute_day, macro_world, direction, rules):
		return false

	return true


# Rettangolo dell'edificio col mouse al centro (2026-10-17, ingombro): {"cell": LiveMacroCell, "anchor": Vector2i,
# "cells": Array[Vector2i]}, {} se il punto non è in una cella viva o il rettangolo esce dalla macrocella. Per un 1x1
# l'ancora è la microcella sotto il mouse, come prima. Un solo punto che traduce il mouse in rettangolo, usato anche da
# GameScene per il piazzamento.
static func resolve_placement(
	live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2,
	direction: GameTypes.Direction, rules: BuildingRules
) -> Dictionary:
	var resolved := _resolve_cell_and_microcell(live_cells, macro_cell_pixels, cell_size, world_position)
	if resolved.is_empty():
		return {}
	var rect_size := BuildingFootprint.size(rules, direction)
	var anchor := BuildingFootprint.anchor_from_center(resolved["microcell"], rules, direction)
	if not BuildingFootprint.fits_in_macrocell(anchor, rect_size):
		return {}
	return {"cell": resolved["cell"], "anchor": anchor, "cells": BuildingFootprint.cells(anchor, rect_size)}


# Risolve world_position nella cella viva/microcella che lo contiene, o {} se nessuna cella viva
# lo copre (fuori dall'area caricata — vedi Criterio 1). Un solo punto che decide "in quale cella/
# microcella ricade questo punto", riusato da is_position_buildable sia per la capanna sia per la
# microcella davanti alla porta (Criterio 7), mai due implementazioni che potrebbero disallinearsi.
static func _resolve_cell_and_microcell(live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2) -> Dictionary:
	for cell in live_cells.values():
		var local_pos: Vector2 = cell.container.to_local(world_position)
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= macro_cell_pixels or local_pos.y >= macro_cell_pixels:
			continue
		return {"cell": cell, "microcell": Vector2i(int(local_pos.x / cell_size), int(local_pos.y / cell_size))}
	return {}


# Criteri 1 (implicito: `cell`/`microcell` già risolti da _resolve_cell_and_microcell) e 2-6 (vedi
# commento in testa al file) — "questo punto è noto e libero da ostacoli permanenti/di tipo",
# usata sia per la posizione della capanna stessa sia, dal Criterio 7, per la microcella davanti
# alla porta — `rules` decide quali dei criteri 3/4/5 si applicano per QUESTO tipo di edificio.
# `ignore_movement_buildings` (2026-09-19, richiesta utente): true SOLO per la microcella davanti alla
# porta (Criterio 7) — un edificio di categoria MOVEMENT (calpestabile, es. terra battuta) lì non è
# un ostacolo per la porta, quindi il Criterio 6 lo salta; gli altri controlli (Fog of War, acqua,
# fiume, roccia) restano. Per la posizione dell'edificio stesso resta false: non si costruisce sopra
# nessun altro edificio, calpestabile o no.
static func _is_position_clear(cell: LiveMacroCell, microcell: Vector2i, current_absolute_day: int, macro_world: World, rules: BuildingRules, ignore_movement_buildings: bool = false) -> bool:
	# Criterio 1
	if cell.macro_cell == null:
		return false

	# Criterio 2
	if cell.fog_of_war_renderer == null or cell.fog_of_war_renderer.fog_of_war_memory == null:
		return false
	if not cell.fog_of_war_renderer.fog_of_war_memory.is_terrain_fresh(
		microcell, current_absolute_day, cell.fog_of_war_renderer.terrain_memory_days
	):
		return false

	# Criteri 3-6: regola condivisa con la posa dei mucchi a terra (is_microcell_free).
	return is_microcell_free(
		Vector2i(cell.macro_x, cell.macro_y), cell.macro_cell, cell.macro_state, cell.river_positions, microcell, macro_world,
		rules.buildable_on_water, rules.buildable_on_river, rules.buildable_on_stone, ignore_movement_buildings
	)


# Criteri 3-6 su dati puri (2026-09-26, estratti da _is_position_clear e condivisi con GroundPileService.
# find_drop_microcell — posa dei mucchi a terra): "la microcella non ha ostacoli permanenti". Nessuna cella viva
# né Fog of War qui: lavora su MacroCellData/MacroCellState/World, così la può usare chi non ha una
# LiveMacroCell. `river_positions` = microcelle del fiume della macrocella (Array o Dictionary, basta .has()).
# I tre flag allow_* corrispondono a BuildingRules.buildable_on_water/_river/_stone; ignore_movement_buildings
# salta gli edifici calpestabili (categoria MOVEMENT).
static func is_microcell_free(
	macro_coords: Vector2i, macro_cell: MacroCellData, macro_state: MacroCellState, river_positions: Variant,
	microcell: Vector2i, macro_world: World, allow_water: bool = false, allow_river: bool = false,
	allow_stone: bool = false, ignore_movement_buildings: bool = false
) -> bool:
	# Regola spostata in MicrocellObstacles (2026-09-27, pathfinding step 1), comportamento invariato: chi interroga
	# molte microcelle della stessa macrocella costruisce MicrocellObstacles una volta e usa is_free direttamente.
	return MicrocellObstacles.build(macro_coords, macro_cell, macro_state, river_positions, macro_world).is_free(
		microcell, allow_water, allow_river, allow_stone, ignore_movement_buildings
	)


# Microcelle del fiume di una macrocella, calcolate dai dati (stessa formula di GameScene._activate_live_cell
# per LiveMacroCell.river_positions), come Dictionary per lookup rapidi. Vuoto se la macrocella non ha fiume.
static func get_river_lookup(macro_cell: MacroCellData, macro_state: MacroCellState) -> Dictionary:
	var lookup: Dictionary = {}
	if macro_cell == null or macro_state == null or macro_cell.water_type != GameTypes.WaterType.RIVER:
		return lookup
	var thickness_ratio: float = float(macro_state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
	for position in RiverMicrocellService.get_river_positions(macro_cell.river_shape, thickness_ratio):
		lookup[position] = true
	return lookup


# Microcella davanti alla porta di un edificio con porta: {"macro": Vector2i, "micro": Vector2i}, {} se
# l'edificio non ha porta. Pubblica per la posa dei mucchi a terra (GroundPileService).
static func get_door_front(building: Building) -> Dictionary:
	if building == null or building.rules == null or not building.rules.has_door:
		return {}
	return BuildingFootprint.door_front_of(building)


# Criterio 8 (vedi commento in testa al file): true se un edificio esistente CON PORTA ha la porta
# rivolta esattamente su (target_macro_x, target_macro_y, target_microcell). Edifici senza porta
# (rules.has_door = false) sono saltati — non hanno una porta da proteggere, la loro `rotation`
# esiste solo come dato residuo (default SOUTH) e non rappresenta un orientamento reale mostrato a
# schermo (vedi BuildingGhost/MicroCellRenderer, che ignorano rotation_dir per questi tipi).
static func _blocks_existing_building_door(
	target_macro_x: int, target_macro_y: int, target_microcell: Vector2i, macro_world: World
) -> bool:
	if macro_world == null:
		return false
	for building in macro_world.buildings:
		if building.rules == null or not building.rules.has_door:
			continue
		var door := BuildingFootprint.door_front_of(building)
		if door["macro"] == Vector2i(target_macro_x, target_macro_y) and door["micro"] == target_microcell:
			return true
	return false


# Ingombro (2026-10-17), per il messaggio al giocatore: prima microcella del rettangolo (`placement` da resolve_placement)
# senza il ceppo richiesto, Vector2i(-1, -1) se non manca o il tipo non lo richiede.
static func find_cell_missing_tree_stump(placement: Dictionary, rules: BuildingRules) -> Vector2i:
	if placement.is_empty() or rules == null or not rules.requires_tree_stump:
		return Vector2i(-1, -1)
	var cell: LiveMacroCell = placement["cell"]
	for microcell: Vector2i in placement["cells"]:
		if not has_required_tree_stump(cell.macro_state, microcell):
			return microcell
	return Vector2i(-1, -1)


# Ingombro (2026-10-17), per i messaggi al giocatore: ostacoli rimovibili su una qualunque microcella del rettangolo —
# {"woody", "pile", "waste_pebbles"}. Senza rettangolo (`placement` vuoto) "woody" resta vero, come prima.
static func get_removable_blocks(placement: Dictionary) -> Dictionary:
	var blocks := {"woody": placement.is_empty(), "pile": false, "waste_pebbles": false}
	if placement.is_empty():
		return blocks
	var cell: LiveMacroCell = placement["cell"]
	var macro_coords := Vector2i(cell.macro_x, cell.macro_y)
	for microcell: Vector2i in placement["cells"]:
		if BuildingSiteClearingService.has_woody_vegetation(cell.macro_state, microcell):
			blocks["woody"] = true
		if GroundPileService.find_at(GameSettings.active_game_data, macro_coords, microcell) != null:
			blocks["pile"] = true
		if RockStoneService.has_waste_pebbles(cell.macro_state, microcell):
			blocks["waste_pebbles"] = true
	return blocks


# Applica il feedback visivo di edificabilità a un BuildingGhost — un solo punto che decide "come
# mostrare" true/false (rosso/verde, vedi BuildingGhost.is_buildable), cosicché il futuro sistema
# più accurato (edifici esistenti/altri ostacoli) debba solo estendere is_position_buildable
# sopra, mai duplicare la parte visiva.
static func set_buildable_appearance(ghost: BuildingGhost, is_buildable: bool) -> void:
	ghost.is_buildable = is_buildable


# true se sulla microcella c'è almeno un ceppo d'albero (BuildingRules.requires_tree_stump; anno della partita attiva).
static func has_required_tree_stump(macro_state: MacroCellState, microcell: Vector2i) -> bool:
	var current_year: int = GameSettings.active_game_data.year if GameSettings.active_game_data != null else 0
	return BuildingSiteClearingService.count_tree_stumps(macro_state, microcell, current_year) > 0


# Criterio 7 (estratto il 2026-10-17 per il messaggio al giocatore): true se l'edificio ha la porta e la microcella
# davanti non è libera (o non è caricata).
static func is_door_blocked(
	live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2,
	current_absolute_day: int, macro_world: World, direction: GameTypes.Direction, rules: BuildingRules
) -> bool:
	if rules == null or not rules.has_door:
		return false
	# Ingombro (2026-10-17): la cella davanti alla porta del rettangolo (BuildingFootprint.door_front), anche nella
	# macrocella accanto; se quella non è viva la porta conta come bloccata, come prima.
	var placement := resolve_placement(live_cells, macro_cell_pixels, cell_size, world_position, direction, rules)
	if placement.is_empty():
		return false
	var cell: LiveMacroCell = placement["cell"]
	var door := BuildingFootprint.door_front(Vector2i(cell.macro_x, cell.macro_y), placement["anchor"], rules, direction)
	var door_cell: LiveMacroCell = live_cells.get(door["macro"])
	if door_cell == null:
		return true
	return not _is_position_clear(door_cell, door["micro"], current_absolute_day, macro_world, rules, true)
