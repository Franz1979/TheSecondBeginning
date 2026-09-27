class_name VisitorService
extends RefCounted

# Gruppi di visitatori (2026-09-27, richiesta utente — infrastruttura dei visitatori). Stateless, funzioni
# statiche, stesso pattern degli altri *Service. Il dato vive in VisitorParty (GameData.visitor_parties);
# GameScene fa avanzare i gruppi ogni frame con advance(), li disegna (VisitorPartyView) e ne applica gli
# esiti (accoglienza con materialize_members, rifiuto con dismiss).
#
# Ciclo di un gruppo:
#   ARRIVING           entra da una microcella di bordo non d'acqua (find_border_point) e cammina in linea
#                      retta verso l'edificio is_village_center; a ARRIVAL_RADIUS si ferma.
#   AWAITING_DECISION  fermo: attende l'esito (oggi: comandi di debug).
#   LEAVING            dopo il rifiuto cammina verso il bordo più vicino e, arrivato, sparisce.
# Nessun contatto con i servizi del villaggio: niente stamina, cibo, terreno, statistiche o selezione.

# Velocità in microcelle per giorno di gioco: la stessa di HumanIndividual.move_speed (default), così il
# gruppo cammina al passo dei pipottini.
const MOVE_SPEED: float = 10.0
# Distanza dal centro del villaggio a cui il gruppo si ferma (microcelle): non finisce sopra l'edificio.
const ARRIVAL_RADIUS: float = 3.0
# Scarto tra i membri nella formazione (microcelle): di lato tra i due di una fila, all'indietro tra le file.
const FORMATION_SIDE_SPACING: float = 0.5
const FORMATION_ROW_SPACING: float = 0.55
const FORMATION_ROW_SIZE: int = 2
# Distanza dal bordo del punto d'ingresso/uscita (centro della microcella di bordo).
const BORDER_INSET: float = 0.5
# Regole per tipo di gruppo (VisitorPartyRules): {PARTY_RULES_DIR}{tipo}_party.tres.
const PARTY_RULES_DIR := "res://gameplay/visitors/data/"
# Tolleranza sul floor(capacità / spazio per unità) della dote, come FoodSelectionService.UNIT_FIT_EPSILON.
const DOWRY_UNIT_FIT_EPSILON: float = 0.000001

static var _party_rules_cache: Dictionary = {}


# Regole del tipo di gruppo, caricate per convenzione dal nome dell'enum (es. MIGRANTS -> migrants_party.tres).
# null se il tipo non ha un .tres (nessuna dote). Una sola lettura per tipo per sessione.
static func get_party_rules(party_type: VisitorTypes.PartyType) -> VisitorPartyRules:
	if _party_rules_cache.has(party_type):
		return _party_rules_cache[party_type]
	var path := PARTY_RULES_DIR + String(VisitorTypes.PartyType.keys()[party_type]).to_lower() + "_party.tres"
	var rules: VisitorPartyRules = load(path) as VisitorPartyRules if ResourceLoader.exists(path) else null
	_party_rules_cache[party_type] = rules
	return rules


# Dote del membro `member_index` accolto come `individual` (capacità di trasporto già calcolata): {"resource_name",
# "quantity"}, quantity 0 se il tipo di gruppo non ha dote o il ruolo del membro non la porta. Quantità = unità
# intere che stanno in dowry_carry_fill_ratio x max_carry_capacity.
static func get_member_dowry(party: VisitorParty, member_index: int, individual: HumanIndividual) -> Dictionary:
	var none := {"resource_name": "", "quantity": 0}
	var rules := get_party_rules(party.party_type)
	if rules == null or rules.dowry_resource_name == "" or member_index < 0 or member_index >= party.members.size():
		return none
	if not rules.dowry_member_roles.has(int(party.members[member_index].get("role", -1))):
		return none
	var resource_rules := CaloricCalculator.get_caloric_source_rules(rules.dowry_resource_name)
	if resource_rules == null or resource_rules.space_per_unit <= 0.0:
		return none
	var space: float = individual.max_carry_capacity * rules.dowry_carry_fill_ratio
	var quantity: int = int(floor(space / resource_rules.space_per_unit + DOWRY_UNIT_FIT_EPSILON))
	return {"resource_name": rules.dowry_resource_name, "quantity": maxi(quantity, 0)}


# Edificio centro del villaggio: completo, non demolito, rules.is_village_center. null se non esiste.
static func find_village_center(world: World) -> Building:
	if world == null:
		return null
	for building in world.buildings:
		if building.is_complete and not building.is_demolished and building.rules != null and building.rules.is_village_center:
			return building
	return null


# Punto di destinazione del centro del villaggio: il centro della sua microcella.
static func get_building_point(building: Building) -> Vector2:
	return Vector2(float(building.micro_x) + 0.5, float(building.micro_y) + 0.5)


# Microcella di bordo della macrocella `macro_coords` più vicina a `from_point`, non d'acqua. I quattro lati
# sono provati dal più vicino; su ciascun lato si parte dalla microcella allineata a `from_point` e ci si
# allarga alternando i due versi. Ritorna il centro della microcella scelta, o null se tutta la cornice è
# acqua (o la cella non esiste).
#
# Pathfinding (2026-09-27, step 5): con `reach_from` (microcella del villaggio da cui il punto deve essere raggiungibile)
# e la griglia della cella disponibile, il punto deve anche essere su una microcella LIBERA e RAGGIUNGIBILE
# (PathfindingService.is_blocked / is_reachable). Se nessun punto del bordo lo è, si ripiega sulla scelta di sempre
# (solo non acqua) con un log [VISITOR].
static func find_border_point(world: World, macro_coords: Vector2i, from_point: Vector2, reach_from: Variant = null) -> Variant:
	if world == null:
		return null
	var cell: MacroCellData = world.get_cell_at(macro_coords.x, macro_coords.y)
	if cell == null:
		return null
	var water: Variant = RiverMicrocellService.get_water_microcells(world, cell)
	if water == null:
		return null
	var live_cell := PathfindingService.get_live_cell(macro_coords)
	if reach_from != null and live_cell != null and live_cell.path_grid != null:
		var from_cell: Vector2i = reach_from
		var strict: Variant = _scan_border(from_point, func(microcell: Vector2i) -> bool:
			return not (water as Dictionary).has(microcell) and not PathfindingService.is_blocked(live_cell, microcell) 				and PathfindingService.is_reachable(live_cell, from_cell, microcell)
		)
		if strict != null:
			return strict
		if DebugLogging.ENABLED:
			print("[VISITOR] Nessun punto del bordo di %s libero e raggiungibile da %s: si usa il primo punto non d'acqua." % [
				macro_coords, from_cell
			])
	return _scan_border(from_point, func(microcell: Vector2i) -> bool: return not (water as Dictionary).has(microcell))


# Scansione della cornice (vedi find_border_point): primo punto per cui `accept` (Callable(Vector2i) -> bool) è vero,
# lati dal più vicino a `from_point`, su ciascun lato a partire dalla microcella allineata. Centro della microcella o null.
static func _scan_border(from_point: Vector2, accept: Callable) -> Variant:
	var width := World.WIDTH
	var height := World.HEIGHT
	# [distanza dal lato, lato] — 0 ovest, 1 est, 2 nord, 3 sud.
	var sides: Array = [
		[from_point.x, 0], [float(width) - from_point.x, 1], [from_point.y, 2], [float(height) - from_point.y, 3],
	]
	sides.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for side_entry in sides:
		var side: int = side_entry[1]
		var vertical_side := side <= 1
		var length := height if vertical_side else width
		var aligned: int = clampi(int(from_point.y if vertical_side else from_point.x), 0, length - 1)
		for step in range(length * 2):
			var delta: int = (step + 1) / 2 * (1 if step % 2 == 1 else -1)
			var along: int = aligned + delta
			if along < 0 or along >= length:
				continue
			var microcell: Vector2i
			match side:
				0: microcell = Vector2i(0, along)
				1: microcell = Vector2i(width - 1, along)
				2: microcell = Vector2i(along, 0)
				_: microcell = Vector2i(along, height - 1)
			if accept.call(microcell):
				return Vector2(microcell) + Vector2(BORDER_INSET, BORDER_INSET)
	return null


# Nuovo gruppo di tipo `party_type` con i membri `members` (vedi VisitorParty.members; es. build_family_members),
# che entra dal bordo della macrocella di `center_building` più vicino al centro del villaggio e ci cammina.
# Aggiunto a game_data.visitor_parties. null (nessuna aggiunta) se non c'è un punto d'ingresso valido o i membri
# sono vuoti. Il posto di ciascuno nella formazione è assegnato qui.
static func spawn_party(
	game_data: GameData, world: World, center_building: Building, party_type: VisitorTypes.PartyType, members: Array[Dictionary]
) -> VisitorParty:
	if members.is_empty():
		return null
	var macro_coords := Vector2i(center_building.macro_x, center_building.macro_y)
	var center_point := get_building_point(center_building)
	# Ingresso raggiungibile dal centro del villaggio (2026-09-27, pathfinding step 5).
	var entry: Variant = find_border_point(world, macro_coords, center_point, Vector2i(center_building.micro_x, center_building.micro_y))
	if entry == null:
		return null
	var party := VisitorParty.new()
	party.id = game_data.allocate_visitor_party_id()
	party.party_type = party_type
	party.phase = VisitorTypes.Phase.ARRIVING
	party.macro_coords = macro_coords
	party.entry_point = entry
	party.exit_point = entry
	party.position = entry
	party.target_point = center_point
	var heading: Vector2 = center_point - party.position
	party.facing_direction = heading.normalized() if heading.length() > 0.0 else Vector2.RIGHT
	party.members = members
	for i in range(party.members.size()):
		party.members[i]["offset"] = _formation_offset(i, party.members.size())
	game_data.visitor_parties.append(party)
	return party


# Famiglia: padre (indice 0), madre (indice 1), poi i figli nell'ordine di `children`, ciascuno
# {"age": int, "sex": HumanTypes.Sex}. Tratti d'aspetto degli adulti a caso, dei figli ereditati (40/40/20,
# stesse probabilità di HumanIndividual.roll_inherited_*). Il posto nella formazione lo assegna spawn_party.
static func build_family_members(father_age: int, mother_age: int, children: Array[Dictionary]) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	members.append(_build_adult_member(HumanTypes.Sex.MALE, father_age, 1))
	members.append(_build_adult_member(HumanTypes.Sex.FEMALE, mother_age, 0))
	var father := members[0]
	var mother := members[1]
	for child in children:
		members.append({
			"sex": child.get("sex", HumanTypes.Sex.MALE),
			"age": int(child.get("age", 0)),
			"role": VisitorTypes.MemberRole.CHILD,
			"hair_color": _roll_inherited_trait(mother["hair_color"], father["hair_color"], HumanTypes.HairColor.values()),
			"skin_color": _roll_inherited_trait(mother["skin_color"], father["skin_color"], HumanTypes.SkinColor.values()),
			"clothing_color": _random_value(HumanTypes.ClothingColor.values()),
			"partner_index": -1,
			"mother_index": 1,
			"father_index": 0,
		})
	return members


static func _build_adult_member(sex: HumanTypes.Sex, age: int, partner_index: int) -> Dictionary:
	return {
		"sex": sex,
		"age": age,
		"role": VisitorTypes.MemberRole.ADULT,
		"hair_color": _random_value(HumanTypes.HairColor.values()),
		"skin_color": _random_value(HumanTypes.SkinColor.values()),
		"clothing_color": _random_value(HumanTypes.ClothingColor.values()),
		"partner_index": partner_index,
		"mother_index": -1,
		"father_index": -1,
	}


static func _random_value(pool: Array) -> int:
	return pool[randi() % pool.size()]


static func _roll_inherited_trait(mother_value: int, father_value: int, pool: Array) -> int:
	var roll := randf()
	if roll < HumanIndividual.HAIR_INHERITANCE_MOTHER_CHANCE:
		return mother_value
	if roll < HumanIndividual.HAIR_INHERITANCE_MOTHER_CHANCE + HumanIndividual.HAIR_INHERITANCE_FATHER_CHANCE:
		return father_value
	return _random_value(pool)


# Posto nella formazione (x in avanti, y di lato, nel riferimento della direzione di marcia): file da
# FORMATION_ROW_SIZE, la prima davanti, ogni fila centrata sul proprio numero di membri.
static func _formation_offset(index: int, count: int) -> Vector2:
	var row: int = index / FORMATION_ROW_SIZE
	var col: int = index % FORMATION_ROW_SIZE
	var row_count: int = mini(FORMATION_ROW_SIZE, count - row * FORMATION_ROW_SIZE)
	var rows: int = ceili(float(count) / float(FORMATION_ROW_SIZE))
	var side := (float(col) - float(row_count - 1) / 2.0) * FORMATION_SIDE_SPACING
	var forward := (float(rows - 1) / 2.0 - float(row)) * FORMATION_ROW_SPACING
	return Vector2(forward, side)


# Posizione del membro `index`: posizione del gruppo più il suo offset ruotato secondo la direzione di marcia.
static func get_member_position(party: VisitorParty, index: int) -> Vector2:
	var offset: Vector2 = party.members[index].get("offset", Vector2.ZERO)
	return party.position + offset.rotated(party.facing_direction.angle())


static func is_moving(party: VisitorParty) -> bool:
	return party.phase != VisitorTypes.Phase.AWAITING_DECISION


# Avanza il gruppo di `game_delta` (frazione di giorno di gioco; 0 in pausa). true = il gruppo è uscito dalla
# mappa e va rimosso (solo in LEAVING).
#
# Pathfinding (2026-09-27, step 5): il punto centrale segue il percorso (_ensure_path) di punto in punto, alla stessa
# velocità; l'ultimo tratto va dritto verso target_point e si ferma a stop_distance come prima. Senza percorso (cella
# non viva, griglia assente, destinazione irraggiungibile) si va in linea retta come prima. I membri restano disposti
# attorno al punto centrale (get_member_position), senza evitare gli ostacoli.
static func advance(party: VisitorParty, game_delta: float) -> bool:
	if game_delta <= 0.0 or party.phase == VisitorTypes.Phase.AWAITING_DECISION:
		return false
	_ensure_path(party)
	var stop_distance := ARRIVAL_RADIUS if party.phase == VisitorTypes.Phase.ARRIVING else 0.0
	if party.position.distance_to(party.target_point) - stop_distance <= 0.0:
		return _on_target_reached(party)
	# Punti intermedi: si passa al successivo entro PathfindingService.WAYPOINT_REACH_DISTANCE (2026-09-27, lisciatura);
	# la destinazione finale resta esatta.
	while not party.path.is_empty() and party.position.distance_to(party.path[0]) <= PathfindingService.WAYPOINT_REACH_DISTANCE:
		party.path.pop_front()
	var following_waypoint := not party.path.is_empty()
	var goal: Vector2 = party.path[0] if following_waypoint else party.target_point
	var to_goal: Vector2 = goal - party.position
	var remaining := to_goal.length() - (0.0 if following_waypoint else stop_distance)
	if remaining <= 0.000001:
		if following_waypoint:
			party.path.pop_front()
			return false
		return _on_target_reached(party)
	var direction := to_goal / to_goal.length()
	party.facing_direction = direction
	var step := MOVE_SPEED * game_delta
	if step >= remaining:
		party.position += direction * remaining
		if following_waypoint:
			party.path.pop_front()
			return false
		return _on_target_reached(party)
	party.position += direction * step
	return false


# Calcola (o ricalcola) il percorso del punto centrale quando serve: prima volta, target_point cambiato (rifiuto, dopo
# un caricamento) o un blocco della macrocella cambiato (LiveMacroCell.path_block_version). Il calcolo è quello dei
# pipottini (PathfindingService.find_path: partenza e destinazione sempre attraversabili); waypoint = centri delle
# microcelle intermedie. Destinazione irraggiungibile: nessun percorso (linea retta) e un log [VISITOR], senza fermare
# il gruppo; si riprova solo al prossimo cambio di blocco.
static func _ensure_path(party: VisitorParty) -> void:
	var cell := PathfindingService.get_live_cell(party.macro_coords)
	var block_version: int = cell.path_block_version if cell != null else -1
	if party.path_planned and party.path_target == party.target_point and party.path_block_version == block_version:
		return
	party.path.clear()
	party.path_planned = true
	party.path_target = party.target_point
	party.path_block_version = block_version
	if cell == null or cell.path_grid == null:
		return
	var from := Vector2i(party.position.floor())
	var to := Vector2i(party.target_point.floor())
	if not PathfindingService._in_bounds(from) or not PathfindingService._in_bounds(to) or from == to:
		return
	var cells := PathfindingService.find_path(cell, from, to)
	if cells.is_empty():
		if DebugLogging.ENABLED:
			print("[VISITOR] Gruppo #%d: destinazione %s irraggiungibile da %s nella macrocella %s — si prosegue in linea retta." % [
				party.id, to, from, party.macro_coords
			])
		return
	for i in range(1, cells.size() - 1):
		party.path.append(Vector2(cells[i]) + Vector2(0.5, 0.5))


static func _on_target_reached(party: VisitorParty) -> bool:
	if party.phase == VisitorTypes.Phase.ARRIVING:
		party.phase = VisitorTypes.Phase.AWAITING_DECISION
		if DebugLogging.ENABLED:
			print("[VISITORS] Gruppo #%d arrivato al centro del villaggio: in attesa di decisione." % party.id)
		return false
	if DebugLogging.ENABLED:
		print("[VISITORS] Gruppo #%d uscito dalla macrocella %s." % [party.id, str(party.macro_coords)])
	return true


# Rifiuto: il gruppo si gira verso il bordo più vicino e se ne va. Solo in AWAITING_DECISION; false se non
# applicabile. Senza un bordo valido (non dovrebbe accadere: il gruppo è entrato da lì) riusa l'ingresso.
static func dismiss(party: VisitorParty, world: World) -> bool:
	if party.phase != VisitorTypes.Phase.AWAITING_DECISION:
		return false
	# Uscita raggiungibile da dove il gruppo si trova (2026-09-27, pathfinding step 5).
	var exit: Variant = find_border_point(world, party.macro_coords, party.position, Vector2i(party.position.floor()))
	party.exit_point = exit if exit != null else party.entry_point
	party.target_point = party.exit_point
	party.phase = VisitorTypes.Phase.LEAVING
	return true


# Accoglienza: crea gli HumanIndividual veri dei membri (id nuovi, anno di nascita dall'età fissa, nome non
# già in uso, tratti d'aspetto della descrizione, skill iniziali, relazioni dagli indici), nella posizione
# attuale di ciascun membro. NON li aggiunge a nulla: vitali, gruppo, viste e casa sono del chiamante
# (GameScene._welcome_visitor_party). Un INFANT viene affidato alla madre (dependent_child_id), come nel
# seeding iniziale.
static func materialize_members(
	party: VisitorParty, game_data: GameData, group: HumanPopulationGroup, used_names: Array[String]
) -> Array[HumanIndividual]:
	var created: Array[HumanIndividual] = []
	for i in range(party.members.size()):
		var member: Dictionary = party.members[i]
		var individual := HumanIndividual.new()
		individual.id = game_data.allocate_human_id()
		individual.sex = member.get("sex", HumanTypes.Sex.MALE)
		individual.birth_year_virtual = game_data.year - int(member.get("age", 0))
		individual.assign_random_name(used_names)
		used_names.append(individual.name)
		individual.hair_color = member.get("hair_color", HumanTypes.HairColor.BROWN)
		individual.skin_color = member.get("skin_color", HumanTypes.SkinColor.LIGHT)
		individual.clothing_color = member.get("clothing_color", HumanTypes.ClothingColor.TAN)
		HumanSeedingService.seed_random_skills(individual)
		individual.source_group_ref = group
		individual.home_macro_coords = party.macro_coords
		individual.position = get_member_position(party, i)
		individual.target_position = individual.position
		individual.facing_direction = party.facing_direction
		created.append(individual)
	for i in range(created.size()):
		var member: Dictionary = party.members[i]
		var partner_index: int = int(member.get("partner_index", -1))
		var mother_index: int = int(member.get("mother_index", -1))
		var father_index: int = int(member.get("father_index", -1))
		if partner_index >= 0 and partner_index < created.size():
			created[i].partner_id = created[partner_index].id
		if mother_index >= 0 and mother_index < created.size():
			created[i].mother_id = created[mother_index].id
		if father_index >= 0 and father_index < created.size():
			created[i].father_id = created[father_index].id
	for i in range(created.size()):
		var child := created[i]
		var mother_index: int = int(party.members[i].get("mother_index", -1))
		if mother_index < 0 or mother_index >= created.size():
			continue
		var age_band := HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			child.sex, float(game_data.year - child.birth_year_virtual)
		)
		if age_band == HumanTypes.AgeBand.INFANT and created[mother_index].dependent_child_id == -1:
			created[mother_index].dependent_child_id = child.id
	return created
