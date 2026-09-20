class_name BuildingRules
extends Resource

# Dati statici per un TIPO di edificio (una .tres per tipo, es. "hut.tres", "granary.tres") —
# stesso schema di AnimalRules per le specie animali: qui vive solo la DEFINIZIONE, mai lo stato
# di una singola istanza piazzata sulla mappa (quello è Building.gd). Caricata per convenzione da
# BuildingCalculator, stesso principio di AnimalCalculator/ResourceCalculator.

@export var building_name: String = "" # chiave tr(), es. "building_hut" — mai una stringa già tradotta qui

# Categoria del tipo (2026-09-07, richiesta utente) — vedi BuildingTypes.gd (stesso principio
# ExpiredObjectTypes/NotificationTypes: enum tenuto fuori da questa classe Resource). Nessun default
# esplicito: il primo valore dell'enum (RESIDENTIAL) è già un default ragionevole per un tipo non
# ancora classificato, stesso comportamento implicito di GDScript per qualunque campo enum-typed
# senza assegnazione — non serve un valore sentinella "non impostato" con solo due categorie
# esistenti, entrambe già valorizzate esplicitamente nei .tres. Solo il dato in questo passo: non
# ancora consultato da BuildBar/altra UI (nessun sottomenu per categoria ancora costruito).
@export var category: BuildingTypes.Category

# RINOMINATO da tech_level_required: int (2026-09-07, richiesta utente — modello dati albero
# tecnologie, vedi Idea.gd): "" = sempre costruibile (sostituisce il vecchio significato "0"),
# altrimenti Idea.id dell'idea che deve risultare in Folk.completed_ideas prima che questo edificio
# sia costruibile. Nessun riferimento orfano al vecchio nome/significato — tech_level_required non
# era consultato da nessuna logica (verificato in ricognizione, 2026-09-07), quindi il rename è
# sicuro: nessun confronto numerico da riscrivere altrove. Il confronto vero (Folk.completed_ideas.
# has(required_idea_id)) vive altrove, quando esisterà un vero consumatore: qui è solo il dato, non
# ancora consultato da nessuna logica.
@export var required_idea_id: String = ""

# Tempo minimo di processo, indipendente dalla forza lavoro sotto — anche con manodopera
# sufficiente a completare il lavoro in un solo giorno, la costruzione non può comunque finire
# prima di questi giorni (fasi che non si parallelizzano: es. una parete deve asciugare). Non
# ancora consultato da nessuna logica (vedi required_labor sotto per lo stesso discorso) — in
# futuro il completamento richiederà ENTRAMBE le soglie soddisfatte, non solo questa.
@export var min_construction_days: int = 5

# Quantità totale di lavoro necessaria per completare la costruzione, nella stessa unità del
# "daily" che verrà aggiunto alla futura classe Uomo (es. capanna=500, un uomo con daily=50 ci
# mette 10 giorni da solo, dieci uomini un giorno solo — ma vedi min_construction_days sopra per
# il floor che comunque si applica). Presuppone una popolazione di lavoratori assegnabile che oggi
# non esiste ancora (solo l'HumanIndividual del player, nessuna popolazione NPC umana) — per ora è solo
# il dato, non consultato da nessuna logica, stesso principio degli altri campi "futuri" qui sotto.
@export var required_labor: int = 0

# -1 = non degrada mai (nessuna scadenza per età) — mai 0, che si leggerebbe come "degrada subito".
@export var lifespan_years: int = -1

# Storage a SLOT (2026-09-07, richiesta utente — sostituisce concettualmente il vecchio
# storage_capacity: int, un singolo numero assoluto, rimosso) — capacità = storage_slot_count ×
# storage_space_per_slot, ma nessuna delle due metà è ancora consultata da alcuna logica: solo il
# dato, in attesa di un futuro sistema di storage a slot (non ancora costruito). Default 0/0 =
# nessuno storage, comportamento "innocuo" per un tipo che non lo valorizza esplicitamente.
@export var storage_slot_count: int = 0
@export var storage_space_per_slot: int = 0

# Categorie stoccabili in questo edificio (2026-09-09, richiesta utente, BuildingStorageService
# Step 1) — vuoto = accetta qualunque categoria (SecondaryResourceTypes.Category), stesso
# principio "array vuoto = nessuna restrizione" già seguito da AnimalRules.suitable_biomes/
# SubtypeRules.suitable_biomes. deposit_site/hut valorizzati entrambi vuoti per ora (nessun
# edificio specializzato ancora) — un futuro edificio specializzato (es. un granaio solo FOOD)
# lo restringerà esplicitamente nel proprio .tres.
@export var accepted_categories: Array[SecondaryResourceTypes.Category] = []

# Moltiplicatore di durabilità PER CATEGORIA DI RISORSA (2026-09-09, richiesta utente) — indice =
# SecondaryResourceTypes.Category (0=FOOD, 1=RAW_MATERIAL, 2=MEDICINAL — un
# elemento per valore dell'enum, da allungare quando se ne aggiunge uno in fondo), stesso principio "array indicizzato per
# enum" già in uso per HumanRules/AnimalRules (es. caloric_multiplier_by_age). Consultato da
# ResourceDecayService.advance_building_decay: l'incremento giornaliero di decay_fraction diventa
# 1/(day_durability × moltiplicatore) invece di 1/day_durability puro — >1.0 rallenta il
# decadimento (l'edificio "conserva meglio" quella categoria), <1.0 lo accelera, 1.0 = invariato.
# Default [1.0, 1.0, 1.0] per OGNI tipo esistente (deposit_site/hut non lo sovrascrivono ancora) —
# comportamento identico a prima dell'introduzione di questo campo finché non lo si valorizza
# esplicitamente in un .tres. Indicizzazione diretta (mai .get(), un Array non un Dictionary): un
# accesso fuori range (una futura categoria aggiunta senza aggiornare questo array) va trattato dal
# chiamante come "nessun moltiplicatore" (1.0), non un crash — vedi ResourceDecayService per la
# guardia.
@export var durability_multiplier_by_category: Array[float] = [1.0, 1.0, 1.0]

# Nome risorsa (stringa libera per ora, es. "wood"/"stick"/"stone"/"iron" — nessun enum dedicato
# finché non esiste un vero inventario/economia) -> quantità richiesta per completare la
# costruzione VERA E PROPRIA (BuildAction, non ancora scritta — vedi setup_site_material_name/
# setup_site_material_per_cell sotto per il fabbisogno materiale della fase PRECEDENTE, SetupSite).
@export var required_materials: Dictionary = {}

# Fabbisogno materiale della fase SetupSite (2026-09-14, richiesta utente — bugfix/chiarimento:
# SetupSiteAction leggeva required_materials["stick"] sopra, confondendo il fabbisogno del CANTIERE
# ("allestire il cantiere consuma legnetti") con quello della COSTRUZIONE vera e propria (il
# campo sopra, riservato a BuildAction) — DUE fasi/DUE fabbisogni distinti, mai lo stesso numero
# per costruzione: un futuro edificio potrà richiedere 4 stick per allestire il cantiere E un
# secondo materiale diverso (via required_materials) per costruirlo davvero.
#
# Regola (2026-09-14, richiesta utente): SEMPRE 4 stick per MICROCELLA occupata dall'edificio in
# fase di setup — quantità totale = setup_site_material_per_cell × required_space sotto (oggi
# required_space=1 per ogni tipo esistente, quindi sempre 4 totali). Default 4/"stick" su QUESTA
# classe (non sui singoli .tres) apposta: vale per OGNI tipo esistente/futuro senza dover editare
# ciascun .tres uno per uno — un futuro tipo che vorrà un materiale/quantità diversi lo
# sovrascriverà esplicitamente nel proprio .tres, esattamente come rest_multiplier/durability_
# multiplier_by_category sopra.
#
# UNICA FONTE DI VERITÀ per QUESTO fabbisogno, letta sia da SetupSiteAction.get_missing_material_
# quantity (gameplay/) sia da BuildingStorageService.can_accept/get_max_depositable (simulation/,
# ramo edificio incompleto) — deliberatamente su BuildingRules (simulation/) e non su una costante
# di SetupSiteAction (gameplay/): questo progetto non fa mai riferimenti simulation/ -> gameplay/
# (verificato in ricognizione, 2026-09-14), quindi il dato condiviso da servizi di ENTRAMBI i
# livelli deve vivere qui, mai su una classe Action.
@export var setup_site_material_name: String = "stick"
@export var setup_site_material_per_cell: int = 4

@export var max_durability: int = 50

# Spazio occupato in microcelle (stessa unità di MacroCellState.TOTAL_SPACE/dedicated_space per la
# vegetazione) — quanto della macrocella ospitante viene sottratto al budget condiviso quando
# l'edificio è completo. Non ancora sottratto da nessuna logica reale (nessuna integrazione con
# MacroCellState scritta qui): solo il dato, per ora.
@export var required_space: int = 0

# Flag per BuildingVerificationService (2026-08-30) — i criteri "questa cella è di un terreno
# proibito" NON sono universali come "non sconosciuta"/"non già occupata": variano da tipo a
# tipo (una capanna non può stare in acqua, un futuro molo sì; una futura cava sì sulla roccia).
# Default = comportamento restrittivo di oggi (solo terreno "normale"), così i tipi esistenti non
# cambiano finché non li si abilita esplicitamente.
@export var buildable_on_water: bool = false
@export var buildable_on_river: bool = false
@export var buildable_on_stone: bool = false

# Controlla SOLO il Criterio 7 di BuildingVerificationService (la porta non può affacciarsi su
# terreno ostacolato/ignoto) — un edificio senza porta (es. una futura fontana) semplicemente non
# ha quel vincolo. Il Criterio 8 (non bloccare la porta di un edificio ESISTENTE già piazzato)
# resta invece SEMPRE attivo indipendentemente da questo flag, anche costruendo un edificio senza
# porta propria: è un vincolo sull'edificio ESISTENTE vicino, non su quello che si sta piazzando.
@export var has_door: bool = true

# Raggio di visibilità in MICROCELLE, dentro la macrocella dell'edificio (2026-09-19, commento
# corretto: prima lo descriveva in macrocelle e "collegamento rimandato", ma il codice lo usa già
# così — vedi GameScene._building_visible_positions_for_cell, che alimenta
# FogOfWarRenderer.set_building_visible_positions). 0 = solo la microcella dell'edificio stessa (è
# comunque visibile e "vista" ad ogni ridisegno), 1 = anche le 8 microcelle intorno, 2 = un altro
# anello, ecc. — quadrato di lato 2r+1 (distanza di Chebyshev), ritagliato ai bordi della macrocella
# (nessuna rivelazione oltre il confine). Applicato SOLO agli edifici COMPLETI: un cantiere non
# completo rivela solo la propria microcella (raggio 0), così piazzare un cantiere senza finirlo non
# scopre territorio.
@export var visibility_radius: int = 0

# political_radius/cultural_radius/religious_radius: raggio in MACROCELLE (un edificio proietta il
# proprio effetto su macrocelle intere attorno a sé, unità diversa da visibility_radius sopra).
# 0 = solo la propria macrocella, 1 = anche le 8 adiacenti, 2 = un altro anello oltre quello, ecc. —
# anelli concentrici (distanza di Chebyshev), confermato con l'utente. Nessun consumatore ancora:
# per ora questi tre campi sono solo il dato che definirà i rispettivi effetti in futuro.
@export var political_radius: int = 0
@export var cultural_radius: int = 0
@export var religious_radius: int = 0

# Vincolo GLOBALE di unicità (2026-09-07, richiesta utente) — al più UN edificio con questo flag
# true può esistere in tutta la partita, indipendentemente da dove/quante volte si provi a
# piazzarlo (oggi solo lo Pebble Circle, il "centro villaggio" paleolitico). Controllato da
# GameScene._refresh_building_slots_buildable, che disabilita lo slot corrispondente in BuildBar
# quando un Building con questo flag esiste già — DELIBERATAMENTE non in
# BuildingVerificationService.is_position_buildable (quella resta legata solo a terreno/spazio/
# sovrapposizioni di UNA posizione, mai a "quanti edifici di un tipo esistono ovunque nel mondo").
# BuildingRules stessa resta solo il dato di TIPO. Default false — nessun tipo esistente (hut) è
# toccato.
@export var is_village_center: bool = false

# Flag per un futuro service generico "trova l'edificio più vicino che accetta X" (2026-09-10,
# richiesta utente — SOLO il dato in questo passo, nessuna logica di ricerca qui né altrove:
# quel service arriverà in un giro successivo, oggi la ricerca magazzino resta quella specifica
# di WarehouseSelectionService, non ancora generalizzata). Vero per lo Pebble Circle (vedi
# pebble_circle.tres) — è già la destinazione del ramo "pensiero" di UnloadAction (Daydream, vedi
# unload_action.gd), questo campo si limita a rendere quel fatto un dato consultabile su
# BuildingRules invece che implicito nel codice. Stesso stile di is_village_center sopra (dato di
# TIPO, non di istanza — nessuna logica ancora lo legge). Default false — nessun tipo esistente
# (hut/deposit_site) è toccato.
@export var accepts_thoughts: bool = false

# Numero massimo di individui che possono lavorare CONTEMPORANEAMENTE alla costruzione di questo
# edificio (2026-09-10, richiesta utente — preparazione Build Task, Step 1: SOLO il dato, nessuna
# logica di condivisione lavoro/assegnazione multipla ancora — arriverà con un giro successivo).
# Stesso stile/stessa posizione di accepts_thoughts sopra (campo semplice di TIPO, non di istanza).
# Default 1 = comportamento invariato per OGNI tipo esistente (hut/deposit_site/pebble_circle):
# nessun .tres da aggiornare, dato che il default vale già per tutti finché non lo si valorizza
# esplicitamente per un tipo che dovrà davvero ammettere più lavoratori in parallelo.
@export var max_builders: int = 1

# Moltiplicatore del recupero stamina per giorno quando un RestAction avviene in questo edificio
# (2026-09-12, richiesta utente — campo base per la Rest Task esplicita: SOLO il dato in questo
# passo, nessuna logica ancora lo legge — RestAction accetta già un parametro rest_multiplier
# moltiplicabile, ma niente qui/altrove risolve ancora questo campo da una Building concreta).
# Default 1.0 = neutro/nessun effetto, comportamento invariato per ogni tipo esistente finché non
# valorizzato esplicitamente (vedi hut.tres, 1.4 — unico .tres toccato in questo passo).
@export var rest_multiplier: float = 1.0

# Capacità residenziale (2026-09-12, richiesta utente — nuovo edificio Stick Tent + AssignHouse
# Service): quanti HumanIndividual.house_id possono puntare a UN'istanza di questo tipo
# contemporaneamente. 0 = non residenziale (default), il comportamento invariato per ogni edificio
# che non lo valorizza esplicitamente (pebble_circle/deposit_site restano a 0 — mai edifici dove
# vivere). Valorizzato su hut.tres (5) e stick_tent.tres (4) — vedi AssignHouseService.
# assign_pending_residents, l'unico consumatore oggi (conta gli occupanti scandendo human_
# individuals con house_id == building.id, confronta con questo tetto).
@export var max_residents: int = 0

# Tier del criterio di assegnazione residenziale (2026-09-12, richiesta utente) — SOLO
# PREDISPOSIZIONE per ora: AssignHouseService.assign_pending_residents usa OGGI un unico criterio
# per QUALUNQUE edificio residenziale, indipendentemente da questo valore (anzianità decrescente,
# i più anziani hanno priorità — vedi lì, questo campo non viene nemmeno letto in quel file ancora).
# L'idea è che tier PIÙ ALTI possano in futuro usare un criterio diverso (es. "famiglia/nucleo"
# invece di anzianità pura per una casa "di pregio") — nessuna logica differenziata per tier
# esiste ancora, questo è solo il dato pronto per quando servirà davvero. Int semplice (non enum,
# a differenza di es. BuildingTypes.Category) — DECISIONE: un enum richiederebbe già nominare i
# tier futuri (es. TIER_ANZIANITA/TIER_FAMIGLIA), una semantica non ancora decisa; un int libero
# non presuppone nulla, stesso principio "non un caso ipotetico anticipato" già seguito altrove nel
# progetto per campi di TIPO ancora privi di consumatori differenziati. Default 1 = valore neutro di
# partenza. Valorizzato su stick_tent.tres (1) e hut.tres (2) — solo per marcare una futura gerarchia
# di qualità, NESSUN effetto di gioco oggi.
@export var residency_assignment_tier: int = 1

# Moltiplicatori di movimento per chi cammina su una microcella occupata da un edificio COMPLETO di
# questo tipo (2026-09-19, richiesta utente — terra battuta: cammino meno faticoso). Default 1.0 =
# nessun effetto. Consultati SOLO da MovementTerrainService.rebuild, che li risolve UNA volta alla
# costruzione della mappa sparsa delle microcelle che deviano dalla norma (LiveMacroCell.
# movement_modifiers) — mai letti da qui a ogni query di movimento.
#   - movement_stamina_multiplier scala la sola quota BASE del costo di stamina per microcella
#     (WalkAction/RunAction.STAMINA_DRAIN_PER_MICROCELL_BASE), non il sovraccarico di carico e
#     utensili. < 1.0 = meno stamina (dirt_ground 0.95), > 1.0 = più stamina.
#   - movement_speed_multiplier scala la velocità di avanzamento (HumanIndividualMovementService).
# Nessuna percorribilità per ora (rocce/edifici non attraversabili): solo stamina e velocità.
@export var movement_stamina_multiplier: float = 1.0
@export var movement_speed_multiplier: float = 1.0
