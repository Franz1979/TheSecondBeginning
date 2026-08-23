class_name DebugLogging

# Interruttore unico per tutti i print di debug temporanei aggiunti per validare growth/
# surplus/migration/mortality (terra e FISH). Metti a true per riattivarli tutti insieme
# senza scommentare riga per riga nei singoli servizi.
const ENABLED := true

# Filtro aggiuntivo per i log di ciclo vita (ANIMAL BIRTHS, ANIMAL AGING, ANIMAL OLD AGE DEATHS,
# BIRTH MITIGATION/TERRITORY DYNAMICS, ANIMAL HUNGER SUMMARY/ANIMAL HUNGER dettaglio,
# POPULATION SPLIT): con ENABLED sopra a true stampano sia erbivori che predatori, troppo rumoroso
# mentre si valida la sola natalità/mortalità/territorio dei lupi. A false: quei log restano
# visibili solo per le specie PredatorRules (ANIMAL HUNGER non stampa mai nulla in questo caso,
# visto che quel service processa solo erbivori per costruzione); gli erbivori continuano ad
# essere processati normalmente (nessun comportamento di simulazione cambia, solo il print viene
# soppresso). Rimetti a true per riavere subito tutti i log come prima, senza toccare i singoli
# servizi.
const SHOW_HERBIVORE_LIFECYCLE_LOGS := false

# Filtro dedicato per i log GIORNALIERI di PredationService ([PREDATION]/[PREDATION ATTEMPT]/
# [PREDATION STARVATION]): a differenza di SHOW_HERBIVORE_LIFECYCLE_LOGS sopra (che filtra gli
# erbivori lasciando sempre visibili i predatori), qui il filtro copre i predatori stessi — troppo
# rumoroso (una riga per branco per OGNI giorno, "silenzio compreso") ora che l'attenzione è sul
# nuovo riepilogo stagionale di AnimalHungerMortalityAggregateService. A false: nessun comportamento
# di simulazione cambia, solo il print viene soppresso — rimetti a true per riavere il dettaglio
# giornaliero delle cacce.
const SHOW_PREDATION_DAILY_LOGS := false

# Filtro dedicato per [HUNGER MORTALITY DIAGNOSTICS] (AnimalHungerMortalityAggregateService) — il
# blocco terreno/bioma/fonti caloriche per cella stampato per ogni gruppo Livello 1 che muore di
# fame aggregata. A false: nessun comportamento di simulazione cambia, solo il print viene
# soppresso — il riepilogo [HUNGER MORTALITY AGGREGATE SUMMARY] resta comunque visibile (gated
# solo da ENABLED, non da questo flag), è solo il dettaglio diagnostico per cella a sparire.
const SHOW_HUNGER_MORTALITY_DIAGNOSTICS_LOGS := false

# Filtro dedicato per [TERRITORY DYNAMICS] dei SOLI predatori (TerritoryDynamicsService) — a
# differenza di SHOW_HERBIVORE_LIFECYCLE_LOGS sopra (che filtra gli erbivori lasciando sempre
# visibili i predatori), qui è il verso opposto: filtra i predatori stessi. A false: nessun
# comportamento di simulazione cambia, solo il print viene soppresso.
const SHOW_PREDATOR_TERRITORY_DYNAMICS_LOGS := false

# Filtro dedicato per i log diagnostici di seeding/crescita/migrazione di FISH e BIRDS
# (ParametricResourceSetupService.populate_fish/populate_birds, FaunaGrowthService,
# FaunaMigrationService) — mostra il calcolo (capacità, presence_chance, densità, spazio/
# quantità risultante) per ogni cella dove la risorsa viene effettivamente seminata/cresce/
# migra, non per ogni cella esaminata (altrimenti 10000 righe anche quando la risorsa è assente).
# A false: nessun comportamento di simulazione cambia, solo il print viene soppresso.
const SHOW_FAUNA_DIAGNOSTICS_LOGS := false
