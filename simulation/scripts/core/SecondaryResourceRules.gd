class_name SecondaryResourceRules
extends Resource

# Rinominata da CaloricSourceRules (2026-09-08, richiesta utente) — non ogni risorsa secondaria è
# calorica (es. i futuri bastoni), il nome generico riflette meglio il dominio. Campo
# caloric_source_name rinominato in secondary_resource_name di conseguenza, stesso rename in ogni
# .tres/riferimento nel codebase.

@export var secondary_resource_name: String = ""

@export_group("Origin")
# Sottotipo di origine (es. "domesticable_fruit"). Vuoto = la fonte non deriva da un
# sottotipo ma dalla risorsa primaria stessa (caso FORAGE: deriva da GRASS, non da un
# suo sottotipo — GRASS non ne ha).
@export var source_subtype: String = ""
# Frutti/unità per pianta. Non si applica a FORAGE (yield 1:1 con GRASS); resta al
# default finché non serve per una fonte con la propria resa distinta dalla pianta madre.
@export var yield_ratio: float = 1.0

@export_group("Calories")
@export var calories_per_unit: float = 1.0

@export_group("Seasonality")
# Frazione delle unità della risorsa primaria/sottotipo collegata EFFETTIVAMENTE raggiungibile/
# consumabile in quella stagione (indice = GameTypes.Season: WINTER, SPRING, SUMMER, AUTUMN).
# Non è un moltiplicatore del valore calorico per unità (quello resta fisso in
# calories_per_unit) — rappresenta quanto è marcito/sepolto/non raggiungibile. Per FORAGE: 0.6
# in inverno significa che il 40% dell'erba residua non è più foraggiabile, il resto sì.
@export var seasonal_availability_multiplier: Array[float] = [1.0, 1.0, 1.0, 1.0]
# Stagione di reset pieno per fonti a STOCK AGGREGATO persistente (consuming_depletes_primary =
# false): a inizio di questa stagione lo stock si azzera e riparte dal tetto pieno di quella
# stagione, scartando il residuo del ciclo precedente ("i frutti non si accumulano da un anno
# all'altro") — vedi CaloricCalculator.update_secondary_resource_stock/seed_secondary_resource_
# stock_now, gli UNICI due punti che lo leggono.
#
# CHI LO LEGGE (2026-09-19, richiesta utente — commento aggiornato per dire esattamente chi legge
# e chi ignora questo campo, verificato nel codice, non inventato): SOLO le risorse del modello a
# stock aggregato via CaloricCalculator.SECONDARY_SOURCES — oggi berry/acorn/fruit/eggs. Qualunque
# altra risorsa lo IGNORA, pur avendolo presente ed export-abile nel proprio .tres:
#   - forage/fish_meat/bird_meat: consuming_depletes_primary=true, stateless per costruzione,
#     nessuno stock da resettare;
#   - pebble/stick/plant_fiber/mushroom/wild_vegetables (modello "capacità per lotto", vedi
#     TerrainScatteredResourceService): non hanno mai avuto un ciclo legato a questo campo — il
#     loro raccolto (dove esiste, vedi reset_all_lot_harvests_on_season_rise) si azzera quando il
#     LORO seasonal_availability_multiplier SALE rispetto alla stagione precedente, un confronto
#     dinamico tra due stagioni consecutive, non un singolo "giorno dell'anno" fisso come questo
#     campo. Impostare cycle_start_season su uno di questi sei .tres non ha ALCUN effetto — non è
#     un uso pianificato per il futuro, è semplicemente un campo della classe base non pertinente
#     per questo modello, lasciato qui invece che reso condizionale per non introdurre una
#     sottoclasse solo per questo.
@export var cycle_start_season: GameTypes.Season = GameTypes.Season.SPRING

@export_group("Consumption")
# true = consumare calorie da questa fonte decrementa DIRETTAMENTE la risorsa primaria
# (dedicated_space/resource_quantity) — caso FORAGE. false (futuro) = la fonte ha un proprio
# stock indipendente (frutti maturi) che il consumo intacca senza toccare la pianta madre.
@export var consuming_depletes_primary: bool = true
# NOTA per quando implementeremo il consumo (non ancora fatto): seasonal_availability_multiplier
# sopra è un TETTO MASSIMO di unità raggiungibili, applicato UNA sola volta per calcolare il
# disponibile (vedi CaloricCalculator.get_available_units) — un consumo di X unità da questa
# fonte deve scalare 1:1 la risorsa fisica collegata (resource_quantity[GRASS] per FORAGE, lo
# stock derivato per i frutti), MAI moltiplicando/dividendo di nuovo per questo multiplier.
# PROMEMORIA esplicito (da NON perdere quando arriverà un vero consumo umano, oggi nessuno
# esiste ancora): fish_meat e bird_meat sono consuming_depletes_primary = true esattamente come
# FORAGE, quindi consumare fish_meat DEVE scalare resource_quantity[FISH] e consumare bird_meat
# DEVE scalare resource_quantity[BIRDS] — non sono risorse secondarie con stock proprio (a
# differenza di eggs/berry/acorn/fruit), il consumo va sulla risorsa primaria stessa.

@export_group("Classification")
# Se questa risorsa è utilizzabile come materiale da costruzione per edifici (BuildingRules.
# required_materials, oggi stringhe libere — vedi commento lì). Indipendente da `category` sotto:
# un materiale grezzo e uno lavorato potranno entrambi averlo true in futuro. Default false —
# nessuna risorsa esistente (frutti/uova/carne/forage) lo è oggi. Solo il dato in questo step:
# nessuna logica lo consulta ancora.
@export var is_construction_material: bool = false
# Vedi SecondaryResourceTypes.Category — enum tenuto separato da questa classe Resource, stesso
# principio già in uso per BuildingTypes.Category/BuildingRules e ExpiredObjectTypes/
# ExpiredObjectRules. Nessun default esplicito assegnato qui (il primo valore dell'enum, FOOD,
# resta il default implicito di GDScript) — coincide col comportamento reale di ogni risorsa
# alimentare senza campo esplicito (forage/berry/fruit/fish_meat/bird_meat). Nessuna logica lo
# consulta ancora.
@export var category: SecondaryResourceTypes.Category

# Id (Idea.id) che deve essere già in Folk.completed_ideas perché questa risorsa sia raccoglibile
# dagli umani — STESSO campo/STESSO significato di BuildingRules.required_idea_id ("" = sempre
# disponibile, nessun requisito). Consultato SOLO da TerrainScatteredResourceService.
# is_resource_locked (usato a sua volta da get_available e da GameScene._resolve_pickup_candidates
# per popup di raccolta/ispezione microcella) — MAI dal rendering (i puntini su arbusti/alberi
# restano disegnati come sempre, indipendentemente dal blocco) né da AnimalConsumptionService (la
# fauna continua a consumare secondary_resource_stock indipendentemente dalle idee umane). NON
# impostato su nessuna .tres esistente oggi: ogni risorsa attuale resta sempre disponibile,
# comportamento invariato.
@export var required_idea_id: String = ""

# Vedi SecondaryResourceTypes.GenerationSource — PURAMENTE descrittivo (documenta la provenienza
# dello stock: pianta/animale vs sparso sul terreno), nessuna logica lo consulta. Default
# PLANT_DERIVED (primo valore dell'enum): coincide col comportamento reale di ogni risorsa
# esistente finora (frutti/uova/carne/forage, tutte derivate da una risorsa primaria vegetale/
# animale via CaloricCalculator) — vedi le .tres esistenti, dove è comunque esplicitato invece di
# lasciato implicito nel default.
@export var generation_source: SecondaryResourceTypes.GenerationSource = SecondaryResourceTypes.GenerationSource.PLANT_DERIVED

# Giorni di gioco che l'oggetto dura DOPO essere stato raccolto, prima di deperire — concetto
# distinto dal deperimento/rigenerazione della risorsa mentre è ancora sulla fonte (quello è già
# gestito da seasonal_availability_multiplier/update_secondary_resource_stock sopra, PRIMA della
# raccolta). -1 = durata infinita, non deperisce mai dopo la raccolta (es. un futuro "sassi/
# pietra" non deperibile). Solo il dato in questo step: nessuna logica di consumo/decadimento
# post-raccolta esiste ancora, nessuna .tres esistente lo valorizza.
@export var day_durability: int = -1

# Spazio/peso occupato da UNA unità della risorsa una volta raccolta — futura base per calcolare
# capacità di trasporto individuale e capienza di storage/deposito. Nessuna unità di misura fissa
# esiste già nel progetto per questo concetto (verificato 2026-09-08): ResourceDensityRules.
# base_density è l'inverso concettuale — quantità per MICROCELLA di terreno, non spazio per
# unità raccolta, dominio diverso (vegetazione in piedi sulla mappa, non un oggetto portabile) —
# e BuildingRules.storage_slot_count/storage_space_per_slot (capacità di stoccaggio di un
# edificio) è già un float "spazio" astratto SENZA unità dichiarata (kg/microcelle/altro), non
# ancora consultato da nessuna logica. Stesso trattamento qui: float generico senza unità
# implicita, pensato per accoppiarsi in futuro proprio con storage_space_per_slot (stesso
# "spazio" astratto su entrambi i lati del calcolo capacità). Solo il dato in questo step:
# nessuna logica di trasporto/storage esiste ancora, nessuna .tres esistente lo valorizza.
@export var space_per_unit: float = 1.0

# Unità di QUESTA risorsa prodotte da UN individuo maturo (ADULT/OLD, non YOUNG) della vegetazione
# che la genera — 2026-09-16, richiesta utente: prima una costante hardcoded per tipo
# (StickPoolService.STICKS_PER_MATURE_TREE/PlantFiberPoolService.UNITS_PER_MATURE_SHRUB, entrambe
# 3), ora spostata qui così è tarabile da .tres senza toccare codice. Consultato SOLO da
# VegetationPoolService.resolve_units_per_mature_individual (stick.tres/plant_fiber.tres/
# mushroom.tres oggi, le sole risorse lot_source=TREE_INDIVIDUAL/SHRUB_INDIVIDUAL — vedi
# SecondaryResourceTypes.LotSource) — nessun'altra risorsa secondaria lo legge. Default 0 (non 3):
# un .tres che non lo valorizza esplicitamente deve produrre un warning
# visibile (capacity sempre 0), MAI un fallback silenzioso a un numero che sembra normale.
@export var units_per_mature_plant: int = 0

# Probabilità [0.0, 1.0] che una data microcella GRASS diventi un "lotto" raccoglibile per questa
# risorsa (2026-09-18, richiesta utente — eggs raccoglibile per microcella; RINOMINATO da
# nest_probability il 2026-09-19, richiesta utente — wild_vegetables: STESSO meccanismo, un
# secondo consumatore su GRASS oltre agli eggs, "lotto" generico invece di "nido" specifico di
# eggs) — consultato da TerrainScatteredResourceService.compute_egg_nest_positions (eggs) e
# LotCapacityService.refresh_grass_patch_lot_capacity (2026-09-19, GRASS_PATCH — wild_vegetables e
# ogni futura risorsa dello stesso lot_source), che filtrano le posizioni GRASS correnti della
# macrocella con hash(str(micro_seed) + salt) sulla posizione contro questa soglia — stesso idioma
# già usato da ResourcePositionService per il bordo sfumato dei semi di rumore, salt DIVERSO per
# risorsa (mai lo stesso hash tra eggs e wild_vegetables, altrimenti selezionerebbero sempre
# esattamente le stesse microcelle). Default 0.0 (nessuna .tres esistente lo valorizza tranne
# eggs.tres/wild_vegetables.tres): un .tres che non lo valorizza esplicitamente produce quindi
# zero lotti, mai un fallback silenzioso a una probabilità che sembra normale — stesso principio
# di units_per_mature_plant sopra.
@export var patch_probability: float = 0.0

# Intervallo [patch_weight_min, patch_weight_max] del peso di UN lotto (2026-09-18, richiesta
# utente — eggs, "i nidi hanno tutti peso uniforme... rendi il peso variabile per nido";
# RINOMINATO da nest_weight_min/max il 2026-09-19 insieme a patch_probability sopra) — consultato
# SOLO da TerrainScatteredResourceService.compute_egg_nest_positions, che risolve il peso di ogni
# nido con hash(str(micro_seed) + salt) sulla posizione (STESSO idioma/STESSA fonte di micro_seed
# di patch_probability sopra, ma un salt DIVERSO — mai lo stesso hash usato per decidere SE una
# posizione è un lotto, altrimenti probabilità e peso sarebbero perfettamente correlati invece che
# indipendenti) interpolato linearmente in questo intervallo. La ripartizione resta stock ×
# peso_nido / peso_totale (TerrainScatteredResourceService.get_egg_stock_available_at) — il totale
# raccoglibile in una macrocella non cambia, solo come si distribuisce tra nidi ricchi e poveri.
# CHI LO LEGGE (2026-09-19, richiesta utente — commento aggiornato per dire esattamente chi legge
# e chi ignora questo campo): SOLO eggs (modello a stock aggregato ripartito per peso, vedi sopra).
# Le risorse "capacità per lotto" (pebble/stick/plant_fiber/mushroom/wild_vegetables) lo IGNORANO
# tutte, pur avendolo presente/export-abile sul proprio .tres come ogni SecondaryResourceRules —
# wild_vegetables in particolare usa invece patch_capacity_min/max sotto (modello a capacità
# ASSOLUTA per lotto, nessuno stock aggregato da ripartire) — due campi distinti perché sono
# concettualmente diversi, non lo stesso valore con un nome diverso; le altre quattro non hanno
# alcun concetto di "peso relativo" nel proprio modello. Default [0.5, 1.5] (richiesta esplicita
# utente): nessun'altra .tres oltre eggs.tres valorizza questi due campi oggi. patch_weight_min ==
# patch_weight_max (incluso il default 0.0==0.0 di una .tres che non li valorizza affatto) equivale
# a peso uniforme — nessun caso speciale nel codice che li consulta, la formula regge da sola anche
# con un intervallo degenere.
@export var patch_weight_min: float = 0.5
@export var patch_weight_max: float = 1.5

# Intervallo [patch_capacity_min, patch_capacity_max] della capacità RAW di UN lotto (2026-09-19,
# richiesta utente — wild_vegetables, "capacità per lotto come stick/mushroom... un valore
# derivato dallo stesso hash (salt diverso) in un intervallo configurabile"): consultato SOLO da
# LotCapacityService.refresh_grass_patch_lot_capacity (lot_source GRASS_PATCH), che risolve la
# capacità RAW di ogni lotto con hash(str(micro_seed) + salt) sulla posizione (stesso idioma di
# patch_probability/patch_weight_min/max sopra, salt ancora diverso — indipendente sia da "è un
# lotto?" sia dal peso eggs) interpolata linearmente in questo intervallo, poi moltiplicata dal
# chiamante per un fattore legato a dedicated_space(GRASS) della macrocella (un prato rado rende
# meno di uno fitto) — quel fattore NON vive qui, è specifico della formula GRASS_PATCH, vedi
# refresh_grass_patch_lot_capacity. A differenza di patch_weight_min/max sopra, questo NON è un peso
# relativo da ripartire su uno stock aggregato: è una capacità ASSOLUTA per lotto, stesso
# significato di units_per_mature_plant × individui_maturi per stick/mushroom, solo che qui non
# ci sono individui da contare (GRASS non ne ha). Default 0 (nessuna .tres esistente lo valorizza
# tranne wild_vegetables.tres): stesso principio "0 = mai configurato, mai un fallback silenzioso"
# di units_per_mature_plant/patch_probability sopra.
@export var patch_capacity_min: int = 0
@export var patch_capacity_max: int = 0

@export_group("Lot capacity")
# Quale delle quattro formule di LotCapacityService risolve i lotti/capacità di questa risorsa —
# vedi SecondaryResourceTypes.LotSource per la spiegazione estesa di ciascun valore. NONE (default)
# = questa risorsa non usa il modello "capacità per lotto" (berry/acorn/fruit/eggs/forage/
# fish_meat/bird_meat restano tutte a NONE). Unica leva che TerrainScatteredResourceService.
# get_available/consume e GameScene._resolve_pickup_candidates leggono per decidere COME trattare
# una risorsa — aggiungerne una nuova in questa famiglia significa impostare questo campo (+ gli
# altri campi già esistenti che la formula scelta consulta: units_per_mature_plant per TREE_
# INDIVIDUAL/SHRUB_INDIVIDUAL, patch_probability/patch_capacity_min/max per GRASS_PATCH, nessuno
# in più per STONE_POSITION) sul proprio .tres, nessun codice nuovo.
@export var lot_source: SecondaryResourceTypes.LotSource = SecondaryResourceTypes.LotSource.NONE

@export_group("Fuel")
# Valore combustibile di UNA unità (2026-09-23, richiesta utente — sistema di produzione). 0.0
# (default) = non combustibile. Valorizzato solo su stick.tres (1.0, provvisorio in attesa di
# taratura). Letto da ProductionService (sezione Combustibile, dal 2026-09-24) per coprire
# recipe_fuel_required delle ricette in corso.
@export var fuel_value: float = 0.0

@export_group("Recipe")
# Ricetta di produzione presso una workstation (2026-09-23, richiesta utente — sistema di
# produzione, step 1: solo il dato, nessuna logica lo legge ancora). Una risorsa prodotta resta
# questa stessa classe: le risorse naturali lasciano l'intero gruppo ai default (vuoto = non
# producibile).
# Nome risorsa (secondary_resource_name) -> quantità consumata per UN ciclo di produzione — stessa
# forma di BuildingRules.required_materials.
@export var recipe_inputs: Dictionary = {}
# Unità di questa risorsa prodotte da UN ciclo.
@export var recipe_output_quantity: int = 1
# Lavoro necessario per UN ciclo, stessa unità di BuildingRules.required_labor.
@export var recipe_labor: float = 0.0
# Valore combustibile (somma di fuel_value degli input bruciati) richiesto per UN ciclo — 0.0 =
# nessun combustibile. Moltiplicato da BuildingRules.production_fuel_multiplier (2026-09-24, vedi
# ProductionService.get_required_fuel).
@export var recipe_fuel_required: float = 0.0
# Tipi di edificio (Building.building_type_name, es. "hut" — non la chiave tr() di BuildingRules.
# building_name) presso cui la ricetta è eseguibile. Vuoto = risorsa non producibile.
@export var recipe_workstation_types: Array[String] = []
