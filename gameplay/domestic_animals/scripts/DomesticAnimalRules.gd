class_name DomesticAnimalRules
extends Resource

# Specie domestica (addomesticazione passo 1, 2026-10-26, richiesta utente): descrive la specie, non il singolo
# animale. Un file per specie in gameplay/domestic_animals/data/{species_name}.tres, caricato per nome da
# DomesticAnimalCalculator. Ogni specie domestica deriva da una selvatica (cane ← lupo): i parametri biologici si
# leggeranno dal suo AnimalRules (DomesticAnimalCalculator.get_wild_rules), qui solo quello che è proprio del
# domestico. Cane, passo 1 (2026-11-03): i numeri già decisi stanno qui anche prima dei passi che li leggeranno.

# Uguale al nome del file .tres (es. "dog").
@export var species_name: String = ""
# Chiave tr() del nome mostrato (es. "domestic_animal_dog").
@export var display_name: String = ""
# Specie selvatica d'origine: nome di un .tres in simulation/data/animals/ (es. "wolf").
@export var wild_species_name: String = ""
# La specie ha animali veri, seguiti uno per uno (DomesticAnimal). Oggi solo il cane.
@export var individuals_enabled: bool = false

@export_group("Domestication")
# Punti addomesticazione per il primo animale (vedi DomesticationPointsService). Specie diverse accumulano in
# parallelo, ognuna verso la propria soglia.
@export var domestication_points_required: int = 1000
# Idea da conoscere perché i punti si accumulino. Vuoto = sempre (il cane: è proprio addomesticando il lupo che si
# scopre l'idea dell'addomesticazione).
@export var required_idea_id: String = ""
# Punti per ogni animale selvatico catturato vivo che arriva in una tettoia (2026-11-12, cattura viva: KeepAnimalAction),
# per fascia d'età e sesso. 0 = nessun punto. Il cane non li usa (i suoi punti vengono dalle visite dei lupi).
@export var capture_points_adult_male: int = 0
@export var capture_points_adult_female: int = 0
@export var capture_points_young: int = 0
@export var capture_points_old: int = 0
# Punti per ogni piccolo nato vivo in un edificio (2026-11-12, cucciolate in cattività). Chi nasce e muore subito perché
# l'edificio è pieno non conta. 0 = nessun punto.
@export var captivity_birth_points: int = 0

@export_group("Arrivals")
# Superata la soglia, arrivano insieme gli animali che mancano per questi numeri di maschi e femmine (cane, passo 2).
@export var arrival_target_males: int = 0
@export var arrival_target_females: int = 0
# Rimpiazzi (2026-11-06): dopo il primo arrivo dal branco gli animali che mancano (DomesticAnimalService.needs_arrivals)
# arrivano da fuori, uno alla volta, ognuno dopo tanti anni da quando ne serve uno. 0 = nessun rimpiazzo da fuori.
@export var stray_arrival_wait_years: int = 0

@export_group("Body")
# Corpo della selvatica, in scala e di questo colore (passo 3).
@export var body_size_scale: float = 1.0
@export var body_color: Color = Color.WHITE
# Da libero gira attorno al magazzino, a questa distanza in microcelle e a questa frazione della velocità.
@export var roam_radius_min: float = 3.0
@export var roam_radius_max: float = 9.0
@export var roam_speed_scale: float = 0.5

@export_group("Life")
# Età a cui l'animale muore di vecchiaia (passo 4), più o meno max_age_variation_years: ognuno ha il suo giorno, così chi è
# nato insieme non muore insieme.
@export var max_age_years: int = 0
@export var max_age_variation_years: int = 0
# Giorni per guarire da quasi morto a salute piena (passo 4); 0 = non guarisce.
@export var health_recovery_days: int = 0
# Sintomo della fame (passo 6): tante persone morte di fame entro tanti giorni e muore un adulto; 0 = la fame non lo tocca.
@export var starved_people_per_death: int = 0
@export var starved_people_window_days: int = 0
# Cuccioli per cucciolata (passo 5).
@export var litter_size_min: int = 0
@export var litter_size_max: int = 0

@export_group("Butchering")
# Rese dell'adulto (Macella, passo 7), scalate per fascia con size_multiplier_by_age della selvatica (ButcherAction.compute_yields).
@export var butcher_meat_units: int = 0
@export var butcher_hide_units: int = 0
@export var butcher_sinew_units: int = 0
@export var butcher_bone_units: int = 0

@export_group("Population")
# Massimo di animali = abitanti / inhabitants_per_animal, mai meno di min_population_cap (passo 5).
@export var inhabitants_per_animal: int = 0
@export var min_population_cap: int = 0
# Adulti che restano sempre nelle partenze d'autunno (passo 5).
@export var min_adult_males_kept: int = 0
@export var min_adult_females_kept: int = 0

@export_group("Guard")
# Guardia contro i branchi in visita (passo 8.1, 2026-11-06), solo per gli animali usciti dalla giovinezza.
# Abbaio d'allarme quando un animale del branco è entro questa distanza (microcelle; 0 = nessuna guardia), ripetuto ogni
# guard_bark_interval_hours ore di gioco finché il branco resta a portata.
@export var guard_alarm_radius: float = 0.0
@export var guard_bark_interval_hours: float = 2.0
# Zona sicura attorno all'animale (microcelle), come quella del focolare: lì il branco non attacca e la carica non entra.
@export var guard_keep_away_radius: float = 0.0
# Raggio in cui il branco in sosta si tiene alla larga dall'animale, sulla scala di AnimalRules.building_reactions (il
# focolare 15); 0 = nessuna repulsione.
@export var guard_keep_away_reaction: float = 0.0
# Difesa (passo 8.2): peso di ogni animale di guardia nella difesa del tiro d'attacco (un adulto vale 1), contato se sta
# entro guard_help_radius da chi è notato. Alla carica corrono contro il branco tutti gli animali di guardia entro
# guard_help_radius (microcelle) da chi è caricato, senza tetto; nella cacciata ognuno copre guard_threats_per_dog animali
# del branco (una persona DangerProfile.drive_off_threats_per_helper) e conta guard_helper_weight aiutanti verso
# DangerProfile.drive_off_min_helpers (una persona 1). Il cane vale mezza persona (2026-11-07, decisione utente).
@export var guard_defense_strength: float = 0.0
@export var guard_help_radius: float = 0.0
@export var guard_threats_per_dog: int = 0
@export var guard_helper_weight: float = 0.0
# Contro il branco (2026-11-07, decisione utente, strada a): in arrivo e in sosta, l'animale che ha un presente entro
# guard_alarm_radius va verso il branco dal punto dove si trovava e si piazza a guard_confront_distance dal presente più
# vicino, senza allontanarsi più di guard_confront_max_advance da quel punto; lì gironzola entro guard_confront_ring_max
# abbaiando. Niente morsi. Torna a seguire la gente quando il branco riparte, se ne va o si allontana oltre
# guard_alarm_radius dal punto di partenza. guard_confront_max_advance 0 = non va incontro, abbaia soltanto.
@export var guard_confront_distance: float = 4.0
@export var guard_confront_max_advance: float = 0.0
@export var guard_confront_ring_max: float = 1.5

@export_group("Hunt")
# Caccia con l'uomo (2026-11-07, DomesticAnimalHuntService): un animale adulto segue chi va a caccia, stretto tra
# hunt_ring_min e hunt_ring_max microcelle alla velocità hunt_speed_scale; più lontano di hunt_catch_up_distance lo
# raggiunge di corsa. hunt_ring_max 0 = la specie non va a caccia. hunt_max_prey_health: salute massima (AnimalRules) di
# una preda che l'animale riesce a tenere a bada (passo 3, non ancora usato).
@export var hunt_ring_min: float = 0.0
@export var hunt_ring_max: float = 0.0
@export var hunt_speed_scale: float = 1.0
@export var hunt_catch_up_distance: float = 6.0
@export var hunt_max_prey_health: float = 0.0
# Fiuto (passo 2): nella caccia in zona una preda entro hunt_scent_radius microcelle dall'animale che accompagna il
# cacciatore conta come avvistata, anche fuori dal raggio di vista di lui (HuntZoneService.find_sighted_prey). 0 = niente.
@export var hunt_scent_radius: float = 0.0
# Inseguire e tenere a bada (passo 3): quando la preda del cacciatore fugge (dopo un tiro) l'animale la insegue di corsa;
# arrivato entro hunt_hold_contact_distance, se la salute massima della specie (AnimalRules.max_health) non supera
# hunt_max_prey_health la ferma lì per hunt_hold_hours ore di gioco (un nuovo tiro la rimette in fuga), altrimenti le
# corre attorno finché smette di fuggire. Oltre hunt_chase_max_distance dal cacciatore lascia perdere e torna.
@export var hunt_hold_hours: float = 0.0
@export var hunt_hold_contact_distance: float = 1.5
@export var hunt_chase_max_distance: float = 25.0

@export_group("Follow")
# Dietro alle persone (passo 8.3, 2026-11-06): ogni animale gironzola attorno a una persona che sta fuori dagli edifici,
# tra follow_ring_min e follow_ring_max microcelle, alla velocità follow_speed_scale, e cambia persona ogni
# follow_change_hours ore di gioco (DomesticAnimalFollowService). follow_ring_max 0 = resta attorno al magazzino.
@export var follow_ring_min: float = 0.0
@export var follow_ring_max: float = 0.0
@export var follow_change_hours: float = 6.0
@export var follow_speed_scale: float = 0.5
# Scontro (passo 8.4): una volta per carica, quando arriva sul branco, l'animale può essere ferito (guard_wound_chance,
# perde guard_wound_health_ratio della salute piena; a 0 muore) e può mordere il presente più vicino (guard_bite_chance,
# guard_bite_damage punti della salute del corpo, come un colpo di caccia; a 0 il lupo muore e lascia la carcassa).
@export var guard_wound_chance: float = 0.0
@export var guard_wound_health_ratio: float = 0.0
@export var guard_bite_chance: float = 0.0
@export var guard_bite_damage: float = 0.0
