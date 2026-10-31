class_name WildAnimalVisit
extends RefCounted

# Visita di un gruppo di animali selvatici al villaggio (2026-10-28, richiesta utente — lupi passo L1): una parte del
# WildAnimalGroup entra dal bordo della macrocella del villaggio, va alla Fossa più piena (o in un punto ai margini del
# villaggio se non c'è una Fossa), resta un poco ed esce. Dato di partita in GameData.wild_animal_visits, salvato
# (vedi to_save_data). Movimento in WildAnimalVisitService.advance, disegno in WildAnimalVisitView.
#
# Coordinate: microcella continue, locali a `macro_coords` (come VisitorParty).

# CHARGING (lupi L4, 2026-10-30): il branco carica una persona entrata nel raggio d'attacco di un presente. In coda.
enum Phase { ARRIVING, STAYING, LEAVING, CHARGING }
enum TargetKind { PIT, VILLAGE_EDGE }

var group_id: int = 0
var species: String = ""
var phase: Phase = Phase.ARRIVING
var target_kind: TargetKind = TargetKind.VILLAGE_EDGE
# Fossa meta della visita (id dell'edificio), -1 ai margini del villaggio.
var pit_building_id: int = -1
var macro_coords: Vector2i = Vector2i(-1, -1)
# Centro del gruppo e direzione di marcia.
var position: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var entry_point: Vector2 = Vector2.ZERO
# Meta corrente: la Fossa o il punto ai margini in ARRIVING, il bordo in LEAVING.
var target_point: Vector2 = Vector2.ZERO
# Punto da guardare durante la sosta (la Fossa o il centro del villaggio).
var look_point: Vector2 = Vector2.ZERO
# Sosta rimasta, in giorni di gioco.
var stay_remaining: float = 0.0
# Animali presenti (id dei WildAnimal del gruppo) e loro posto attorno al centro (microcelle, nel riferimento della
# direzione di marcia), stessi indici.
var animal_ids: Array[int] = []
var offsets: Array[Vector2] = []
# Posto di partenza nella formazione: in viaggio ogni animale ci torna piano (dopo la sosta erano sparsi).
var home_offsets: Array[Vector2] = []
# Sosta (2026-10-28): ogni animale gironzola da solo con i dati della specie (AnimalRules: alternanza movimento/riposo,
# deriva della direzione, raggio di raccolta). Direzione propria (angolo nel mondo), se si muove, tempo rimasto della
# fase. In viaggio la direzione è quella del gruppo.
var headings: Array[float] = []
var moving: Array[bool] = []
var phase_timers: Array[float] = []
# Balzo o pausa tra balzi, e tempo rimasto, come la fauna (2026-10-29 in sosta, 2026-10-30 anche in viaggio).
var hopping: Array[bool] = []
var hop_timers: Array[float] = []
# Sosta (2026-10-30): punto attorno alla meta verso cui l'animale va ad annusare (microcelle, nel mondo).
var sniff_points: Array[Vector2] = []
# Edifici a cui la specie reagisce durante la sosta (2026-10-29, AnimalRules.building_reactions), presi all'arrivo:
# posizione (microcelle) e raggio col segno (+ respinge, − attira), stessi indici.
var reaction_points: Array[Vector2] = []
var reaction_radii: Array[float] = []
# Riparo dagli attacchi (2026-10-30, lupi L4): pianta degli edifici completati della macrocella
# che proteggono chi ci sta (tutti tranne i calpestabili e quelli che attirano la specie), presi all'arrivo (microcelle).
var shelter_rects: Array[Rect2] = []
# Zone sicure (2026-10-30): centro degli edifici che la specie teme esplicitamente (building_reactions positivo: il
# focolare); entro WildAnimalVisitService.FEAR_SAFE_RADIUS non si attacca e la carica non entra.
var safe_points: Array[Vector2] = []
# Collisione con rocce, edifici e acqua durante la sosta: la stessa griglia della fauna
# (PathfindingService.blocked_test_for, Callable(Vector2i) -> bool), presa all'inizio della visita.
var blocked_test: Callable = Callable()
# Attacco (lupi L4, 2026-10-30): raggio in cui ogni presente nota le persone (microcelle, dalla sua aggressività
# all'inizio della visita; stessi indici), probabilità di caricare una persona notata (dal più aggressivo dei presenti),
# persone già tirate in questa visita (id dell'HumanIndividual -> true, un tiro solo a testa), persona caricata (-1
# nessuna), tempo rimasto alla carica (giorni) e visita con attacco (niente punti né calma,
# WildAnimalVisitService.apply_visit_outcome).
var notice_radii: Array[float] = []
var attack_chance: float = 0.0
var attack_rolled_ids: Dictionary = {}
var attack_target_id: int = -1
var charge_remaining: float = 0.0
# Distanza minima raggiunta da un presente durante la carica (microcelle), per il log di una carica senza contatto.
var charge_min_distance: float = INF
# Distanza del presente più vicino alla persona all'inizio della carica (microcelle), per il log.
var charge_start_distance: float = 0.0
# Inseguimento (lupi L5b, 2026-10-30): pausa rimasta dopo un morso (giorni) e morsi dati in questa carica.
var charge_pause: float = 0.0
var bites: int = 0
# Scacciati in gruppo (lupi L6.1, 2026-10-30): chi corre contro il branco (id degli HumanIndividual), quanti ne servono
# perché rinunci (0 = nessuno interviene) e branco scacciato (se ne va di corsa).
var defender_ids: Array[int] = []
var defenders_needed: int = 0
var driven_off: bool = false
# Ringhio della carica già suonato (GameScene.wild_animal_charged): una volta sola.
var charge_announced: bool = false
# Grido di chi l'ha scacciato già suonato (GameScene.wild_animal_driven_off): una volta sola.
var driven_off_announced: bool = false
var attacked: bool = false
# Scia del centro in viaggio (2026-10-30): ultimi punti percorsi (microcelle), dal più vecchio al più recente; chi ha
# il suo posto nella formazione dietro un ostacolo la segue (WildAnimalVisitService._follow_with_collision).
var trail: Array[Vector2] = []
# Arrivo già annunciato (ululato alla meta, GameScene.wild_animal_arrived): una volta sola per visita.
var arrival_announced: bool = false

# Percorso del centro (PathfindingService.find_path), come VisitorParty: ricalcolato al cambio di meta o di blocchi.
var path: Array[Vector2] = []
var path_target: Vector2 = Vector2.ZERO
var path_planned: bool = false
var path_block_version: int = -1
# Da ricostruire alla prima mossa dopo il caricamento (WildAnimalVisitService._restore_after_load): collisione, edifici
# a cui reagire, animali usciti dal branco nel frattempo. Mai salvato.
var needs_restore: bool = false


# Salvataggio (2026-10-30, richiesta utente — visite e fughe salvate): lo stato che non si ricalcola. Collisione,
# percorso, scia ed edifici (reazioni, ripari, zone del fuoco) si ricostruiscono al caricamento. Vettori come [x, y].
func to_save_data() -> Dictionary:
	return {
		"group_id": group_id, "species": species, "phase": phase, "target_kind": target_kind,
		"pit_building_id": pit_building_id, "macro_coords": _pair(Vector2(macro_coords)),
		"position": _pair(position), "facing_direction": _pair(facing_direction), "entry_point": _pair(entry_point),
		"target_point": _pair(target_point), "look_point": _pair(look_point), "stay_remaining": stay_remaining,
		"animal_ids": animal_ids, "offsets": offsets.map(_pair), "home_offsets": home_offsets.map(_pair),
		"headings": headings, "moving": moving, "phase_timers": phase_timers, "hopping": hopping,
		"hop_timers": hop_timers, "sniff_points": sniff_points.map(_pair), "notice_radii": notice_radii,
		"attack_chance": attack_chance, "attack_rolled_ids": attack_rolled_ids.keys(),
		"attack_target_id": attack_target_id, "charge_remaining": charge_remaining,
		"charge_min_distance": charge_min_distance if is_finite(charge_min_distance) else -1.0,
		"charge_start_distance": charge_start_distance, "charge_pause": charge_pause, "bites": bites,
		"attacked": attacked, "arrival_announced": arrival_announced,
		"defender_ids": defender_ids, "defenders_needed": defenders_needed, "driven_off": driven_off, "driven_off_announced": driven_off_announced, "charge_announced": charge_announced,
	}


static func from_save_data(data: Dictionary) -> WildAnimalVisit:
	var visit := WildAnimalVisit.new()
	visit.group_id = int(data.get("group_id", 0))
	visit.species = String(data.get("species", ""))
	visit.phase = int(data.get("phase", Phase.ARRIVING)) as Phase
	visit.target_kind = int(data.get("target_kind", TargetKind.VILLAGE_EDGE)) as TargetKind
	visit.pit_building_id = int(data.get("pit_building_id", -1))
	visit.macro_coords = Vector2i(_vector(data.get("macro_coords")))
	visit.position = _vector(data.get("position"))
	visit.facing_direction = _vector(data.get("facing_direction"))
	visit.entry_point = _vector(data.get("entry_point"))
	visit.target_point = _vector(data.get("target_point"))
	visit.look_point = _vector(data.get("look_point"))
	visit.stay_remaining = float(data.get("stay_remaining", 0.0))
	for value in data.get("animal_ids", []):
		visit.animal_ids.append(int(value))
	for value in data.get("offsets", []):
		visit.offsets.append(_vector(value))
	for value in data.get("home_offsets", []):
		visit.home_offsets.append(_vector(value))
	for value in data.get("headings", []):
		visit.headings.append(float(value))
	for value in data.get("moving", []):
		visit.moving.append(bool(value))
	for value in data.get("phase_timers", []):
		visit.phase_timers.append(float(value))
	for value in data.get("hopping", []):
		visit.hopping.append(bool(value))
	for value in data.get("hop_timers", []):
		visit.hop_timers.append(float(value))
	for value in data.get("sniff_points", []):
		visit.sniff_points.append(_vector(value))
	for value in data.get("notice_radii", []):
		visit.notice_radii.append(float(value))
	visit.attack_chance = float(data.get("attack_chance", 0.0))
	for value in data.get("attack_rolled_ids", []):
		visit.attack_rolled_ids[int(value)] = true
	visit.attack_target_id = int(data.get("attack_target_id", -1))
	visit.charge_remaining = float(data.get("charge_remaining", 0.0))
	var min_distance := float(data.get("charge_min_distance", -1.0))
	visit.charge_min_distance = min_distance if min_distance >= 0.0 else INF
	visit.charge_start_distance = float(data.get("charge_start_distance", 0.0))
	visit.charge_pause = float(data.get("charge_pause", 0.0))
	visit.bites = int(data.get("bites", 0))
	visit.attacked = bool(data.get("attacked", false))
	visit.arrival_announced = bool(data.get("arrival_announced", false))
	for value in data.get("defender_ids", []):
		visit.defender_ids.append(int(value))
	visit.defenders_needed = int(data.get("defenders_needed", 0))
	visit.driven_off = bool(data.get("driven_off", false))
	visit.driven_off_announced = bool(data.get("driven_off_announced", false))
	visit.charge_announced = bool(data.get("charge_announced", false))
	visit.needs_restore = true
	return visit


static func _pair(vector: Vector2) -> Array:
	return [vector.x, vector.y]


static func _vector(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
