class_name WildAnimalVisit
extends RefCounted

# Visita di un gruppo di animali selvatici al villaggio (2026-10-28, richiesta utente — lupi passo L1): una parte del
# WildAnimalGroup entra dal bordo della macrocella del villaggio, va alla Fossa più piena (o al magazzino del
# villaggio se non c'è una Fossa), resta un poco ed esce. Dato di partita in GameData.wild_animal_visits, salvato
# (vedi to_save_data). Copione in WildAnimalVisitService.advance; dal 2026-11-01 (passo 7b) gli animali sono corpi di un
# AnimalGroupRenderer solo per la visita (GameScene._sync_wild_animal_visit_bodies), che li muove col comportamento
# assegnato dal copione.
#
# Coordinate: microcella continue, locali a `macro_coords` (come VisitorParty).

# CHARGING (lupi L4, 2026-10-30): il branco carica una persona entrata nel raggio d'attacco di un presente. In coda.
enum Phase { ARRIVING, STAYING, LEAVING, CHARGING }
enum TargetKind { PIT, STORAGE }

var group_id: int = 0
var species: String = ""
var phase: Phase = Phase.ARRIVING
var target_kind: TargetKind = TargetKind.STORAGE
# Fossa meta della visita (id dell'edificio), -1 se la meta è il magazzino.
var pit_building_id: int = -1
var macro_coords: Vector2i = Vector2i(-1, -1)
# Centro del gruppo: media dei presenti, aggiornata a ogni mossa (suoni, uscita).
var position: Vector2 = Vector2.ZERO
var entry_point: Vector2 = Vector2.ZERO
# Meta corrente: la Fossa o il magazzino in ARRIVING, il bordo in LEAVING.
var target_point: Vector2 = Vector2.ZERO
# Punto da guardare durante la sosta (la Fossa o il centro del villaggio).
var look_point: Vector2 = Vector2.ZERO
# Sosta rimasta, in giorni di gioco.
var stay_remaining: float = 0.0
# Animali presenti (id dei WildAnimal del gruppo) e loro posizione (microcelle), stessi indici: copiata dai corpi a ogni
# mossa, è quello che si salva e da dove i corpi ripartono se vengono ricreati.
var animal_ids: Array[int] = []
var animal_positions: Array[Vector2] = []
# Salute dei presenti, stessi indici (lupi L7, 2026-11-01): copiata dai corpi come le posizioni, così la ferita resta dopo
# un salvataggio. Vale solo per questa visita: tra una visita e l'altra il lupo guarisce. Vuoto = tutti sani.
var animal_healths: Array[float] = []
# Corpi nel renderer (AnimalVisualGroup.id), stessi indici; vuoto = corpi non ancora creati o cella non viva; 0 = uscito
# dal bordo. Li crea WildAnimalVisitService.spawn_bodies. Mai salvati.
var body_ids: Array[int] = []
# Fase per cui i corpi hanno già il comportamento (-1 nessuna, WildAnimalVisitService._assign_behaviors). Mai salvata.
var assigned_phase: int = -1
# Meta irraggiungibile già segnalata nel log. Mai salvato.
var target_redirected: bool = false
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
# Tiro d'attacco (2026-10-31, uno per visita): aggressività media e numero dei presenti senza i cuccioli, presi
# all'inizio della visita, e tiro già fatto.
var attack_aggression: float = 0.0
var attack_wolves: int = 0
var attack_rolled: bool = false
var attack_target_id: int = -1
var charge_remaining: float = 0.0
# Distanza minima raggiunta da un presente durante la carica (microcelle), per il log di una carica senza contatto.
var charge_min_distance: float = INF
# Distanza del presente più vicino alla persona all'inizio della carica (microcelle), per il log.
var charge_start_distance: float = 0.0
# Inseguimento (lupi L5b, 2026-10-30): pausa rimasta dopo un morso (giorni) e morsi dati in questa carica.
var charge_pause: float = 0.0
var bites: int = 0
# Attesa prima di far scegliere di nuovo la fuga allo scoperto al caricato (giorni; WildAnimalVisitService). Mai salvata.
var redirect_cooldown: float = 0.0
# Scacciati in gruppo (lupi L6.1, 2026-10-30): chi corre contro il branco (id degli HumanIndividual), quanti ne servono
# perché rinunci (0 = nessuno interviene) e branco scacciato (se ne va di corsa).
var defender_ids: Array[int] = []
var defenders_needed: int = 0
var driven_off: bool = false
# Gli hanno tirato (lupi L7, 2026-11-01): il branco se ne va di corsa, senza punti né calma (WildAnimalVisitService.on_member_shot_at).
var hunted: bool = false
# Il messaggio "hanno tentato di cacciarlo" di questa visita è già stato dato.
var hunted_notified: bool = false
# Tempo (giorni) in cui quanti servono hanno gridato insieme davanti al branco (DangerProfile.drive_off_shout_days).
var drive_off_shouting: float = 0.0
# Ringhio della carica già suonato (GameScene.wild_animal_charged): una volta sola.
var charge_announced: bool = false
# Grido di chi l'ha scacciato già suonato (GameScene.wild_animal_driven_off): una volta sola.
var driven_off_announced: bool = false
var attacked: bool = false
# Arrivo già annunciato (ululato alla meta, GameScene.wild_animal_arrived): una volta sola per visita.
var arrival_announced: bool = false

# Da ricostruire alla prima mossa dopo il caricamento (WildAnimalVisitService._restore_after_load): collisione, edifici
# a cui reagire, animali usciti dal branco nel frattempo. Mai salvato.
var needs_restore: bool = false


# Salvataggio (2026-10-30, richiesta utente — visite e fughe salvate): lo stato che non si ricalcola. Collisione, corpi
# ed edifici (reazioni, ripari, zone del fuoco) si ricostruiscono al caricamento. Vettori come [x, y].
func to_save_data() -> Dictionary:
	return {
		"group_id": group_id, "species": species, "phase": phase, "target_kind": target_kind,
		"pit_building_id": pit_building_id, "macro_coords": _pair(Vector2(macro_coords)),
		"position": _pair(position), "entry_point": _pair(entry_point),
		"target_point": _pair(target_point), "look_point": _pair(look_point), "stay_remaining": stay_remaining,
		"animal_ids": animal_ids, "animal_positions": animal_positions.map(_pair), "animal_healths": animal_healths, "notice_radii": notice_radii,
		"attack_aggression": attack_aggression, "attack_wolves": attack_wolves, "attack_rolled": attack_rolled,
		"attack_target_id": attack_target_id, "charge_remaining": charge_remaining,
		"charge_min_distance": charge_min_distance if is_finite(charge_min_distance) else -1.0,
		"charge_start_distance": charge_start_distance, "charge_pause": charge_pause, "bites": bites,
		"attacked": attacked, "arrival_announced": arrival_announced,
		"defender_ids": defender_ids, "defenders_needed": defenders_needed, "driven_off": driven_off, "hunted": hunted, "hunted_notified": hunted_notified, "drive_off_shouting": drive_off_shouting, "driven_off_announced": driven_off_announced, "charge_announced": charge_announced,
	}


static func from_save_data(data: Dictionary) -> WildAnimalVisit:
	var visit := WildAnimalVisit.new()
	visit.group_id = int(data.get("group_id", 0))
	visit.species = String(data.get("species", ""))
	visit.phase = int(data.get("phase", Phase.ARRIVING)) as Phase
	visit.target_kind = int(data.get("target_kind", TargetKind.STORAGE)) as TargetKind
	visit.pit_building_id = int(data.get("pit_building_id", -1))
	visit.macro_coords = Vector2i(_vector(data.get("macro_coords")))
	visit.position = _vector(data.get("position"))
	visit.entry_point = _vector(data.get("entry_point"))
	visit.target_point = _vector(data.get("target_point"))
	visit.look_point = _vector(data.get("look_point"))
	visit.stay_remaining = float(data.get("stay_remaining", 0.0))
	for value in data.get("animal_ids", []):
		visit.animal_ids.append(int(value))
	for value in data.get("animal_positions", []):
		visit.animal_positions.append(_vector(value))
	# Salvataggi di prima del passo 7b.1: centro + posto nella formazione.
	if visit.animal_positions.is_empty():
		var frame_angle := _vector(data.get("facing_direction")).angle()
		for value in data.get("offsets", []):
			visit.animal_positions.append(visit.position + _vector(value).rotated(frame_angle))
	for value in data.get("animal_healths", []):
		visit.animal_healths.append(float(value))
	for value in data.get("notice_radii", []):
		visit.notice_radii.append(float(value))
	visit.attack_aggression = float(data.get("attack_aggression", 0.0))
	visit.attack_wolves = int(data.get("attack_wolves", 0))
	visit.attack_rolled = bool(data.get("attack_rolled", false))
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
	visit.hunted = bool(data.get("hunted", false))
	visit.hunted_notified = bool(data.get("hunted_notified", false))
	visit.drive_off_shouting = float(data.get("drive_off_shouting", 0.0))
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
