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

# Filtro dedicato per gli STESSI log di ciclo vita ([ANIMAL AGING]/[ANIMAL BIRTHS]/[ANIMAL OLD AGE
# DEATHS]/[STOCHASTIC ROUND] con label AGING/BIRTHS/OLD AGE DEATHS), ma sul lato PREDATORI — che
# a differenza di SHOW_HERBIVORE_LIFECYCLE_LOGS sopra restavano SEMPRE visibili indipendentemente
# da quel flag (era così per design, quando l'attenzione era sulla sola natalità/mortalità/
# territorio dei lupi — vedi project memory). A false: nessun comportamento di simulazione
# cambia, solo il print viene soppresso — rimetti a true per riavere il dettaglio dei predatori.
const SHOW_PREDATOR_LIFECYCLE_LOGS := false

# Filtro dedicato per [LOD] Popolazioni totali/LEVEL_2/LEVEL_1 (LODOrchestrator.
# print_classification_log) — stampato ad ogni ricalcolo della focus region (attivazione/
# disattivazione di un vicino in streaming, vedi GameScene._refresh_lod_focus_region), quindi
# spesso durante l'esplorazione. A false: nessun comportamento di simulazione cambia, solo il
# print viene soppresso.
const SHOW_LOD_CLASSIFICATION_LOGS := true

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

# Filtro dedicato per [DAY TIMING] (WorldTimeService.advance_day) — tempo dei 4 passi che girano
# OGNI giorno indipendentemente dai checkpoint stagionali (consumo/predazione/stagger territorio/
# fame), mai coperti dal riepilogo [LOD TIMING] esistente (quello misura solo _run_seasonal_
# checkpoints). Aggiunto per capire se la lentezza percepita "anche nei giorni senza checkpoint"
# viene da uno di questi passi giornalieri o da altrove (rendering/streaming celle vive in
# GameScene). A false: nessun comportamento di simulazione cambia, solo il print viene soppresso.
const SHOW_DAILY_TIMING_LOGS := true

# Filtro dedicato per [VEG REFRESH TIMING] (GameScene._refresh_resource_visuals) — diagnostica per
# la Proposta 2 (evitare di costruire MultiMesh per individui coperti da FoW pieno): serve a capire
# se il costo dell'8.9s osservato al checkpoint stagionale (8 celle vive) è nella generazione
# posizioni (VegetationPositionService, indipendente dal FoW) o nel rebuild MultiMesh
# (MicroCellRenderer.set_vegetation_positions e affini) — solo il secondo beneficerebbe di un
# filtro per visibilità. A false: nessun comportamento di simulazione cambia, solo il print viene
# soppresso.
const SHOW_VEGETATION_REFRESH_TIMING_LOGS := true
