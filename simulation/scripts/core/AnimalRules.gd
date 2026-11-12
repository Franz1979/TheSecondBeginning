class_name AnimalRules
extends Resource

@export var species_name: String = ""
# Calorie di un individuo ADULTO, scalate per le altre fasce con size_multiplier_by_age: stima della ricchezza di una
# cella alla scelta della partenza (CellRichnessCalculator).
@export var prey_calories: float

# Resistenza di un individuo ADULTO della specie (2026-09-26, richiesta utente — caccia, step 1: solo
# dati). Scalata per le altre fasce d'età con size_multiplier_by_age (adult=1.0 è il riferimento),
# stesso principio di prey_calories sopra. Unità astratta, da tarare insieme a SecondaryResourceRules.
# attack_power degli attrezzi. Ogni specie la dichiara nel proprio .tres (partridge 8 … aurochs 50,
# proporzionata alla taglia). Letta oggi solo per inizializzare la salute corrente degli individui
# disegnati (AnimalVisualGroup.health, via AnimalGroupRenderer); nessuna logica di danno ancora.
@export var max_health: float = 0.0
# Moltiplicatore della probabilità di colpire un individuo della specie (2026-09-26, richiesta utente — prima
# era la costante unica HuntService.HIT_CHANCE_SCALE, 1.4 per tutte): >1 più facile, <1 più difficile. Usato
# da HuntService.compute_hit_chance. Negativo (default) = la specie non lo dichiara e vale
# HuntService.DEFAULT_HIT_CHANCE_SCALE.
@export var hit_chance_scale: float = -1.0
# Cacciatori al massimo per un individuo della specie (2026-11-10, richiesta utente, stesso schema di
# BuildingRules.max_builders). 1 (default) = caccia da soli; > 1 = preda grossa, cacciabile da più persone insieme
# (2026-11-11: la battuta di caccia è stata tolta; la regola dei più cacciatori sulla stessa preda è da decidere).
# Oggi lo legge solo il pulsante di debug 🦌+ (WildFaunaService.debug_spawn_small_herd).
@export var max_hunters: int = 1

@export_group("Butchering")
# Resa della macellazione di un individuo ADULTO della specie (2026-09-26, richiesta utente — macellazione,
# step 1: solo dati, nessuna logica li legge ancora), in unità delle risorse meat/hide/sinew/bone
# (simulation/data/secondary_resources/raw_materials/). Per le altre fasce d'età si scalano con size_multiplier_by_age
# (adulto = 1.0), come prey_calories. 0 = la specie non rende quella risorsa (es. una pernice non ha una pelle
# utile). Valori iniziali proporzionali alla taglia (carne ≈ prey_calories / 5), da tarare.
@export var butcher_meat_units: int = 0
@export var butcher_hide_units: int = 0
@export var butcher_sinew_units: int = 0
@export var butcher_bone_units: int = 0

@export_group("Behavior")
# Comportamento degli individui verso umani ed edifici (2026-09-26, richiesta utente — comportamento
# degli animali, step 1: SOLO i parametri, nessuna logica li legge ancora). Per specie, non per età.
# Distanze in MICROCELLE, stessa unità di AnimalVisualGroup.position/HumanIndividual.position.
# Entro questa distanza da un essere umano l'individuo si allontana con calma.
@export var discomfort_radius: float = 0.0
# Entro questa distanza da un essere umano l'individuo fugge davvero (tipicamente < discomfort_radius).
@export var flee_radius: float = 0.0
# Distanza a cui l'individuo tende a restare dagli edifici COMPLETI.
@export var building_avoidance_radius: float = 0.0
# Reattività al disagio (2026-09-26, richiesta utente — "fa parte del carattere dell'animale"): quanto
# ogni balzo piega la direzione verso "via dall'umano/edificio", a intensità piena (a contatto). Frazione
# 0..1 della rotazione, usata da AnimalGroupRenderer._apply_avoidance_on_hop. Negativo (default) = la
# specie non la dichiara e vale AnimalGroupRenderer.AVOID_BIAS_PER_HOP.
@export var avoidance_strength: float = -1.0
# Reazioni a edifici precisi (2026-10-29, richiesta utente): chiave = nome del file dell'edificio
# (Building.building_type_name, es. "campfire"), valore = raggio in microcelle col segno: positivo respinge (come
# building_avoidance_radius), negativo attira, 0 ignora. Gli edifici non elencati valgono building_avoidance_radius.
# Letto per ora solo dalle visite (WildAnimalVisitService._collect_reaction_sources, che le passa al renderer dei corpi),
# non dalla fauna del mondo.
@export var building_reactions: Dictionary = {}

@export_group("Visualization")
# Quanti individui rappresenta una singola icona/gruppo nella resa visiva animata (vedi
# AnimalGroupRenderer). Default 1 = rappresentazione 1:1, per compatibilità con specie che
# non lo impostano esplicitamente nel proprio .tres.
# NON PIÙ LETTO (individui animali step 1): AnimalGroupRenderer disegna ora un individuo per
# animale, sempre 1:1. Campo lasciato per compatibilità con i .tres esistenti (rabbit=10,
# partridge=8).
@export var visual_group_size: int = 1
# Quanti individui al massimo per cluster (branco visivo di gruppi vicini tra loro, vedi
# AnimalGroupRenderer). Default 1 fa collassare il numero di cluster al numero di gruppi
# (un cluster per gruppo), disattivando di fatto l'effetto per le specie che non lo impostano
# esplicitamente — stesso pattern "default = no-op" di visual_group_size sopra.
@export var max_individuals_per_cluster: int = 1
# Movimento a balzi degli individui (vedi AnimalGroupRenderer): un balzo (hop_duration) alterna a
# una breve pausa (hop_pause) durante la fase "movimento" (movement_phase_duration); a quella
# segue una sosta lunga (rest_phase_duration) prima del prossimo movimento. Ogni durata è
# pescata a caso nel proprio range min/max a ogni transizione, indipendentemente per individuo.
# TEMPO DI GIOCO (2026-09-25): tutte le durate sono in GIORNI DI GIOCO, come il movimento umano
# (HumanIndividualMovementService) — scorrono con la velocità di gioco e si fermano in pausa. I
# valori sono la conversione dei vecchi secondi reali a 1x (1 giorno = 8 s reali, vedi
# GameClockController.SECONDS_PER_DAY_BY_SPEED): secondi / 8.
@export var hop_duration_min: float = 0.025
@export var hop_duration_max: float = 0.05
@export var hop_pause_min: float = 0.0125
@export var hop_pause_max: float = 0.0375
@export var movement_phase_duration_min: float = 0.25
@export var movement_phase_duration_max: float = 0.625
@export var rest_phase_duration_min: float = 0.375
@export var rest_phase_duration_max: float = 0.875
# Velocità durante un singolo balzo, in MICROCELLE PER GIORNO DI GIOCO (stessa unità di
# HumanIndividual.move_speed, 10.0 per un umano che cammina) — sostituisce move_speed per il
# movimento degli individui disegnati; move_speed resta usato solo per il vagare continuo dei
# centri-cluster invisibili (vedi AnimalGroupRenderer). Vecchi microcelle/secondo × 8.
@export var hop_speed: float = 48.0
# Andature (2026-11-01, richiesta utente: gli animali sembravano correre sempre). hop_speed è la corsa: la fuga e gli scatti.
# Quando vaga la specie cammina a hop_speed × walk_speed_fraction, e ogni periodo di movimento ha run_phase_chance di essere
# uno scatto di corsa. Quanto si muove lo dicono movement_phase_duration_* e rest_phase_duration_*.
@export var walk_speed_fraction: float = 1.0
@export var run_phase_chance: float = 0.0
# Moltiplicatore di scala visiva (young, adult, old) applicato da AnimalGroupRenderer a ogni
# icona disegnata — adult=1.0 è il riferimento a cui le dimensioni base (body_length/body_width,
# passate da chi istanzia il renderer) sono tarate; young tipicamente <1 (cucciolo più piccolo),
# old libero di essere >1 (un anziano può essere più grande della media, non solo "rimpicciolito").
# Letto SOLO quando track_age_bands=true (vedi sotto) — per una specie che non traccia età ogni
# icona è disegnata a scala fissa 1.0 (AnimalGroupRenderer.set_population, non age-aware).
@export var size_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0]

@export_group("Cluster Movement")
# Movimento continuo dei centri-cluster invisibili (deriva + rimbalzo ai bordi della mappa, vedi
# AnimalGroupRenderer._process) — DIVERSO dal movimento a balzi dei gruppi disegnati sopra (quello
# usa hop_speed): move_speed/turn_rate governano solo il vagare del centro-cluster stesso, i
# gruppi disegnati non si muovono mai a questa velocità, vengono solo debolmente attratti verso
# il centro (vedi cluster_comfort_radius/cluster_attraction_strength sotto). Default = valori
# storici di rabbit (erano hardcoded in MacroCellScene prima di questo refactor).
# TEMPO DI GIOCO (2026-09-25): unità per GIORNO DI GIOCO come le durate sopra — vecchi valori per
# secondo reale × 8 (1 giorno = 8 s reali a 1x).
@export var move_speed: float = 24.0 # microcelle/giorno di gioco
# Radianti/giorno di gioco massimi di deriva casuale della direzione — vale sia per i centri-cluster
# sia per gli individui.
@export var turn_rate: float = 12.0
# Guinzaglio elastico (AnimalGroupRenderer._apply_cluster_attraction): entro questo raggio
# (microcelle, NON dipende dal tempo) dal centro-cluster un individuo non subisce alcuna trazione;
# oltre la soglia la sua direzione viene gradualmente reindirizzata verso il centro, con intensità
# cluster_attraction_strength — un tasso per GIORNO DI GIOCO (moltiplica il delta), quindi
# convertito anch'esso: vecchio valore per secondo × 8.
@export var cluster_comfort_radius: float = 5.0
@export var cluster_attraction_strength: float = 12.0

@export_group("Age Bands")
# Master switch, analogo a SubtypeRules.track_age_bands: false (default) = nessuna delle
# logiche sotto viene mai letta per questa specie (nessuna specie futura la eredita per
# sbaglio). true solo per rabbit oggi.
@export var track_age_bands: bool = false
# Stagione delle nascite della specie (vedi WildFaunaService): a differenza della vegetazione, che
# matura sempre a fine primavera, ogni specie animale ha la propria.
@export var birth_season: GameTypes.Season = GameTypes.Season.SPRING
# Anni interi: durata PROPRIA di ciascuna fascia, indipendente dalle altre (non soglie
# cumulative di età dalla nascita) — quanti anni un individuo trascorre in YOUNG prima di passare
# ad ADULT (youth_duration_years), e quanti in ADULT prima di passare a OLD (adult_duration_years).
@export var youth_duration_years: int = 2
@export var adult_duration_years: int = 6
# Durata PROPRIA della fascia OLD (stesso principio di youth_duration_years/adult_duration_years
# sopra, non un'età cumulativa dalla nascita): quanti anni un individuo trascorre OLD prima di
# morire di vecchiaia — vita attesa totale = youth_duration_years + adult_duration_years +
# old_duration_years.
@export var old_duration_years: int = 10
# Moltiplicatore (young, adult, old) di fertilità per fascia — coefficiente, non un gate
# binario "solo adult": una fascia a 0.0 semplicemente non contribuisce alle nascite, ma resta
# configurabile per una fertilità parziale futura (es. young/old parzialmente fertili). Usato
# da WildFaunaService insieme a base_birth_rate.
@export var fertility_multiplier_by_age: Array[float] = [0.0, 1.0, 0.0]
# Coefficiente di natalità annuale per la specie: nascite = (young×fert[Y] + adult×fert[A] +
# old×fert[O]) × base_birth_rate, stesso principio della crescita logistica vegetale (un
# coefficiente che moltiplica la popolazione di riferimento, nessuna curva/modulazione per
# ora).
@export var base_birth_rate: float = 0.0
# Ripartizione (young, adult, old) di una mandria appena creata (WildFaunaService). Assente o
# tutto a 0 => pesi uguali, stesso fallback di SubtypeRules.initial_age_ratio.
@export var initial_age_ratio: Dictionary = {}

@export_group("Dispersal")
# Quota (young, adult, old) di chi si stacca per fondare una mandria altrove (WildFaunaService) —
# pesi, non un gate binario, così una fascia senza abbastanza individui per la propria quota non
# blocca la partenza: il mancante si riproporziona sulle fasce con capienza residua. Young
# tipicamente più propenso a disperdersi (in natura è la fascia che lascia il branco natale in
# cerca di un proprio territorio), old meno (mobilità/spinta a fondare un nuovo areale minori).
@export var dispersal_share_by_age: Array[float] = [0.34, 0.33, 0.33]
@export_group("Wild herd")
# false: la specie non ha mandrie nei riquadri (il lupo, che esiste solo come branco del villaggio, WildAnimalGroup).
@export var has_wild_herds: bool = true
# Fauna ad hoc (2026-10-31, piano fauna — WildFaunaService): lato in macrocelle del riquadro fisso in cui vive al più una
# mandria della specie (1 = stanziale nella cella). Più è grande, più di rado la mandria passa da una data cella.
@export var herd_region_side: int = 1
# herd_size_max: massimo fisso della mandria, fatto rispettare dallo split di fine estate; la taglia del menu decide solo
# la partenza, come quota di questo massimo (WildFaunaService.START_RATIO_BY_SIZE). herd_size_min oggi non è usato.
@export var herd_size_min: int = 1
@export var herd_size_max: int = 1
# Giorni in cui la mandria resta in una cella del riquadro prima di passare a un'altra (passo 1b). Ignorati con
# herd_region_side 1: la mandria non si sposta.
@export var herd_stay_days_min: int = 1
@export var herd_stay_days_max: int = 3
# Anni dopo cui una mandria sparita (cacciata o morta di vecchiaia) torna nel suo riquadro con un gruppetto
# (WildFaunaService, passo 3b). I riquadri vuoti fin dall'inizio restano vuoti.
@export var recolonization_years: int = 2

@export_group("Suitability")
# Stessa forma e stessa semantica di SubtypeRules.suitable_biomes/suitable_terrains (vedi
# SubtypeRules.gd) — vuoto = nessuna restrizione, altrimenti lista bianca.
@export var suitable_biomes: Array[GameTypes.Biome] = []
@export var suitable_terrains: Array[GameTypes.TerrainBase] = []


# Stessa logica di SubtypeRules.is_suitable_for: array vuoto = sempre idoneo su quell'asse,
# altrimenti richiede l'appartenenza alla lista.
func is_suitable_for(biome: GameTypes.Biome, terrain: GameTypes.TerrainBase) -> bool:
	if not suitable_biomes.is_empty() and not suitable_biomes.has(biome):
		return false
	if not suitable_terrains.is_empty() and not suitable_terrains.has(terrain):
		return false
	return true
