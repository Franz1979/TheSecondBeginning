class_name WildAnimalVisit
extends RefCounted

# Visita di un gruppo di animali selvatici al villaggio (2026-10-28, richiesta utente — lupi passo L1): una parte del
# WildAnimalGroup entra dal bordo della macrocella del villaggio, va alla Fossa più piena (o in un punto ai margini del
# villaggio se non c'è una Fossa), resta un poco ed esce. Dato di partita in GameData.wild_animal_visits, NON salvato
# (L1): al caricamento la visita sparisce. Movimento in WildAnimalVisitService.advance, disegno in WildAnimalVisitView.
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
