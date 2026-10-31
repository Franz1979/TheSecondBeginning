class_name WildAnimalVisitService
extends RefCounted

# Visite dei gruppi di animali selvatici al villaggio (2026-10-28, richiesta utente — lupi passo L1). Stateless, come
# VisitorService, di cui riusa ingresso/uscita dal bordo (find_border_point) e lo schema di movimento. Per ora la visita
# parte solo a comando (debug); a fine sosta dà punti addomesticazione e calma (apply_visit_outcome, L3). Niente
# attacchi né visite spontanee (passi L2, L4-L5).
#
# Ciclo:
#   ARRIVING  entra dal bordo più vicino alla meta e ci cammina: la Fossa più piena della macrocella del villaggio, o
#             un punto appena fuori dagli edifici del villaggio se non c'è una Fossa.
#   STAYING   per una durata a caso ognuno va ad annusare punti attorno alla meta, fermandosi rivolto alla Fossa (o al
#             centro del villaggio).
#   LEAVING   torna al bordo più vicino e sparisce.

# Chi viene: ogni animale con questa probabilità (cuccioli compresi), almeno MIN_PARTICIPANTS, sempre un riproduttore.
const PARTICIPATION_CHANCE: float = 0.7
const MIN_PARTICIPANTS: int = 2
# Sosta in giorni di gioco (2026-10-29: 1-2 giorni, 8-16 secondi a 1x; con 0.25-0.5 ripartivano quasi subito).
const STAY_DAYS_MIN: float = 1.0
const STAY_DAYS_MAX: float = 2.0
# Distanza dalla Fossa a cui il gruppo si ferma (microcelle).
const PIT_ARRIVAL_RADIUS: float = 2.0
# Punto ai margini: distanza oltre l'edificio del villaggio più lontano dal centro (microcelle).
const VILLAGE_EDGE_DISTANCE: float = 6.0
const VILLAGE_EDGE_ATTEMPTS: int = 8
const BORDER_MARGIN: float = 3.0
# Disposizione sciolta attorno al centro del gruppo (microcelle).
const CLUSTER_RADIUS: float = 1.4
const CLUSTER_MIN_SPACING: float = 0.6
const CLUSTER_PLACEMENT_ATTEMPTS: int = 12
# Reazioni agli edifici in sosta (2026-10-29): richiamo di un edificio che attira, costante entro il suo raggio (una
# spinta che cresce avvicinandosi risucchierebbe l'animale dentro l'edificio) e nullo entro ATTRACTION_STOP_DISTANCE
# microcelle, dove l'animale ci gironzola attorno. Più debole della repulsione a contatto, così il fuoco vince da vicino.
const ATTRACTION_WEIGHT: float = 0.5
const ATTRACTION_STOP_DISTANCE: float = 2.0
# Sosta (2026-10-30, richiesta utente: "annusare" la Fossa invece di girare a caso): ognuno sceglie un punto su un
# anello attorno alla meta (microcelle), ci va a balzi e lì si ferma rivolto alla meta, poi un altro punto. Il punto è
# il meno spinto dagli edifici che respingono tra SNIFF_POINT_ATTEMPTS tentati su microcelle libere.
const SNIFF_RING_MIN: float = 1.5
const SNIFF_RING_MAX: float = 3.5
const SNIFF_POINT_ATTEMPTS: int = 6
const SNIFF_REACH_DISTANCE: float = 0.3
# Scarto casuale della direzione a ogni balzo verso il punto (radianti), per non andare dritti come su un binario.
const SNIFF_HEADING_JITTER: float = 0.4
# Esito di una visita tranquilla (lupi L3, 2026-10-30, richiesta utente): punti addomesticazione per animale presente —
# pieni se la meta è una Fossa piena almeno PIT_FULL_RATIO, metà con una Fossa meno piena o senza Fossa (una sola Fossa
# conta, quella della visita) — e calo dell'aggressività di ogni presente.
const PIT_FULL_RATIO: float = 0.5
const POINTS_PER_ANIMAL_FULL_PIT: float = 1.0
const POINTS_PER_ANIMAL_OTHERWISE: float = 0.5
const AGGRESSION_DROP_PER_VISIT: float = 1.0
# Giovani (cuccioli compresi, fascia YOUNG) prendono questa quota dei punti di un adulto (2026-10-30, richiesta utente).
const YOUNG_POINTS_SHARE: float = 0.5
# Attacco (lupi L4, 2026-10-30, richiesta utente): una persona, chiunque, entrata nel raggio in cui un presente nota le
# persone (da MIN_NOTICE_RADIUS ad aggressività 0 a MAX_NOTICE_RADIUS a 100, microcelle) mentre il branco è in sosta alla
# meta viene tirata una volta sola per visita, con probabilità MAX_ATTACK_CHANCE × aggressività/100 del più aggressivo dei
# presenti (0 = non attacca mai). Riuscito: la persona scappa (L5a, DangerFleeService col profilo DANGER_PROFILE) e tutto
# il branco la insegue a balzi con pause (L5b, 2026-10-30, richiesta utente). Al contatto (ATTACK_CONTACT_DISTANCE) la
# morde (BITE_CONDITION_ID, si sommano) con log e notifica, poi il branco resta fermo BITE_PAUSE_DAYS e riparte.
# L'inseguimento finisce quando la persona è al riparo, sparisce o muore, dopo MAX_BITES_PER_CHARGE morsi o
# MAX_CHARGE_DAYS; poi il branco se ne va. In ogni caso la visita è "con attacco".
const DANGER_PROFILE: String = "predator"
const BITE_CONDITION_ID: String = "bite"
# Pausa dopo un morso (giorni: 2 ore), in cui chi scappa guadagna strada.
const BITE_PAUSE_DAYS: float = 2.0 / 24.0
# Tetto dei morsi in una carica: chi non ha un riparo e aspetta allo scoperto non viene morso fino alla morte.
const MAX_BITES_PER_CHARGE: int = 3
# Scacciati in gruppo (L6.1, 2026-10-30, richiesta utente): all'inizio della carica gli adulti vicini corrono contro il
# branco (DangerFleeService.start_drive_off, regole nel profilo DANGER_PROFILE); appena ne sono arrivati quanti servono
# (finita la loro corsa, o entro DRIVE_OFF_GIVE_UP_DISTANCE microcelle da un presente) il branco rinuncia e se ne va di
# corsa. Niente punti né calma (visita con attacco), aggressività invariata: il branco annota la cacciata
# (WildAnimalGroup.driven_off_count/last_driven_off_day), che le visite spontanee (L2) useranno.
const DRIVE_OFF_GIVE_UP_DISTANCE: float = 3.0
const MIN_NOTICE_RADIUS: float = 3.0
const MAX_NOTICE_RADIUS: float = 6.0
const MAX_ATTACK_CHANCE: float = 0.5
# Zona sicura attorno agli edifici che la specie teme (il focolare, 2026-10-30, richiesta utente), microcelle: più
# stretta della repulsione in sosta (building_reactions, 15 per il lupo coprirebbe mezzo villaggio).
const FEAR_SAFE_RADIUS: float = 3.0
# Contatto a 1 microcella: chi lavora a un cantiere sta su una microcella bloccata e il lupo arriva solo a quella accanto.
const ATTACK_CONTACT_DISTANCE: float = 1.0
const MAX_CHARGE_DAYS: float = 1.0
# Via libera (2026-10-30, richiesta utente): si carica solo chi è raggiungibile in linea retta — passo di controllo sulla
# linea lupo-persona (microcelle); una microcella bloccata in mezzo (palizzata, edifici, rocce) la protegge. Quella
# della persona non conta (un cantiere blocca, ma non ripara): ripara solo stare in un edificio completato (shelter_rects).
const ATTACK_LINE_STEP: float = 0.5
# Riparo (2026-10-30, richiesta utente): chi sta in un edificio completato (chi produce, il Warehouse Manager, chi riposa
# in casa) non si attacca; chi è in giro, a caccia, a raccogliere o a un cantiere sì. "Nell'edificio" = sulla sua pianta,
# senza margine (chi passa accanto non è protetto): chi produce e chi riposa in casa sta nella microcella dell'edificio
# (ProduceAction.get_required_position, NeedTaskAssignmentService.resolve_rest_target). Non riparano gli edifici
# calpestabili (sentieri) e quelli che attirano la specie (AnimalRules.building_reactions negativo: la Fossa, i
# magazzini), altrimenti chi va alla Fossa sarebbe sempre al sicuro.
# Velocità di riserva se la specie non ha AnimalRules (microcelle/giorno).
const DEFAULT_MOVE_SPEED: float = 24.0
# In viaggio, velocità con cui ognuno torna al suo posto nella formazione (frazione della velocità di marcia).
const FORMATION_RETURN_RATE: float = 0.5
# Scia del centro in viaggio (2026-10-30, richiesta utente: in arrivo passavano sopra la palizzata): un punto ogni
# TRAIL_SPACING microcelle, gli ultimi TRAIL_MAX_POINTS (12 microcelle di strada).
const TRAIL_SPACING: float = 0.5
const TRAIL_MAX_POINTS: int = 24


static func find_visit(game_data: GameData, group_id: int) -> WildAnimalVisit:
	for visit in game_data.wild_animal_visits:
		if visit.group_id == group_id:
			return visit
	return null


# Fa partire una visita del gruppo. null (e un log) se il gruppo è già in visita, non c'è un magazzino o un
# ingresso dal bordo.
static func start_visit(game_data: GameData, world: World, group: WildAnimalGroup) -> WildAnimalVisit:
	if group == null or group.animals.is_empty():
		return null
	if find_visit(game_data, group.id) != null:
		print("[WILD ANIMAL VISITS] %s: già in visita" % group.species)
		return null
	# Basta un magazzino (2026-10-28, richiesta utente): la visita si orienta su di lui, non sul centro del villaggio.
	var center := WildAnimalGroupService.find_anchor_storage(world)
	if center == null:
		print("[WILD ANIMAL VISITS] %s: nessun magazzino" % group.species)
		return null
	var visit := WildAnimalVisit.new()
	visit.group_id = group.id
	visit.species = group.species
	visit.macro_coords = Vector2i(center.macro_x, center.macro_y)
	var center_point := VisitorService.get_building_point(center)
	var pit := _find_fullest_pit(world, visit.macro_coords)
	if pit != null:
		visit.target_kind = WildAnimalVisit.TargetKind.PIT
		visit.pit_building_id = pit.id
		visit.target_point = VisitorService.get_building_point(pit)
	else:
		visit.target_kind = WildAnimalVisit.TargetKind.VILLAGE_EDGE
		visit.target_point = _find_village_edge_point(world, visit.macro_coords, center_point)
	visit.look_point = visit.target_point if pit != null else center_point
	var entry: Variant = VisitorService.find_border_point(world, visit.macro_coords, visit.target_point,
		Vector2i(visit.target_point.floor()))
	if entry == null:
		print("[WILD ANIMAL VISITS] %s: nessun ingresso dal bordo di %s" % [group.species, visit.macro_coords])
		return null
	visit.entry_point = entry
	visit.position = entry
	var heading: Vector2 = visit.target_point - visit.position
	visit.facing_direction = heading.normalized() if heading.length() > 0.0 else Vector2.RIGHT
	visit.animal_ids = _pick_participants(group)
	visit.offsets = _cluster_offsets(visit.animal_ids.size())
	visit.home_offsets = visit.offsets.duplicate()
	visit.blocked_test = PathfindingService.blocked_test_for(visit.macro_coords)
	var wild_rules := _wild_rules(group.species)
	for i in range(visit.animal_ids.size()):
		visit.headings.append(visit.facing_direction.angle())
		visit.moving.append(false)
		visit.phase_timers.append(0.0)
		# Balzi sfasati fin dall'ingresso, così non pulsano tutti insieme.
		visit.hopping.append(randf() < 0.5)
		visit.hop_timers.append(randf_range(0.0, wild_rules.hop_duration_max) if wild_rules != null else 0.0)
		visit.sniff_points.append(Vector2.ZERO)
		var animal := group.find_animal(visit.animal_ids[i])
		var aggression_share := clampf(animal.aggression, 0.0, 100.0) / 100.0 if animal != null else 0.0
		visit.notice_radii.append(lerpf(MIN_NOTICE_RADIUS, MAX_NOTICE_RADIUS, aggression_share))
		visit.attack_chance = maxf(visit.attack_chance, MAX_ATTACK_CHANCE * aggression_share)
	game_data.wild_animal_visits.append(visit)
	print("[WILD ANIMAL VISITS] %s: arrivano %d animali %s, meta %s" % [
		group.species, visit.animal_ids.size(), visit.animal_ids,
		"fossa #%d" % pit.id if pit != null else "margini del villaggio"])
	return visit


# Fossa che riceve rifiuti nella macrocella, la più piena (WasteDisposalService.get_pit_fill); null se nessuna.
static func _find_fullest_pit(world: World, macro_coords: Vector2i) -> Building:
	var best: Building = null
	for building in world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		if not WasteDisposalService.is_waste_pit(building):
			continue
		if best == null or WasteDisposalService.get_pit_fill(building) > WasteDisposalService.get_pit_fill(best):
			best = building
	return best


# Punto appena fuori dal villaggio: in una direzione a caso, VILLAGE_EDGE_DISTANCE oltre l'edificio più lontano dal
# centro, dentro la cella e su una microcella libera (se la cella è viva); dopo VILLAGE_EDGE_ATTEMPTS l'ultimo provato.
static func _find_village_edge_point(world: World, macro_coords: Vector2i, center_point: Vector2) -> Vector2:
	var reach := 0.0
	for building in world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y or building.is_demolished:
			continue
		reach = maxf(reach, VisitorService.get_building_point(building).distance_to(center_point))
	var live_cell := PathfindingService.get_live_cell(macro_coords)
	var point := center_point
	for attempt in range(VILLAGE_EDGE_ATTEMPTS):
		var direction := Vector2.RIGHT.rotated(randf() * TAU)
		point = center_point + direction * (reach + VILLAGE_EDGE_DISTANCE)
		point.x = clampf(point.x, BORDER_MARGIN, float(World.WIDTH) - BORDER_MARGIN)
		point.y = clampf(point.y, BORDER_MARGIN, float(World.HEIGHT) - BORDER_MARGIN)
		if live_cell == null or live_cell.path_grid == null or not PathfindingService.is_blocked(live_cell, Vector2i(point.floor())):
			break
	return point


# Ogni animale al PARTICIPATION_CHANCE; poi almeno MIN_PARTICIPANTS (o tutti, se sono meno) e almeno un riproduttore.
static func _pick_participants(group: WildAnimalGroup) -> Array[int]:
	var chosen: Array[int] = []
	var left_out: Array[int] = []
	for animal in group.animals:
		if randf() < PARTICIPATION_CHANCE:
			chosen.append(animal.id)
		else:
			left_out.append(animal.id)
	left_out.shuffle()
	while chosen.size() < MIN_PARTICIPANTS and not left_out.is_empty():
		chosen.append(left_out.pop_back())
	if not chosen.has(group.breeding_male_id) and not chosen.has(group.breeding_female_id):
		for breeder_id in [group.breeding_male_id, group.breeding_female_id]:
			if group.find_animal(breeder_id) != null:
				chosen.append(breeder_id)
				break
	return chosen


# Posti sciolti attorno al centro, a distanza minima tra loro quando possibile.
static func _cluster_offsets(count: int) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	for i in range(count):
		var candidate := Vector2.ZERO
		for attempt in range(CLUSTER_PLACEMENT_ATTEMPTS):
			candidate = Vector2.RIGHT.rotated(randf() * TAU) * sqrt(randf()) * CLUSTER_RADIUS
			if offsets.all(func(other: Vector2) -> bool: return other.distance_to(candidate) >= CLUSTER_MIN_SPACING):
				break
		offsets.append(candidate)
	return offsets


static func get_animal_position(visit: WildAnimalVisit, index: int) -> Vector2:
	return visit.position + visit.offsets[index].rotated(visit.facing_direction.angle())


# Direzione disegnata dell'animale (angolo nel mondo): la sua durante la sosta, quella del gruppo in viaggio.
static func get_animal_heading(visit: WildAnimalVisit, index: int) -> float:
	if (visit.phase == WildAnimalVisit.Phase.STAYING or visit.phase == WildAnimalVisit.Phase.CHARGING) \
			and index < visit.headings.size():
		return visit.headings[index]
	return visit.facing_direction.angle()


# Fa avanzare tutte le visite di `game_delta` (frazione di giorno; 0 in pausa) e toglie quelle uscite dalla mappa.
# Chiamato a ogni fotogramma da GameSimulation.tick_frame; folk ed effects servono all'esito di fine sosta, individuals
# all'attacco.
static func advance_all(game_data: GameData, world: World, game_delta: float, folk: Folk,
		individuals: Array[HumanIndividual], effects: GameEffects) -> void:
	if game_data == null or game_data.wild_animal_visits.is_empty() or game_delta <= 0.0:
		return
	var departed: Array[WildAnimalVisit] = []
	for visit in game_data.wild_animal_visits:
		if visit.needs_restore and not _restore_after_load(visit, game_data, world):
			departed.append(visit)
			continue
		if advance(visit, world, game_delta, game_data, folk, individuals, effects):
			departed.append(visit)
	for visit in departed:
		game_data.wild_animal_visits.erase(visit)


# Visita appena caricata (2026-10-30, WildAnimalVisit.to_save_data): toglie gli animali non più nel branco, rimette la
# collisione, fa ripianificare il percorso e, in sosta o in carica, raccoglie di nuovo gli edifici come all'arrivo.
# false = non resta nessuno (o il branco non c'è più): la visita va tolta.
static func _restore_after_load(visit: WildAnimalVisit, game_data: GameData, world: World) -> bool:
	visit.needs_restore = false
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return false
	for i in range(visit.animal_ids.size() - 1, -1, -1):
		if group.find_animal(visit.animal_ids[i]) != null:
			continue
		for per_animal: Array in [visit.animal_ids, visit.offsets, visit.home_offsets, visit.headings, visit.moving,
				visit.phase_timers, visit.hopping, visit.hop_timers, visit.sniff_points, visit.notice_radii]:
			if i < per_animal.size():
				per_animal.remove_at(i)
	if visit.animal_ids.is_empty():
		return false
	visit.blocked_test = PathfindingService.blocked_test_for(visit.macro_coords)
	visit.path.clear()
	visit.path_planned = false
	visit.trail.clear()
	if visit.phase == WildAnimalVisit.Phase.STAYING or visit.phase == WildAnimalVisit.Phase.CHARGING:
		_collect_reaction_sources(visit, world, _wild_rules(visit.species))
	print("[WILD ANIMAL VISITS] %s: visita ripresa dal salvataggio (fase %d, %d animali)" % [
		visit.species, visit.phase, visit.animal_ids.size()])
	return true


# true = la visita è uscita dalla mappa e va tolta.
static func advance(visit: WildAnimalVisit, world: World, game_delta: float, game_data: GameData, folk: Folk,
		individuals: Array[HumanIndividual], effects: GameEffects) -> bool:
	var wild_rules := _wild_rules(visit.species)
	# Solo in sosta (2026-10-30, richiesta utente): in arrivo la carica partiva lontano dalla meta e si fermava contro la
	# palizzata.
	if visit.phase == WildAnimalVisit.Phase.STAYING:
		var target := _find_attack_target(visit, individuals)
		if target != null:
			_start_charge(visit, target, world, game_data, individuals)
	if visit.phase == WildAnimalVisit.Phase.CHARGING:
		_charge(visit, wild_rules, game_delta, individuals, game_data, world, folk, effects)
		return false
	if visit.phase == WildAnimalVisit.Phase.STAYING:
		_sniff(visit, wild_rules, game_delta)
		visit.stay_remaining -= game_delta
		if visit.stay_remaining <= 0.0:
			apply_visit_outcome(visit, game_data, world, folk, effects)
			_start_leaving(visit, world)
		return false
	_ensure_path(visit)
	var stop_distance := PIT_ARRIVAL_RADIUS \
		if visit.phase == WildAnimalVisit.Phase.ARRIVING and visit.target_kind == WildAnimalVisit.TargetKind.PIT else 0.0
	while not visit.path.is_empty() and visit.position.distance_to(visit.path[0]) <= PathfindingService.WAYPOINT_REACH_DISTANCE:
		visit.path.pop_front()
	var following_waypoint := not visit.path.is_empty()
	var goal: Vector2 = visit.path[0] if following_waypoint else visit.target_point
	var to_goal: Vector2 = goal - visit.position
	var remaining := to_goal.length() - (0.0 if following_waypoint else stop_distance)
	if remaining <= 0.000001:
		if following_waypoint:
			visit.path.pop_front()
			return false
		return _on_target_reached(visit, world, wild_rules)
	var direction := to_goal / to_goal.length()
	# Scacciati: se ne vanno di corsa, balzi senza pause.
	var driven_away := visit.driven_off and visit.phase == WildAnimalVisit.Phase.LEAVING and wild_rules != null
	var speed := wild_rules.hop_speed if driven_away else _travel_speed(wild_rules)
	var old_positions: Array[Vector2] = []
	for i in range(visit.offsets.size()):
		old_positions.append(get_animal_position(visit, i))
	_turn_formation(visit, direction, speed * game_delta)
	var step := speed * game_delta
	if not driven_away:
		_travel_gait(visit, wild_rules, step, game_delta)
	var reached := step >= remaining
	visit.position += direction * (remaining if reached else step)
	if visit.trail.is_empty() or visit.trail[visit.trail.size() - 1].distance_to(visit.position) >= TRAIL_SPACING:
		visit.trail.append(visit.position)
		if visit.trail.size() > TRAIL_MAX_POINTS:
			visit.trail.pop_front()
	_follow_with_collision(visit, old_positions, wild_rules, game_delta)
	if not reached:
		return false
	if following_waypoint:
		visit.path.pop_front()
		return false
	return _on_target_reached(visit, world, wild_rules)


# Viaggio con la collisione (2026-10-30, richiesta utente: in arrivo passavano sopra la palizzata). Il centro segue il
# percorso; ognuno va verso il suo posto nella formazione (balzi e pause compresi, _travel_gait) con la collisione della
# fauna (PathfindingService.move_with_collision), al massimo a hop_speed. Se il posto è dietro un ostacolo (microcella
# bloccata o linea non libera) segue invece la scia del centro, il punto più recente che vede: ai cancelli e tra gli
# edifici passano in fila. Il posto diventa dove l'animale è arrivato davvero; il ritorno in formazione lo riallinea.
static func _follow_with_collision(visit: WildAnimalVisit, old_positions: Array[Vector2], wild_rules: AnimalRules,
		delta: float) -> void:
	if not visit.blocked_test.is_valid():
		return
	var max_step := (wild_rules.hop_speed if wild_rules != null else DEFAULT_MOVE_SPEED) * delta
	var frame_angle := visit.facing_direction.angle()
	for i in range(visit.offsets.size()):
		var from_position := old_positions[i]
		var goal := get_animal_position(visit, i)
		if bool(visit.blocked_test.call(Vector2i(goal.floor()))) or not _is_line_clear(visit, from_position, goal):
			goal = _trail_point_in_sight(visit, from_position)
		var next_position := PathfindingService.move_with_collision(visit.blocked_test, from_position,
			(goal - from_position).limit_length(max_step), visit.macro_coords)
		next_position = next_position.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
		visit.offsets[i] = (next_position - visit.position).rotated(-frame_angle)


# Punto più recente della scia visibile in linea retta da `from_position`; nessuno = il centro.
static func _trail_point_in_sight(visit: WildAnimalVisit, from_position: Vector2) -> Vector2:
	for index in range(visit.trail.size() - 1, -1, -1):
		if _is_line_clear(visit, from_position, visit.trail[index]):
			return visit.trail[index]
	return visit.position


static func _wild_rules(species: String) -> AnimalRules:
	var rules := WildAnimalGroupService.get_rules(species)
	return AnimalCalculator.get_animal_rules(rules.wild_species_name) if rules != null else null


# Velocità di marcia del centro (2026-10-29): la velocità media con cui un animale della specie si sposta a vista nella
# fauna (AnimalGroupRenderer: balzi a hop_speed con pause, fasi di movimento alternate a riposi), non move_speed — quella
# muove i centri invisibili dei gruppetti, di continuo, e in visita rendeva i lupi quasi 3 volte più veloci di un umano.
static func _travel_speed(wild_rules: AnimalRules) -> float:
	if wild_rules == null or wild_rules.hop_speed <= 0.0:
		return DEFAULT_MOVE_SPEED
	var moving := (wild_rules.movement_phase_duration_min + wild_rules.movement_phase_duration_max) * 0.5
	var resting := (wild_rules.rest_phase_duration_min + wild_rules.rest_phase_duration_max) * 0.5
	var moving_share := moving / (moving + resting) if moving + resting > 0.0 else 1.0
	return wild_rules.hop_speed * _hop_share(wild_rules) * moving_share


# Quota di tempo passata in balzo dentro la fase di movimento (durate medie di balzo e pausa della specie).
static func _hop_share(wild_rules: AnimalRules) -> float:
	var hop := (wild_rules.hop_duration_min + wild_rules.hop_duration_max) * 0.5
	var pause := (wild_rules.hop_pause_min + wild_rules.hop_pause_max) * 0.5
	return hop / (hop + pause) if hop + pause > 0.0 else 1.0


# Andatura in viaggio (2026-10-30, richiesta utente: scivolando sembravano volare): il centro avanza a velocità media e
# ognuno, sfasato dagli altri, alterna balzi e pause come la fauna — nella pausa resta fermo (il suo posto arretra di
# `step`), nel balzo recupera. In media il posto non cambia; lo scarto residuo lo riassorbe il ritorno in formazione.
static func _travel_gait(visit: WildAnimalVisit, wild_rules: AnimalRules, step: float, delta: float) -> void:
	if wild_rules == null:
		return
	var hop_share := _hop_share(wild_rules)
	if hop_share <= 0.0 or hop_share >= 1.0:
		return
	for i in range(visit.offsets.size()):
		visit.hop_timers[i] -= delta
		if visit.hop_timers[i] <= 0.0:
			visit.hopping[i] = not visit.hopping[i]
			visit.hop_timers[i] = randf_range(wild_rules.hop_duration_min, wild_rules.hop_duration_max) \
				if visit.hopping[i] else randf_range(wild_rules.hop_pause_min, wild_rules.hop_pause_max)
		# Asse locale +X = direzione di marcia (get_animal_position ruota i posti con facing_direction).
		visit.offsets[i].x += step * (1.0 / hop_share - 1.0) if visit.hopping[i] else -step


# In viaggio: cambio di direzione del gruppo senza far saltare gli animali (i posti si riesprimono nel nuovo
# riferimento), poi ognuno torna piano verso il suo posto nella formazione (dopo la sosta erano sparsi).
static func _turn_formation(visit: WildAnimalVisit, direction: Vector2, step: float) -> void:
	var turn := visit.facing_direction.angle() - direction.angle()
	visit.facing_direction = direction
	for i in range(visit.offsets.size()):
		visit.offsets[i] = visit.offsets[i].rotated(turn).move_toward(visit.home_offsets[i], step * FORMATION_RETURN_RATE)


# Sosta (2026-10-30): ognuno va ad annusare un punto attorno alla meta (_pick_sniff_point) a balzi a hop_speed e pause
# (hop_duration_*/hop_pause_*), come la fauna; arrivato, o finita la fase di movimento (movement_phase_duration_*), si
# ferma rivolto alla meta per una fase di riposo (rest_phase_duration_*), poi sceglie un altro punto. All'inizio di ogni
# balzo la direzione punta al punto, con un piccolo scarto, e si piega con la spinta degli edifici. I posti restano nel
# riferimento del gruppo, fermo durante la sosta.
static func _sniff(visit: WildAnimalVisit, wild_rules: AnimalRules, delta: float) -> void:
	if wild_rules == null:
		return
	var frame_angle := visit.facing_direction.angle()
	for i in range(visit.offsets.size()):
		var from_position := visit.position + visit.offsets[i].rotated(frame_angle)
		visit.phase_timers[i] -= delta
		if not visit.moving[i]:
			if visit.phase_timers[i] > 0.0:
				continue
			_start_sniff_walk(visit, i, from_position, wild_rules)
		var to_point := visit.sniff_points[i] - from_position
		if to_point.length() <= SNIFF_REACH_DISTANCE or visit.phase_timers[i] <= 0.0:
			_start_sniffing(visit, i, from_position, wild_rules)
			continue
		var hop_started := false
		visit.hop_timers[i] -= delta
		if visit.hop_timers[i] <= 0.0:
			visit.hopping[i] = not visit.hopping[i]
			visit.hop_timers[i] = randf_range(wild_rules.hop_duration_min, wild_rules.hop_duration_max) \
				if visit.hopping[i] else randf_range(wild_rules.hop_pause_min, wild_rules.hop_pause_max)
			hop_started = visit.hopping[i]
		if not visit.hopping[i]:
			continue
		var heading := visit.headings[i]
		if hop_started:
			heading = to_point.angle() + randf_range(-1.0, 1.0) * SNIFF_HEADING_JITTER
			# Edifici (2026-10-29): la direzione si piega verso la spinta, come il disagio della fauna
			# (AnimalGroupRenderer._apply_avoidance_on_hop), con la forza della specie.
			if not visit.reaction_points.is_empty():
				var push := building_push(from_position, visit.reaction_points, visit.reaction_radii)
				if push.length_squared() > 0.000001:
					var strength := wild_rules.avoidance_strength if wild_rules.avoidance_strength >= 0.0 else AnimalGroupRenderer.AVOID_BIAS_PER_HOP
					heading = lerp_angle(heading, push.angle(), clampf(push.length() * strength, 0.0, 1.0))
		# Collisione: stessa regola della fauna (PathfindingService.move_with_collision), poi dentro la cella.
		var next_position := PathfindingService.move_with_collision(visit.blocked_test, from_position,
			Vector2.from_angle(heading) * minf(wild_rules.hop_speed * delta, to_point.length()), visit.macro_coords)
		next_position = next_position.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
		if next_position == from_position:
			# Bloccato su entrambi gli assi: per il resto del balzo da un'altra parte, invece di restare incollato.
			heading = randf() * TAU
		visit.headings[i] = heading
		visit.offsets[i] = (next_position - visit.position).rotated(-frame_angle)


# Parte verso un nuovo punto da annusare, per al massimo una fase di movimento; il primo balzo parte subito.
static func _start_sniff_walk(visit: WildAnimalVisit, index: int, from_position: Vector2, wild_rules: AnimalRules) -> void:
	visit.sniff_points[index] = _pick_sniff_point(visit, from_position)
	visit.moving[index] = true
	visit.phase_timers[index] = randf_range(wild_rules.movement_phase_duration_min, wild_rules.movement_phase_duration_max)
	visit.hopping[index] = false
	visit.hop_timers[index] = 0.0


# Si ferma ad annusare, rivolto alla meta (la Fossa, o il centro del villaggio), per una fase di riposo.
static func _start_sniffing(visit: WildAnimalVisit, index: int, from_position: Vector2, wild_rules: AnimalRules) -> void:
	visit.moving[index] = false
	visit.phase_timers[index] = randf_range(wild_rules.rest_phase_duration_min, wild_rules.rest_phase_duration_max)
	var to_look := visit.look_point - from_position
	if to_look.length() > 0.001:
		visit.headings[index] = to_look.angle()


# Punto sull'anello SNIFF_RING_MIN..MAX attorno alla meta (target_point durante la sosta), su una microcella libera; tra
# SNIFF_POINT_ATTEMPTS tentativi quello meno spinto dagli edifici che respingono (il fuoco). Nessuno libero = resta dov'è.
static func _pick_sniff_point(visit: WildAnimalVisit, from_position: Vector2) -> Vector2:
	var best := from_position
	var best_repulsion := INF
	for attempt in range(SNIFF_POINT_ATTEMPTS):
		var point := visit.target_point + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(SNIFF_RING_MIN, SNIFF_RING_MAX)
		point = point.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
		if visit.blocked_test.is_valid() and bool(visit.blocked_test.call(Vector2i(point.floor()))):
			continue
		var repulsion := building_push(point, visit.reaction_points, visit.reaction_radii, false).length()
		if repulsion < best_repulsion:
			best = point
			best_repulsion = repulsion
			if repulsion <= 0.0:
				break
	return best


static func _on_target_reached(visit: WildAnimalVisit, world: World, wild_rules: AnimalRules) -> bool:
	if visit.phase == WildAnimalVisit.Phase.ARRIVING:
		visit.phase = WildAnimalVisit.Phase.STAYING
		visit.stay_remaining = randf_range(STAY_DAYS_MIN, STAY_DAYS_MAX)
		_collect_reaction_sources(visit, world, wild_rules)
		# Metà parte subito verso un punto da annusare, gli altri annusano dove sono per un poco: non si muovono tutti
		# insieme. Riferimento del gruppo rivolto alla meta; i posti si riesprimono nel nuovo riferimento (niente salti).
		var old_angle := visit.facing_direction.angle()
		var to_look := visit.look_point - visit.position
		if to_look.length() > 0.0:
			visit.facing_direction = to_look.normalized()
		var frame_angle := visit.facing_direction.angle()
		for i in range(visit.animal_ids.size()):
			visit.offsets[i] = visit.offsets[i].rotated(old_angle - frame_angle)
			var from_position := visit.position + visit.offsets[i].rotated(frame_angle)
			visit.headings[i] = frame_angle
			if wild_rules != null and randf() < 0.5:
				_start_sniff_walk(visit, i, from_position, wild_rules)
			else:
				visit.moving[i] = false
				visit.phase_timers[i] = randf_range(0.0, 0.3)
		print("[WILD ANIMAL VISITS] %s: arrivati, restano %.2f giorni" % [visit.species, visit.stay_remaining])
		return false
	print("[WILD ANIMAL VISITS] %s: usciti dalla macrocella %s" % [visit.species, visit.macro_coords])
	return true


# Edifici completi della macrocella della visita a cui la specie reagisce (AnimalRules.building_reactions; non elencati
# = building_avoidance_radius, respinge; 0 = ignorato). Presi una volta all'arrivo: in una sosta di 1-2 giorni gli
# edifici non cambiano in modo che conti.
static func _collect_reaction_sources(visit: WildAnimalVisit, world: World, wild_rules: AnimalRules) -> void:
	visit.reaction_points.clear()
	visit.reaction_radii.clear()
	visit.shelter_rects.clear()
	visit.safe_points.clear()
	if wild_rules == null or world == null:
		return
	for building in world.buildings:
		if building.macro_x != visit.macro_coords.x or building.macro_y != visit.macro_coords.y:
			continue
		if not building.is_complete or building.is_demolished:
			continue
		var radius := float(wild_rules.building_reactions.get(building.building_type_name, wild_rules.building_avoidance_radius))
		# Riparo dagli attacchi (L4): stessi edifici, tranne i calpestabili e quelli che attirano.
		if radius >= 0.0 and building.rules != null and not building.rules.walkable:
			visit.shelter_rects.append(Rect2(Vector2(building.micro_x, building.micro_y), Vector2(BuildingFootprint.size_of(building))))
		if radius == 0.0:
			continue
		var point := VisitorService.get_building_point(building)
		visit.reaction_points.append(point)
		visit.reaction_radii.append(radius)
		# Zona sicura: solo gli edifici temuti esplicitamente (elencati con raggio positivo, il focolare), non i non
		# elencati che respingono col raggio di default.
		if radius > 0.0 and wild_rules.building_reactions.has(building.building_type_name):
			visit.safe_points.append(point)
	if not visit.reaction_points.is_empty():
		print("[WILD ANIMAL VISITS] %s: %d edifici a cui reagire in sosta" % [visit.species, visit.reaction_points.size()])


# Spinta degli edifici su un animale in `from_position` (microcelle): somma dei contributi entro il raggio di ciascuno.
# Raggio positivo = respinge, con la curva della fauna (AnimalGroupRenderer.AVOID_CURVE_EXPONENT: 0 al bordo, 1 a
# contatto); negativo = attira, ATTRACTION_WEIGHT costante, nullo entro ATTRACTION_STOP_DISTANCE (saltato con
# include_attraction false). Direzione = verso della somma, intensità = sua lunghezza (massimo 1). Statica e senza
# stato: riusabile dal servizio comune della fauna.
static func building_push(from_position: Vector2, points: Array[Vector2], radii: Array[float],
		include_attraction: bool = true) -> Vector2:
	var push := Vector2.ZERO
	for i in range(points.size()):
		var offset := from_position - points[i]
		var distance := offset.length()
		var radius := absf(radii[i])
		if distance > radius:
			continue
		if radii[i] > 0.0:
			var away: Vector2 = offset / distance if distance > 0.001 else Vector2.RIGHT.rotated(randf() * TAU)
			push += away * pow(1.0 - distance / radius, AnimalGroupRenderer.AVOID_CURVE_EXPONENT)
		elif include_attraction and distance > ATTRACTION_STOP_DISTANCE:
			push -= offset / distance * ATTRACTION_WEIGHT
	return push.limit_length(1.0)


# Persona da caricare: la prima della macrocella della visita non ancora tirata, non al sicuro (_is_safe), entro il raggio
# in cui un presente la nota (notice_radii) e raggiungibile in linea retta (_is_line_clear), per cui il tiro
# (attack_chance) riesce. Ogni persona notata è tirata una volta sola per visita. null se nessuna.
static func _find_attack_target(visit: WildAnimalVisit, individuals: Array[HumanIndividual]) -> HumanIndividual:
	if individuals.is_empty() or visit.attack_chance <= 0.0:
		return null
	for member in individuals:
		if member.home_macro_coords != visit.macro_coords or visit.attack_rolled_ids.has(member.id):
			continue
		if _is_safe(visit, member.position):
			continue
		for i in range(visit.animal_ids.size()):
			var radius: float = visit.notice_radii[i] if i < visit.notice_radii.size() else MIN_NOTICE_RADIUS
			var animal_position := get_animal_position(visit, i)
			if animal_position.distance_to(member.position) > radius \
					or not _is_line_clear(visit, animal_position, member.position):
				continue
			visit.attack_rolled_ids[member.id] = true
			if randf() < visit.attack_chance:
				return member
			print("[WILD ANIMAL VISITS] %s: notano #%d %s ma non attaccano (probabilità %d%%)" % [
				visit.species, member.id, member.name, roundi(visit.attack_chance * 100.0)])
			break
	return null


# Al sicuro: al riparo in un edificio completato (shelter_rects) o in una zona sicura (_in_fear_zone).
static func _is_safe(visit: WildAnimalVisit, point: Vector2) -> bool:
	return visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(point)) or _in_fear_zone(visit, point)


# Entro FEAR_SAFE_RADIUS da un edificio che la specie teme (safe_points: il focolare).
static func _in_fear_zone(visit: WildAnimalVisit, point: Vector2) -> bool:
	return visit.safe_points.any(func(safe_point: Vector2) -> bool: return safe_point.distance_to(point) <= FEAR_SAFE_RADIUS)


# Nessuna microcella bloccata (visit.blocked_test) sulla linea da `from` a `to`, escluse quella di partenza (l'animale ci
# sta già) e quella di arrivo (la persona: un cantiere blocca ma non ripara). Senza griglia = sempre libera.
static func _is_line_clear(visit: WildAnimalVisit, from: Vector2, to: Vector2) -> bool:
	if not visit.blocked_test.is_valid():
		return true
	var start_cell := Vector2i(from.floor())
	var end_cell := Vector2i(to.floor())
	var steps := maxi(int(ceil(from.distance_to(to) / ATTACK_LINE_STEP)), 1)
	for step in range(1, steps + 1):
		var cell := Vector2i(from.lerp(to, float(step) / float(steps)).floor())
		if cell != start_cell and cell != end_cell and bool(visit.blocked_test.call(cell)):
			return false
	return true


static func _find_individual(individuals: Array[HumanIndividual], individual_id: int) -> HumanIndividual:
	for member in individuals:
		if member.id == individual_id:
			return member
	return null


# Parte la carica: il riferimento del gruppo resta fermo (come in sosta), ognuno con la sua direzione. La persona
# caricata scappa (L5a, DangerFleeService, profilo DANGER_PROFILE): il pericolo ha l'id del gruppo (una visita alla volta
# per gruppo) e arriva dal presente più vicino; i punti sicuri sono le zone del fuoco (safe_points).
static func _start_charge(visit: WildAnimalVisit, target: HumanIndividual, world: World, game_data: GameData,
		individuals: Array[HumanIndividual]) -> void:
	visit.phase = WildAnimalVisit.Phase.CHARGING
	visit.attack_target_id = target.id
	visit.charge_remaining = MAX_CHARGE_DAYS
	visit.charge_min_distance = INF
	visit.charge_pause = 0.0
	visit.bites = 0
	visit.attacked = true
	visit.path.clear()
	visit.path_planned = false
	var nearest_wolf := visit.position
	for i in range(visit.animal_ids.size()):
		var animal_position := get_animal_position(visit, i)
		if animal_position.distance_to(target.position) < nearest_wolf.distance_to(target.position):
			nearest_wolf = animal_position
	visit.charge_start_distance = nearest_wolf.distance_to(target.position)
	print("[WILD ANIMAL VISITS] %s: caricano #%d %s da %.1f microcelle" % [
		visit.species, target.id, target.name, visit.charge_start_distance])
	DangerFleeService.start_flee(target, DANGER_PROFILE, visit.group_id, nearest_wolf, visit.safe_points, world, game_data)
	var wolf_positions: Array[Vector2] = []
	for i in range(visit.animal_ids.size()):
		wolf_positions.append(get_animal_position(visit, i))
	# Aiuta chi è fuori dagli edifici e vede i lupi in linea retta (stessa regola dell'attacco).
	var can_help := func(member: HumanIndividual) -> bool:
		if visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(member.position)):
			return false
		return wolf_positions.any(func(wolf: Vector2) -> bool: return _is_line_clear(visit, wolf, member.position))
	var drive_off := DangerFleeService.start_drive_off(individuals, target, DANGER_PROFILE, visit.group_id,
		wolf_positions, can_help, game_data)
	visit.defender_ids = drive_off["helper_ids"]
	visit.defenders_needed = int(drive_off["needed"]) if not visit.defender_ids.is_empty() else 0


# Inseguimento: ognuno va dritto verso la persona alternando balzi a hop_speed e pause (hop_*), come la fauna, con la
# sua collisione; in media un po' più veloce di chi corre. Il primo che arriva a ATTACK_CONTACT_DISTANCE morde
# (_on_attack_contact), poi tutti fermi per BITE_PAUSE_DAYS. Fine: vedi il commento delle costanti d'attacco.
static func _charge(visit: WildAnimalVisit, wild_rules: AnimalRules, delta: float, individuals: Array[HumanIndividual],
		game_data: GameData, world: World, folk: Folk, effects: GameEffects) -> void:
	var target := _find_individual(individuals, visit.attack_target_id)
	visit.charge_remaining -= delta
	var end_reason := ""
	if target == null:
		end_reason = "persona sparita"
	elif target.home_macro_coords != visit.macro_coords:
		end_reason = "persona uscita dalla macrocella"
	elif visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(target.position)):
		end_reason = "persona al riparo in un edificio"
	elif visit.defenders_needed > 0 and _defenders_arrived(visit, individuals) >= visit.defenders_needed:
		_on_driven_off(visit, individuals, game_data, effects)
		_end_charge(visit, individuals, game_data, world, folk, effects)
		return
	elif _in_fear_zone(visit, target.position):
		end_reason = "persona al sicuro vicino al fuoco"
	elif visit.bites >= MAX_BITES_PER_CHARGE:
		end_reason = "%d morsi" % visit.bites
	elif visit.charge_remaining <= 0.0:
		end_reason = "tempo scaduto"
	elif wild_rules == null:
		end_reason = "regole della specie mancanti"
	if end_reason != "":
		print("[WILD ANIMAL VISITS] %s: carica finita (%s) dopo %.1f ore, %d morsi, distanza minima %.1f microcelle" % [
			visit.species, end_reason, _charge_hours(visit), visit.bites, visit.charge_min_distance])
		_end_charge(visit, individuals, game_data, world, folk, effects)
		return
	if visit.charge_pause > 0.0:
		visit.charge_pause -= delta
		return
	var frame_angle := visit.facing_direction.angle()
	for i in range(visit.offsets.size()):
		var from_position := visit.position + visit.offsets[i].rotated(frame_angle)
		var to_target := target.position - from_position
		var distance := to_target.length()
		visit.charge_min_distance = minf(visit.charge_min_distance, distance)
		if distance <= ATTACK_CONTACT_DISTANCE:
			_on_attack_contact(visit, target, game_data, effects)
			visit.charge_pause = BITE_PAUSE_DAYS
			return
		visit.hop_timers[i] -= delta
		if visit.hop_timers[i] <= 0.0:
			visit.hopping[i] = not visit.hopping[i]
			visit.hop_timers[i] = randf_range(wild_rules.hop_duration_min, wild_rules.hop_duration_max) 				if visit.hopping[i] else randf_range(wild_rules.hop_pause_min, wild_rules.hop_pause_max)
		var heading := to_target.angle()
		visit.headings[i] = heading
		if not visit.hopping[i]:
			continue
		var next_position := PathfindingService.move_with_collision(visit.blocked_test, from_position,
			Vector2.from_angle(heading) * minf(wild_rules.hop_speed * delta, distance), visit.macro_coords)
		next_position = next_position.clamp(Vector2.ZERO, Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001))
		# Nella zona sicura del fuoco non si entra: ci si ferma al bordo.
		if _in_fear_zone(visit, next_position) and not _in_fear_zone(visit, from_position):
			next_position = from_position
		visit.offsets[i] = (next_position - visit.position).rotated(-frame_angle)


# Morso (L5b): la ferita BITE_CONDITION_ID (si somma a quelle di prima, HealthConditionRules.repeat_adds), log e notifica.
static func _on_attack_contact(visit: WildAnimalVisit, target: HumanIndividual, game_data: GameData,
		effects: GameEffects) -> void:
	visit.bites += 1
	var bitten := HealthConditionService.add_condition(target, BITE_CONDITION_ID, game_data)
	print("[WILD ANIMAL VISITS] %s: morso %d a #%d %s dopo %.1f ore di carica (partiti da %.1f microcelle)%s, salute %d" % [
		visit.species, visit.bites, target.id, target.name, _charge_hours(visit), visit.charge_start_distance,
		"" if bitten else " (ferita rifiutata)", int(target.current_health)])
	if effects == null:
		return
	var group_rules := WildAnimalGroupService.get_rules(visit.species)
	var wild_species := group_rules.wild_species_name if group_rules != null else visit.species
	effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_ATTACK,
		GameContext.tr_text("notification_wild_animal_attack").format({
			"species": GameContext.tr_text("animal_species_" + wild_species), "name": target.name}))


# Aiutanti arrivati: corsa finita (gridano sul posto) o entro DRIVE_OFF_GIVE_UP_DISTANCE da un presente.
static func _defenders_arrived(visit: WildAnimalVisit, individuals: Array[HumanIndividual]) -> int:
	if visit.defender_ids.is_empty():
		return 0
	var frame_angle := visit.facing_direction.angle()
	var arrived := 0
	for defender_id in visit.defender_ids:
		var member := _find_individual(individuals, defender_id)
		if member == null or not DangerFleeService.is_fleeing_from(member, visit.group_id):
			continue
		if DangerFleeService.has_reached_danger(member, visit.group_id):
			arrived += 1
			continue
		for i in range(visit.offsets.size()):
			if (visit.position + visit.offsets[i].rotated(frame_angle)).distance_to(member.position) <= DRIVE_OFF_GIVE_UP_DISTANCE:
				arrived += 1
				break
	return arrived


# Il branco rinuncia (L6.1): log, notifica coi nomi di chi l'ha scacciato, cacciata annotata sul branco.
static func _on_driven_off(visit: WildAnimalVisit, individuals: Array[HumanIndividual], game_data: GameData,
		effects: GameEffects) -> void:
	visit.driven_off = true
	var names: Array[String] = []
	for defender_id in visit.defender_ids:
		var member := _find_individual(individuals, defender_id)
		if member != null:
			names.append(member.name)
	var group := _find_group(game_data, visit.group_id)
	if group != null:
		group.driven_off_count += 1
		group.last_driven_off_day = game_data.get_absolute_day()
	print("[WILD ANIMAL VISITS] %s: scacciati da %s dopo %.1f ore, %d morsi (cacciate in tutto: %d)" % [
		visit.species, ", ".join(names), _charge_hours(visit), visit.bites, group.driven_off_count if group != null else 0])
	if effects == null:
		return
	var group_rules := WildAnimalGroupService.get_rules(visit.species)
	var wild_species := group_rules.wild_species_name if group_rules != null else visit.species
	effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_DRIVEN_OFF,
		GameContext.tr_text("notification_wild_animal_driven_off").format({
			"species": GameContext.tr_text("animal_species_" + wild_species), "names": ", ".join(names)}))


static func _find_group(game_data: GameData, group_id: int) -> WildAnimalGroup:
	for group in game_data.wild_animal_groups:
		if group.id == group_id:
			return group
	return null


# Durata della carica fin qui, in ore di gioco (per i log).
static func _charge_hours(visit: WildAnimalVisit) -> float:
	return (MAX_CHARGE_DAYS - visit.charge_remaining) * 24.0


# Fine della carica (con o senza contatto): il pericolo è passato (chi scappava riprende il lavoro), esito della visita
# (con attacco) e partenza dal bordo più vicino.
static func _end_charge(visit: WildAnimalVisit, individuals: Array[HumanIndividual], game_data: GameData, world: World,
		folk: Folk, effects: GameEffects) -> void:
	visit.attack_target_id = -1
	DangerFleeService.end_danger(individuals, visit.group_id)
	apply_visit_outcome(visit, game_data, world, folk, effects)
	_start_leaving(visit, world)


# Esito della visita, unico punto (lupi L3, 2026-10-30): chiamato a fine sosta, prima della partenza. Visita tranquilla:
# punti addomesticazione alla specie domestica che deriva da questa selvatica (POINTS_PER_ANIMAL_* per adulto presente,
# YOUNG_POINTS_SHARE per giovane, la parte
# decimale messa da parte in WildAnimalGroup.pending_domestication_points) e −AGGRESSION_DROP_PER_VISIT a ogni presente.
# Visita con attacco (L4): niente punti né calma. Qui arriveranno gli altri casi (lupo ferito o ucciso L7).
static func apply_visit_outcome(visit: WildAnimalVisit, game_data: GameData, world: World, folk: Folk,
		effects: GameEffects) -> void:
	if visit.attacked:
		print("[WILD ANIMAL VISITS] %s: visita con attacco, niente punti né calma" % visit.species)
		return
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return
	var pit_ratio := _visit_pit_fill_ratio(visit, world)
	var per_animal := POINTS_PER_ANIMAL_FULL_PIT if pit_ratio >= PIT_FULL_RATIO else POINTS_PER_ANIMAL_OTHERWISE
	var present: Array[WildAnimal] = []
	for animal_id in visit.animal_ids:
		var animal := group.find_animal(animal_id)
		if animal != null:
			present.append(animal)
	var wild_rules := _wild_rules(group.species)
	var today := game_data.get_absolute_day()
	var visit_points := 0.0
	for animal in present:
		animal.aggression = maxf(animal.aggression - AGGRESSION_DROP_PER_VISIT, 0.0)
		var is_young := animal.get_age_band(today, wild_rules) == GameTypes.AgeBand.YOUNG
		visit_points += per_animal * (YOUNG_POINTS_SHARE if is_young else 1.0)
	var domestic_species := _domestic_species_for(group.species)
	var whole_points := 0
	if domestic_species != "":
		group.pending_domestication_points += visit_points
		whole_points = int(floor(group.pending_domestication_points))
		group.pending_domestication_points -= whole_points
		if whole_points > 0:
			DomesticationPointsService.add_points(game_data, folk, domestic_species, whole_points, effects)
	print("[WILD ANIMAL VISITS] %s: visita tranquilla (%s), %d presenti, %.2f punti (adulto %.1f, giovane metà) -> +%d punti %s (resto %.2f), aggressività -%d a %s" % [
		group.species,
		"fossa piena al %d%%" % roundi(pit_ratio * 100.0) if visit.target_kind == WildAnimalVisit.TargetKind.PIT else "senza fossa",
		present.size(), visit_points, per_animal, whole_points, domestic_species, group.pending_domestication_points,
		roundi(AGGRESSION_DROP_PER_VISIT),
		", ".join(present.map(func(animal: WildAnimal) -> String: return "#%d (%d)" % [animal.id, roundi(animal.aggression)]))])


# Riempimento (0..1) della Fossa meta della visita; 0 senza Fossa o se nel frattempo non riceve più rifiuti.
static func _visit_pit_fill_ratio(visit: WildAnimalVisit, world: World) -> float:
	if visit.target_kind != WildAnimalVisit.TargetKind.PIT or world == null:
		return 0.0
	for building in world.buildings:
		if building.id == visit.pit_building_id:
			if not WasteDisposalService.is_waste_pit(building):
				return 0.0
			return float(WasteDisposalService.get_pit_fill(building)) / float(building.rules.waste_capacity)
	return 0.0


# Specie domestica che deriva dalla selvatica del gruppo (DomesticAnimalRules.wild_species_name: cane ← lupo); "" se
# nessuna.
static func _domestic_species_for(group_species: String) -> String:
	var group_rules := WildAnimalGroupService.get_rules(group_species)
	var wild_species := group_rules.wild_species_name if group_rules != null else group_species
	for species in DomesticAnimalCalculator.list_species():
		var rules := DomesticAnimalCalculator.get_rules(species)
		if rules != null and rules.wild_species_name == wild_species:
			return species
	return ""


# Uscita dal bordo più vicino raggiungibile da dove il gruppo si trova; senza un bordo valido, l'ingresso.
static func _start_leaving(visit: WildAnimalVisit, world: World) -> void:
	# Dopo la sosta o la carica sono sparsi: il centro passa sull'animale più vicino alla loro media (una microcella
	# libera, dove qualcuno sta davvero), così chi si è allontanato lo ritrova seguendo la scia; posti riespressi.
	var frame_angle := visit.facing_direction.angle()
	var mean := Vector2.ZERO
	for i in range(visit.offsets.size()):
		mean += get_animal_position(visit, i)
	if not visit.offsets.is_empty():
		mean /= float(visit.offsets.size())
		var new_center := get_animal_position(visit, 0)
		for i in range(1, visit.offsets.size()):
			var animal_position := get_animal_position(visit, i)
			if animal_position.distance_to(mean) < new_center.distance_to(mean):
				new_center = animal_position
		var shift := (new_center - visit.position).rotated(-frame_angle)
		for i in range(visit.offsets.size()):
			visit.offsets[i] -= shift
		visit.position = new_center
	visit.trail.clear()
	var exit: Variant = VisitorService.find_border_point(world, visit.macro_coords, visit.position,
		Vector2i(visit.position.floor()))
	visit.target_point = exit if exit != null else visit.entry_point
	visit.phase = WildAnimalVisit.Phase.LEAVING
	print("[WILD ANIMAL VISITS] %s: se ne vanno" % visit.species)


# Stesso calcolo di VisitorService._ensure_path: percorso del centro ricalcolato al cambio di meta o di blocchi della
# macrocella; senza griglia o con meta irraggiungibile si va in linea retta.
static func _ensure_path(visit: WildAnimalVisit) -> void:
	var cell := PathfindingService.get_live_cell(visit.macro_coords)
	var block_version: int = cell.path_block_version if cell != null else -1
	if visit.path_planned and visit.path_target == visit.target_point and visit.path_block_version == block_version:
		return
	visit.path.clear()
	visit.path_planned = true
	visit.path_target = visit.target_point
	visit.path_block_version = block_version
	if cell == null or cell.path_grid == null:
		return
	var from := Vector2i(visit.position.floor())
	var to := Vector2i(visit.target_point.floor())
	if not PathfindingService._in_bounds(from) or not PathfindingService._in_bounds(to) or from == to:
		return
	# Meta irraggiungibile (2026-10-30, richiesta utente: la Fossa dentro un recinto chiuso) — prima si andava in linea
	# retta, attraverso la palizzata: la meta diventa la microcella libera più vicina nella regione del gruppo, e la
	# sosta si fa lì (rivolti sempre alla Fossa, look_point).
	if not PathfindingService.is_reachable(cell, from, to):
		var region := PathfindingService.get_region(cell, from)
		var nearest := PathfindingService.find_open_microcell(cell, to, 0, region) \
			if region >= 0 else PathfindingService.NO_POCKET_EXIT
		if nearest == PathfindingService.NO_POCKET_EXIT or nearest == from:
			return
		print("[WILD ANIMAL VISITS] %s: meta %s irraggiungibile, si fermano a %s" % [visit.species, to, nearest])
		to = nearest
		visit.target_point = Vector2(nearest) + Vector2(0.5, 0.5)
		visit.path_target = visit.target_point
	var cells := PathfindingService.find_path(cell, from, to)
	for i in range(1, cells.size() - 1):
		visit.path.append(Vector2(cells[i]) + Vector2(0.5, 0.5))


# DEBUG — riga per il tooltip della DebugBar: fase e animali presenti.
static func debug_line(visit: WildAnimalVisit) -> String:
	var phase_names := ["in arrivo", "fermi", "se ne vanno", "caricano"]
	return "In visita (%s, %s): %s" % [phase_names[visit.phase],
		"fossa" if visit.target_kind == WildAnimalVisit.TargetKind.PIT else "margini",
		", ".join(visit.animal_ids.map(func(animal_id: int) -> String: return "#%d" % animal_id))]
