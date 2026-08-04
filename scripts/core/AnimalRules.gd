class_name AnimalRules
extends Resource

@export var species_name: String = ""
@export var daily_caloric_requirement: float = 0.0
# resource_name (chiave di CaloricSourceRules.caloric_source_name) -> moltiplicatore di
# edibilità, usato da AnimalConsumptionService per ripartire il fabbisogno giornaliero tra le
# fonti compatibili, pesato per calorie disponibili × questo moltiplicatore. 0 (o chiave
# assente) esclude la fonte del tutto.
@export var diet_compatibility: Dictionary = {}

@export_group("Visualization")
# Quanti individui rappresenta una singola icona/gruppo nella resa visiva animata (vedi
# AnimalGroupRenderer). Default 1 = rappresentazione 1:1, per compatibilità con specie che
# non lo impostano esplicitamente nel proprio .tres.
@export var visual_group_size: int = 1
# Quanti individui al massimo per cluster (branco visivo di gruppi vicini tra loro, vedi
# AnimalGroupRenderer). Default 1 fa collassare il numero di cluster al numero di gruppi
# (un cluster per gruppo), disattivando di fatto l'effetto per le specie che non lo impostano
# esplicitamente — stesso pattern "default = no-op" di visual_group_size sopra.
@export var max_individuals_per_cluster: int = 1
# Movimento a balzi dei gruppi (vedi AnimalGroupRenderer): un balzo (hop_duration) alterna a
# una breve pausa (hop_pause) durante la fase "movimento" (movement_phase_duration); a quella
# segue una sosta lunga (rest_phase_duration) prima del prossimo movimento. Ogni durata è
# pescata a caso nel proprio range min/max a ogni transizione, indipendentemente per gruppo.
@export var hop_duration_min: float = 0.2
@export var hop_duration_max: float = 0.4
@export var hop_pause_min: float = 0.1
@export var hop_pause_max: float = 0.3
@export var movement_phase_duration_min: float = 2.0
@export var movement_phase_duration_max: float = 5.0
@export var rest_phase_duration_min: float = 3.0
@export var rest_phase_duration_max: float = 7.0
# Velocità durante un singolo balzo (microcelle/secondo) — sostituisce move_speed per il
# movimento dei gruppi disegnati; move_speed resta usato solo per il vagare continuo dei
# centri-cluster invisibili (vedi AnimalGroupRenderer).
@export var hop_speed: float = 6.0
# Moltiplicatore di scala visiva (young, adult, old) applicato da AnimalGroupRenderer a ogni
# icona disegnata — adult=1.0 è il riferimento a cui le dimensioni base (body_length/body_width,
# passate da chi istanzia il renderer) sono tarate; young tipicamente <1 (cucciolo più piccolo),
# old libero di essere >1 (un anziano può essere più grande della media, non solo "rimpicciolito").
# Letto SOLO quando track_age_bands=true (vedi sotto) — per una specie che non traccia età ogni
# icona è disegnata a scala fissa 1.0 (AnimalGroupRenderer.set_population, non age-aware).
@export var size_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0]

@export_group("Age Bands")
# Master switch, analogo a SubtypeRules.track_age_bands: false (default) = nessuna delle
# logiche sotto viene mai letta per questa specie (nessuna specie futura la eredita per
# sbaglio). true solo per rabbit oggi.
@export var track_age_bands: bool = false
# Stagione di fine-checkpoint in cui gira la maturazione annuale delle age band per QUESTA
# specie (vedi WorldTimeService._run_animal_lifecycle_checkpoint / AnimalAgeBandService) — a
# differenza della vegetazione, che matura sempre a fine primavera, ogni specie animale ha la
# propria stagione di "nascita" e quindi il proprio momento di invecchiamento annuale.
@export var birth_season: GameTypes.Season = GameTypes.Season.SPRING
# Anni interi: durata PROPRIA di ciascuna fascia, indipendente dalle altre (non soglie
# cumulative di età dalla nascita) — quanti cicli di maturazione (vedi birth_season sopra) un
# individuo trascorre in YOUNG prima di passare ad ADULT (youth_duration_years), e quanti in
# ADULT prima di passare a OLD (adult_duration_years). Transizione frazionaria 1/N per anno,
# stessa semantica di SubtypeRules.youth_duration_years/adult_duration_years.
@export var youth_duration_years: int = 2
@export var adult_duration_years: int = 6
# Durata PROPRIA della fascia OLD (stesso principio di youth_duration_years/adult_duration_years
# sopra, non un'età cumulativa dalla nascita): quanti anni un individuo trascorre OLD prima di
# morire di vecchiaia — vita attesa totale = youth_duration_years + adult_duration_years +
# old_duration_years. NON ancora usato da nessuna logica (mortalità per vecchiaia è un prompt
# futuro): solo campo dati per ora. Per le piante questo parametro non serve (la mortalità è
# già coperta da fill_ratio/competizione spaziale), ma gli animali non hanno un equivalente del
# fill_ratio, quindi serve un limite di età reale.
@export var old_duration_years: int = 10
# Quota (young, adult, old) del totale perso per fame/vecchiaia attribuita a ciascuna fascia —
# NON ancora usato da nessuna logica (prompt futuro). Stesso schema di
# SubtypeRules.mortality_share_by_age: convenzionalmente somma a 1.0, non validato a runtime.
@export var mortality_share_by_age: Array[float] = [0.34, 0.33, 0.33]
# Moltiplicatore (young, adult, old) applicato a daily_caloric_requirement nel calcolo del
# fabbisogno totale per cella (vedi AnimalConsumptionService._get_total_daily_requirement):
# adult=1.0 è il valore di riferimento a cui daily_caloric_requirement è tarato, young
# tipicamente <1 (cucciolo, mangia meno). Letto SOLO quando track_age_bands=true — altrimenti
# il fabbisogno resta la vecchia formula flat population × daily_caloric_requirement.
@export var caloric_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0]
# Moltiplicatore (young, adult, old) di fertilità per fascia — coefficiente, non un gate
# binario "solo adult": una fascia a 0.0 semplicemente non contribuisce alle nascite, ma resta
# configurabile per una fertilità parziale futura (es. young/old parzialmente fertili). Usato
# da AnimalBirthService insieme a base_birth_rate, stesso schema di caloric_multiplier_by_age.
@export var fertility_multiplier_by_age: Array[float] = [0.0, 1.0, 0.0]
# Coefficiente di natalità annuale per la specie: nascite = (young×fert[Y] + adult×fert[A] +
# old×fert[O]) × base_birth_rate, stesso principio della crescita logistica vegetale (un
# coefficiente che moltiplica la popolazione di riferimento, nessuna curva/modulazione per
# ora). Letto SOLO quando track_age_bands=true (vedi AnimalBirthService).
@export var base_birth_rate: float = 0.0
# Ripartizione (young, adult, old) usata SOLO dal seeding/reseeding manuale della popolazione
# (oggi il pulsante debug "set rabbit population" in GameScene.gd, vedi
# PopulationGroup.set_age_composition) — mai durante la simulazione a regime. Assente o
# tutto a 0 => pesi uguali, stesso fallback di SubtypeRules.initial_age_ratio.
@export var initial_age_ratio: Dictionary = {}

@export_group("Hunger")
# Soglia di specie (giorni CONSECUTIVI in cui un individuo non riceve fabbisogno calorico
# sufficiente, vedi AnimalHungerService) oltre la quale l'individuo muore per digiuno prolungato —
# indipendente da mortality_share_by_age sopra (quello pesa COME distribuire le morti tra le fasce
# d'età, non SE/QUANDO scattano). Nessun default: ogni specie deve dichiararlo esplicitamente nel
# proprio .tres, stesso principio di min_territory_cells/max_territory_cells sotto (rabbit=5,
# metabolismo alto/riserve minime; deer=30, corpo grande/riserve adipose reali — il rapporto 6x
# non rispecchia il rapporto 15x di daily_caloric_requirement: la tolleranza al digiuno non scala
# linearmente col fabbisogno calorico).
@export var max_days_without_food: int = 0

@export_group("Territory")
# Home range minimo e massimo di specie, in numero di macrocelle — indipendenti da
# popolazione/risorse locali (es. rabbit: 1/1, deer: 3/20). Campi DORMIENTI per ora: dichiarati
# qui e nei .tres di ciascuna specie, ma nessuna logica li legge ancora — verranno usati
# quando il Territory diventerà multi-cella (Step 5+ del refactoring fauna, espansione/
# restringimento territorio). Nessun default: ogni specie deve dichiararli esplicitamente nel
# proprio .tres.
@export var min_territory_cells: int = 1
@export var max_territory_cells: int = 1
# Limite etologico/comportamentale di quanti individui della specie possono convivere in una
# singola macrocella, indipendentemente dalle risorse disponibili — un tetto di densità sociale,
# non di carrying capacity (quello resta implicito nel fabbisogno calorico/risorse). Campo
# DORMIENTE per ora (Step 5 del refactoring fauna): dichiarato ma non ancora letto da nessuna
# logica di distribuzione/espansione territorio. Nessun default: ogni specie deve dichiararlo
# esplicitamente nel proprio .tres (rabbit=999, di fatto senza vincolo dato il suo territorio
# sempre a 1 cella; deer=18, un branco realistico).
@export var max_density_per_cell: int = 999
