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
# Stagione di reset pieno per fonti a stock persistente (consuming_depletes_primary = false):
# a inizio di questa stagione lo stock si azzera e riparte dal tetto pieno di quella stagione,
# scartando il residuo del ciclo precedente ("i frutti non si accumulano da un anno all'altro").
# Ignorato per FORAGE (consuming_depletes_primary = true), che resta stateless — vedi
# CaloricCalculator.update_secondary_resource_stock.
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
# VegetationPoolService.resolve_units_per_mature_individual (stick.tres/plant_fiber.tres oggi, i
# soli due tipi con un pool per-lotto derivato da individui maturi) — nessun'altra risorsa secondaria
# lo legge. Default 0 (non 3): un .tres che non lo valorizza esplicitamente deve produrre un warning
# visibile (capacity sempre 0), MAI un fallback silenzioso a un numero che sembra normale.
@export var units_per_mature_plant: int = 0
