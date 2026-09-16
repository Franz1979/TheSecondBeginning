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
#
# RINOMINATO in SHOW_LOD_LOGS (2026-09-16, richiesta utente — riordino dei log di debug per
# categoria): stesso identico consumatore/comportamento, solo il nome allineato alla categoria
# "LOD" del nuovo schema in fondo a questo file (vedi blocco "CATEGORIE" sotto) — nessun secondo
# flag separato da tenere sincronizzato.
const SHOW_LOD_LOGS := false

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

# Filtro dedicato per [HUMAN STAMINA RECALC] (HumanStaminaIndividualService, agganciato a
# GameTimeService._on_day_advanced) — riga diretta (non un accumulatore come SHOW_HUMAN_VIEW_
# TIMING_LOGS sopra: gira una volta al GIORNO, non ad alta frequenza per-frame, quindi una riga per
# ricalcolo resta leggibile) col tempo impiegato a ricalcolare HumanIndividual.max_stamina per
# l'intera popolazione. A false: nessun comportamento di simulazione cambia (il ricalcolo gira
# comunque ogni giorno), solo il print viene soppresso.
const SHOW_STAMINA_RECALC_LOGS := false

# Filtro dedicato per [HUMAN CARRY CAPACITY RECALC] (HumanCarryCapacityIndividualService,
# agganciato a GameTimeService._on_day_advanced) — stesso identico trattamento di
# SHOW_STAMINA_RECALC_LOGS sopra (riga diretta, una volta al giorno) per il ricalcolo di
# HumanIndividual.max_carry_capacity. A false: nessun comportamento di simulazione cambia (il
# ricalcolo gira comunque ogni giorno), solo il print viene soppresso.
const SHOW_CARRY_CAPACITY_RECALC_LOGS := false

# Filtro dedicato per [HUMAN VITALS RECALC] (HumanVitalsIndividualService, agganciato a
# GameTimeService._on_day_advanced) — 2026-09-13, richiesta utente, 5 nuovi parametri vitali
# hunger/thirst/health/happiness/loyalty: stesso identico trattamento di SHOW_STAMINA_RECALC_LOGS/
# SHOW_CARRY_CAPACITY_RECALC_LOGS sopra (riga diretta SOLO quando un clamp scatta davvero, non un
# accumulatore). A false: nessun comportamento di simulazione cambia (il ricalcolo gira comunque
# ogni giorno), solo il print viene soppresso.
const SHOW_VITALS_RECALC_LOGS := false

# Filtro dedicato per [VITALS INTERACTION] (HumanVitalsInteractionService, agganciato a
# GameTimeService._on_day_advanced, SUBITO DOPO HumanVitalsIndividualService.recalculate_vitals)
# — 2026-09-13, richiesta utente: le due regole giornaliere stamina->happiness/happiness->loyalty.
# Riga diretta SOLO per gli individui toccati (stesso principio "non ogni ricalcolo, solo l'evento
# reale" di SHOW_VITALS_RECALC_LOGS sopra — qui però OGNI individuo è sempre "toccato", una delle
# due regole scatta comunque in un verso o nell'altro, quindi la riga è sempre stampata per ognuno,
# non solo quando cambia qualcosa). A false: nessun comportamento di simulazione cambia, solo il
# print viene soppresso.
const SHOW_VITALS_INTERACTION_LOGS := false

# Filtro dedicato per [SELECTED PANEL REFRESH] (GameScene._on_day_advanced, refresh giornaliero del
# pannello individuo selezionato) — riga diretta (stesso stile di SHOW_STAMINA_RECALC_LOGS sopra:
# gira una volta al giorno, costo atteso trascurabile — 0 o 1 individuo selezionato, mai un ciclo
# sulla popolazione intera — ma misurato con un dato reale invece che assunto). A false: nessun
# comportamento di simulazione cambia (il refresh gira comunque ogni giorno), solo il print viene
# soppresso.
const SHOW_SELECTED_PANEL_REFRESH_LOGS := false

# ---------------------------------------------------------------------------------------------
# CATEGORIE (2026-09-16, richiesta utente — "riordino dei log di debug") — SOSTITUISCONO i flag
# dedicati per-feature che c'erano prima in questa posizione (SHOW_TASK_TOTAL_COST_LOGS,
# SHOW_UNLOAD_COMPLETION_LOGS, SHOW_SKILL_GROWTH_LOGS, SHOW_RUN_DEBUG_LOGS, SHOW_JUMP_DEBUG_LOGS —
# rimossi, nessun consumatore li legge più) e SHOW_LOD_CLASSIFICATION_LOGS più sopra (rinominato
# in SHOW_LOD_LOGS, stesso consumatore). Ogni categoria raggruppa TUTTI i prefissi di log di un
# solo sottosistema sotto UN SOLO flag, invece di un flag per singolo tipo di riga — più facile da
# tenere a mente/accendere in blocco quando si indaga un'area, meno voci da scorrere in questo
# file. A false su qualunque di questi: nessun comportamento di simulazione cambia MAI, solo il
# print viene soppresso — stesso principio di ogni altro flag in questo file.
#
# MOVEMENT — [RUN DEBUG] (RunAction.get_stamina_delta), [JUMP DEBUG] (JumpAction.get_stamina_delta).
const SHOW_MOVEMENT_LOGS := false

# RESOURCE_POOL — [DBG_POOL] (VegetationPoolService).
const SHOW_RESOURCE_POOL_LOGS := false

# LOD — [LOD] (LODOrchestrator.print_classification_log — vedi SHOW_LOD_LOGS più sopra, stesso
# flag, questo commento resta qui solo per l'elenco delle categorie).

# RECONNECT_FACTORY — [RECONNECT DEBUG]/[DBG_PICKUP] (GameScene, ricollegamento segnali dopo
# reload), [TASKFACTORY DEBUG] (task_factory.gd), [CENTER DEBUG] (GameScene), [PICKUP CMD DEBUG]
# (GameScene, comando debug raccolta).
const SHOW_RECONNECT_FACTORY_LOGS := false

# TASK_LIFECYCLE — [TASK COST] (Task.print_cost_summary), [INTERRUPT DEBUG]/[RESUME WALKBACK]
# (HumanIndividualActionService), [TASK GUARD]/[TASK SUSPEND] (HumanIndividual), [SKILL GROWTH]
# (HumanIndividualActionService), [QUEUE OVERFLOW] (TaskQueueService).
const SHOW_TASK_LIFECYCLE_LOGS := false

# IDLE — [IDLE FALLBACK] (IdleTaskAssignmentService), [REST]/[EMERGENCY REST]
# (NeedTaskAssignmentService), [WANDER]/[PLAY] (GameScene, trigger manuali tasti G/P per le stesse
# due Task).
const SHOW_IDLE_LOGS := true

# TRANSPORT_BUILD — [UNLOAD] (unload_action.gd), [WALK AWAY]/[WAREHOUSE SEARCH]/
# [THOUGHT TARGET SEARCH]/[BUILD MATERIAL NEEDED]/[BUILD MATERIAL BONUS]/[BUILD MATERIAL RETRY]
# (HumanIndividualActionService), [BUILD]/[BUILD DEBUG]/[TRANSPORT] (GameScene),
# [BUILD PROGRESS DEBUG]/[OCCUPIED SPACE DEBUG] (SetupSiteAction/ClearAction/BuildAction),
# [ASSIGN HOUSE] (AssignHouseService).
const SHOW_TRANSPORT_BUILD_LOGS := false

# SAFETY — [ZOMBIE GUARD] (TaskQueueService/HumanIndividualActionService/HumanIndividual),
# [BORDER] (GameScene). Default true (a differenza della maggior parte delle categorie sopra):
# segnalano un'anomalia reale (una task zombie intercettata, un attraversamento di bordo), non un
# evento di routine — utile vederli anche senza aver acceso apposta il debug.
const SHOW_SAFETY_LOGS := true

# DAILY_SUMMARY — [DBG_TASK] (GameScene._on_day_advanced, riepilogo giornaliero task/stamina/
# carico per individuo). Default true, stesso motivo di SHOW_SAFETY_LOGS: introdotto apposta come
# strumento di indagine sempre pronto, non rumoroso quanto le categorie per-frame sopra (gira una
# volta al giorno).
const SHOW_DAILY_SUMMARY_LOGS := true
