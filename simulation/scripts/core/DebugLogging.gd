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
# fame). Esteso (richiesta utente, 2026-09-05 — "nascondi i log timing, rendono illeggibile
# l'evento mortality") a coprire anche [LOD TIMING]/[GAMESCENE DAY]/[DAY TOTAL]/[SECONDARY STOCK
# SKIP], prima sparsi tra questo flag e DebugLogging.ENABLED — tutti diagnostici di
# performance/timing, stesso interruttore unico. A false: nessun comportamento di simulazione
# cambia, solo il print viene soppresso — rimetti a true per riavere tutto il gruppo com'era
# (utile quando si torna a misurare i checkpoint stagionali).
const SHOW_DAILY_TIMING_LOGS := false

# Filtro dedicato per [VEG REFRESH TIMING]/[VEG REFRESH TRIGGER]/[DEBUG INDIVIDUI]/[DEBUG SPAZIO]/
# [DEBUG CELLE VIVE] (GameScene._refresh_resource_visuals e affini) — diagnostica per la Proposta 2
# (evitare di costruire MultiMesh per individui coperti da FoW pieno): serve a capire se il costo
# dell'8.9s osservato al checkpoint stagionale (8 celle vive) è nella generazione posizioni
# (VegetationPositionService, indipendente dal FoW) o nel rebuild MultiMesh (MicroCellRenderer.
# set_vegetation_positions e affini) — solo il secondo beneficerebbe di un filtro per visibilità.
# A false (richiesta utente, 2026-09-02 — troppo rumoroso durante l'esplorazione normale, un
# blocco intero ad ogni ~3 microcelle di movimento): nessun comportamento di simulazione cambia,
# solo il print viene soppresso. Rimetti a true per riavere tutto il gruppo come prima.
const SHOW_VEGETATION_REFRESH_TIMING_LOGS := false

# Filtro dedicato per [FOW REDRAW TIMING] (FogOfWarRenderer._draw) — diagnostica per lo Step 4 FoW
# multi-sorgente (2026-09-02): misura il costo reale del ciclo da 10.000 celle ora che il test di
# distanza è a N vie (una per sorgente rilevante, vedi GameScene._relevant_source_positions_for_cell)
# invece che a una sola — serve a capire se quell'aggiunta pesa abbastanza da giustificare uno
# "splat" pre-calcolato per-sorgente (rimandato finché non misurato, vedi discussione con l'utente).
# A false (richiesta utente, 2026-09-04 — diagnostica del primo test già raccolta, log troppo
# rumorosi ora): nessun comportamento di simulazione cambia, solo [FOW REDRAW TIMING]/[FOW REDRAW
# COUNT] vengono soppressi. Non rimosso: tornerà utile per rimisurare dopo un futuro cambiamento
# al ciclo di redraw multi-sorgente.
const SHOW_FOW_REDRAW_TIMING_LOGS := false

# Filtro dedicato per [HUMAN VIEW TIMING] (HumanIndividualView._process/_draw) — richiesta utente,
# 2026-09-04: verificare col numero reale (non a occhio dal log FoW, che non misura affatto questo
# nodo — sono CanvasItem separati) se disegnare/animare i pipottini (busto/gambe/braccia/capelli
# via _draw() immediate-mode, fino a ~20 individui contemporanei — vedi ricognizione) pesa in modo
# misurabile. Accumulatori STATIC (non per-istanza: HumanIndividualView ha fino a 20 istanze
# contemporanee, un log per istanza per frame sarebbe troppo rumoroso) sommati su TUTTE le view in
# una finestra di un secondo, stesso principio già usato per [FOW REDRAW COUNT]. A false: nessun
# comportamento di simulazione cambia, solo il print viene soppresso.
# A false (richiesta utente, 2026-09-04 — dato già raccolto: ~0.4-0.45ms per redraw di un singolo
# individuo, confermato col fix dell'early-out in HumanIndividualView). Non rimosso: tornerà utile
# quando più di un individuo potrà muoversi contemporaneamente (oggi limite esplicito a uno solo),
# per rimisurare il costo aggregato in quello scenario.
const SHOW_HUMAN_VIEW_TIMING_LOGS := false
