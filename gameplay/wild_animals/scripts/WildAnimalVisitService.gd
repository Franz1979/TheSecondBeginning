class_name WildAnimalVisitService
extends RefCounted

# Visite dei gruppi di animali selvatici al villaggio (2026-10-28, richiesta utente — lupi passo L1). Stateless, come
# VisitorService, di cui riusa ingresso/uscita dal bordo (find_border_point) e lo schema di movimento. La visita parte da
# sola (tick_day, L2) o a comando (debug); a fine sosta dà punti addomesticazione e calma (apply_visit_outcome, L3).
#
# Ciclo:
#   ARRIVING  entra dal bordo più vicino alla meta e ci cammina: la Fossa più piena della macrocella del villaggio, o
#             il magazzino se non c'è una Fossa (2026-11-01, richiesta utente: ai margini non si vedevano).
#   STAYING   per una durata a caso ognuno va ad annusare punti attorno alla meta, fermandosi rivolto a lei.
#   LEAVING   torna al bordo più vicino e sparisce.

# Visite spontanee (lupi L2, 2026-11-01, regole dell'utente): sotto MIN_VILLAGERS_FOR_VISITS abitanti nessuna visita; con una
# visita in corso o durante l'attesa dopo l'uscita nessun tiro; poi un dado al giorno, con facce VISIT_DICE_*_BASE / abitanti
# (mai meno di VISIT_DICE_*_MIN): più gente attira di più. L'aggressività non c'entra.
const MIN_VILLAGERS_FOR_VISITS: int = 10
const VISIT_DICE_PIT_BASE: float = 300.0
const VISIT_DICE_PIT_MIN: float = 5.0
const VISIT_DICE_STORAGE_BASE: float = 600.0
const VISIT_DICE_STORAGE_MIN: float = 20.0
# Giorni di attesa dall'uscita dei lupi: se scacciati o cacciati nell'ultima visita, altrimenti (vale la più lunga).
const WAIT_DAYS_AFTER_HUNTED: int = 20
const WAIT_DAYS_AFTER_DRIVEN_OFF: int = 10
const WAIT_DAYS_AFTER_VISIT: int = 5
# TEMPORANEO: vedi _debug_log_leaving.
static var _debug_leaving_log_day: Dictionary = {}
# Chi viene: ogni animale con questa probabilità (cuccioli compresi), almeno MIN_PARTICIPANTS, sempre un riproduttore.
const PARTICIPATION_CHANCE: float = 0.7
const MIN_PARTICIPANTS: int = 2
# Sosta in giorni di gioco (2026-10-29: 1-2 giorni, 8-16 secondi a 1x; con 0.25-0.5 ripartivano quasi subito).
const STAY_DAYS_MIN: float = 1.0
const STAY_DAYS_MAX: float = 2.0
# In uscita: giorni di gioco, da quando esce il primo, dopo cui chi è rimasto indietro esce lo stesso (vedi advance).
const STRAGGLER_EXIT_DAYS: float = 0.5
# Distanza dalla meta (Fossa o magazzino) a cui il gruppo si ferma (microcelle).
const PIT_ARRIVAL_RADIUS: float = 2.0
# Ingresso e uscita (2026-10-31, richiesta utente): tra BORDER_CANDIDATES punti a caso del bordo il branco prende quello
# il cui tragitto in linea retta passa vicino a meno edifici del villaggio (entro BORDER_BUILDING_CLEARANCE microcelle):
# arriva dalla parte libera invece di attraversare le case.
const BORDER_CANDIDATES: int = 8
const BORDER_BUILDING_CLEARANCE: float = 4.0
# Disposizione sciolta attorno al centro del gruppo (microcelle).
const CLUSTER_RADIUS: float = 1.4
const CLUSTER_MIN_SPACING: float = 0.6
const CLUSTER_PLACEMENT_ATTEMPTS: int = 12
# Reazioni agli edifici in sosta (2026-10-29): richiamo di un edificio che attira, costante entro il suo raggio (una
# spinta che cresce avvicinandosi risucchierebbe l'animale dentro l'edificio) e nullo entro ATTRACTION_STOP_DISTANCE
# microcelle, dove l'animale ci gironzola attorno. Più debole della repulsione a contatto, così il fuoco vince da vicino.
# Sosta (2026-10-30, richiesta utente: "annusare" la Fossa invece di girare a caso): ognuno sceglie un punto su un
# anello attorno alla meta (microcelle), ci va a balzi e lì si ferma rivolto alla meta, poi un altro punto
# (comportamento STAND_AROUND del renderer).
const SNIFF_RING_MIN: float = 1.5
const SNIFF_RING_MAX: float = 3.5
# Esito di una visita tranquilla (lupi L3, 2026-10-30, richiesta utente): punti addomesticazione per animale presente —
# pieni se la meta è una Fossa, metà se è il magazzino — e calo dell'aggressività di ogni presente.
# Una Fossa attira da PIT_ATTRACTION_WASTE rifiuti in su (2026-11-01, richiesta utente: col 50% della capienza un villaggio
# piccolo non ci arrivava mai); sotto, il branco va al magazzino.
const PIT_ATTRACTION_WASTE: int = 300
const POINTS_PER_ANIMAL_FULL_PIT: float = 1.0
const POINTS_PER_ANIMAL_OTHERWISE: float = 0.5
const AGGRESSION_DROP_PER_VISIT: float = 1.0
# Giovani (cuccioli compresi, fascia YOUNG) prendono questa quota dei punti di un adulto (2026-10-30, richiesta utente).
const YOUNG_POINTS_SHARE: float = 0.5
# Attacco (lupi L4, 2026-10-30; tiro rifatto il 2026-10-31, richiesta utente): un tiro solo per visita, la prima volta
# che il branco nota una persona che può caricare, in arrivo o in sosta. Nota chi è nel raggio di un presente (da
# MIN_NOTICE_RADIUS ad aggressività 0 a MAX_NOTICE_RADIUS a 100, microcelle), in linea retta e fuori dagli edifici.
# Per ogni notato caricabile (non al sicuro vicino al fuoco) probabilità = ATTACK_BASE_CHANCE × aggressività media/100 ×
# lupi ÷ difesa (tetto ATTACK_CHANCE_CAP): lupi = presenti senza i cuccioli (sotto CUB_MAX_AGE_YEARS), difesa = forza sua
# e di chi gli sta attorno fuori dagli edifici entro DangerProfile.drive_off_radius (chi verrebbe a scacciarli; adulto
# sano 1, bambino/ragazzo/ferito/malato WEAK_PERSON_STRENGTH). Bersaglio: quello con la probabilità più alta (il debole
# più isolato), su cui si tira. Riuscito: la persona scappa (L5a, DangerFleeService col profilo DANGER_PROFILE) e tutto
# il branco la insegue a balzi con pause (L5b, 2026-10-30, richiesta utente). Al contatto (ATTACK_CONTACT_DISTANCE) la
# morde (BITE_CONDITION_ID, si sommano) con log e notifica, poi il branco resta fermo BITE_PAUSE_DAYS e riparte.
# L'inseguimento finisce quando la persona è al riparo, sparisce o muore, dopo MAX_BITES_PER_CHARGE morsi o
# MAX_CHARGE_DAYS; poi il branco se ne va. In ogni caso la visita è "con attacco".
const DANGER_PROFILE: String = "predator"
const ATTACK_BASE_CHANCE: float = 0.4
const ATTACK_CHANCE_CAP: float = 0.9
const WEAK_PERSON_STRENGTH: float = 0.5
const CUB_MAX_AGE_YEARS: int = 1
const BITE_CONDITION_ID: String = "bite"
# Pausa dopo un morso (giorni: 2 ore), in cui chi scappa guadagna strada.
const BITE_PAUSE_DAYS: float = 2.0 / 24.0
# Tetto dei morsi in una carica: chi non ha un riparo e aspetta allo scoperto non viene morso fino alla morte.
const MAX_BITES_PER_CHARGE: int = 3
# Scacciati in gruppo (L6.1, 2026-10-30, richiesta utente): all'inizio della carica gli adulti vicini corrono contro il
# branco (DangerFleeService.start_drive_off, regole nel profilo DANGER_PROFILE); quando ne sono arrivati quanti servono
# (finita la loro corsa, o entro DRIVE_OFF_GIVE_UP_DISTANCE microcelle da un presente) il branco si ferma e, dopo che
# hanno gridato insieme per DangerProfile.drive_off_shout_days, rinuncia e se ne va di corsa. Niente punti né calma
# (visita con attacco), aggressività invariata: il branco annota la cacciata
# (WildAnimalGroup.driven_off_count/last_driven_off_day).
const DRIVE_OFF_GIVE_UP_DISTANCE: float = 3.0
# Caccia al branco (lupi L7, 2026-11-01, regola dell'utente): una volta per visita, al primo tiro, l'aggressività di ogni
# presente sale di tanto; mai oltre AGGRESSION_MAX.
const AGGRESSION_RISE_WHEN_HUNTED: float = 1.0
const AGGRESSION_MAX: float = 100.0
# Soglie di aggressività media del branco annunciate al giocatore (_notify_calmer), dalla più bassa.
const CALM_NOTICE_THRESHOLDS: Array[int] = [25, 50, 75]
# Tra due nuove scelte della fuga allo scoperto (giorni: 1 ora), così chi è chiuso contro il bordo o non trova un posto
# non ci riprova a ogni fotogramma.
const REDIRECT_COOLDOWN_DAYS: float = 1.0 / 24.0
const MIN_NOTICE_RADIUS: float = 3.0
const MAX_NOTICE_RADIUS: float = 6.0
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
static func find_visit(game_data: GameData, group_id: int) -> WildAnimalVisit:
	for visit in game_data.wild_animal_visits:
		if visit.group_id == group_id:
			return visit
	return null


# Fa partire una visita del gruppo. null (e un log) se il gruppo è già in visita, non c'è un magazzino o un
# ingresso dal bordo.
# Giro giornaliero (GameSimulation.tick_day): il dado delle visite spontanee di ogni gruppo.
static func tick_day(ctx: GameContext) -> void:
	if ctx.game_data == null or ctx.world == null:
		return
	var today := ctx.game_data.get_absolute_day()
	for group in ctx.game_data.wild_animal_groups:
		if group.animals.is_empty() or find_visit(ctx.game_data, group.id) != null or today < group.next_visit_day:
			continue
		var faces := visit_dice_faces(ctx.world, ctx.individuals.size(), ctx.game_data, group)
		if faces > 0.0 and randf() * faces < 1.0:
			print("[WILD ANIMAL VISITS] %s: visita spontanea, giorno %d (dado da %.1f facce, %d abitanti)" % [
				group.species, today, faces, ctx.individuals.size()])
			start_visit(ctx.game_data, ctx.world, group)


# Facce del dado giornaliero (vedi MIN_VILLAGERS_FOR_VISITS); 0 = nessuna visita possibile (pochi abitanti, nessun magazzino).
# Dopo il primo arrivo della specie domestica, oltre WildAnimalGroupRules.visit_thinning_population abitanti le facce
# crescono in proporzione (visite più rade).
static func visit_dice_faces(world: World, villagers: int, game_data: GameData = null, group: WildAnimalGroup = null) -> float:
	var center := WildAnimalGroupService.find_anchor_storage(world)
	if center == null or villagers < MIN_VILLAGERS_FOR_VISITS:
		return 0.0
	var faces := maxf(VISIT_DICE_STORAGE_BASE / float(villagers), VISIT_DICE_STORAGE_MIN)
	if _find_fullest_pit(world, Vector2i(center.macro_x, center.macro_y)) != null:
		faces = maxf(VISIT_DICE_PIT_BASE / float(villagers), VISIT_DICE_PIT_MIN)
	if game_data == null or group == null:
		return faces
	var group_rules := WildAnimalGroupService.get_rules(group.species)
	var threshold := group_rules.visit_thinning_population if group_rules != null else 0
	var domestic_species := _domestic_species_for(group.species)
	if threshold > 0 and villagers > threshold and domestic_species != "" \
			and DomesticAnimalService.is_domesticated(game_data, domestic_species):
		faces *= float(villagers) / float(threshold)
	return faces


# I lupi sono usciti, o sono morti tutti i presenti: da qui parte l'attesa prima del prossimo tiro.
static func _note_visit_ended(visit: WildAnimalVisit, game_data: GameData) -> void:
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return
	var wait_days := WAIT_DAYS_AFTER_VISIT
	if visit.hunted:
		wait_days = WAIT_DAYS_AFTER_HUNTED
	elif visit.driven_off:
		wait_days = WAIT_DAYS_AFTER_DRIVEN_OFF
	group.last_visit_end_day = game_data.get_absolute_day()
	group.next_visit_day = group.last_visit_end_day + wait_days
	print("[WILD ANIMAL VISITS] %s: visita finita il giorno %d, prossimo tiro dal giorno %d" % [
		group.species, group.last_visit_end_day, group.next_visit_day])


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
	var pit := _find_fullest_pit(world, visit.macro_coords)
	if pit != null:
		visit.target_kind = WildAnimalVisit.TargetKind.PIT
		visit.pit_building_id = pit.id
	else:
		visit.target_kind = WildAnimalVisit.TargetKind.STORAGE
	var target_building := pit if pit != null else center
	visit.target_point = VisitorService.get_building_point(target_building)
	visit.look_point = visit.target_point
	var entry: Variant = _pick_quiet_border_point(world, visit.macro_coords, visit.target_point, target_building.id)
	if entry == null:
		print("[WILD ANIMAL VISITS] %s: nessun ingresso dal bordo di %s" % [group.species, visit.macro_coords])
		return null
	visit.entry_point = entry
	visit.position = entry
	visit.animal_ids = _pick_participants(group)
	for offset in _cluster_offsets(visit.animal_ids.size()):
		visit.animal_positions.append((visit.position + offset).clamp(Vector2.ZERO,
			Vector2(float(World.WIDTH) - 0.001, float(World.HEIGHT) - 0.001)))
	visit.blocked_test = PathfindingService.blocked_test_for(visit.macro_coords)
	var wild_rules := _wild_rules(group.species)
	var today := game_data.get_absolute_day()
	var aggression_sum := 0.0
	for i in range(visit.animal_ids.size()):
		var animal := group.find_animal(visit.animal_ids[i])
		var aggression_share := clampf(animal.aggression, 0.0, 100.0) / 100.0 if animal != null else 0.0
		visit.notice_radii.append(lerpf(MIN_NOTICE_RADIUS, MAX_NOTICE_RADIUS, aggression_share))
		# Forza del branco per il tiro d'attacco: i cuccioli non contano.
		if animal != null and animal.get_age_years(today) >= CUB_MAX_AGE_YEARS:
			visit.attack_wolves += 1
			aggression_sum += clampf(animal.aggression, 0.0, 100.0)
	visit.attack_aggression = aggression_sum / float(visit.attack_wolves) if visit.attack_wolves > 0 else 0.0
	# Ripari e zone del fuoco servono già in arrivo (tiro d'attacco anche per strada).
	_collect_reaction_sources(visit, world, wild_rules)
	game_data.wild_animal_visits.append(visit)
	print("[WILD ANIMAL VISITS] %s: arrivano %d animali %s, meta %s" % [
		group.species, visit.animal_ids.size(), visit.animal_ids,
		"fossa #%d" % pit.id if pit != null else "magazzino #%d" % center.id])
	return visit


# Punto del bordo per entrare o uscire (vedi BORDER_CANDIDATES): tra punti a caso raggiungibili da `point`, quello il
# cui tragitto in linea retta verso `point` ha meno edifici della macrocella entro BORDER_BUILDING_CLEARANCE (escluso
# `ignored_building_id`, la Fossa meta); a parità il primo estratto. null se il bordo non ha punti validi.
static func _pick_quiet_border_point(world: World, macro_coords: Vector2i, point: Vector2, ignored_building_id: int) -> Variant:
	var buildings: Array[Vector2] = []
	for building in world.buildings:
		if building.macro_x == macro_coords.x and building.macro_y == macro_coords.y and not building.is_demolished \
				and building.id != ignored_building_id:
			buildings.append(VisitorService.get_building_point(building))
	var best: Variant = null
	var best_count := -1
	var tried := 0
	for attempt in range(BORDER_CANDIDATES):
		var candidate: Variant = VisitorService.find_border_point(world, macro_coords, point, Vector2i(point.floor()), true)
		if candidate == null:
			break
		tried += 1
		var count := 0
		for building_point in buildings:
			var closest := Geometry2D.get_closest_point_to_segment(building_point, candidate, point)
			if closest.distance_to(building_point) <= BORDER_BUILDING_CLEARANCE:
				count += 1
		if best == null or count < best_count:
			best = candidate
			best_count = count
	if best != null:
		print("[WILD ANIMAL VISITS]   bordo scelto %s: %d edifici sul tragitto (migliore di %d punti a caso)" % [
			best, best_count, tried])
	return best


# Fossa che riceve rifiuti nella macrocella, la più piena (WasteDisposalService.get_pit_fill); null se nessuna.
static func _find_fullest_pit(world: World, macro_coords: Vector2i) -> Building:
	var best: Building = null
	for building in world.buildings:
		if building.macro_x != macro_coords.x or building.macro_y != macro_coords.y:
			continue
		if not WasteDisposalService.is_waste_pit(building) or WasteDisposalService.get_pit_fill(building) < PIT_ATTRACTION_WASTE:
			continue
		if best == null or WasteDisposalService.get_pit_fill(building) > WasteDisposalService.get_pit_fill(best):
			best = building
	return best


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
	return visit.animal_positions[index]


# Fa avanzare tutte le visite di `game_delta` (frazione di giorno; 0 in pausa) e toglie quelle uscite dalla mappa.
# Chiamato a ogni fotogramma da GameSimulation.tick_frame; folk ed effects servono all'esito di fine sosta, individuals
# all'attacco.
static func advance_all(game_data: GameData, world: World, game_delta: float, folk: Folk,
		individuals: Array[HumanIndividual], effects: GameEffects) -> void:
	if game_data == null or game_data.wild_animal_visits.is_empty() or game_delta <= 0.0:
		return
	var departed: Array[WildAnimalVisit] = []
	# Su una copia: un cane di guardia può uccidere l'ultimo presente e togliere la visita durante il giro (passo 8.4).
	for visit in game_data.wild_animal_visits.duplicate():
		if not game_data.wild_animal_visits.has(visit):
			continue
		if visit.needs_restore and not _restore_after_load(visit, game_data, world):
			departed.append(visit)
			continue
		if advance(visit, world, game_delta, game_data, folk, individuals, effects):
			departed.append(visit)
	for visit in departed:
		_note_visit_ended(visit, game_data)
		game_data.wild_animal_visits.erase(visit)


# Visita appena caricata (2026-10-30, WildAnimalVisit.to_save_data): toglie gli animali non più nel branco, rimette la
# collisione, fa ripianificare il percorso e raccoglie di nuovo gli edifici come all'inizio della visita.
# false = non resta nessuno (o il branco non c'è più): la visita va tolta.
static func _restore_after_load(visit: WildAnimalVisit, game_data: GameData, world: World) -> bool:
	visit.needs_restore = false
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return false
	for i in range(visit.animal_ids.size() - 1, -1, -1):
		if group.find_animal(visit.animal_ids[i]) != null:
			continue
		_remove_from_visit_arrays(visit, i)
	if visit.animal_ids.is_empty():
		return false
	visit.blocked_test = PathfindingService.blocked_test_for(visit.macro_coords)
	_collect_reaction_sources(visit, world, _wild_rules(visit.species))
	print("[WILD ANIMAL VISITS] %s: visita ripresa dal salvataggio (fase %d, %d animali)" % [
		visit.species, visit.phase, visit.animal_ids.size()])
	return true


# true = la visita è uscita dalla mappa e va tolta. Copione (2026-11-01, passo 7b.1): qui si decidono fasi, tiro d'attacco,
# morsi e uscita; a muovere gli animali è il renderer, col comportamento assegnato (_assign_behaviors). In una cella non
# viva non ci sono corpi: non si attacca, e arrivo e uscita sono immediati.
static func advance(visit: WildAnimalVisit, world: World, game_delta: float, game_data: GameData, folk: Folk,
		individuals: Array[HumanIndividual], effects: GameEffects) -> bool:
	var wild_rules := _wild_rules(visit.species)
	var has_bodies := _read_bodies(visit)
	# Cella viva ma corpi non ancora creati (GameScene._sync_wild_animal_visit_bodies): si aspetta il prossimo fotogramma.
	if not has_bodies and PathfindingService.get_live_cell(visit.macro_coords) != null:
		return false
	_notify_visit_news(visit, game_data, effects)
	# Cani di guardia (passo 8.1): abbaio d'allarme e posizione aggiornata come zona da cui stare alla larga.
	DomesticAnimalGuardService.update_visit(visit, game_data, game_delta)
	# Gli hanno tirato (lupi L7): la carica o la sosta finiscono qui, senza esito della visita, e se ne vanno di corsa.
	if visit.hunted and visit.phase != WildAnimalVisit.Phase.LEAVING:
		visit.attack_target_id = -1
		DangerFleeService.end_danger(individuals, visit.group_id)
		DomesticAnimalGuardService.end_run(visit, game_data, world)
		_start_leaving(visit, world)
	# In arrivo e in sosta (2026-10-31, richiesta utente: il branco che attraversa il villaggio deve poter attaccare per
	# strada). Una palizzata in mezzo toglie la linea retta (_is_line_clear): chi sta dietro non viene notato.
	if has_bodies and (visit.phase == WildAnimalVisit.Phase.STAYING or visit.phase == WildAnimalVisit.Phase.ARRIVING):
		var target := _find_attack_target(visit, individuals, game_data)
		if target != null:
			_start_charge(visit, target, world, game_data, individuals)
	if has_bodies and visit.assigned_phase != visit.phase:
		_assign_behaviors(visit, wild_rules)
	if visit.phase == WildAnimalVisit.Phase.CHARGING:
		_charge(visit, wild_rules, game_delta, individuals, game_data, world, folk, effects)
		return false
	if visit.phase == WildAnimalVisit.Phase.STAYING:
		_settle_arrivals(visit)
		visit.stay_remaining -= game_delta
		if visit.stay_remaining <= 0.0:
			apply_visit_outcome(visit, game_data, world, folk, effects)
			_start_leaving(visit, world)
		return false
	if not has_bodies:
		return _on_target_reached(visit)
	if visit.phase == WildAnimalVisit.Phase.ARRIVING:
		_note_redirected_target(visit)
		for body_id in visit.body_ids:
			if _has_arrived(visit, AnimalGroupRenderer.find_live_individual(body_id)):
				return _on_target_reached(visit)
		return false
	# In uscita: chi arriva al bordo esce subito; la visita finisce con l'ultimo.
	var still_here := false
	var someone_left := false
	for i in range(visit.body_ids.size()):
		if visit.body_ids[i] == 0:
			someone_left = true
			continue
		if _has_arrived(visit, AnimalGroupRenderer.find_live_individual(visit.body_ids[i])):
			AnimalGroupRenderer.remove_live_individual(visit.body_ids[i])
			visit.body_ids[i] = 0
			someone_left = true
		else:
			still_here = true
	# Rimasti indietro (2026-11-07, richiesta utente — lupo incastrato contro la Fossa, visita mai finita e cani che
	# abbaiavano per sempre): passati STRAGGLER_EXIT_DAYS da quando è uscito il primo, chi è ancora in scena esce lo stesso.
	# Resta nel branco, vivo, e torna alla prossima visita.
	if still_here and someone_left:
		visit.straggler_days += game_delta
		if visit.straggler_days >= STRAGGLER_EXIT_DAYS:
			for i in range(visit.body_ids.size()):
				if visit.body_ids[i] == 0:
					continue
				var body := AnimalGroupRenderer.find_live_individual(visit.body_ids[i])
				print("[WILD ANIMAL VISITS] %s #%d rimasto indietro in %s, esce lo stesso." % [
					visit.species, visit.animal_ids[i] if i < visit.animal_ids.size() else -1,
					Vector2i(body.position.floor()) if body != null else Vector2i(-1, -1)])
				AnimalGroupRenderer.remove_live_individual(visit.body_ids[i])
				visit.body_ids[i] = 0
			still_here = false
	_debug_log_leaving(visit, game_data)
	return false if still_here else _on_target_reached(visit)


# TEMPORANEO (2026-11-01, uscite lente dei lupi: togliere trovata la causa): una riga al giorno per ogni corpo ancora in uscita.
static func _debug_log_leaving(visit: WildAnimalVisit, game_data: GameData) -> void:
	var today := game_data.get_absolute_day()
	if _debug_leaving_log_day.get(visit.group_id, -1) == today:
		return
	_debug_leaving_log_day[visit.group_id] = today
	for body_id in visit.body_ids:
		if body_id == 0:
			continue
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body == null:
			print("[WILD ANIMAL VISITS] uscita g.%d: corpo %d NON TROVATO" % [today, body_id])
			continue
		print("[WILD ANIMAL VISITS] uscita g.%d: corpo %d in %s, meta %s (dist %.1f), behavior %d, arrived %s, path %s, salute %.2f, macro %d, micro %d" % [
			today, body_id, Vector2i(body.position.floor()), Vector2i(body.behavior_point.floor()), body.position.distance_to(body.behavior_point),
			body.behavior, body.behavior_arrived, body.behavior_path_planned, body.health, body.macro_phase, body.micro_phase])


# Crea un corpo per ogni presente, dove la visita dice che si trova, nel renderer dato (solo per questa visita, vedi
# GameScene._sync_wild_animal_visit_bodies). Reazioni e zone del fuoco sono gli stessi array della visita, non copie: dopo un
# caricamento si riempiono dopo (_restore_after_load).
static func spawn_bodies(visit: WildAnimalVisit, game_data: GameData, renderer: AnimalGroupRenderer) -> void:
	renderer.reaction_points = visit.reaction_points
	renderer.reaction_radii = visit.reaction_radii
	renderer.chase_no_enter_points = visit.safe_points
	renderer.chase_no_enter_radii = visit.safe_radii
	var group := _find_group(game_data, visit.group_id)
	var wild_rules := _wild_rules(visit.species)
	var today := game_data.get_absolute_day()
	visit.body_ids.clear()
	visit.assigned_phase = -1
	for i in range(visit.animal_ids.size()):
		var animal: WildAnimal = group.find_animal(visit.animal_ids[i]) if group != null else null
		var band: GameTypes.AgeBand = animal.get_age_band(today, wild_rules) if animal != null else GameTypes.AgeBand.ADULT
		var body := renderer.add_identified_individual(band, visit.animal_positions[i], visit.group_id, visit.animal_ids[i])
		if i < visit.animal_healths.size() and visit.animal_healths[i] > 0.0:
			body.health = visit.animal_healths[i]
		visit.body_ids.append(body.id)


# Id del corpo di un animale della visita; 0 se non è in scena.
static func get_body_id(visit: WildAnimalVisit, animal_id: int) -> int:
	var index := visit.animal_ids.find(animal_id)
	return visit.body_ids[index] if index >= 0 and index < visit.body_ids.size() else 0


# Il primo tiro di una visita (lupi L7, 2026-11-01, ThrowAction, anche a vuoto): aggressività su per ogni presente, una volta
# sola, e il branco annota l'episodio; a farlo andare via di corsa è il copione al prossimo advance.
static func on_member_shot_at(game_data: GameData, group_id: int) -> void:
	var visit := find_visit(game_data, group_id)
	var group := _find_group(game_data, group_id)
	if visit == null or group == null or visit.hunted:
		return
	visit.hunted = true
	visit.assigned_phase = -1
	for animal_id in visit.animal_ids:
		var animal := group.find_animal(animal_id)
		if animal != null:
			animal.aggression = minf(animal.aggression + AGGRESSION_RISE_WHEN_HUNTED, AGGRESSION_MAX)
	group.hunted_count += 1
	group.last_hunted_day = game_data.get_absolute_day()
	print("[WILD ANIMAL VISITS] %s: gli hanno tirato, se ne vanno di corsa; aggressività +%d a %d presenti (caccia in tutto: %d)" % [
		visit.species, roundi(AGGRESSION_RISE_WHEN_HUNTED), visit.animal_ids.size(), group.hunted_count])


# Un animale del branco ucciso (lupi L7, 2026-11-01, GameScene._on_prey_killed): esce dal branco, dalla visita e dalla scena;
# la carcassa l'ha già lasciata ThrowAction. Se era l'ultimo presente la visita finisce qui.
static func on_member_killed(game_data: GameData, body: AnimalVisualGroup, individuals: Array[HumanIndividual], effects: GameEffects) -> void:
	var group := _find_group(game_data, body.wild_group_id)
	if group != null:
		var animal := group.find_animal(body.wild_animal_id)
		if animal != null:
			group.animals.erase(animal)
		print("[WILD ANIMAL VISITS] %s: ucciso #%d, nel branco ne restano %d" % [group.species, body.wild_animal_id, group.animals.size()])
		_notify_group(effects, "notification_wild_killed_%s" % group.species, {"count": group.animals.size()})
	var visit := find_visit(game_data, body.wild_group_id)
	if visit != null:
		var index := visit.animal_ids.find(body.wild_animal_id)
		if index >= 0:
			_remove_from_visit_arrays(visit, index)
		if visit.animal_ids.is_empty():
			DangerFleeService.end_danger(individuals, visit.group_id)
			_note_visit_ended(visit, game_data)
			game_data.wild_animal_visits.erase(visit)
	AnimalGroupRenderer.remove_live_individual(body.id)


static func _remove_from_visit_arrays(visit: WildAnimalVisit, index: int) -> void:
	for per_animal: Array in [visit.animal_ids, visit.animal_positions, visit.animal_healths, visit.notice_radii, visit.body_ids]:
		if index < per_animal.size():
			per_animal.remove_at(index)


# Copia le posizioni dai corpi nella visita, e il centro. false se non ci sono corpi: mai creati, o spariti con la cella
# (si ricreano da animal_positions se la cella torna viva).
static func _read_bodies(visit: WildAnimalVisit) -> bool:
	if visit.body_ids.is_empty():
		return false
	var sum := Vector2.ZERO
	var count := 0
	visit.animal_healths.resize(visit.body_ids.size())
	for i in range(visit.body_ids.size()):
		if visit.body_ids[i] == 0:
			continue
		var body := AnimalGroupRenderer.find_live_individual(visit.body_ids[i])
		if body == null:
			visit.body_ids.clear()
			visit.assigned_phase = -1
			return false
		visit.animal_positions[i] = body.position
		visit.animal_healths[i] = body.health
		sum += body.position
		count += 1
	if count > 0:
		visit.position = sum / float(count)
	return true


# Assegna a ogni corpo il comportamento della fase, una volta per fase (e di nuovo se i corpi sono stati ricreati).
static func _assign_behaviors(visit: WildAnimalVisit, wild_rules: AnimalRules) -> void:
	visit.assigned_phase = visit.phase
	var travel_scale := _travel_speed_scale(wild_rules)
	var driven_away := (visit.driven_off or visit.hunted) and visit.phase == WildAnimalVisit.Phase.LEAVING
	for body_id in visit.body_ids:
		if body_id == 0:
			continue
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body == null:
			continue
		match visit.phase:
			WildAnimalVisit.Phase.CHARGING:
				# Il bersaglio lo aggiorna _charge a ogni mossa; fino ad allora fermo dov'è.
				AnimalGroupRenderer.set_live_behavior(body_id, AnimalVisualGroup.Behavior.CHASE, body.position)
			WildAnimalVisit.Phase.STAYING:
				if body.position.distance_to(visit.target_point) <= _stop_distance(visit):
					_start_sniffing(visit, body_id)
				else:
					# Chi è rimasto indietro arriva col suo percorso (_settle_arrivals).
					AnimalGroupRenderer.set_live_behavior(body_id, AnimalVisualGroup.Behavior.GO_TO, visit.target_point,
						0.0, 0.0, travel_scale)
			_:
				# In arrivo e in uscita; scacciati: di corsa, senza pause.
				AnimalGroupRenderer.set_live_behavior(body_id, AnimalVisualGroup.Behavior.GO_TO, visit.target_point,
					0.0, 0.0, 1.0 if driven_away else travel_scale, driven_away)


static func _start_sniffing(visit: WildAnimalVisit, body_id: int) -> void:
	AnimalGroupRenderer.set_live_behavior(body_id, AnimalVisualGroup.Behavior.STAND_AROUND, visit.target_point,
		SNIFF_RING_MIN, SNIFF_RING_MAX)
	# Rivolti alla Fossa o al centro del villaggio, anche se la sosta si fa altrove (meta irraggiungibile).
	var body := AnimalGroupRenderer.find_live_individual(body_id)
	if body != null:
		body.behavior_look_point = visit.look_point


# In sosta: chi era rimasto indietro, appena arrivato, comincia ad annusare.
static func _settle_arrivals(visit: WildAnimalVisit) -> void:
	for body_id in visit.body_ids:
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body != null and body.behavior == AnimalVisualGroup.Behavior.GO_TO and _has_arrived(visit, body):
			_start_sniffing(visit, body_id)


# Distanza dalla meta a cui il gruppo è arrivato: attorno all'edificio in arrivo, al punto esatto del bordo in uscita.
static func _stop_distance(visit: WildAnimalVisit) -> float:
	return AnimalGroupRenderer.GO_TO_REACH_DISTANCE if visit.phase == WildAnimalVisit.Phase.LEAVING else PIT_ARRIVAL_RADIUS


static func _has_arrived(visit: WildAnimalVisit, body: AnimalVisualGroup) -> bool:
	return body != null and (body.behavior_arrived or body.position.distance_to(body.behavior_point) <= _stop_distance(visit))


# Meta irraggiungibile (2026-10-30, richiesta utente: la Fossa dentro un recinto chiuso): il percorso del corpo l'ha
# spostata sulla microcella libera più vicina (PathfindingService.plan_waypoints), e la sosta si fa lì.
static func _note_redirected_target(visit: WildAnimalVisit) -> void:
	if visit.target_redirected:
		return
	for body_id in visit.body_ids:
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body != null and body.behavior_path_planned and body.behavior_point != visit.target_point:
			print("[WILD ANIMAL VISITS] %s: meta %s irraggiungibile, si fermano a %s" % [
				visit.species, Vector2i(visit.target_point.floor()), Vector2i(body.behavior_point.floor())])
			visit.target_point = body.behavior_point
			visit.target_redirected = true
			return


static func _wild_rules(species: String) -> AnimalRules:
	var rules := WildAnimalGroupService.get_rules(species)
	return AnimalCalculator.get_animal_rules(rules.wild_species_name) if rules != null else null


# Andatura in viaggio (2026-10-29): la velocità media con cui un animale della specie si sposta a vista nella fauna
# (balzi a hop_speed con pause, fasi di movimento alternate a riposi), non move_speed, che in visita rendeva i lupi quasi
# 3 volte più veloci di un umano. In viaggio non si riposano: i balzi vanno a hop_speed × quota del tempo in movimento.
static func _travel_speed_scale(wild_rules: AnimalRules) -> float:
	if wild_rules == null:
		return 1.0
	var moving := (wild_rules.movement_phase_duration_min + wild_rules.movement_phase_duration_max) * 0.5
	var resting := (wild_rules.rest_phase_duration_min + wild_rules.rest_phase_duration_max) * 0.5
	return moving / (moving + resting) if moving + resting > 0.0 else 1.0


static func _on_target_reached(visit: WildAnimalVisit) -> bool:
	if visit.phase == WildAnimalVisit.Phase.ARRIVING:
		visit.phase = WildAnimalVisit.Phase.STAYING
		visit.stay_remaining = randf_range(STAY_DAYS_MIN, STAY_DAYS_MAX)
		print("[WILD ANIMAL VISITS] %s: arrivati, restano %.2f giorni" % [visit.species, visit.stay_remaining])
		return false
	print("[WILD ANIMAL VISITS] %s: usciti dalla macrocella %s" % [visit.species, visit.macro_coords])
	return true


# Edifici completi della macrocella della visita a cui la specie reagisce (AnimalRules.building_reactions; non elencati
# = building_avoidance_radius, respinge; 0 = ignorato). Presi una volta all'inizio della visita: in pochi giorni gli
# edifici non cambiano in modo che conti.
static func _collect_reaction_sources(visit: WildAnimalVisit, world: World, wild_rules: AnimalRules) -> void:
	visit.reaction_points.clear()
	visit.reaction_radii.clear()
	visit.shelter_rects.clear()
	visit.safe_points.clear()
	visit.safe_radii.clear()
	visit.building_reaction_count = 0
	visit.building_safe_count = 0
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
			visit.safe_radii.append(FEAR_SAFE_RADIUS)
	visit.building_reaction_count = visit.reaction_points.size()
	visit.building_safe_count = visit.safe_points.size()
	if not visit.reaction_points.is_empty():
		print("[WILD ANIMAL VISITS] %s: %d edifici a cui reagire" % [visit.species, visit.reaction_points.size()])


# Tiro d'attacco della visita (vedi il commento delle costanti d'attacco): fatto una volta sola, appena il branco nota
# qualcuno che può caricare. Ritorna il bersaglio se il tiro riesce, null altrimenti (o se non c'è ancora nessuno).
static func _find_attack_target(visit: WildAnimalVisit, individuals: Array[HumanIndividual], game_data: GameData) -> HumanIndividual:
	if visit.attack_rolled or visit.attack_wolves <= 0 or visit.attack_aggression <= 0.0 or individuals.is_empty():
		return null
	var candidates: Array[HumanIndividual] = []
	for member in individuals:
		if member.home_macro_coords == visit.macro_coords and _is_noticed(visit, member) \
				and not _in_fear_zone(visit, member.position):
			candidates.append(member)
	if candidates.is_empty():
		return null
	visit.attack_rolled = true
	var profile := DangerFleeService.get_profile(DANGER_PROFILE)
	var defense_radius: float = profile.drive_off_radius if profile != null else MAX_NOTICE_RADIUS
	# Chi può difendere: fuori dagli edifici, nella macrocella. Forza presa una volta sola per persona.
	var defenders: Array[HumanIndividual] = []
	var strengths: Array[float] = []
	for member in individuals:
		if member.home_macro_coords == visit.macro_coords \
				and not visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(member.position)):
			defenders.append(member)
			strengths.append(_person_strength(member, game_data))
	# Cani di guardia (passo 8.2): pesano nella difesa di chi sta entro il loro guard_help_radius.
	var dogs := DomesticAnimalGuardService.guard_dogs(game_data, visit.macro_coords)
	var target: HumanIndividual = null
	var target_chance := -1.0
	var target_defense := 0.0
	var candidate_texts: PackedStringArray = []
	for candidate in candidates:
		var defense := 0.0
		var nearby := 0
		for k in range(defenders.size()):
			if defenders[k].position.distance_to(candidate.position) <= defense_radius:
				defense += strengths[k]
				nearby += 1
		var dog_defense := DomesticAnimalGuardService.defense_near(dogs, candidate.position)
		defense += float(dog_defense["strength"])
		defense = maxf(defense, WEAK_PERSON_STRENGTH)
		var chance := minf(ATTACK_CHANCE_CAP,
			ATTACK_BASE_CHANCE * visit.attack_aggression / 100.0 * float(visit.attack_wolves) / defense)
		var age_band := HumanIndividualActionService._resolve_age_band(candidate, game_data)
		candidate_texts.append("#%d %s %s%s difesa %.1f (%d persone, %d cani) %d%%" % [candidate.id, candidate.name,
			String(HumanTypes.AgeBand.keys()[age_band]).to_lower(),
			" ferito/malato" if not candidate.health_conditions.is_empty() else "", defense, nearby, int(dog_defense["count"]),
			roundi(chance * 100.0)])
		if chance > target_chance:
			target = candidate
			target_chance = chance
			target_defense = defense
	var roll := randf()
	print("[WILD ANIMAL VISITS] %s: tiro d'attacco (%s) su #%d %s — aggressività media %d, %d lupi contro difesa %.1f -> %d%%, uscito %d -> %s" % [
		visit.species, "in arrivo" if visit.phase == WildAnimalVisit.Phase.ARRIVING else "in sosta", target.id, target.name,
		roundi(visit.attack_aggression), visit.attack_wolves, target_defense, roundi(target_chance * 100.0),
		roundi(roll * 100.0), "caricano" if roll < target_chance else "non attaccano in questa visita"])
	print("[WILD ANIMAL VISITS]   bersaglio: il notato con la probabilità più alta (il debole più isolato; difesa = lui e chi gli sta entro %.0f microcelle fuori dagli edifici); notati caricabili: %s" % [
		defense_radius, ", ".join(candidate_texts)])
	return target if roll < target_chance else null


# Notata dal branco: nel raggio di un presente (notice_radii), in linea retta (_is_line_clear) e fuori dagli edifici.
# Controlli dal più economico (2026-10-31): la distanza scarta quasi tutti, gli edifici si guardano solo per chi resta.
static func _is_noticed(visit: WildAnimalVisit, member: HumanIndividual) -> bool:
	for i in range(visit.animal_ids.size()):
		var radius: float = visit.notice_radii[i] if i < visit.notice_radii.size() else MIN_NOTICE_RADIUS
		var animal_position := get_animal_position(visit, i)
		if animal_position.distance_squared_to(member.position) <= radius * radius \
				and _is_line_clear(visit, animal_position, member.position):
			return not visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(member.position))
	return false


# Quanto una persona scoraggia il branco: 1 un adulto sano, WEAK_PERSON_STRENGTH un bambino, un ragazzo, un ferito o un
# malato (qualunque condizione di salute in corso).
static func _person_strength(member: HumanIndividual, game_data: GameData) -> float:
	var age_band := HumanIndividualActionService._resolve_age_band(member, game_data)
	if age_band == HumanTypes.AgeBand.INFANT or age_band == HumanTypes.AgeBand.CHILD or age_band == HumanTypes.AgeBand.TEENAGER:
		return WEAK_PERSON_STRENGTH
	return WEAK_PERSON_STRENGTH if not member.health_conditions.is_empty() else 1.0


# Al sicuro: al riparo in un edificio completato (shelter_rects) o in una zona sicura (_in_fear_zone).
static func _is_safe(visit: WildAnimalVisit, point: Vector2) -> bool:
	return visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(point)) or _in_fear_zone(visit, point)


# Entro il raggio di una zona sicura (safe_points/safe_radii: il focolare, i cani di guardia).
static func _in_fear_zone(visit: WildAnimalVisit, point: Vector2) -> bool:
	for i in range(visit.safe_points.size()):
		if visit.safe_points[i].distance_to(point) <= visit.safe_radii[i]:
			return true
	return false


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


# Parte la carica. La persona caricata scappa (L5a, DangerFleeService, profilo DANGER_PROFILE): il pericolo ha l'id del gruppo (una visita alla volta
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
	var nearest_wolf := _nearest_wolf(visit, target.position)
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
	# Cani di guardia (passo 8.2): corrono comunque tutti; nella scelta di chi chiamare stanno in fila con le persone, per
	# distanza (2026-11-07, decisione utente).
	var dogs := DomesticAnimalGuardService.start_run(visit, game_data, target.position)
	visit.drive_off_threats = wolf_positions.size()
	var drive_off := DangerFleeService.start_drive_off(individuals, target, DANGER_PROFILE, visit.group_id,
		wolf_positions, can_help, game_data, dogs)
	visit.defender_ids = drive_off["helper_ids"]
	visit.defenders_needed = int(drive_off["needed"]) if not visit.defender_ids.is_empty() else 0


# Inseguimento: ognuno va dritto verso la persona (comportamento CHASE) alternando balzi a hop_speed e pause, come la
# fauna, con la sua collisione; in media un po' più veloce di chi corre. Il primo che arriva a ATTACK_CONTACT_DISTANCE morde
# (_on_attack_contact), poi tutti fermi per BITE_PAUSE_DAYS. Fine: vedi il commento delle costanti d'attacco.
static func _charge(visit: WildAnimalVisit, wild_rules: AnimalRules, delta: float, individuals: Array[HumanIndividual],
		game_data: GameData, world: World, folk: Folk, effects: GameEffects) -> void:
	var target := _find_individual(individuals, visit.attack_target_id)
	visit.charge_remaining -= delta
	DomesticAnimalGuardService.update_run(visit, game_data)
	# Scontro dei cani col branco (passo 8.4); ucciso l'ultimo presente, la visita è già tolta.
	if DomesticAnimalGuardService.resolve_clashes(visit, game_data, individuals, effects) or visit.animal_ids.is_empty():
		DomesticAnimalGuardService.end_run(visit, game_data, world)
		return
	var end_reason := ""
	if target == null:
		end_reason = "persona sparita"
	elif target.home_macro_coords != visit.macro_coords:
		end_reason = "persona uscita dalla macrocella"
	elif visit.shelter_rects.any(func(rect: Rect2) -> bool: return rect.has_point(target.position)):
		end_reason = "persona al riparo in un edificio"
	elif _drive_off_ready(visit, individuals, game_data):
		visit.drive_off_shouting += delta
		var profile := DangerFleeService.get_profile(DANGER_PROFILE)
		if profile == null or visit.drive_off_shouting >= profile.drive_off_shout_days:
			_on_driven_off(visit, individuals, game_data, effects)
			_end_charge(visit, individuals, game_data, world, folk, effects)
		# Davanti al gruppo che grida il branco resta fermo: niente inseguimento né morsi.
		_hold_bodies(visit)
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
	# Arrivato dove era corso via, senza riparo e coi lupi ancora dietro: sceglie di nuovo (DangerFleeService).
	visit.redirect_cooldown -= delta
	if visit.redirect_cooldown <= 0.0 and DangerFleeService.needs_new_escape(target, visit.group_id):
		_redirect_flight(visit, target, world, game_data)
	if visit.charge_pause > 0.0:
		visit.charge_pause -= delta
		_hold_bodies(visit)
		return
	if visit.body_ids.is_empty():
		return
	for i in range(visit.animal_ids.size()):
		var distance := get_animal_position(visit, i).distance_to(target.position)
		visit.charge_min_distance = minf(visit.charge_min_distance, distance)
		if distance <= ATTACK_CONTACT_DISTANCE:
			_on_attack_contact(visit, target, game_data, effects)
			visit.charge_pause = BITE_PAUSE_DAYS
			_hold_bodies(visit)
			# Morso allo scoperto: approfitta della pausa per scegliere di nuovo dove scappare.
			if DangerFleeService.needs_new_escape(target, visit.group_id, false):
				_redirect_flight(visit, target, world, game_data)
			return
	for body_id in visit.body_ids:
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body != null:
			body.behavior_point = target.position


# Tutti fermi dove sono: il bersaglio dell'inseguimento diventa la propria posizione.
static func _hold_bodies(visit: WildAnimalVisit) -> void:
	for body_id in visit.body_ids:
		var body := AnimalGroupRenderer.find_live_individual(body_id)
		if body != null:
			body.behavior_point = body.position


# Il presente più vicino a `point`.
static func _nearest_wolf(visit: WildAnimalVisit, point: Vector2) -> Vector2:
	var nearest := get_animal_position(visit, 0)
	for i in range(1, visit.animal_ids.size()):
		var animal_position := get_animal_position(visit, i)
		if animal_position.distance_to(point) < nearest.distance_to(point):
			nearest = animal_position
	return nearest


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


# Il caricato sceglie di nuovo dove scappare (DangerFleeService.needs_new_escape), lontano dal presente più vicino.
static func _redirect_flight(visit: WildAnimalVisit, target: HumanIndividual, world: World, game_data: GameData) -> void:
	visit.redirect_cooldown = REDIRECT_COOLDOWN_DAYS
	DangerFleeService.start_flee(target, DANGER_PROFILE, visit.group_id, _nearest_wolf(visit, target.position), visit.safe_points, world,
		game_data, true)


# Cacciata pronta (passo 8.2, persone e cani insieme): arrivati almeno DangerProfile.drive_off_min_helpers aiutanti
# (persona 1, cane guard_helper_weight), che coprono tutti i presenti alla carica (persona drive_off_threats_per_helper,
# cane guard_threats_per_dog). Con le sole persone è la regola di prima.
static func _drive_off_ready(visit: WildAnimalVisit, individuals: Array[HumanIndividual], game_data: GameData) -> bool:
	if visit.defender_ids.is_empty() and visit.guard_dog_ids.is_empty():
		return false
	var profile := DangerFleeService.get_profile(DANGER_PROFILE)
	if profile == null:
		return false
	var people := _defenders_arrived(visit, individuals)
	var dogs := DomesticAnimalGuardService.arrived_support(visit, game_data)
	var threats := visit.drive_off_threats if visit.drive_off_threats > 0 else visit.animal_ids.size()
	return float(people) + float(dogs["helpers"]) >= float(profile.drive_off_min_helpers) - 0.001 		and people * profile.drive_off_threats_per_helper + int(dogs["threats"]) >= threats


# Aiutanti arrivati: corsa finita (gridano sul posto) o entro DRIVE_OFF_GIVE_UP_DISTANCE da un presente.
static func _defenders_arrived(visit: WildAnimalVisit, individuals: Array[HumanIndividual]) -> int:
	if visit.defender_ids.is_empty():
		return 0
	var arrived := 0
	for defender_id in visit.defender_ids:
		var member := _find_individual(individuals, defender_id)
		if member == null or not DangerFleeService.is_fleeing_from(member, visit.group_id):
			continue
		if DangerFleeService.has_reached_danger(member, visit.group_id):
			arrived += 1
			continue
		for i in range(visit.animal_positions.size()):
			if visit.animal_positions[i].distance_to(member.position) <= DRIVE_OFF_GIVE_UP_DISTANCE:
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
	if not visit.guard_dog_ids.is_empty():
		names.append(GameContext.tr_text("wild_animal_driven_off_dogs").format({"count": visit.guard_dog_ids.size()}))
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
	DomesticAnimalGuardService.end_run(visit, game_data, world)
	apply_visit_outcome(visit, game_data, world, folk, effects)
	_start_leaving(visit, world)


# Esito della visita, unico punto (lupi L3, 2026-10-30): chiamato a fine sosta, prima della partenza. Visita tranquilla:
# punti addomesticazione alla specie domestica che deriva da questa selvatica (POINTS_PER_ANIMAL_* per adulto presente,
# YOUNG_POINTS_SHARE per giovane, la parte
# decimale messa da parte in WildAnimalGroup.pending_domestication_points) e −AGGRESSION_DROP_PER_VISIT a ogni presente.
# Visita con attacco (L4): niente punti né calma. Una visita in cui gli hanno tirato (L7) non arriva qui.
static func apply_visit_outcome(visit: WildAnimalVisit, game_data: GameData, world: World, folk: Folk,
		effects: GameEffects) -> void:
	if visit.attacked:
		print("[WILD ANIMAL VISITS] %s: visita con attacco, niente punti né calma" % visit.species)
		return
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return
	var at_pit := visit.target_kind == WildAnimalVisit.TargetKind.PIT
	var per_animal := POINTS_PER_ANIMAL_FULL_PIT if at_pit else POINTS_PER_ANIMAL_OTHERWISE
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
	var domestic_rules := DomesticAnimalCalculator.get_rules(domestic_species)
	# Dopo il primo arrivo dei cani i lupi restano un pericolo, ma senza più punti.
	if domestic_rules != null and not DomesticAnimalService.is_domesticated(game_data, domestic_species):
		group.pending_domestication_points += visit_points
		whole_points = int(floor(group.pending_domestication_points))
		group.pending_domestication_points -= whole_points
		if whole_points > 0:
			DomesticationPointsService.add_points(game_data, folk, domestic_species, whole_points, effects)
	print("[WILD ANIMAL VISITS] %s: visita tranquilla (%s), %d presenti, %.2f punti (adulto %.1f, giovane metà) -> +%d punti %s (resto %.2f), aggressività -%d a %s" % [
		group.species,
		"alla fossa" if at_pit else "al magazzino",
		present.size(), visit_points, per_animal, whole_points, domestic_species, group.pending_domestication_points,
		roundi(AGGRESSION_DROP_PER_VISIT),
		", ".join(present.map(func(animal: WildAnimal) -> String: return "#%d (%d)" % [animal.id, roundi(animal.aggression)]))])
	if domestic_rules != null:
		_release_domestic_arrivals(visit, group, domestic_rules, wild_rules, game_data, world, effects)
	if at_pit and not group.notified_first_quiet_pit:
		group.notified_first_quiet_pit = true
		_notify_group(effects, "notification_wild_first_quiet_pit_%s" % group.species)
	_notify_calmer(group, effects)


# Arrivi dal branco (cane, passo 2, 2026-11-03, richiesta utente: tutti insieme): da una visita tranquilla con i punti alla
# soglia, i più calmi del branco diventano gli animali domestici che mancano. Chi manca perché il branco non ha candidati, o
# perché ne è morto uno, arriva alla visita tranquilla successiva. Sesso e nascita restano quelli del lupo.
static func _release_domestic_arrivals(visit: WildAnimalVisit, group: WildAnimalGroup, rules: DomesticAnimalRules,
		wild_rules: AnimalRules, game_data: GameData, world: World, effects: GameEffects) -> void:
	if not rules.individuals_enabled:
		return
	if DomesticationPointsService.get_points(game_data, rules.species_name) < rules.domestication_points_required:
		return
	# Solo il primo arrivo viene dal branco (2026-11-06): poi i rimpiazzi arrivano da fuori (DomesticAnimalLifeService).
	if DomesticAnimalService.is_domesticated(game_data, rules.species_name):
		return
	var storage := WildAnimalGroupService.find_anchor_storage(world)
	var village_id := storage.village_id if storage != null else -1
	var today := game_data.get_absolute_day()
	var arrived := 0
	for is_male: bool in [true, false]:
		for i in range(DomesticAnimalService.missing_for_arrival(game_data, rules, is_male)):
			# L'ultimo presente resta: una visita senza nessuno non può uscire.
			var excluded_id := visit.animal_ids[0] if visit.animal_ids.size() == 1 else -1
			var leaver := WildAnimalGroupService.pick_calmest_leaver(group, is_male, today, wild_rules, excluded_id)
			if leaver == null:
				break
			var arrival := DomesticAnimalService.add_animal(game_data, rules.species_name, leaver.is_male, leaver.birth_day, village_id)
			# Chi era in visita resta dove si trovava; gli altri li piazza vicino al magazzino DomesticAnimalBodyService.
			var visit_index := visit.animal_ids.find(leaver.id)
			if arrival != null and visit_index >= 0:
				arrival.macro_coords = visit.macro_coords
				arrival.position = get_animal_position(visit, visit_index)
			group.animals.erase(leaver)
			_leave_visit(visit, leaver.id)
			arrived += 1
	if arrived > 0:
		game_data.domestic_first_arrival_day[rules.species_name] = today
		print("[WILD ANIMAL VISITS] %s: %d lasciano il branco per diventare %s, nel branco ne restano %d" % [
			group.species, arrived, rules.species_name, group.animals.size()])
		_notify_group(effects, "notification_domestic_arrival_%s" % rules.species_name, {"count": arrived})


# Toglie dalla visita un animale uscito dal branco, col suo corpo se è sulla mappa. Nessun effetto se non era presente.
static func _leave_visit(visit: WildAnimalVisit, animal_id: int) -> void:
	var index := visit.animal_ids.find(animal_id)
	if index < 0:
		return
	if index < visit.body_ids.size() and visit.body_ids[index] != 0:
		AnimalGroupRenderer.remove_live_individual(visit.body_ids[index])
	_remove_from_visit_arrays(visit, index)


# Messaggi al giocatore (2026-11-01, richiesta utente: deve capire che il branco si abitua e che cacciarlo costa). Testi
# senza numeri né punti; una chiave per specie (notification_wild_<evento>_<specie>). Le visite tranquille normali restano
# senza messaggio.
static func _notify_group(effects: GameEffects, text_key: String, values: Dictionary = {}) -> void:
	if effects != null:
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS, GameContext.tr_text(text_key).format(values))


# Prima visita del branco e tentativo di caccia in questa visita (il tiro nasce in ThrowAction, che non ha gli effetti).
static func _notify_visit_news(visit: WildAnimalVisit, game_data: GameData, effects: GameEffects) -> void:
	var group := _find_group(game_data, visit.group_id)
	if group == null:
		return
	if not group.notified_first_visit:
		group.notified_first_visit = true
		_notify_group(effects, "notification_wild_first_visit_%s" % group.species)
	if visit.hunted and not visit.hunted_notified:
		visit.hunted_notified = true
		_notify_group(effects, "notification_wild_hunted_%s" % group.species)


# Aggressività media scesa sotto una soglia nuova, più bassa di quelle già annunciate: se risale e riscende non si ripete.
static func _notify_calmer(group: WildAnimalGroup, effects: GameEffects) -> void:
	if group.animals.is_empty():
		return
	var total := 0.0
	for animal in group.animals:
		total += animal.aggression
	var average := total / float(group.animals.size())
	for threshold in CALM_NOTICE_THRESHOLDS:
		if average < float(threshold) and threshold < group.notified_calm_below:
			group.notified_calm_below = threshold
			_notify_group(effects, "notification_wild_calmer_%s" % group.species)
			return


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
	# Dopo la sosta o la carica sono sparsi: l'uscita si sceglie dall'animale più vicino alla loro media (una microcella
	# libera, dove qualcuno sta davvero).
	visit.position = _nearest_wolf(visit, visit.position)
	# Uscita dalla parte libera come l'ingresso, ma il branco scacciato scappa dal bordo più vicino.
	var exit: Variant = VisitorService.find_border_point(world, visit.macro_coords, visit.position,
		Vector2i(visit.position.floor())) if visit.driven_off or visit.hunted \
		else _pick_quiet_border_point(world, visit.macro_coords, visit.position, visit.pit_building_id)
	visit.target_point = exit if exit != null else visit.entry_point
	visit.phase = WildAnimalVisit.Phase.LEAVING
	print("[WILD ANIMAL VISITS] %s: se ne vanno" % visit.species)


# DEBUG — riga per il tooltip della DebugBar: giorni dall'ultima visita, attesa e dado delle visite spontanee.
static func debug_dice_line(game_data: GameData, world: World, group: WildAnimalGroup, villagers: int) -> String:
	var today := game_data.get_absolute_day()
	if group.animals.is_empty():
		return "Visite: nessun animale, nuovo gruppo tra %d giorni" % (group.new_pack_day - today)
	var last_text := "ultima %d giorni fa" % (today - group.last_visit_end_day) if group.last_visit_end_day >= 0 else "nessuna finita"
	var faces := visit_dice_faces(world, villagers, game_data, group)
	var dice_text := "dado da %.1f facce (%.1f%% al giorno)" % [faces, 100.0 / faces] if faces > 0.0 else "nessun dado (%d abitanti)" % villagers
	var wait_text := ", attesa ancora %d giorni" % (group.next_visit_day - today) if today < group.next_visit_day else ""
	return "Visite: %s, %s%s" % [last_text, dice_text, wait_text]


# DEBUG — riga per il tooltip della DebugBar: fase e animali presenti.
static func debug_line(visit: WildAnimalVisit) -> String:
	var phase_names := ["in arrivo", "fermi", "se ne vanno", "caricano"]
	return "In visita (%s, %s): %s" % [phase_names[visit.phase],
		"fossa" if visit.target_kind == WildAnimalVisit.TargetKind.PIT else "magazzino",
		", ".join(visit.animal_ids.map(func(animal_id: int) -> String: return "#%d" % animal_id))]
