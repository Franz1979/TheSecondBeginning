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
# stone_positions) — ostacolo permanente, mai rimovibile (a differenza della vegetazione, che può
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
# pixel — vedi _door_target_macro_micro sotto): non richiede che la macrocella dell'edificio
# esistente sia viva, l'edificio è comunque un dato reale in macro_world.buildings. UNIVERSALE
# (SEMPRE attivo, anche se il NUOVO edificio non ha porta propria — has_door riguarda solo se
# l'edificio che si sta piazzando ha una porta da tenere sgombra, non se può bloccare quella di un
# altro).

static func is_position_buildable(
	live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2,
	current_absolute_day: int, macro_world: World, direction: GameTypes.Direction, rules: BuildingRules
) -> bool:
	var resolved := _resolve_cell_and_microcell(live_cells, macro_cell_pixels, cell_size, world_position)
	if resolved.is_empty():
		return false
	if not _is_position_clear(resolved["cell"], resolved["microcell"], current_absolute_day, macro_world, rules):
		return false

	# Criterio 7
	if rules.has_door:
		var door_front_position: Vector2 = world_position + _direction_vector(direction) * cell_size
		var door_front_resolved := _resolve_cell_and_microcell(live_cells, macro_cell_pixels, cell_size, door_front_position)
		if door_front_resolved.is_empty():
			return false
		if not _is_position_clear(door_front_resolved["cell"], door_front_resolved["microcell"], current_absolute_day, macro_world, rules):
			return false

	# Criterio 8
	if _blocks_existing_building_door(
		resolved["cell"].macro_x, resolved["cell"].macro_y, resolved["microcell"], macro_world
	):
		return false

	return true


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
static func _is_position_clear(cell: LiveMacroCell, microcell: Vector2i, current_absolute_day: int, macro_world: World, rules: BuildingRules) -> bool:
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

	# Criterio 3
	if not rules.buildable_on_water and cell.macro_cell.terrain_base == GameTypes.TerrainBase.WATER:
		return false

	# Criterio 4
	if not rules.buildable_on_river and cell.river_positions.has(microcell):
		return false

	# Criterio 5
	if not rules.buildable_on_stone and cell.macro_state != null and cell.macro_state.stone_positions.has(microcell):
		return false

	# Criterio 6
	if macro_world != null:
		for building in macro_world.buildings:
			if (
				building.macro_x == cell.macro_x and building.macro_y == cell.macro_y
				and building.micro_x == microcell.x and building.micro_y == microcell.y
			):
				return false

	return true


# Criterio 8 (vedi commento in testa al file): true se un edificio esistente ha la porta rivolta
# esattamente su (target_macro_x, target_macro_y, target_microcell).
static func _blocks_existing_building_door(
	target_macro_x: int, target_macro_y: int, target_microcell: Vector2i, macro_world: World
) -> bool:
	if macro_world == null:
		return false
	for building in macro_world.buildings:
		var door := _door_target_macro_micro(building.macro_x, building.macro_y, building.micro_x, building.micro_y, building.rotation)
		if door["macro"] == Vector2i(target_macro_x, target_macro_y) and door["micro"] == target_microcell:
			return true
	return false


# Microcella (macro+micro) verso cui punta la porta di un edificio in (macro_x, macro_y, micro_x,
# micro_y) con orientamento `direction` — stesso attraversamento di bordo di macrocella del
# Criterio 7, qui in coordinate intere invece che in pixel (nessuna cella viva necessaria: pura
# aritmetica su World.WIDTH/HEIGHT).
static func _door_target_macro_micro(macro_x: int, macro_y: int, micro_x: int, micro_y: int, direction: GameTypes.Direction) -> Dictionary:
	var dir_vector := _direction_vector(direction)
	var target_micro_x: int = micro_x + int(dir_vector.x)
	var target_micro_y: int = micro_y + int(dir_vector.y)
	var target_macro_x: int = macro_x
	var target_macro_y: int = macro_y
	if target_micro_x < 0:
		target_macro_x -= 1
		target_micro_x = World.WIDTH - 1
	elif target_micro_x >= World.WIDTH:
		target_macro_x += 1
		target_micro_x = 0
	if target_micro_y < 0:
		target_macro_y -= 1
		target_micro_y = World.HEIGHT - 1
	elif target_micro_y >= World.HEIGHT:
		target_macro_y += 1
		target_micro_y = 0
	return {"macro": Vector2i(target_macro_x, target_macro_y), "micro": Vector2i(target_micro_x, target_micro_y)}


# Vettore unitario (in microcelle) della direzione indicata — stessa funzione (duplicata apposta,
# stesso principio già in uso tra MicroCellRenderer/BuildingGhost per la geometria della porta)
# di MicroCellRenderer._direction_vector/BuildingGhost._direction_vector.
static func _direction_vector(direction: GameTypes.Direction) -> Vector2:
	match direction:
		GameTypes.Direction.NORTH:
			return Vector2(0, -1)
		GameTypes.Direction.EAST:
			return Vector2(1, 0)
		GameTypes.Direction.WEST:
			return Vector2(-1, 0)
		_: # SOUTH, anche default
			return Vector2(0, 1)


# Applica il feedback visivo di edificabilità a un BuildingGhost — un solo punto che decide "come
# mostrare" true/false (rosso/verde, vedi BuildingGhost.is_buildable), cosicché il futuro sistema
# più accurato (edifici esistenti/altri ostacoli) debba solo estendere is_position_buildable
# sopra, mai duplicare la parte visiva.
static func set_buildable_appearance(ghost: BuildingGhost, is_buildable: bool) -> void:
	ghost.is_buildable = is_buildable
