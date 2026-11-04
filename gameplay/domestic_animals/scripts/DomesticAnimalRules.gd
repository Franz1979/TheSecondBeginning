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

@export_group("Arrivals")
# Superata la soglia, arrivano insieme gli animali che mancano per questi numeri di maschi e femmine (cane, passo 2).
@export var arrival_target_males: int = 0
@export var arrival_target_females: int = 0

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
