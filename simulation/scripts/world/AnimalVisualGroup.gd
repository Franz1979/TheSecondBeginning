class_name AnimalVisualGroup
extends RefCounted

# Stato per-sessione (mai persistito) di un singolo individuo animale disegnato da
# AnimalGroupRenderer (individui animali step 1: un'istanza = un animale reale della quota di
# questa cella, non più un'icona che ne rappresenta visual_group_size): posizione in coordinate
# microcella (float, stesso spazio 0..100 di World) e direzione di marcia normalizzata.
#
# id: progressivo, assegnato UNA volta alla generazione (AnimalGroupRenderer._make_individual) e
# mai riassegnato — la riconciliazione con la popolazione rimuove per id, non per indice
# nell'array. 0 = nessuna identità: istanza usata come centro-cluster invisibile (vedi
# _make_random_group), mai un individuo. Non persistito: alla disattivazione della cella gli
# individui vengono scartati e alla riattivazione ne nascono di nuovi con id nuovi.
var id: int = 0
var species_name: String = ""
var position: Vector2
var direction: Vector2
# Indice nell'array _clusters di AnimalGroupRenderer verso cui questo individuo è attratto.
# Assegnato UNA volta alla nascita (AnimalGroupRenderer._make_individual) e poi fisso: cambia solo
# se quel centro viene rimosso (_reassign_orphaned_individuals). -1 = non ancora assegnato
# (individuo appena ricostruito da un salvataggio). Irrilevante quando l'istanza è usata essa
# stessa come centro-cluster, assegnato solo esternamente.
var cluster_index: int = 0
# Fascia d'età di QUESTO individuo (assegnata da AnimalGroupRenderer.
# set_population_by_age, o sempre ADULT per il fallback set_population non age-aware) — determina
# la scala visiva applicata in _write_instance_transform (AnimalRules.size_multiplier_by_age).
# Irrilevante quando l'istanza è usata come centro-cluster (mai disegnata, stesso trattamento di
# cluster_index sopra).
var age_band: GameTypes.AgeBand = GameTypes.AgeBand.ADULT
# Salute corrente (2026-09-26, richiesta utente — caccia, step 1: solo dati, nessun danno ancora).
# Parte dal massimo della specie scalato per la fascia d'età di QUESTO individuo (AnimalRules.
# max_health × size_multiplier_by_age[age_band], assegnato da AnimalGroupRenderer alla nascita).
# Vive quanto l'individuo: alla disattivazione della cella si perde con lui. Salvata e ricaricata
# con gli altri dati dell'individuo (caccia step 2, AnimalGroupRenderer.get_individuals_snapshot/
# restore_individuals). Irrilevante per i centri-cluster (id 0).
var health: float = 0.0
# Macrocella in cui l'individuo vive (2026-09-26, caccia step 2): la sua `position` è locale a questa
# cella. Copiata da AnimalGroupRenderer.macro_coords alla nascita/ricostruzione; serve a chi insegue
# l'individuo da un'altra cella (ApproachPreyAction) per convertirne la posizione. Un individuo non
# cambia mai macrocella (la posizione resta dentro 0..World.WIDTH/HEIGHT).
var macro_coords: Vector2i = Vector2i.ZERO

# Comportamento verso umani ed edifici (2026-09-26, richiesta utente — comportamento degli animali,
# step 2). Transitorio, mai salvato: si ricalcola da sé.
# Disagio: direzione in cui allontanarsi e intensità 0..1 (0 = nessun disagio), ricalcolate a ogni
# controllo periodico di AnimalGroupRenderer (_run_disturbance_check). Solo una spinta sulla direzione:
# balzi, velocità e pause restano quelli normali. Vale anche per i centri-cluster (id 0), così il
# gruppetto non richiama gli animali verso l'umano.
var avoid_direction: Vector2 = Vector2.ZERO
var avoid_weight: float = 0.0
# Fuga: giorni di gioco residui (0 = non in fuga) e direzione, impostati da un evento (un colpo di
# caccia, AnimalGroupRenderer.trigger_flee). Durante la fuga l'individuo corre dritto a hop_speed senza
# pause, poi torna al movimento normale.
var flee_timer: float = 0.0
var flee_direction: Vector2 = Vector2.ZERO

# Comportamento (2026-10-31, motore unico degli animali passo 7a): cosa vuole fare adesso l'individuo, assegnato da chi
# ne regge il copione (AnimalGroupRenderer.set_individual_behavior). Transitorio, mai salvato. La fuga resta
# un'interruzione sopra a qualsiasi comportamento (flee_timer sopra), finita la quale il comportamento riprende.
#   WANDER: il vagare a balzi di sempre attorno al proprio gruppetto (default, la fauna anonima resta così);
#   GO_TO: va a behavior_point a balzi seguendo un percorso A* (behavior_path), poi behavior_arrived;
#   STAND_AROUND: gira attorno a behavior_point, su punti dell'anello behavior_ring_min..max, fermandosi rivolto al
#     centro (annusare);
#   CHASE: insegue behavior_point, che il copione aggiorna a ogni frame (un bersaglio che si muove), a balzi e pause;
#     behavior_arrived quando è a contatto.
enum Behavior { WANDER, GO_TO, STAND_AROUND, CHASE }
var behavior: Behavior = Behavior.WANDER
var behavior_point: Vector2 = Vector2.ZERO
var behavior_ring_min: float = 0.0
var behavior_ring_max: float = 0.0
var behavior_arrived: bool = false
# Andatura (2026-11-01, passo 7b.1): fattore su hop_speed e, per GO_TO, di corsa senza pause tra i balzi.
var behavior_speed_scale: float = 1.0
var behavior_run: bool = false
# GO_TO: punti intermedi del percorso (PathfindingService.plan_waypoints) e per quale meta/versione dei blocchi.
var behavior_path: Array[Vector2] = []
var behavior_path_planned: bool = false
var behavior_path_target: Vector2 = Vector2.ZERO
var behavior_path_block_version: int = -1
# GO_TO che non avanza (2026-11-07, richiesta utente — lupo incastrato contro la Fossa): tempo dei balzi in cui la
# collisione lo ha tenuto quasi fermo; oltre la soglia il percorso si ricalcola dalla posizione vera, passando prima dal
# centro della sua microcella (behavior_replan_via_center). Vedi AnimalGroupRenderer._step_go_to.
var behavior_blocked_time: float = 0.0
var behavior_replan_via_center: bool = false
# STAND_AROUND: punto dell'anello verso cui sta andando e punto verso cui si gira da fermo (di norma il centro).
var behavior_stand_point: Vector2 = Vector2.ZERO
var behavior_look_point: Vector2 = Vector2.ZERO

# Identità facoltativa (2026-10-31, passo 7a): 0 = animale anonimo della fauna. Per un animale seguito per individuo
# (il branco, WildAnimalGroup/WildAnimal) gli id del gruppo e dell'animale.
var wild_group_id: int = 0
var wild_animal_id: int = 0
# Mandria che cambia cella (2026-11-01, passo 7c, AnimalGroupRenderer.start_herd_walk_in/start_herd_leaving): a piedi dal
# bordo o verso il bordo con GO_TO. Giorni di attesa prima di partire e giorni dopo cui la camminata finisce comunque.
enum HerdWalk { NONE, ENTERING, LEAVING }
var herd_walk: HerdWalk = HerdWalk.NONE
var herd_walk_delay: float = 0.0
var herd_walk_timer: float = 0.0

# Macchina a stati a due livelli per il movimento a balzi (vedi AnimalGroupRenderer). Rilevante
# solo per i gruppi disegnati, ignorata quando l'istanza è usata come centro-cluster (stesso
# trattamento di cluster_index sopra) — i centri-cluster vagano in modo continuo, non a balzi.
enum MacroPhase { MOVING, RESTING }
enum MicroPhase { HOPPING, HOP_PAUSE }
var macro_phase: MacroPhase = MacroPhase.MOVING
var macro_phase_timer: float = 0.0
var micro_phase: MicroPhase = MicroPhase.HOPPING
var micro_phase_timer: float = 0.0
# Questo periodo di movimento è uno scatto di corsa invece del passo (AnimalRules.run_phase_chance).
var running_phase: bool = false

func _init(_position: Vector2, _direction: Vector2) -> void:
	position = _position
	direction = _direction
