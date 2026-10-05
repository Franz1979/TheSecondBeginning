class_name MicroCellRenderer
extends Node2D

const CELL_SIZE: int = 10
const NEIGHBOR_STRIP_DEPTH: int = 40 # px, solo un'anteprima, non è territorio giocabile
const COLOR_STONE := Color(0.45, 0.45, 0.45, 0.6) # alpha bassa: i cerchi sovrapposti si fondono per densità
# Sassi/pebble (2026-09-08, richiesta utente: "colore un po' più simile a stone, magari un po'
# più scuri") — stesso grigio di base di COLOR_STONE ma un filo più scuro, invece del tono
# bruno-chiaro precedente.
const COLOR_PEBBLE := Color(0.35, 0.35, 0.34, 0.85)
const VEGETATION_COLORS := {
	GameTypes.WorldObjectType.TREE: Color(0.10, 0.45, 0.15, 0.85),
}
const COLOR_TREE_TRUNK := Color(0.40, 0.26, 0.13, 0.95)
const COLOR_TREE_FRUIT_WILD := Color(0.75, 0.50, 0.15, 0.95) # marroncino: ghiande/castagne (wild_fruit)
const COLOR_TREE_FRUIT_DOMESTICABLE := Color(0.80, 0.15, 0.15, 0.95) # rosso: frutti da futura domesticazione (mele/pere)
const COLOR_SHRUB_GREEN := Color(0.38, 0.55, 0.18, 0.85) # lobi "fogliosi"
const COLOR_SHRUB_BROWN := Color(0.50, 0.38, 0.20, 0.85) # lobi "legnosi"
const COLOR_SHRUB_BERRY := Color(0.75, 0.08, 0.10, 0.95) # puntini rossi per gli shrub fruit_bearing
const COLOR_GRASS_BASE := Color(0.28, 0.58, 0.18, 0.85) # verde più scuro
const COLOR_GRASS_TIP := Color(0.55, 0.80, 0.30, 0.85)  # verde più chiaro
const COLOR_FISH_BODY := Color(0.45, 0.55, 0.65, 0.85) # grigio-azzurro argentato
const COLOR_FISH_TAIL := Color(0.35, 0.44, 0.53, 0.85) # leggermente più scuro del corpo
# Palette erba per stagione (base=radice/filo scuro, tip=punta): PRIMAVERA/ESTATE riusano
# COLOR_GRASS_BASE/TIP sopra (verde vivo, invariato), AUTUNNO vira a dorato/paglierino,
# INVERNO a un verde-grigio spento (vegetazione dormiente). Cambio netto a inizio stagione,
# non una transizione giorno per giorno — vedi _rebuild_grass_buffers.
const GRASS_PALETTE_BY_SEASON := {
	GameTypes.Season.WINTER: {"base": Color(0.42, 0.40, 0.26, 0.80), "tip": Color(0.58, 0.52, 0.34, 0.80)},
	GameTypes.Season.SPRING: {"base": Color(0.28, 0.58, 0.18, 0.85), "tip": Color(0.55, 0.80, 0.30, 0.85)},
	GameTypes.Season.SUMMER: {"base": Color(0.28, 0.58, 0.18, 0.85), "tip": Color(0.55, 0.80, 0.30, 0.85)},
	GameTypes.Season.AUTUMN: {"base": Color(0.55, 0.42, 0.12, 0.85), "tip": Color(0.82, 0.62, 0.18, 0.85)},
}
# Colore chioma per stagione, solo per gli alberi NON conifer (is_evergreen=false: wood_only,
# wild_fruit, domesticable_fruit — non distinti fra loro a livello di rendering, un solo colore
# "chioma caduca" condiviso). SPRING/SUMMER riusano VEGETATION_COLORS[TREE] (verde normale,
# invariato), AUTUMN vira a marrone-rossiccio, WINTER scende ad alpha molto bassa su un colore
# spento grigio-bruno anziché verde ("rami spogli visti da lontano", non del tutto invisibile).
# Gli alberi conifer non usano questa palette: chioma a forma di abete, sempre piena/verde in
# ogni stagione — vedi _rebuild_tree_multimeshes (il sottotipo "conifer" arriva già deciso in
# tree_individual_subtype, vedi IndividualVegetationService).
const TREE_CANOPY_PALETTE_BY_SEASON := {
	GameTypes.Season.WINTER: Color(0.35, 0.30, 0.22, 0.20),
	GameTypes.Season.SPRING: Color(0.10, 0.45, 0.15, 0.85),
	GameTypes.Season.SUMMER: Color(0.10, 0.45, 0.15, 0.85),
	GameTypes.Season.AUTUMN: Color(0.55, 0.28, 0.10, 0.85),
}
const COLOR_TREE_CONIFER_CANOPY := Color(0.10, 0.45, 0.15, 0.85) # identico al verde normale odierno
# Marker statici per uno slot bloccato da taglio (vedi cut_positions) — forme DISTINTE per tipo,
# non un placeholder unico: TREE riusa la mesh del tronco vero (_tree_trunk_mesh, stesso colore
# COLOR_TREE_TRUNK) ridotta a TREE_STUMP_HEIGHT_RATIO della sua altezza normale e senza chioma —
# un ceppo, non un albero mozzato a metà; SHRUB usa una sagoma a stella (rovi intrecciati, vedi
# _build_bramble_mesh) invece del blob tondo dei lobi vivi, per leggersi come "cespuglio raso e
# aggrovigliato" a colpo d'occhio. Entrambe scalate da PlayerHarvestService.cut_individual al
# momento del taglio (vedi vegetation_cut_exceptions.size_multiplier) — stessa proporzione
# età×densità di un individuo vivo equivalente, non una taglia fissa.
const COLOR_BRAMBLE := Color(0.35, 0.22, 0.12, 0.95) # marrone scuro, stesso tono di un ceppo fresco
const TREE_STUMP_HEIGHT_RATIO: float = 1.0 / 3.0
const BRAMBLE_BASE_RADIUS: float = 1.5
const BRAMBLE_POINT_COUNT: int = 7
const BRAMBLE_INNER_RADIUS_RATIO: float = 0.35
# Marker "pianta morta" (mortalità naturale, vedi vegetation_death_exceptions). SHRUB resta il
# placeholder generico a cerchio (vedi DEAD_RADIUS_BY_TYPE, ora usato solo per lui — richiesta
# esplicita dell'utente di lasciarlo così per ora). TREE invece ha una sagoma dedicata — vedi
# _build_dead_tree_mesh/_build_dead_tree_transform sotto: colore tronco (non grigio, per non
# leggersi come un placeholder generico), nessuna chioma (a differenza del ceppo da taglio,
# _build_tree_stump_transform, che è anche troncato in altezza — qui l'albero morto resta IN
# PIEDI, solo spoglio), e una sagoma SPEZZATA (una piega a metà altezza, non una linea dritta —
# altrimenti a distanza si confondeva con un filo d'erba) più allungata del tronco vivo, oltre
# alla consueta leggera inclinazione deterministica per-istanza (DEAD_TREE_MAX_TILT_DEGREES).
const COLOR_DEAD := Color(0.55, 0.52, 0.46, 0.80) # grigio-bruno spento, "pianta secca" (solo SHRUB)
const DEAD_RADIUS_BY_TYPE := {
	GameTypes.WorldObjectType.SHRUB: 1.4,
}
const DEAD_TREE_TRUNK_WIDTH_RATIO: float = 0.7 # frazione della larghezza del tronco vivo (1.6)
const DEAD_TREE_MAX_TILT_DEGREES: float = 12.0
# Punti (in spazio unitario locale, stessa convenzione 0..1 del quad del tronco vivo) della
# spezzata: base a terra -> piega -> cima, deliberatamente NON allineati in verticale (silhouette
# a "<": la piega sporge da un lato, la cima torna verso il centro) — vedi _build_dead_tree_mesh.
const DEAD_TREE_BEND_POINTS: Array = [Vector2(0.5, 1.0), Vector2(0.12, 0.42), Vector2(0.62, 0.0)]
const DEAD_TREE_LINE_HALF_THICKNESS: float = 0.11
# Finestra di fruttificazione per i marcatori bacche/frutti (tarda estate/autunno): fuori da
# queste stagioni i marcatori non vengono disegnati, ma il sottotipo congelato dell'individuo
# (vedi tree_individual_subtype/shrub_individual_subtype) resta invariato — è solo un gate a
# draw-time.
const FRUITING_SEASONS := [GameTypes.Season.SUMMER, GameTypes.Season.AUTUMN]
const BOUNDARY_DASH_COLOR := Color(0, 0, 0, 0.6)
const BOUNDARY_DASH_WIDTH: float = 2.0
const BOUNDARY_DASH_LENGTH: float = 6.0

# Edifici piazzati (vedi World.buildings/GameScene._place_building_at) — vista dall'ALTO (non più
# pareti+tetto di profilo come il primo tentativo, vedi discussione con l'utente 2026-08-30: serve
# a mostrare l'orientamento della porta, che di profilo non si potrebbe leggere), stessa
# convenzione/costanti di BuildingGhost per l'anteprima, ma OPACA e senza la variante rossa "non
# edificabile" (un edificio già piazzato è sempre valido). Pochi edifici per macrocella attesi:
# disegnati immediate-mode come il fiume/i confini, nessun MultiMesh.
#
# Capanna TONDA dentro un recinto TONDO — "una o dentro una O" (richiesta utente, 2026-08-30,
# coerente con la discussione precedente sulla capanna preistorica: un diametro di 10m/microcella
# era spropositato) — due cerchi concentrici, il cerchio interno della capanna vera
# (BUILDING_HUT_RADIUS) più piccolo del cerchio esterno del recinto (BUILDING_FENCE_RADIUS,
# linea continua e più sottile del bordo della capanna, vedi _draw_building_fence sotto — non
# tratteggiato, non un quadrato: entrambi tentativi precedenti scartati), con una vera apertura
# sul recinto in corrispondenza della porta (stesso spicchio mancante della capanna) e una
# lineetta verso l'esterno a simulare il cancello aperto sul cardine. Nessun cambiamento alla
# logica di occupazione spazio/edificabilità, resta comunque tutta la microcella (vedi
# discussione: la capanna occupa un intero "lotto", non solo la propria impronta). La porta è un
# RITAGLIO a V nel cerchio, riempito col colore del bordo (non lasciato trasparente sul terreno
# sotto, leggeva come una sagoma "stile Batman") — vedi _building_hut_polygon: il poligono della
# capanna segue il cerchio tranne nel punto della porta, dove rientra fino all'apice invece di
# seguire l'arco; il triangolo risultante viene poi riempito a parte col colore del bordo).
const BUILDING_COLOR := Color(0.55, 0.42, 0.28, 1.0)
const BUILDING_OUTLINE_COLOR := Color(0.3, 0.22, 0.12, 1.0)
const BUILDING_OUTLINE_WIDTH: float = 0.6
const BUILDING_FENCE_COLOR := Color(0.45, 0.35, 0.2, 0.9)
const BUILDING_FENCE_WIDTH: float = 0.4
const BUILDING_HUT_RADIUS: float = 2.5
const BUILDING_FENCE_RADIUS: float = 4.0
const BUILDING_GATE_LENGTH: float = 1.5
const BUILDING_DOOR_NOTCH_HALF_WIDTH: float = 1.0
const BUILDING_DOOR_NOTCH_DEPTH: float = 1.3
const BUILDING_CIRCLE_SEGMENTS: int = 24

# Pebble Circle (2026-09-07, richiesta utente) — "centro villaggio" paleolitico, is_village_center
# nelle sue BuildingRules (vincolo di unicità globale verificato da GameScene/BuildBar, non da
# questo renderer: qui si sa solo disegnare). Nessuna porta (has_door=false in pebble_circle.tres),
# quindi nessun rientro a V come la capanna — un anello di sassolini attorno al centro. Palette
# grigia per distinguerlo a colpo d'occhio dal marrone della capanna.
#
# RIVISTO (2026-09-07, richiesta utente, dopo il primo giro di test: "le pietre sono tutte uguali e
# sembrano sfocate") — non più cerchi perfetti (draw_circle/draw_arc, tutti identici, bordo sottile
# a basso contrasto che a piccola scala legge come una macchia sfumata): ogni sassolino è ora un
# poligono IRREGOLARE (vedi _pebble_blob_polygon), stesso principio già in uso per le pietre naturali
# (MultiMesh con STONE_VARIANT_COUNT mesh pre-generate jittered, vedi _rebuild_stone_multimeshes) ma
# qui immediate-mode, coerente con lo stile "usa e getta" della capanna: solo PEBBLE_CIRCLE_PEBBLE_
# COUNT sassolini per l'unico Pebble Circle possibile in partita, nessun bisogno di MultiMesh. Seed
# deterministico = indice del sassolino (0..PEBBLE_CIRCLE_PEBBLE_COUNT-1), non la posizione: essendo
# l'edificio unico per costruzione (vedi vincolo di unicità), non c'è rischio che due Pebble Circle
# nel mondo condividano lo stesso seed e sembrino stampati dallo stesso timbro. Bordo scuro più
# spesso per un contorno netto invece che sfumato.
#
# RITARATO 2026-09-12 (richiesta utente — rename Stone Circle -> Pebble Circle, "sassolini più
# piccoli in cerchio e un po' più numerosi"): raggio 0.75->0.45, conteggio 8->14, anello invariato
# (PEBBLE_CIRCLE_RING_RADIUS) — più sassolini più fitti sullo stesso anello, non un anello più largo.
const PEBBLE_CIRCLE_COLOR := Color(0.60, 0.58, 0.54, 1.0)
const PEBBLE_CIRCLE_OUTLINE_COLOR := Color(0.24, 0.22, 0.19, 1.0)
const PEBBLE_CIRCLE_OUTLINE_WIDTH: float = 0.5
const PEBBLE_CIRCLE_RING_RADIUS: float = 4.0
const PEBBLE_CIRCLE_PEBBLE_RADIUS: float = 0.45
const PEBBLE_CIRCLE_PEBBLE_COUNT: int = 14
const PEBBLE_CIRCLE_BLOB_VERTEX_COUNT: int = 8

# Deposit Site (2026-09-08, richiesta utente) — "sito di deposito", a disegno una chiazza di terra
# battuta SQUADRATA (2026-09-08, revisione: "molto più squadrato", non un quadrato perfetto però):
# nessuna porta/recinto/rotazione (has_door=false in deposit_site.tres). Stessa geometria (duplicata
# apposta, stesso principio già in uso tra MicroCellRenderer/BuildingGhost) di
# BuildingGhost._draw_deposit_site (entrambi da DepositSiteShape), così l'anteprima e l'edificio finito
# coincidono esattamente.
# Riempimento schiarito (2026-09-12, richiesta utente: "leggermente più chiaro, lascia il bordo di
# questo colore", poi "ancora un po' più chiaro") — DEPOSIT_SITE_COLOR alzato in due passi (era
# 0.42/0.34/0.24, poi 0.50/0.41/0.29), DEPOSIT_SITE_OUTLINE_COLOR INVARIATO apposta in entrambi, come
# richiesto.
const DEPOSIT_SITE_COLOR := Color(0.58, 0.48, 0.34, 1.0)
const DEPOSIT_SITE_OUTLINE_COLOR := Color(0.24, 0.18, 0.12, 1.0)
const DEPOSIT_SITE_OUTLINE_WIDTH: float = 0.5
# 4.5 (2026-09-08, richiesta utente: "allarga ancora di più, quasi ad occupare tutta la microcella")
# — la microcella è larga CELL_SIZE=10, quindi mezza cella = 5: 4.5 lascia un margine minimo prima
# del bordo anche col jitter massimo (vedi DepositSiteShape: lati irregolari spostati al più di 0.05 × semilato verso l esterno).
const DEPOSIT_SITE_HALF_SIDE: float = 4.5
# Sagoma con angoli smussati diversamente da DepositSiteShape.build_polygon (2026-09-19, richiesta
# utente) — il vecchio poligono a 8 vertici con jitter (DEPOSIT_SITE_VERTEX_COUNT) non esiste più.

# Tende (dal 2026-10-03 in TentShapes, condiviso con BuildingGhost e con le icone della barra di costruzione).

# Griglia di stoccaggio (2026-09-11, richiesta utente iniziale; REVISIONATA 2026-09-12 dopo
# feedback esplicito: "il modo con cui rappresenti bastoni e pietre è proprio l'opposto di quello
# che ti avevo detto, disegni un cerchio con lo sfondo della rispettiva icona. io voglio un
# quadrato (circa 1/9 del deposito), che rimetta la icona ma senza sfondo della icona... se non
# vuoi complicare troppo con lo sfondo trasparente, usa lo stratagemma di fare lo stesso disegno
# con lo sfondo stesso colore del deposit site" — QUESTA è quella versione, la precedente (cerchio
# pieno nel colore della risorsa) è stata sostituita, non affiancata) — un marker per SLOT occupato
# (non per tipo di risorsa: 2 slot di stick + 1 di pietra = 3 marker, stesso modello "slot
# univoci" già usato da BuildingInfoPanel.StorageGrid, vedi BuildingStorageService.
# get_slot_breakdown), disposti su una griglia 3×3 (9 = deposit_site.storage_slot_count) centrata su
# `ground`. Ogni marker è ora un QUADRATO (non un cerchio) riempito con DEPOSIT_SITE_COLOR — lo
# "stratagemma sfondo-uguale-al-deposito" indicato dall'utente al posto della trasparenza vera
# (immediate-mode Node2D _draw() non supporta facilmente un blend "vedi sotto" per un rettangolo
# pieno) — sopra il quale viene ridisegnata la VERA icona pebble/stick (geometria replicata da
# PebbleIcon.gd/StickIcon.gd, vedi DepositStorageIcons._draw_deposit_storage_pebble_icon/_draw_deposit_storage_stick_
# icon: non riusabili direttamente, quelle sono Control._draw(), qui serve immediate-mode
# Node2D in world-space) SENZA alcuno sfondo proprio — il risultato visivo voluto dall'utente:
# "si devono vedere solo i bastoncini sopra il terreno del deposito... o solo i sassolini". Nessuna
# dimensione proporzionale alla quantità (richiesta esplicita, invariata) — un semplice "c'è/non
# c'è" questo tipo di risorsa in questo slot.
const DEPOSIT_SITE_STORAGE_GRID_COLUMNS: int = 3
const DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING: float = 2.4
# "circa 1/9 del deposito" (richiesta utente) — DEPOSIT_SITE_HALF_SIDE=4.5 sopra, quindi il
# deposito pieno è ~9×9: un nono lineare sarebbe 3.0, qui leggermente più stretto (2.2) del passo
# griglia (2.4) apposta, per lasciare un piccolo margine visivo tra un quadrato e il successivo
# invece di un mosaico perfettamente contiguo.
const DEPOSIT_SITE_STORAGE_SQUARE_SIDE: float = 2.2

# Cartello "work in progress" (2026-09-11, richiesta utente, revisione della resa "cantiere in
# attesa" — SOSTITUISCE il primo tentativo, grayscale dell'edificio, scartato non appena visto
# in-game: la sagoma tornava colorata insieme ai bastoncini, effetto non voluto) — disegnato al
# posto della sagoma vera dell'edificio (capanna/Pebble Circle/Deposit Site, MAI insieme, vedi
# _draw_buildings) finché Building.site_setup_complete resta false. Un piccolo cartello triangolare
# giallo/nero su un palo sottile, stile segnale di cantiere — deliberatamente MODESTO in dimensione
# (WIP_SIGN_PLATE_RADIUS ben sotto BUILDING_HUT_RADIUS) e disegnato per ultimo in _draw() (vedi
# l'ordine lì: _draw_buildings gira DOPO _draw_vegetation_positions), quindi appare SOPRA la
# vegetazione già presente sulla microcella senza sostituirla — esattamente la richiesta "lasci
# vedere cmq le piante". Nessuna icona da asset/tema (questo progetto non ha texture per gli
# edifici, tutto è disegnato a primitive — stesso principio "usa e getta"/procedurale già seguito
# per capanna/Pebble Circle/Deposit Site, coerenza stilistica preferita a un'icona editor-only che
# non sarebbe comunque disponibile in una build esportata).
const WIP_SIGN_POST_COLOR := Color(0.35, 0.25, 0.15, 1.0)
const WIP_SIGN_POST_WIDTH: float = 0.3
const WIP_SIGN_POST_HEIGHT: float = 2.0
const WIP_SIGN_PLATE_COLOR := Color(0.95, 0.75, 0.1, 1.0)
const WIP_SIGN_PLATE_OUTLINE_COLOR := Color(0.15, 0.1, 0.05, 1.0)
const WIP_SIGN_PLATE_OUTLINE_WIDTH: float = 0.25
const WIP_SIGN_PLATE_RADIUS: float = 1.4
const WIP_SIGN_MARK_COLOR := Color(0.15, 0.1, 0.05, 1.0)
const WIP_SIGN_MARK_WIDTH: float = 0.35

const DIRECTIONS := [
	Vector2i(0, -1), # nord
	Vector2i(0, 1),  # sud
	Vector2i(1, 0),  # est
	Vector2i(-1, 0), # ovest
]

# Per ogni curva, il perno (angolo vero della griglia, in frazione 0..1 di grid_size) e
# l'intervallo di angoli (radianti) dell'arco che collega i due lati. Il raggio medio
# dell'arco è sempre grid_size/2, quindi l'arco tocca esattamente il bordo della cella nei
# punti dove prima finivano i due rettangoli dritti (stessa larghezza, nessuna discontinuità
# con i connettori nelle celle vicine) — solo la piega diventa un quarto di cerchio invece
# che uno spigolo a 90°.
const CORNER_ARC_DATA := {
	GameTypes.RiverShape.CORNER_TOP_RIGHT: {"pivot": Vector2(1, 0), "from": PI, "to": PI / 2.0},
	GameTypes.RiverShape.CORNER_RIGHT_BOTTOM: {"pivot": Vector2(1, 1), "from": -PI / 2.0, "to": -PI},
	GameTypes.RiverShape.CORNER_BOTTOM_LEFT: {"pivot": Vector2(0, 1), "from": 0.0, "to": -PI / 2.0},
	GameTypes.RiverShape.CORNER_LEFT_TOP: {"pivot": Vector2(0, 0), "from": PI / 2.0, "to": 0.0},
}
const CORNER_ARC_SEGMENTS: int = 24

var world: World
# Vector2i direzione -> MacroCellData/MacroCellState del vicino reale (o null se fuori mappa).
# Sono solo un'anteprima visiva: non fanno parte di `world` e non saranno mai interagibili.
var neighbor_cells: Dictionary = {}
var neighbor_states: Dictionary = {}

var is_river: bool = false
var river_shape: GameTypes.RiverShape = GameTypes.RiverShape.NONE
var river_thickness_ratio: float = 0.0 # river_space / MacroCellState.TOTAL_SPACE

var stone_positions: Array = [] # Array[Vector2i]
# Edifici già piazzati in QUESTA macrocella — Array[Dictionary], ciascuna {"position": Vector2i,
# "rotation": GameTypes.Direction, "id": int, "building_type_name": String} ("id" aggiunto Step 4,
# richiesta utente 2026-09-04 — vedi set_selected_building/get_building_screen_position sotto;
# "building_type_name" aggiunto 2026-09-07 per lo Pebble Circle, vedi _draw_buildings) — vedi GameScene.
# _refresh_building_visuals, che filtra World.buildings per macro_x/macro_y prima di passarli qui:
# questo renderer non conosce World/Building, solo "dove e come disegnare" (e, ora, quale id tra
# questi risulta selezionato).
var buildings: Array = []
var vegetation_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i] per TREE/SHRUB (lotto x,y + indice individuo), Array[Vector2i] per GRASS (nessuna identità individuale)

# Batching dei rebuild MultiMesh vegetazione (diagnostica 2026-08-30: GameScene._refresh_resource_
# visuals chiama in sequenza set_vegetation_positions/set_shrub_subtypes/set_shrub_age_params/
# set_tree_subtypes/set_tree_age_params/set_season — SEI setter che, senza batching, ricostruiscono
# TREE fino a 4 volte, SHRUB fino a 3 volte, GRASS fino a 2 volte per un SOLO refresh, tutti sugli
# stessi individui: lavoro ridondante misurato come il grosso del costo di un checkpoint stagionale
# con più celle vive. Con begin_vegetation_batch()/end_vegetation_batch() i setter dentro la
# finestra si limitano a segnare "sporco" (_vegetation_batch_dirty), il rebuild vero avviene UNA
# SOLA volta per tipo dentro end_vegetation_batch(). Fuori da una finestra di batch (_vegetation_
# batch_active=false, default) ogni setter si comporta ESATTAMENTE come prima — nessun cambiamento
# per un eventuale futuro chiamante che invochi un setter da solo.
var _vegetation_batch_active: bool = false
var _vegetation_batch_dirty: Dictionary = {} # "tree"/"shrub"/"grass"/"tree_fruit"/"shrub_fruit" -> true

# Solo diagnostica (2026-10-03, richiesta utente — letti da GameScene per la riga [VEG REFRESH TIMING]):
#   - last_batch_timings_ms: tempo in ms di ogni ricostruzione fatta dall'ultimo end_vegetation_batch, per chiave
#     "tree"/"shrub"/"grass"/"tree_fruit"/"shrub_fruit" (assente = non rifatta);
#   - last_fruit_rebuild_paths: per "tree"/"shrub", come sono stati rifatti i frutti nell'ultima ricostruzione dei
#     frutti: "solo frutti" (percorso nuovo) o "ripiego completo" (elenco delle piante da frutto mancante o non valido).
var last_batch_timings_ms: Dictionary = {}
var last_fruit_rebuild_paths: Dictionary = {}
# Individui la cui geometria è stata ricalcolata o presa dalla memoria nell'ultima ricostruzione di alberi/arbusti
# (2026-10-03, passo B): "tree"/"shrub" -> {"computed": int, "reused": int}. Solo diagnostica.
var last_geometry_stats: Dictionary = {}


func begin_vegetation_batch() -> void:
	_vegetation_batch_active = true
	_vegetation_batch_dirty.clear()
	last_batch_timings_ms.clear()
	last_fruit_rebuild_paths.clear()
	last_geometry_stats.clear()
	last_tree_group_stats.clear()
	last_shrub_group_stats.clear()


# Esegue UNA SOLA VOLTA per tipo ciascun rebuild segnato "sporco" durante la finestra di batch,
# nell'ordine originale (tree/shrub/grass) — irrilevante ai fini del risultato (ogni rebuild legge
# solo il proprio stato già aggiornato dai setter, mai lo stato di un altro tipo), tenuto solo per
# leggibilità del log. Un solo queue_redraw() finale, non uno per setter.
#
# Soli frutti (2026-10-03, richiesta utente): "tree_fruit"/"shrub_fruit" rifanno solo i MultiMesh dei frutti
# (_rebuild_tree_fruit_multimeshes/_rebuild_shrub_fruit_multimesh); se nello stesso batch il tipo è segnato anche per la
# ricostruzione completa, vince la completa (che rifà anche i frutti).
func end_vegetation_batch() -> void:
	_vegetation_batch_active = false
	var start_usec := Time.get_ticks_usec()
	if _vegetation_batch_dirty.get("tree", false):
		_rebuild_tree_multimeshes()
		last_batch_timings_ms["tree"] = (Time.get_ticks_usec() - start_usec) / 1000.0
	elif _vegetation_batch_dirty.get("tree_fruit", false):
		_rebuild_tree_fruit_multimeshes()
		last_batch_timings_ms["tree_fruit"] = (Time.get_ticks_usec() - start_usec) / 1000.0
	start_usec = Time.get_ticks_usec()
	if _vegetation_batch_dirty.get("shrub", false):
		_rebuild_shrub_multimeshes()
		last_batch_timings_ms["shrub"] = (Time.get_ticks_usec() - start_usec) / 1000.0
	elif _vegetation_batch_dirty.get("shrub_fruit", false):
		_rebuild_shrub_fruit_multimesh()
		last_batch_timings_ms["shrub_fruit"] = (Time.get_ticks_usec() - start_usec) / 1000.0
	start_usec = Time.get_ticks_usec()
	if _vegetation_batch_dirty.get("grass", false):
		_rebuild_grass_buffers()
		last_batch_timings_ms["grass"] = (Time.get_ticks_usec() - start_usec) / 1000.0
	_vegetation_batch_dirty.clear()
	queue_redraw()


# Usati dai setter sotto al posto della chiamata diretta a _rebuild_*_multimeshes/_rebuild_grass_
# buffers: dentro una finestra di batch rimandano il rebuild vero a end_vegetation_batch(), fuori
# (comportamento di sempre) rebuildano subito.
# Un dato degli alberi/arbusti è cambiato: l'elenco delle piante da frutto non vale più finché la ricostruzione completa
# (subito o a fine batch) non lo rifà — così il percorso dei soli frutti non usa mai dati vecchi.
func _defer_or_rebuild_tree() -> void:
	_tree_fruit_entries_valid = false
	if _vegetation_batch_active:
		_vegetation_batch_dirty["tree"] = true
	else:
		_rebuild_tree_multimeshes()


func _defer_or_rebuild_shrub() -> void:
	_shrub_fruit_entries_valid = false
	if _vegetation_batch_active:
		_vegetation_batch_dirty["shrub"] = true
	else:
		_rebuild_shrub_multimeshes()


# Cambiato solo il rapporto dei frutti (set_fruit_stock_available_ratio_by_lot): soli frutti, nel batch o subito.
func _defer_or_rebuild_tree_fruit() -> void:
	if _vegetation_batch_active:
		_vegetation_batch_dirty["tree_fruit"] = true
	else:
		last_fruit_rebuild_paths.erase("tree")
		_rebuild_tree_fruit_multimeshes()


func _defer_or_rebuild_shrub_fruit() -> void:
	if _vegetation_batch_active:
		_vegetation_batch_dirty["shrub_fruit"] = true
	else:
		last_fruit_rebuild_paths.erase("shrub")
		_rebuild_shrub_fruit_multimesh()


func _defer_or_rebuild_grass() -> void:
	if _vegetation_batch_active:
		_vegetation_batch_dirty["grass"] = true
	else:
		_rebuild_grass_buffers()


var fish_positions: Array = [] # Array[Vector2i] — STEP 1: valorizzato solo per macrocelle SEA/LAKE
# Posizioni (Vector3i, per TREE/SHRUB) con un blocco di taglio/morte attualmente attivo — vedi
# IndividualVegetationService.get_cut_positions/get_dead_positions. Disegnate con un marker
# statico distinto (tronco mozzato / pianta secca, vedi _rebuild_cut_dead_multimeshes) al posto
# del blob vivo normale, che per quello slot semplicemente non esiste (vegetation_positions non
# lo contiene, vedi IndividualVegetationService._is_blocked).
var cut_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i]
var dead_positions: Dictionary = {} # WorldObjectType -> Array[Vector3i]

# STONE_VARIANT_COUNT sagome-base pre-generate una sola volta (stessa formula di jitter
# per-vertice di sempre, seminata per variante invece che per posizione) e riusate per tutte le
# posizioni stone via MultiMesh — invece di un draw_polygon irregolare per ogni singola pietra,
# ne bastano STONE_VARIANT_COUNT in totale indipendentemente da quante pietre ci sono nella
# cella. Ogni pietra sceglie deterministicamente la sua variante da hash(pos) e riceve comunque
# posizione/rotazione/scala per-istanza uniche, quindi la ripetizione tra pietre non è mai
# "identica": solo la sagoma di base è condivisa fra gruppi di ~1/12 delle pietre.
var _stone_variant_meshes: Array = [] # ArrayMesh, indicizzato per variante — costruito una volta sola
var _stone_multimeshes: Array = [] # MultiMesh, indicizzato per variante — un draw_multimesh ciascuno

# Sassi/pebble (2026-09-08, richiesta utente) — Vector2i -> int, disponibilità GIÀ RISOLTA dal
# chiamante (2026-09-19, refactor lot_source — RINOMINATO da pebble_quantities: prima era la
# quantità grezza di MacroCellState.pebble_quantities, ora GameScene/MacroCellScene risolvono
# TerrainScatteredResourceService.get_available per ciascuna posizione stone prima di passarla qui,
# STESSO principio già in uso per egg_nest_availability/grass_patch_availability sotto), MAI
# ricalcolata qui: il renderer si limita a leggerla per decidere QUANTI puntini-sasso disegnare
# attorno a ciascuna posizione stone, a 3 livelli (vedi PEBBLE_TIER_*/_pebble_tier_count) — 0 =
# nessun puntino disegnato, così quando il consumo porta una posizione a 0 basterà richiamare
# set_pebble_availability con i valori aggiornati perché i puntini spariscano da soli (nessuna
# logica di rimozione dedicata: il rebuild riparte sempre da zero, stesso principio già in uso per
# _rebuild_stone_multimeshes).
var pebble_availability: Dictionary = {}
var _pebble_variant_meshes: Array = []
var _pebble_multimeshes: Array = []

# Bastoni/stick (2026-09-08, richiesta utente) — Vector2i (lotto TREE) -> int, disponibilità GIÀ
# RISOLTA dal chiamante (2026-09-19, refactor lot_source — RINOMINATO da stick_quantities: prima
# era {"checkpoint_day","capacity","harvested"}, con "capacity - harvested" calcolato QUI dentro;
# ora GameScene/MacroCellScene risolvono TerrainScatteredResourceService.get_available per lotto
# PRIMA di passarla qui, STESSO principio di pebble_availability sopra — mai un secondo calcolo nel
# renderer). Disegnati a terra attorno al "ground" del lotto (non della singola pianta: un lotto
# può avere più individui), a 3 livelli come i pebble (vedi STICK_TIER_*/_stick_tier_count). Un
# solo mesh condiviso (non varianti multiple come stone/pebble): un bastone è solo un rettangolo
# sottile, rotazione+scala per-istanza bastano per la varietà visiva.
var stick_availability: Dictionary = {}
var _stick_mesh: ArrayMesh = null
var _stick_multimesh: MultiMesh = null
# Nidi "eggs" (2026-09-18, richiesta utente — uova raccoglibili per microcella) — Vector2i (nido,
# una microcella GRASS) -> quantità disponibile RESIDUA, già netta del raccolto e già filtrata a
# > 0 dal chiamante (GameScene._refresh_resource_visuals, tramite TerrainScatteredResourceService.
# get_egg_stock_available_at — la funzione di disponibilità residua, non un secondo calcolo qui).
# MIRROR di stick_availability sopra (stesso schema int diretto — il chiamante ha già risolto la
# sottrazione, questo renderer si limita a leggere "quanto disegnare"). Un solo mesh condiviso
# (stesso principio di stick: nessuna variante multipla necessaria).
var egg_nest_availability: Dictionary = {}
var _egg_mesh: ArrayMesh = null
var _egg_multimesh: MultiMesh = null
# Lotti GRASS_PATCH (wild_vegetables dal 2026-09-19, GENERALIZZATO lo stesso giorno per le erbe
# medicinali — richiesta utente: "un dizionario resource_name → multimesh, invece di duplicare il
# blocco") — MIRROR di egg_nest_availability sopra, stesso formato per risorsa (Vector2i lotto ->
# quantità residua già > 0 e filtrata FoW dal chiamante). resource_name -> {lotto: quantità} /
# resource_name -> MultiMesh (creato al primo uso da _get_grass_patch_multimesh, mesh cotta una
# volta sola da GRASS_PATCH_MARKER_SHAPES).
var grass_patch_availability: Dictionary = {}
var _grass_patch_multimeshes: Dictionary = {}
var _grass_patch_missing_shape_warned: Dictionary = {}
# Sottotipo congelato per individuo — Vector3i -> String ("wood_only"/"fruit_bearing" per SHRUB,
# "wood_only"/"wild_fruit"/"domesticable_fruit"/"conifer" per TREE), stesso oggetto di
# MacroCellState.tree_individual_subtype/shrub_individual_subtype (Dictionary per riferimento,
# vedi set_tree_subtypes/set_shrub_subtypes) — deciso una sola volta da IndividualVegetationService
# alla nascita dell'individuo, mai più ricalcolato qui: il renderer si limita a leggerlo. Sostituisce
# i vecchi shrub_fruit_ratio/tree_wild_fruit_ratio/tree_domesticable_fruit_ratio/tree_conifer_ratio
# (rimossi insieme ai test hash a schermo _is_tree_conifer ecc., spostati in
# IndividualVegetationService dove ora avviene la decisione).
var shrub_individual_subtype: Dictionary = {}
var tree_individual_subtype: Dictionary = {}
# Parametri fasce età per sottotipo SHRUB, chiave = subtype_name ("wood_only"/"fruit_bearing"),
# valore = {"youth_duration_years": int, "adult_duration_years": int, "size_multiplier_by_age":
# Array[float], "ratios": Array[float]} — tutti già risolti dal chiamante (SubtypeRules + age_composition):
# il renderer non legge mai ResourceCalculator/MacroCellState direttamente. Un sottotipo assente da
# questo dizionario (es. track_age_bands=false) non riceve mai variazione di dimensione (vedi
# _resolve_age_band_and_size).
var shrub_age_params: Dictionary = {}
# Anno di gioco corrente (game_data.year), servito insieme a shrub_age_params perché
# AgeBandVisualService ne ha bisogno per calcolare gli anni vissuti di ogni posizione.
var shrub_current_year: int = 0
# Stessa coppia di shrub_age_params/shrub_current_year sopra, ma per i 4 sottotipi TREE
# ("wood_only"/"wild_fruit"/"domesticable_fruit"/"conifer") — vedi set_tree_age_params.
var tree_age_params: Dictionary = {}
var tree_current_year: int = 0
# Stagione corrente (vedi GRASS_PALETTE_BY_SEASON/FRUITING_SEASONS sopra) — arriva già risolta
# dal chiamante (MacroCellScene, via SeasonCalculator.get_season_for_day), stessa separazione
# di responsabilità delle altre proprietà "calcolate altrove" del renderer.
# Il default è la stagione del giorno di partenza di una nuova partita (GameData.START_DAY),
# calcolata e non scritta a mano: se il giorno di partenza cambia, il default resta allineato
# anche nei frame prima del primo set_season.
var current_season: GameTypes.Season = SeasonCalculator.get_season_for_day(GameData.START_DAY)

# DEBUG TEMPORANEO: conta le chiamate di disegno EFFETTIVE (draw_multimesh/draw_multiline_colors)
# per stone+grass+shrub+tree+bacche in un singolo _draw(), non più le istanze logiche — dopo la
# conversione a MultiMesh/draw_multiline_colors il numero atteso è un piccolo valore costante
# (stone: fino a 12, vegetazione: fino a 5), indipendente da quante posizioni ci sono nella
# cella. Da rimuovere una volta confermato che il freeze di rendering non si presenta più.
var _debug_draw_primitive_count: int = 0


func setup(_world: World) -> void:
	world = _world
	_terrain_uniform = _is_world_uniform(_world)
	queue_redraw()


# Terreno uniforme (2026-09-20, richiesta utente — profilo del frame del click: il ciclo sulle 10.000
# celle di _draw costava ~340 ms a ogni ridisegno): il micro-mondo di una macrocella viva è generato da
# World.generate_uniform_terrain (GameScene._activate_live_cell, MacroCellScene), quindi le 10.000
# microcelle hanno lo stesso terreno/acqua/costa/bioma e quindi lo STESSO colore. Verificato UNA volta
# in setup(), non a ogni _draw: vero => _draw usa _draw_uniform_terrain (un rettangolo + un
# draw_multiline_colors) invece del ciclo per-cella; falso (es. il ripiego generate_empty_world() quando la
# macrocella non esiste) => si tiene il ciclo per-cella di sempre. I campi confrontati sono TUTTI e SOLI
# quelli letti da TerrainColors.get_cell_color/get_land_color (water_type, terrain_base, coast_type, biome).
# `world` non viene modificato dopo setup() (nessun editor sul micro-mondo): se un giorno lo fosse, va
# richiamata setup() per rivalutare il flag.
var _terrain_uniform: bool = false

static func _is_world_uniform(w: World) -> bool:
	if w == null or w.cells.is_empty():
		return false
	var first: MacroCellData = w.cells[0]
	for cell in w.cells:
		if cell.terrain_base != first.terrain_base \
				or cell.water_type != first.water_type \
				or cell.coast_type != first.coast_type \
				or cell.biome != first.biome:
			return false
	return true


func set_neighbors(neighbors: Dictionary, states: Dictionary = {}) -> void:
	neighbor_cells = neighbors
	neighbor_states = states
	queue_redraw()


# Da chiamare solo se la macrocella reale ha water_type == RIVER: `shape` è il suo
# river_shape reale, `thickness_ratio` è river_space/TOTAL_SPACE (quanto della cella
# è dedicato al fiume, usato per dare uno spessore proporzionale alla fascia disegnata).
func set_river(shape: GameTypes.RiverShape, thickness_ratio: float) -> void:
	is_river = true
	river_shape = shape
	river_thickness_ratio = clamp(thickness_ratio, 0.0, 1.0)
	queue_redraw()


# Da chiamare quando la macrocella caricata NON ha un fiume (GameScene._load_macro_cell, riuso
# della stessa istanza di renderer tra macrocelle diverse) — set_river sopra non ha mai modo di
# tornare a false una volta impostato a true, quindi senza questa chiamata un fiume disegnato in
# una macrocella resterebbe visibile anche dopo essere passati a una macrocella senza fiume.
func clear_river() -> void:
	is_river = false
	river_shape = GameTypes.RiverShape.NONE
	river_thickness_ratio = 0.0
	queue_redraw()


func set_stone_positions(positions: Array) -> void:
	stone_positions = positions
	_rebuild_stone_multimeshes()
	# I pebble sono ancorati alle STESSE posizioni (2026-09-08) — ricalcolati anche qui, non solo
	# da set_pebble_availability sotto: copre l'ordine di chiamata "prima le posizioni, poi le
	# quantità" E il caso in cui stone_positions cambi da sola (pebble_availability già valorizzato).
	_rebuild_pebble_multimeshes()
	queue_redraw()


# Sassi/pebble (2026-09-08, richiesta utente) — chiamato da GameScene/MacroCellScene subito dopo
# set_stone_positions, stessa disponibilità già risolta (vedi pebble_availability sopra per il
# perché). Rebuild anche qui (non solo da set_stone_positions sopra): copre il caso in cui le
# quantità cambino da sole a parità di posizioni (es. un consumo).
func set_pebble_availability(availability: Dictionary) -> void:
	pebble_availability = availability
	_rebuild_pebble_multimeshes()
	queue_redraw()


# Bastoni/stick (2026-09-08, richiesta utente) — chiamato da GameScene/MacroCellScene subito dopo
# LotCapacityService.refresh_vegetation_lot_capacity, stessa disponibilità già risolta (vedi
# stick_availability sopra per il perché). A differenza di stone/pebble non dipende da un
# "set_positions" separato: i lotti sono già le chiavi del Dictionary stesso (MacroCellState.
# tree_claimed_lots concettualmente, qui letto indirettamente dalle chiavi di stick_availability).
func set_stick_availability(availability: Dictionary) -> void:
	stick_availability = availability
	_rebuild_stick_multimesh()
	queue_redraw()


# Nidi "eggs" (2026-09-18, richiesta utente) — chiamato da GameScene._refresh_resource_visuals con
# la disponibilità RESIDUA già filtrata a > 0 e da Fog of War (STESSO momento/STESSA cadenza di
# set_stick_availability sopra — checkpoint stagionale/raccolta/movimento con visibilità cambiata).
# A differenza di stone/pebble non dipende da un "set_positions" separato: i nidi sono già le
# chiavi del Dictionary stesso (MacroCellState.egg_nest_positions concettualmente, qui letto
# indirettamente dalle chiavi di egg_nest_availability) — stesso schema di set_stick_availability.
func set_egg_nest_availability(availability: Dictionary) -> void:
	egg_nest_availability = availability
	_rebuild_egg_multimesh()
	queue_redraw()


# Lotti GRASS_PATCH (2026-09-19, generalizzato da set_wild_vegetable_availability) — MIRROR di
# set_egg_nest_availability sopra, stesso momento/stessa cadenza di chiamata da GameScene, ma UNA
# chiamata per risorsa GRASS_PATCH (ogni risorsa ha il proprio MultiMesh, vedi
# _get_grass_patch_multimesh).
func set_grass_patch_availability(resource_name: String, availability: Dictionary) -> void:
	grass_patch_availability[resource_name] = availability
	_rebuild_grass_patch_multimesh(resource_name)
	queue_redraw()


# Fascia di disegno di una risorsa sparsa per una quantità (2026-10-04, richiesta utente — raccolta leggera per lotto,
# GameScene._patch_scattered_lot): quante istanze disegnerebbe il rebuild per quel lotto. "stick"/"pebble": le fasce di
# _stick_tier_count/_pebble_tier_count; "grass_patch": un segno se la quantità è > 0 (come _rebuild_grass_patch_multimesh).
# Stessa fascia = stesso disegno del lotto (posizioni e forme dipendono solo dal lotto e dall'indice dell'istanza).
func scattered_availability_tier(kind: String, quantity: int) -> int:
	match kind:
		"stick":
			return _stick_tier_count(quantity)
		"pebble":
			return _pebble_tier_count(quantity)
		_:
			return 1 if quantity > 0 else 0


func set_buildings(buildings_data: Array) -> void:
	buildings = buildings_data
	_rebuild_dirt_ground_mesh()
	queue_redraw()


func set_vegetation_positions(positions: Dictionary) -> void:
	vegetation_positions = positions
	_rebuild_selection_lot_index(SELECTION_SOURCE_LIVE)
	_defer_or_rebuild_tree()
	_defer_or_rebuild_shrub()
	_defer_or_rebuild_grass()
	queue_redraw()


# ============================================================================================
# Click-detection su un singolo individuo (TREE/SHRUB) — vedi VegetationSelectorController, che
# interroga queste due query per ogni candidato vicino al click. Entrambe riusano ESATTAMENTE le
# stesse funzioni del rebuild (_compute_tree_visual/_compute_shrub_visual), mai una copia della
# formula — vedi il commento lì sul perché `is_first_sight` resta al default `false` in una query
# isolata.
# ============================================================================================

# Posizione a schermo (spazio locale di questo renderer, stessi pixel di CELL_SIZE) del "centro
# visivo" di un individuo: canopy_center per un TREE vivo (il grosso della massa visiva sta nella
# chioma, non nel tronco) ma "ground" per un TREE bloccato (tagliato/morto) — non ha più chioma,
# solo il ceppo a livello del suolo, vedi _build_tree_stump_transform. Per SHRUB resta sempre
# "center" del cluster (vivo o rovi, stesso ancoraggio). GameTypes.WorldObjectType diversi da
# TREE/SHRUB (GRASS non ha identità individuale, vedi vegetation_positions) ritornano Vector2.ZERO.
func get_individual_screen_position(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Vector2:
	match object_type:
		GameTypes.WorldObjectType.TREE:
			var visual := _compute_tree_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.TREE))
			return visual["canopy_center"] if has_individual(object_type, individual_key) else visual["ground"]
		GameTypes.WorldObjectType.SHRUB:
			return _compute_shrub_visual(individual_key, _lot_extent_counts(GameTypes.WorldObjectType.SHRUB))["center"]
		_:
			return Vector2.ZERO


# ============================================================================================
# Indice per lotto della selezione col clic (2026-10-04, richiesta utente — la ricerca della vegetazione al clic costava
# 38-220 ms: VegetationSelectorController copiava l'intero elenco di ogni tipo e, per ogni candidato vicino, rifaceva
# _lot_extent_counts e has_individual sull'intera cella). Per TREE/SHRUB e per ogni fonte (vivi, ceppi, morti):
# lotto -> indici nell'elenco della fonte, ricostruito nei setter delle posizioni (set_vegetation_positions,
# set_cut_positions, set_dead_positions, set_cut_dead_positions), mai al clic. Ricorda gli elenchi da cui è stato
# costruito: se l'elenco corrente non è più lo stesso oggetto o ha cambiato lunghezza, l'indice non vale e il chiamante
# ripiega sul metodo completo (find_selection_candidates ritorna null).
# ============================================================================================
const SELECTION_SOURCE_LIVE := 0
const SELECTION_SOURCE_CUT := 1
const SELECTION_SOURCE_DEAD := 2
const SELECTION_INDEX_TYPES: Array[GameTypes.WorldObjectType] = [
	GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB,
]
# [fonte][WorldObjectType] -> {"list": Array o null, "size": int, "lots": Dictionary Vector2i -> Array[int]}
var _selection_lot_index: Array = [{}, {}, {}]


func _selection_source_list(source: int, object_type: GameTypes.WorldObjectType) -> Variant:
	var by_type: Dictionary = vegetation_positions if source == SELECTION_SOURCE_LIVE else (
		cut_positions if source == SELECTION_SOURCE_CUT else dead_positions
	)
	return by_type.get(object_type, null)


func _rebuild_selection_lot_index(source: int) -> void:
	var index: Dictionary = {}
	for object_type in SELECTION_INDEX_TYPES:
		var list: Variant = _selection_source_list(source, object_type)
		var lots: Dictionary = {}
		if list != null:
			var entries: Array = list
			for i in range(entries.size()):
				# Vivi: Vector3i; ceppi e morti: Dictionary con "key" (vedi cut_positions/dead_positions).
				var key: Vector3i = entries[i] if source == SELECTION_SOURCE_LIVE else entries[i]["key"]
				var lot := Vector2i(key.x, key.y)
				if lots.has(lot):
					(lots[lot] as Array).append(i)
				else:
					lots[lot] = [i]
		index[object_type] = {"list": list, "size": (list as Array).size() if list != null else 0, "lots": lots}
	_selection_lot_index[source] = index


func _selection_index_entry_valid(source: int, object_type: GameTypes.WorldObjectType) -> bool:
	var entry: Dictionary = (_selection_lot_index[source] as Dictionary).get(object_type, {})
	if entry.is_empty():
		return false
	var current: Variant = _selection_source_list(source, object_type)
	if current == null or entry["list"] == null:
		return current == null and entry["list"] == null
	return is_same(current, entry["list"]) and (current as Array).size() == int(entry["size"])


# Candidati alla selezione di `object_type` nei 3x3 lotti attorno a `click_lot`, come Array di [individual_key, posizione
# a schermo], nello STESSO ordine del metodo completo (vivi nell'ordine del loro elenco, poi ceppi, poi morti: a parità di
# distanza vince il primo, come prima) e con la STESSA posizione di get_individual_screen_position — _compute_*_visual
# legge di lot_counts solo il lotto dell'individuo, quindi basta il conteggio di quel lotto (vivi + ceppi + morti, lo
# stesso di _lot_extent_counts), e "vivo" (chioma o ceppo per TREE) è la presenza nell'elenco dei vivi di quel lotto,
# l'unico dove la chiave può stare. null se l'indice non vale per questi elenchi: il chiamante usa il metodo completo.
func find_selection_candidates(object_type: GameTypes.WorldObjectType, click_lot: Vector2i) -> Variant:
	for source in [SELECTION_SOURCE_LIVE, SELECTION_SOURCE_CUT, SELECTION_SOURCE_DEAD]:
		if not _selection_index_entry_valid(source, object_type):
			return null
	var found: Array = [] # [fonte, indice, chiave]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var lot := click_lot + Vector2i(dx, dy)
			for source in [SELECTION_SOURCE_LIVE, SELECTION_SOURCE_CUT, SELECTION_SOURCE_DEAD]:
				var entry: Dictionary = _selection_lot_index[source][object_type]
				var indices: Array = (entry["lots"] as Dictionary).get(lot, [])
				if indices.is_empty():
					continue
				var list: Array = entry["list"]
				for i in indices:
					var key: Vector3i = list[i] if source == SELECTION_SOURCE_LIVE else list[i]["key"]
					found.append([source, int(i), key])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	var result: Array = []
	for item in found:
		var key: Vector3i = item[2]
		var lot := Vector2i(key.x, key.y)
		var local_count := 0
		var alive := false
		for source in [SELECTION_SOURCE_LIVE, SELECTION_SOURCE_CUT, SELECTION_SOURCE_DEAD]:
			var entry: Dictionary = _selection_lot_index[source][object_type]
			var indices: Array = (entry["lots"] as Dictionary).get(lot, [])
			local_count += indices.size()
			if source == SELECTION_SOURCE_LIVE and not alive:
				var live_list: Array = entry["list"]
				for i in indices:
					if live_list[i] == key:
						alive = true
						break
		var lot_counts := {lot: local_count}
		var screen_pos: Vector2
		if object_type == GameTypes.WorldObjectType.TREE:
			var visual := _compute_tree_visual(key, lot_counts)
			screen_pos = visual["canopy_center"] if alive else visual["ground"]
		else:
			screen_pos = _compute_shrub_visual(key, lot_counts)["center"]
		result.append([key, screen_pos])
	return result


# Posizione a schermo del centro visivo di UNA pietra in `pos` — stessa formula di jitter (2026-09-08,
# richiesta utente, click su STONE) già usata da _rebuild_stone_multimeshes per posizionare il
# blob: estratta qui in modo che StoneSelectorController possa confrontare il click con l'esatto
# punto disegnato, invece di una tolleranza scollegata come già avviene per TREE/SHRUB via
# get_individual_screen_position sopra. Nessun controllo che `pos` sia davvero in stone_positions —
# stesso principio "il renderer sa solo disegnare" già dichiarato altrove, il chiamante (StoneSelectorController)
# itera solo posizioni reali.
func get_stone_screen_position(pos: Vector2i) -> Vector2:
	var half: float = CELL_SIZE / 2.0
	# Scostamento ridotto a ±STONE_CENTER_JITTER (2026-09-27, rocce contenute nella microcella; era ±0,8 px).
	var offset_x: float = lerp(-STONE_CENTER_JITTER, STONE_CENTER_JITTER, float(hash(pos * 5 + Vector2i(2, 9)) % 1000) / 1000.0)
	var offset_y: float = lerp(-STONE_CENTER_JITTER, STONE_CENTER_JITTER, float(hash(pos * 5 + Vector2i(9, 2)) % 1000) / 1000.0)
	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	return base + Vector2(half, half) + Vector2(offset_x, offset_y)


# Dati per il pannello informativo (sottotipo/fascia età/anni vissuti) di un individuo VIVO già
# selezionato — {} se object_type non è TREE/SHRUB o l'individuo non esiste più (il chiamante
# dovrebbe aver già verificato has_individual prima di arrivare qui). Per uno slot bloccato
# (tagliato/morto) vedi get_blocked_marker_info sotto, non questa.
func get_individual_info(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Dictionary:
	debug_last_lot_extent_counts_ms = 0.0
	match object_type:
		GameTypes.WorldObjectType.TREE:
			var counts_start_usec := Time.get_ticks_usec()
			var lot_counts := _lot_extent_counts(GameTypes.WorldObjectType.TREE)
			debug_last_lot_extent_counts_ms = (Time.get_ticks_usec() - counts_start_usec) / 1000.0
			var visual := _compute_tree_visual(individual_key, lot_counts)
			return {"subtype_name": visual["subtype_name"], "age_band": visual["age_band"], "years_lived": visual["years_lived"], "size_multiplier": visual["size_multiplier"]}
		GameTypes.WorldObjectType.SHRUB:
			var counts_start_usec := Time.get_ticks_usec()
			var lot_counts := _lot_extent_counts(GameTypes.WorldObjectType.SHRUB)
			debug_last_lot_extent_counts_ms = (Time.get_ticks_usec() - counts_start_usec) / 1000.0
			var visual := _compute_shrub_visual(individual_key, lot_counts)
			return {"subtype_name": visual["subtype_name"], "age_band": visual["age_band"], "years_lived": visual["years_lived"], "size_multiplier": visual["size_multiplier"]}
		_:
			return {}


# [SELECT TIMING] (2026-10-04, solo diagnostica — vedi DebugLogging.SHOW_SELECTION_TIMING_LOGS): durata dell'ultimo
# _lot_extent_counts di get_individual_info, letta da GameScene._refresh_vegetation_panel; frame del clic di selezione
# che chiede la riga "draw" del prossimo _draw (-1 = nessuna richiesta) e coordinate della macrocella per la riga.
var debug_last_lot_extent_counts_ms: float = 0.0
var debug_selection_draw_frame: int = -1
var debug_selection_draw_coords: Vector2i = Vector2i(-1, -1)


# Dati per il pannello informativo di uno slot BLOCCATO (tagliato o morto) selezionato — {} se non
# è bloccato (individuo vivo o slot inesistente). "years_ago" = anni trascorsi dal blocco, letto
# dall'anno corrente del tipo giusto (tree_current_year/shrub_current_year, già tenuti aggiornati
# da set_tree_age_params/set_shrub_age_params).
func get_blocked_marker_info(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> Dictionary:
	var current_year: int = tree_current_year if object_type == GameTypes.WorldObjectType.TREE else shrub_current_year
	for entry in cut_positions.get(object_type, []):
		if entry["key"] == individual_key:
			return {"state": "cut", "years_ago": current_year - int(entry["event_year"]), "size_multiplier": float(entry["size_multiplier"])}
	for entry in dead_positions.get(object_type, []):
		if entry["key"] == individual_key:
			return {"state": "dead", "years_ago": current_year - int(entry["event_year"]), "size_multiplier": float(entry["size_multiplier"])}
	return {}


func has_blocked_marker(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> bool:
	return not get_blocked_marker_info(object_type, individual_key).is_empty()


# Vero se `individual_key` è ancora tra le posizioni correnti di `object_type` — usato dal
# chiamante (GameScene) per invalidare una selezione dopo un rebuild (pianta morta/migrata, in
# futuro tagliata da PlayerHarvestService).
func has_individual(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> bool:
	return vegetation_positions.get(object_type, []).has(individual_key)


# Limiti SUPERIORI dei range usati in _rebuild_shrub_multimeshes per posizione/raggio di un blob
# (distanza 0.8-1.8, raggio 1.4-2.2) — usati da _draw_selected_individual_highlight per un cerchio
# che racchiude per costruzione ogni blob possibile del cluster (bacche incluse, il cui ingombro
# massimo è sempre minore): nessun singolo raggio esatto esiste per SHRUB (posizione/raggio
# per-blob sono randomizzati e ricalcolati solo dentro il rebuild, mai memorizzati per posizione),
# quindi questa resta un'approssimazione per eccesso dichiarata, non un contorno che segue i
# singoli lobi (tracciarne l'unione esatta non vale la spesa per un indicatore di selezione).
const SHRUB_BLOB_MAX_DISTANCE_RATIO: float = 1.8
const SHRUB_BLOB_MAX_RADIUS_RATIO: float = 2.2


# Individuo attualmente selezionato per l'ispezione — analogo a HumanIndividual.is_selected per il
# player, ma vive qui (non su un oggetto persistente: un individuo vegetale non ha una Resource
# propria, solo l'identità posizionale Vector3i) e solo sul renderer della cella che lo possiede
# davvero (ogni LiveMacroCell ha la propria istanza — vedi GameScene._select_vegetation, che pulisce
# esplicitamente la selezione su tutte le ALTRE celle vive). object_type=-1 è il sentinel "nessuna
# selezione" (GameTypes.WorldObjectType non ha un valore NONE riusabile qui).
var _selected_individual_type: int = -1
var _selected_individual_key: Vector3i


func set_selected_individual(object_type: GameTypes.WorldObjectType, individual_key: Vector3i) -> void:
	_selected_individual_type = object_type
	_selected_individual_key = individual_key
	queue_redraw()


func clear_selected_individual() -> void:
	if _selected_individual_type == -1:
		return
	_selected_individual_type = -1
	queue_redraw()


# Contorno rosso sottile che segue la sagoma REALE dell'individuo (non un cerchio bianco a
# distanza fissa dal centro come per il player — scelta esplicita dell'utente): un TREE non-
# conifer e uno SHRUB hanno comunque una chioma/cluster rotondi, quindi un cerchio È la sagoma
# corretta lì; un TREE conifer invece ha una chioma a triangolo (vedi CONIFER_SHAPE_POINTS/
# _build_conifer_mesh) — disegnargli sopra un cerchio lo faceva sembrare sempre rotondo e
# (nell'intervallo stretto 2.8-3.8×size_multiplier) quasi sempre della stessa dimensione
# percepita, invece di aderire alla punta e alla base larga del suo vero contorno. Nessun disegno
# se l'individuo selezionato è sparito da questo rebuild (has_individual): evita un contorno
# "fantasma" nel frame tra un rebuild che rimuove l'individuo e la chiamata di GameScene a
# clear_selected_individual (vedi _invalidate_selected_vegetation_if_missing), che avviene
# comunque nello stesso frame ma dopo il primo queue_redraw.
const SELECTION_HIGHLIGHT_COLOR := Color(0.95, 0.1, 0.1, 0.95)
const SELECTION_HIGHLIGHT_WIDTH: float = 0.5
# Leggero margine verso l'esterno (10%) così il contorno risulta aderente-ma-fuori dalla sagoma
# disegnata sotto, invece di sovrapporsi esattamente al suo bordo (che con un tratto da 0.8px
# rischierebbe di confondersi visivamente con l'edge della mesh stessa).
const SELECTION_OUTLINE_PADDING_RATIO: float = 1.1

func _draw_selected_individual_highlight() -> void:
	if _selected_individual_type == -1:
		return

	if has_individual(_selected_individual_type, _selected_individual_key):
		_draw_alive_selection_outline()
		return

	# Slot bloccato (tagliato/morto): niente sagoma da inseguire (conifer/chioma non esistono più
	# per un ceppo), un semplice cerchio proporzionato alla stessa size_multiplier persistita usata
	# per disegnare il marker (vedi _build_tree_stump_transform/_build_shrub_stump_transform) è
	# sufficiente a confermare "è questo che hai selezionato".
	var blocked_info := get_blocked_marker_info(_selected_individual_type, _selected_individual_key)
	if blocked_info.is_empty():
		return
	var center := get_individual_screen_position(_selected_individual_type, _selected_individual_key)
	var base_radius: float = 1.6 if _selected_individual_type == GameTypes.WorldObjectType.TREE else BRAMBLE_BASE_RADIUS
	var radius: float = base_radius * float(blocked_info["size_multiplier"]) * SELECTION_OUTLINE_PADDING_RATIO
	draw_arc(center, radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Contorno che segue la sagoma di un individuo VIVO — stessa logica di sempre (chioma tonda per
# TREE non-conifer/SHRUB, triangolo per conifer), estratta a parte da _draw_selected_individual_
# highlight solo per separare questo caso da quello di uno slot bloccato (vedi sopra).
func _draw_alive_selection_outline() -> void:
	if _selected_individual_type == GameTypes.WorldObjectType.TREE:
		var visual := _compute_tree_visual(_selected_individual_key, _lot_extent_counts(GameTypes.WorldObjectType.TREE))
		if visual["is_conifer"]:
			_draw_conifer_selection_outline(visual["canopy_center"], visual["canopy_radius"])
		else:
			var radius: float = visual["canopy_radius"] * SELECTION_OUTLINE_PADDING_RATIO
			draw_arc(visual["canopy_center"], radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)
	elif _selected_individual_type == GameTypes.WorldObjectType.SHRUB:
		var visual := _compute_shrub_visual(_selected_individual_key, _lot_extent_counts(GameTypes.WorldObjectType.SHRUB))
		var radius: float = (
			SHRUB_BLOB_MAX_DISTANCE_RATIO * float(visual["density_scale"])
			+ SHRUB_BLOB_MAX_RADIUS_RATIO * float(visual["size_multiplier"])
		) * SELECTION_OUTLINE_PADDING_RATIO
		draw_arc(visual["center"], radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Stessi CONIFER_SHAPE_POINTS della mesh reale (mai una copia separata dei tre vertici), scalati
# leggermente oltre canopy_radius (SELECTION_OUTLINE_PADDING_RATIO) e ripetendo il primo punto in
# coda: draw_polyline non chiude da sé il poligono.
func _draw_conifer_selection_outline(canopy_center: Vector2, canopy_radius: float) -> void:
	# `radius`, non `scale`: Node2D ha già una proprietà `scale` (Vector2) — un local scalare con
	# lo stesso nome la ombreggerebbe senza motivo.
	var radius: float = canopy_radius * SELECTION_OUTLINE_PADDING_RATIO
	var points := PackedVector2Array()
	for p in CONIFER_SHAPE_POINTS:
		points.append(canopy_center + p * radius)
	points.append(points[0])
	draw_polyline(points, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Edificio attualmente selezionato per l'ispezione — Step 4 (richiesta utente, 2026-09-04), stesso
# principio di _selected_individual_type/_key sopra (vive qui, non su Building: coerenza di design
# anche se un Building ha già un id stabile a differenza della vegetazione — nessun motivo per
# trattarlo diversamente solo perché potrebbe). -1 = nessuna selezione.
var _selected_building_id: int = -1


func set_selected_building(building_id: int) -> void:
	_selected_building_id = building_id
	queue_redraw()


func clear_selected_building() -> void:
	if _selected_building_id == -1:
		return
	_selected_building_id = -1
	queue_redraw()


# Posizione a schermo (spazio locale di questo renderer) del centro dell'edificio selezionato —
# stesso ancoraggio di _draw_buildings ("ground"), esposta per GameScene._center_camera_on_selection
# (stesso ruolo di get_individual_screen_position per la vegetazione). Vector2(-1,-1) sentinel se
# l'edificio non è (più) tra quelli di questa cella.
func get_building_screen_position(building_id: int) -> Vector2:
	var half: float = CELL_SIZE / 2.0
	for entry in buildings:
		if entry.get("id", -1) == building_id:
			var pos: Vector2i = entry["position"]
			return Vector2(pos.x * CELL_SIZE + half, pos.y * CELL_SIZE + half)
	return Vector2(-1, -1)


# Stesso colore/spessore del contorno vegetazione (SELECTION_HIGHLIGHT_COLOR/WIDTH sopra) — coerenza
# visiva "questo è selezionato" in tutto il progetto. Anello attorno al recinto (BUILDING_FENCE_
# RADIUS, stesso margine SELECTION_OUTLINE_PADDING_RATIO della vegetazione). Nessun disegno se
# l'edificio selezionato non è (più) tra quelli di questa cella — stesso principio difensivo già
# usato per la vegetazione (has_individual).
func _draw_selected_building_highlight() -> void:
	if _selected_building_id == -1:
		return
	var center := get_building_screen_position(_selected_building_id)
	if center == Vector2(-1, -1):
		return
	var radius: float = BUILDING_FENCE_RADIUS * SELECTION_OUTLINE_PADDING_RATIO
	draw_arc(center, radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Posizione STONE attualmente selezionata per l'ispezione (2026-09-08, richiesta utente) — stesso
# principio di _selected_building_id sopra: Vector2i(-1,-1) = nessuna selezione (sentinel fuori
# range, ogni posizione valida è 0..World.WIDTH/HEIGHT-1).
var _selected_stone_position := Vector2i(-1, -1)


func set_selected_stone(pos: Vector2i) -> void:
	_selected_stone_position = pos
	queue_redraw()


func clear_selected_stone() -> void:
	if _selected_stone_position == Vector2i(-1, -1):
		return
	_selected_stone_position = Vector2i(-1, -1)
	queue_redraw()


# Stesso colore/spessore/margine del contorno vegetazione/edifici (SELECTION_HIGHLIGHT_COLOR/WIDTH/
# SELECTION_OUTLINE_PADDING_RATIO, già dichiarati sopra per _draw_selected_individual_highlight) —
# coerenza visiva "questo è selezionato" in tutto il progetto. Raggio = quello massimo del blob
# stone disegnato (STONE_MAX_EXTENT: raggio massimo della sagoma per lo scostamento dei vertici e la scala massima —
# 2026-09-27, rocce ridisegnate contenute nella microcella), così il contorno racchiude
# sempre l'intero masso indipendentemente da quale variante è toccata a questa posizione. Nessun
# disegno se la posizione selezionata non è (più) tra le stone_positions di questa cella — stesso
# principio difensivo di has_individual/get_building_screen_position sopra.
func _draw_selected_stone_highlight() -> void:
	if _selected_stone_position == Vector2i(-1, -1):
		return
	if not stone_positions.has(_selected_stone_position):
		return
	var center := get_stone_screen_position(_selected_stone_position)
	# Raggio della roccia ridisegnata (2026-09-27): STONE_MAX_EXTENT invece del vecchio 7,5 fisso.
	var radius: float = STONE_MAX_EXTENT * SELECTION_OUTLINE_PADDING_RATIO
	draw_arc(center, radius, 0, TAU, 24, SELECTION_HIGHLIGHT_COLOR, SELECTION_HIGHLIGHT_WIDTH)


# Lotto (microcella) attualmente selezionato per l'ispezione "terreno" bastoni/legno (2026-09-08,
# richiesta utente) — a differenza di _selected_stone_position (un oggetto puntiforme) qui è
# selezionato l'intero lotto, quindi il contorno è un QUADRATO (il perimetro della microcella
# stessa), non un cerchio attorno a un singolo oggetto — distingue visivamente "ho selezionato
# questo tile" da "ho selezionato quell'oggetto preciso".
var _selected_stick_lot := Vector2i(-1, -1)


func set_selected_stick_lot(lot: Vector2i) -> void:
	_selected_stick_lot = lot
	queue_redraw()


func clear_selected_stick_lot() -> void:
	if _selected_stick_lot == Vector2i(-1, -1):
		return
	_selected_stick_lot = Vector2i(-1, -1)
	queue_redraw()


func _draw_selected_stick_lot_highlight() -> void:
	if _selected_stick_lot == Vector2i(-1, -1):
		return
	var rect := Rect2(_selected_stick_lot.x * CELL_SIZE, _selected_stick_lot.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
	draw_rect(rect, SELECTION_HIGHLIGHT_COLOR, false, SELECTION_HIGHLIGHT_WIDTH)


# Lotto (microcella) selezionato per l'ISPEZIONE con doppio click (2026-09-16, richiesta utente —
# "hai tolto anche il quadrato rosso sulla cella selezionata": la mutua esclusione a 7 vie in
# GameScene toglie il contorno dell'oggetto eventualmente selezionato dal primo click del doppio
# click, ma senza questo la microcella ispezionata restava senza ALCUN contorno — regressione
# visiva, non l'assenza di contorno "voluta" ipotizzata in origine). Campo/funzioni/disegno
# DUPLICATI da _selected_stick_lot/_draw_selected_stick_lot_highlight sopra (stessa identica
# geometria — un lotto è sempre l'intera microcella, quadrato non cerchio) invece di riusarli:
# STICK_LOT e MICROCELL sono due SelectionKind distinti e mutuamente esclusivi in GameScene, un
# campo condiviso li farebbe interferire (selezionare l'uno spegnerebbe silenziosamente il contorno
# dell'altro senza passare da clear_selected_stick_lot/clear_selected_microcell) — stesso principio
# "nessuno stato condiviso tra selezioni concettualmente diverse" già seguito ovunque in questo file.
var _selected_microcell := Vector2i(-1, -1)


func set_selected_microcell(lot: Vector2i) -> void:
	_selected_microcell = lot
	queue_redraw()


func clear_selected_microcell() -> void:
	if _selected_microcell == Vector2i(-1, -1):
		return
	_selected_microcell = Vector2i(-1, -1)
	queue_redraw()


func _draw_selected_microcell_highlight() -> void:
	if _selected_microcell == Vector2i(-1, -1):
		return
	var rect := Rect2(_selected_microcell.x * CELL_SIZE, _selected_microcell.y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
	draw_rect(rect, SELECTION_HIGHLIGHT_COLOR, false, SELECTION_HIGHLIGHT_WIDTH)


func set_fish_positions(positions: Array) -> void:
	fish_positions = positions
	_rebuild_fish_multimeshes()
	queue_redraw()


func set_shrub_subtypes(subtype_store: Dictionary) -> void:
	shrub_individual_subtype = subtype_store
	_defer_or_rebuild_shrub()
	queue_redraw()


func set_shrub_age_params(current_year: int, age_params: Dictionary, birth_year_store: Dictionary) -> void:
	shrub_current_year = current_year
	shrub_age_params = age_params
	shrub_birth_year_store = birth_year_store
	_defer_or_rebuild_shrub()
	queue_redraw()


# resource_name -> Dictionary[Vector2i lotto, float [0.0, 1.0]], quota di disponibilità RESIDUA
# nel lotto rispetto al pieno stagionale (2026-09-17, richiesta utente — TerrainScatteredResourceService.
# get_fruit_stock_visual_ratio_at, chiamato da GameScene._refresh_resource_visuals; GENERALIZZATO
# lo stesso giorno per risorsa, in preparazione dei due multimesh frutto degli alberi — fruit/acorn,
# non ancora aggiunti — nessun cambio di comportamento per berry). Un lotto ASSENTE dal Dictionary
# di una risorsa vale 1.0 (mostra tutto il frutto di quella risorsa, comportamento invariato) — così
# un chiamante che non invoca questo setter per una risorsa (es. MacroCellScene, che non usa la
# raccolta/TerrainScatteredResourceService) continua a mostrarla esattamente come prima, nessuna
# regressione lì.
var fruit_stock_available_ratio_by_lot: Dictionary = {}


# `object_type` (2026-09-17, richiesta utente — generalizzazione): quale famiglia di multimesh
# marcare "sporca" — il renderer non consulta MAI TerrainScatteredResourceService.
# FRUIT_STOCK_SOURCES per dedurlo da `resource_name` (violerebbe il principio "il renderer riceve
# solo dati già risolti" già seguito ovunque in questo file), quindi il chiamante (GameScene, che
# la tabella la conosce già) lo passa esplicito. Innesca lo stesso rebuild TREE/SHRUB già innescato
# da set_*_subtypes/set_*_age_params — dentro la finestra di batch di GameScene.
# _refresh_resource_visuals (begin_vegetation_batch/end_vegetation_batch) questa chiamata si limita
# a marcare "sporco", NESSUN rebuild aggiuntivo rispetto a quelli già innescati dagli altri setter
# nella stessa chiamata.
func set_fruit_stock_available_ratio_by_lot(resource_name: String, object_type: GameTypes.WorldObjectType, ratios: Dictionary) -> void:
	fruit_stock_available_ratio_by_lot[resource_name] = ratios
	# Dal 2026-10-03 solo i MultiMesh dei frutti (vedi _rebuild_tree_fruit_multimeshes): dentro il ridisegno completo di
	# GameScene il tipo è comunque segnato per la ricostruzione completa dagli altri setter, che vince.
	if object_type == GameTypes.WorldObjectType.TREE:
		_defer_or_rebuild_tree_fruit()
	else:
		_defer_or_rebuild_shrub_fruit()
	queue_redraw()


func set_tree_subtypes(subtype_store: Dictionary) -> void:
	tree_individual_subtype = subtype_store
	_defer_or_rebuild_tree()
	queue_redraw()


func set_tree_age_params(current_year: int, age_params: Dictionary, birth_year_store: Dictionary) -> void:
	tree_current_year = current_year
	tree_age_params = age_params
	tree_birth_year_store = birth_year_store
	_defer_or_rebuild_tree()
	queue_redraw()


# Vedi cut_positions/dead_positions in testa al file: rigenera solo i marker statici (tronco
# mozzato / pianta secca), mai i blob vivi (quelli dipendono da vegetation_positions, invariato).
func set_cut_positions(positions: Dictionary) -> void:
	cut_positions = positions
	_rebuild_selection_lot_index(SELECTION_SOURCE_CUT)
	_cut_dead_signature = []
	_rebuild_cut_dead_multimeshes()
	queue_redraw()


func set_dead_positions(positions: Dictionary) -> void:
	dead_positions = positions
	_rebuild_selection_lot_index(SELECTION_SOURCE_DEAD)
	_cut_dead_signature = []
	_rebuild_cut_dead_multimeshes()
	queue_redraw()


# Ceppi e piante morte insieme, con il salto (2026-10-04, richiesta utente). Ogni segno dipende SOLO da: la sua voce
# (chiave, size_multiplier, tipo), il numero di individui del suo lotto (_lot_extent_counts: vivi nell'elenco filtrato
# per la nebbia + ceppi + morti — è da qui che arriva la dipendenza dalla visibilità) e costanti del file (vedi
# _build_tree_stump_transform/_build_shrub_stump_transform/_build_dead_tree_transform/_build_dead_marker_transform, che
# di _compute_*_visual usano solo "ground"/"center"). Firma = voci di ceppi e morti + quel conteggio per i soli lotti che
# hanno un segno: con `allow_skip` e firma uguale all'ultima ricostruzione, nessuna ricostruzione. Va chiamata DOPO
# set_vegetation_positions (vegetation_positions già aggiornato). Ritorna true se ha ricostruito.
func set_cut_dead_positions(cut: Dictionary, dead: Dictionary, allow_skip: bool) -> bool:
	cut_positions = cut
	dead_positions = dead
	_rebuild_selection_lot_index(SELECTION_SOURCE_CUT)
	_rebuild_selection_lot_index(SELECTION_SOURCE_DEAD)
	var signature: Array = [cut, dead, _cut_dead_lot_counts()]
	if allow_skip and not _cut_dead_signature.is_empty() and signature == _cut_dead_signature:
		return false
	_cut_dead_signature = signature
	_rebuild_cut_dead_multimeshes()
	queue_redraw()
	return true


# Firma dell'ultima ricostruzione di ceppi e morti ([] = nessuna o non confrontabile).
var _cut_dead_signature: Array = []


# Stesso conteggio di _lot_extent_counts, solo per i lotti con un ceppo o una pianta morta: tipo -> {lotto: conteggio}.
func _cut_dead_lot_counts() -> Dictionary:
	var result: Dictionary = {}
	for object_type in [GameTypes.WorldObjectType.TREE, GameTypes.WorldObjectType.SHRUB]:
		var counts: Dictionary = {}
		for entry in cut_positions.get(object_type, []):
			var key: Vector3i = entry["key"]
			counts[Vector2i(key.x, key.y)] = int(counts.get(Vector2i(key.x, key.y), 0)) + 1
		for entry in dead_positions.get(object_type, []):
			var key: Vector3i = entry["key"]
			counts[Vector2i(key.x, key.y)] = int(counts.get(Vector2i(key.x, key.y), 0)) + 1
		if counts.is_empty():
			continue
		for individual_key in vegetation_positions.get(object_type, []):
			var lot := Vector2i(individual_key.x, individual_key.y)
			if counts.has(lot):
				counts[lot] = int(counts[lot]) + 1
		result[object_type] = counts
	return result


# Il colore dell'erba e quello della chioma degli alberi NON conifer dipendono dalla stagione,
# quindi entrambi vanno ricalcolati qui; la visibilità dei frutti (FRUITING_SEASONS) è invece un
# gate a draw-time, non richiede nessun rebuild dei loro buffer. La chioma conifer (a forma di
# abete) resta sempre piena/verde in ogni stagione, ma il rebuild va comunque rifatto per intero
# perché lo stesso _rebuild_tree_multimeshes ricostruisce entrambi i gruppi insieme.
func set_season(season: GameTypes.Season) -> void:
	current_season = season
	_defer_or_rebuild_grass()
	_defer_or_rebuild_tree()
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	# [SELECT TIMING] (2026-10-04): ridisegno chiesto da un clic di selezione (debug_selection_draw_frame, scritto da
	# GameScene._select_timing_request_draw) — misura il tempo di script di questo _draw e dei due contorni.
	var _sel_timing: bool = DebugLogging.SHOW_SELECTION_TIMING_LOGS and debug_selection_draw_frame >= 0
	var _sel_start_usec: int = Time.get_ticks_usec() if _sel_timing else 0
	var _sel_individual_outline_usec: int = 0
	var _sel_building_outline_usec: int = 0

	_debug_draw_primitive_count = 0

	if _terrain_uniform:
		_draw_uniform_terrain()
	else:
		for cell in world.cells:
			var color: Color = TerrainColors.get_land_color(cell) if is_river else TerrainColors.get_cell_color(cell)
			var rect := Rect2(
				cell.x * CELL_SIZE,
				cell.y * CELL_SIZE,
				CELL_SIZE,
				CELL_SIZE
			)
			draw_rect(rect, color)
			draw_rect(rect, TerrainColors.GRID, false, 1.0)

	var grid_size: int = World.WIDTH * CELL_SIZE
	if is_river:
		_draw_river(grid_size)

	_draw_stone_positions()
	_draw_pebble_positions()
	_draw_selected_stone_highlight()
	_draw_stick_positions()
	_draw_egg_nest_positions()
	_draw_grass_patch_positions()
	_draw_selected_stick_lot_highlight()
	_draw_selected_microcell_highlight()
	_draw_vegetation_positions()
	var _sel_outline_start_usec := Time.get_ticks_usec()
	_draw_selected_individual_highlight()
	_sel_individual_outline_usec = Time.get_ticks_usec() - _sel_outline_start_usec
	_draw_fish_positions()
	_draw_buildings()
	_sel_outline_start_usec = Time.get_ticks_usec()
	_draw_selected_building_highlight()
	_sel_building_outline_usec = Time.get_ticks_usec() - _sel_outline_start_usec
	_draw_neighbor_previews(grid_size)
	_draw_boundary(grid_size)

	#print("[DEBUG RENDER] primitive stone+grass+shrub+tree+bacche in questo _draw(): ", _debug_draw_primitive_count)
	if _sel_timing:
		# Solo il ridisegno dello stesso fotogramma del clic (o del successivo): un flag rimasto da un clic che non ha
		# fatto ridisegnare questa cella non deve attribuire al clic un ridisegno arrivato dopo per altri motivi.
		if Engine.get_process_frames() - debug_selection_draw_frame <= 1:
			print("[SELECT TIMING] draw macrocella=(%d,%d) _draw=%.2fms | contorno pianta=%.2fms, contorno edificio=%.2fms" % [
				debug_selection_draw_coords.x, debug_selection_draw_coords.y,
				(Time.get_ticks_usec() - _sel_start_usec) / 1000.0,
				_sel_individual_outline_usec / 1000.0, _sel_building_outline_usec / 1000.0,
			])
		debug_selection_draw_frame = -1


# Terreno uniforme (vedi _terrain_uniform/_is_world_uniform sopra): UN rettangolo con il colore comune a
# tutta la griglia (get_land_color se c'è un fiume, come il ciclo per-cella) + UN draw_multiline_colors con
# le linee della griglia. Il ciclo per-cella disegnava il contorno da 1 px di ogni cella con alpha
# TerrainColors.GRID.a: ogni bordo interno è condiviso da due celle, quindi veniva disegnato due volte
# (alpha composta 1 - (1 - a)^2 = ~0,28 con a = 0,15), mentre il bordo esterno una volta sola (alpha a).
# Le linee interne usano quindi l'alpha composta, quelle esterne l'alpha singola: stesso aspetto medio con
# 404 punti in un solo comando invece di 20.000 comandi.
# Punti e colori delle linee sono costanti (dipendono solo da CELL_SIZE e dal numero di celle), costruiti
# una volta sola e condivisi da tutte le istanze.
static var _uniform_grid_points: PackedVector2Array = PackedVector2Array()
static var _uniform_grid_colors: PackedColorArray = PackedColorArray()

static func _ensure_uniform_grid_lines() -> void:
	if not _uniform_grid_points.is_empty():
		return
	var width_px: float = float(World.WIDTH * CELL_SIZE)
	var height_px: float = float(World.HEIGHT * CELL_SIZE)
	var outer_color: Color = TerrainColors.GRID
	var inner_color: Color = Color(
		TerrainColors.GRID.r, TerrainColors.GRID.g, TerrainColors.GRID.b,
		1.0 - pow(1.0 - TerrainColors.GRID.a, 2.0)
	)
	for column in range(World.WIDTH + 1):
		var x: float = float(column * CELL_SIZE)
		_uniform_grid_points.append(Vector2(x, 0.0))
		_uniform_grid_points.append(Vector2(x, height_px))
		_uniform_grid_colors.append(outer_color if column == 0 or column == World.WIDTH else inner_color)
	for row in range(World.HEIGHT + 1):
		var y: float = float(row * CELL_SIZE)
		_uniform_grid_points.append(Vector2(0.0, y))
		_uniform_grid_points.append(Vector2(width_px, y))
		_uniform_grid_colors.append(outer_color if row == 0 or row == World.HEIGHT else inner_color)


func _draw_uniform_terrain() -> void:
	var first_cell: MacroCellData = world.cells[0]
	var color: Color = TerrainColors.get_land_color(first_cell) if is_river else TerrainColors.get_cell_color(first_cell)
	draw_rect(Rect2(0.0, 0.0, float(World.WIDTH * CELL_SIZE), float(World.HEIGHT * CELL_SIZE)), color)
	_ensure_uniform_grid_lines()
	draw_multiline_colors(_uniform_grid_points, _uniform_grid_colors, 1.0)


# Stessa geometria di BuildingGhost._draw() (recinto a linea continua + capanna tonda con porta a V,
# ancorati al centro della microcella), ma opaca: un edificio piazzato non è più un'anteprima.
# Ancoraggio al centro della microcella (base+half), nessun jitter/dispersione come per la
# vegetazione — un edificio occupa una posizione precisa, non un lotto condiviso da più individui.
func _draw_buildings() -> void:
	var half: float = CELL_SIZE / 2.0
	# Terra battuta PRIMA di ogni altro edificio (2026-09-19): è una superficie piatta a livello
	# del terreno, mai sopra la sagoma di un altro edificio — vedi _rebuild_dirt_ground_mesh.
	_draw_dirt_ground_tiles()
	_draw_linear_grounds()
	for entry in buildings:
		var pos: Vector2i = entry["position"]
		var ground := Vector2(pos.x * CELL_SIZE + half, pos.y * CELL_SIZE + half)
		# "Cantiere in attesa" (2026-09-11, richiesta utente, REVISIONATA lo stesso giorno — primo
		# tentativo era una variante grayscale della sagoma vera, scartato appena visto in-game) —
		# finché Building.is_complete resta false, la sagoma vera dell'edificio (capanna/Stone
		# Circle/Deposit Site) NON viene disegnata affatto: solo un cartello "work in progress" (se
		# site_setup_complete è ancora false, vedi _draw_construction_wip_marker) oppure nulla (una
		# volta che site_setup_complete diventa true — i bastoncini spawnati da GameScene.
		# _spawn_build_site_placeholders restano nodi separati, non gestiti qui). Default true per
		# compatibilità con entry che non passano ancora questi campi (nessuna in pratica oggi,
		# GameScene._buildings_for_cell li valorizza sempre — stesso principio difensivo già seguito
		# per "building_type_name" sotto).
		var is_complete: bool = entry.get("is_complete", true)
		if not is_complete:
			if not entry.get("site_setup_complete", false):
				_draw_construction_wip_marker(ground)
			continue
		# Smistamento per tipo (2026-09-07, richiesta utente, Pebble Circle) — .get() con default
		# "hut" per compatibilità con entry costruite prima che "building_type_name" esistesse
		# (nessuna in pratica, buildings è ricostruito ad ogni attivazione cella, mai persistito qui
		# — ma stesso principio difensivo già usato altrove nel progetto per Dictionary in evoluzione).
		var building_type_name: String = entry.get("building_type_name", "hut")
		if building_type_name == "pebble_circle":
			_draw_pebble_circle(ground)
			continue
		if building_type_name == "campfire":
			_draw_campfire(ground)
			continue
		if building_type_name == "dirt_ground":
			# Già disegnato da _draw_dirt_ground_tiles (una sola mesh per cella, un draw call) — qui solo lo skip, il ramo "cantiere" sopra copre i tile
			# non ancora completi.
			continue
		if building_type_name == "deposit_site":
			_draw_deposit_site(ground)
			# Griglia di stoccaggio (2026-09-11, richiesta utente — "sul deposit site... disegna gli
			# oggetti che ci sono, tipo mucchietti... solo un alert visivo, non mi interessa
			# proporzionalità alla quantità") — SOLO per deposit_site, vedi GameScene.
			# _buildings_for_cell per dove "slot_breakdown" viene calcolato/allegato a questa entry.
			# .get() con default [] per compatibilità con entry che non lo passano (nessuna in
			# pratica oggi, GameScene lo valorizza sempre per questo tipo — stesso principio
			# difensivo già seguito sopra per "building_type_name").
			_draw_deposit_site_storage_grid(ground, entry.get("slot_breakdown", []))
			continue
		# Deposito coperto (2026-10-04, richiesta utente): lo spiazzo e i mucchietti del sito di deposito, con sopra la
		# tettoia leggera di CoveredDepotShape (pali, graticcio, due pelli) che lascia vedere i mucchi.
		if building_type_name == "covered_depot":
			_draw_deposit_site(ground)
			_draw_deposit_site_storage_grid(ground, entry.get("slot_breakdown", []))
			CoveredDepotShape.draw_cover(self, ground)
			continue
		# Edifici segnaposto (2026-09-26, richiesta utente) — disegno provvisorio condiviso, senza porta.
		# Vallo difensivo a pezzi uniti (2026-10-04, richiesta utente): cumulo più un braccio verso ogni lato con un altro
		# pezzo di vallo, finito o cantiere ("linear_neighbors"/"linear_clip", calcolate da GameScene._buildings_for_cell
		# per ogni edificio lineare; un futuro edificio lineare aggiunge qui il proprio ramo con il proprio stile).
		if building_type_name == "earthwork":
			EarthworkShape.draw(self, ground, int(entry.get("linear_neighbors", 0)), false, 1.0, 1.0, int(entry.get("linear_clip", 0)))
			continue
		if PlaceholderBuildingShapes.TYPES.has(building_type_name):
			PlaceholderBuildingShapes.draw(self, building_type_name, ground)
			continue
		var direction: GameTypes.Direction = entry["rotation"]
		# Tende (2026-10-03, scambio di aspetto — TentShapes): la tenda di pelli ha il disco liscio che prima avevano
		# entrambe, la tenda di rami la copertura di rami a raggiera.
		if building_type_name == "hide_tent":
			TentShapes.draw_hide_tent(self, ground, direction)
			continue
		if building_type_name == "stick_tent":
			TentShapes.draw_stick_tent(self, ground, direction)
			continue
		# Capanna di stoccaggio (2026-10-03, richiesta utente): pianta quadrata chiusa, StorageHutShape. Niente griglia
		# dei mucchietti (solo il sito di deposito la ha).
		if building_type_name == "storage_hut":
			StorageHutShape.draw(self, ground, direction)
			continue
		# Capanna dell'attrezzista (2026-09-24, richiesta utente) — disegno provvisorio: stessa sagoma
		# della capanna (porta + recinto, ruota con `direction`), riempimento più scuro e un segno
		# "attrezzi incrociati" al centro, vedi _draw_toolmaker_hut_mark.
		var is_toolmaker_hut: bool = building_type_name == "toolmaker_hut"
		_draw_building_fence(ground, direction)
		var hut_points := _building_hut_polygon(ground, direction)
		draw_colored_polygon(hut_points, TOOLMAKER_HUT_COLOR if is_toolmaker_hut else BUILDING_COLOR)
		# Riempie il ritaglio della porta col colore del bordo invece di lasciarlo trasparente
		# (richiesta utente, 2026-08-30: aperto sul terreno sotto leggeva come una sagoma a V
		# "stile Batman", non come una porta) — stessi tre punti già calcolati per hut_points:
		# la spalla iniziale (indice 0), l'apice (ultimo punto) e la spalla finale (penultimo).
		draw_colored_polygon(
			PackedVector2Array([hut_points[0], hut_points[hut_points.size() - 1], hut_points[hut_points.size() - 2]]),
			BUILDING_OUTLINE_COLOR
		)
		var outline_points := hut_points.duplicate()
		outline_points.append(hut_points[0])
		draw_polyline(outline_points, BUILDING_OUTLINE_COLOR, BUILDING_OUTLINE_WIDTH)
		if is_toolmaker_hut:
			_draw_toolmaker_hut_mark(ground)


# Capanna dell'attrezzista (2026-09-24, richiesta utente) — forma provvisoria: riempimento della
# sagoma capanna più scuro/grigiastro (pietra lavorata) + due tratti incrociati chiari al centro
# (attrezzi incrociati), con una piccola "testa" su ciascuno. Stessa geometria (duplicata apposta)
# di BuildingGhost._draw_toolmaker_hut_mark.
const TOOLMAKER_HUT_COLOR := Color(0.46, 0.40, 0.34, 1.0)
const TOOLMAKER_HUT_MARK_COLOR := Color(0.88, 0.84, 0.76, 1.0)
const TOOLMAKER_HUT_MARK_HALF_LENGTH: float = 1.3
const TOOLMAKER_HUT_MARK_WIDTH: float = 0.35
const TOOLMAKER_HUT_MARK_HEAD_RADIUS: float = 0.4

func _draw_toolmaker_hut_mark(ground: Vector2) -> void:
	for diagonal in [Vector2(1, -1), Vector2(-1, -1)]:
		var half: Vector2 = diagonal.normalized() * TOOLMAKER_HUT_MARK_HALF_LENGTH
		draw_line(ground - half, ground + half, TOOLMAKER_HUT_MARK_COLOR, TOOLMAKER_HUT_MARK_WIDTH)
		draw_circle(ground + half, TOOLMAKER_HUT_MARK_HEAD_RADIUS, TOOLMAKER_HUT_MARK_COLOR)


# Cartello "work in progress" — vedi il commento esteso su WIP_SIGN_POST_COLOR sopra per il perché.
# Palo sottile verticale + cartello triangolare giallo/nero con punto esclamativo, ancorato al
# centro della microcella (stesso ancoraggio `ground` di ogni altra sagoma edificio qui).
func _draw_construction_wip_marker(ground: Vector2) -> void:
	var post_top: Vector2 = ground + Vector2(0, -WIP_SIGN_POST_HEIGHT)
	draw_line(ground, post_top, WIP_SIGN_POST_COLOR, WIP_SIGN_POST_WIDTH)

	var plate_center: Vector2 = post_top + Vector2(0, -WIP_SIGN_PLATE_RADIUS * 0.3)
	var triangle := PackedVector2Array([
		plate_center + Vector2(0.0, -WIP_SIGN_PLATE_RADIUS),
		plate_center + Vector2(WIP_SIGN_PLATE_RADIUS * 0.9, WIP_SIGN_PLATE_RADIUS * 0.75),
		plate_center + Vector2(-WIP_SIGN_PLATE_RADIUS * 0.9, WIP_SIGN_PLATE_RADIUS * 0.75),
	])
	draw_colored_polygon(triangle, WIP_SIGN_PLATE_COLOR)
	var outline := triangle.duplicate()
	outline.append(triangle[0])
	draw_polyline(outline, WIP_SIGN_PLATE_OUTLINE_COLOR, WIP_SIGN_PLATE_OUTLINE_WIDTH)

	# Punto esclamativo: un trattino verticale + un puntino, entrambi centrati nel triangolo.
	draw_line(
		plate_center + Vector2(0.0, -WIP_SIGN_PLATE_RADIUS * 0.45),
		plate_center + Vector2(0.0, WIP_SIGN_PLATE_RADIUS * 0.15),
		WIP_SIGN_MARK_COLOR, WIP_SIGN_MARK_WIDTH
	)
	draw_circle(plate_center + Vector2(0.0, WIP_SIGN_PLATE_RADIUS * 0.4), WIP_SIGN_MARK_WIDTH * 0.5, WIP_SIGN_MARK_COLOR)


# Anello di sassolini attorno al centro della microcella — nessuna porta/rotazione da rispettare
# (has_door=false per questo tipo), quindi geometria fissa: PEBBLE_CIRCLE_PEBBLE_COUNT sassolini
# equidistanti sul cerchio di raggio PEBBLE_CIRCLE_RING_RADIUS, ciascuno un poligono irregolare (vedi
# _pebble_blob_polygon) invece di un cerchio perfetto. Stessa funzione (duplicata apposta, stesso
# principio già in uso tra MicroCellRenderer/BuildingGhost per la geometria della capanna) in
# BuildingGhost._draw_pebble_circle. Chiamata SOLO a edificio completo (vedi _draw_buildings): il
# breve esperimento di una variante colore/parametro per il "cantiere in attesa" (2026-09-11) è
# stato scartato lo stesso giorno a favore del cartello WIP, che sostituisce del tutto questa
# sagoma finché is_complete resta false — nessun parametro colore più necessario qui.
func _draw_pebble_circle(ground: Vector2) -> void:
	for i in range(PEBBLE_CIRCLE_PEBBLE_COUNT):
		var angle: float = TAU * float(i) / float(PEBBLE_CIRCLE_PEBBLE_COUNT)
		var pebble_center: Vector2 = ground + Vector2(cos(angle), sin(angle)) * PEBBLE_CIRCLE_RING_RADIUS
		var blob := _pebble_blob_polygon(pebble_center, i)
		draw_colored_polygon(blob, PEBBLE_CIRCLE_COLOR)
		var outline := blob.duplicate()
		outline.append(blob[0])
		draw_polyline(outline, PEBBLE_CIRCLE_OUTLINE_COLOR, PEBBLE_CIRCLE_OUTLINE_WIDTH)


# Poligono a PEBBLE_CIRCLE_BLOB_VERTEX_COUNT lati con raggio-per-vertice jittered attorno a `center`
# — stesso principio delle mesh "jittered-blob" già usate per le pietre naturali (vedi
# _rebuild_stone_multimeshes), qui immediate-mode e molto più leggero (un solo sassolino alla volta,
# non migliaia). `seed_index` (0..PEBBLE_CIRCLE_PEBBLE_COUNT-1, l'indice del sassolino nell'anello,
# non la sua posizione) rende ogni sassolino diverso dagli altri ma STABILE tra un _draw() e il
# successivo — una RandomNumberGenerator locale seedata, non randf() globale, altrimenti la sagoma
# "tremolerebbe" ad ogni ridisegno. Anche la dimensione complessiva varia leggermente da sassolino a
# sassolino (non solo il contorno), per un anello che legga come sassolini veri e diversi tra loro,
# non stampati dallo stesso timbro.
func _pebble_blob_polygon(center: Vector2, seed_index: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_index
	var pebble_radius: float = PEBBLE_CIRCLE_PEBBLE_RADIUS * rng.randf_range(0.8, 1.2)
	var points := PackedVector2Array()
	for v in range(PEBBLE_CIRCLE_BLOB_VERTEX_COUNT):
		var vertex_angle: float = TAU * float(v) / float(PEBBLE_CIRCLE_BLOB_VERTEX_COUNT)
		var vertex_radius: float = pebble_radius * rng.randf_range(0.75, 1.15)
		points.append(center + Vector2(cos(vertex_angle), sin(vertex_angle)) * vertex_radius)
	return points


# Recinto: linea circolare CONTINUA attorno alla capanna (BUILDING_FENCE_RADIUS, "O" attorno alla
# "o" della capanna vera, più sottile del bordo della capanna — BUILDING_FENCE_WIDTH <
# BUILDING_OUTLINE_WIDTH), interrotta SOLO in corrispondenza della porta — stesso spicchio
# mancante (stesso angolo/stessa direction) di _building_hut_polygon, così l'apertura del recinto
# è sempre allineata alla porta. All'imbocco dell'apertura, una linea corta verso l'esterno
# (BUILDING_GATE_LENGTH) simula il cancello aperto sul cardine — niente tratteggio (richiesta
# utente, 2026-08-30: leggeva come sfumature indistinte vicino alla capanna, non come un recinto).
# Stessa funzione (duplicata apposta, vedi commento su _draw_buildings) in
# BuildingGhost._draw_fence. Chiamata SOLO a edificio completo (vedi commento su _draw_pebble_circle
# sopra) — nessun parametro colore più necessario.
func _draw_building_fence(ground: Vector2, direction: GameTypes.Direction) -> void:
	var dir_vector := _direction_vector(direction)
	var gate_center_angle: float = dir_vector.angle()
	var gate_half_angle: float = BUILDING_DOOR_NOTCH_HALF_WIDTH / BUILDING_FENCE_RADIUS
	var start_angle: float = gate_center_angle + gate_half_angle
	var end_angle: float = gate_center_angle - gate_half_angle + TAU
	draw_arc(ground, BUILDING_FENCE_RADIUS, start_angle, end_angle, BUILDING_CIRCLE_SEGMENTS, BUILDING_FENCE_COLOR, BUILDING_FENCE_WIDTH, true)

	var hinge_dir := Vector2(cos(start_angle), sin(start_angle))
	var hinge: Vector2 = ground + hinge_dir * BUILDING_FENCE_RADIUS
	draw_line(hinge, hinge + hinge_dir * BUILDING_GATE_LENGTH, BUILDING_FENCE_COLOR, BUILDING_FENCE_WIDTH)


# Poligono della capanna: segue il cerchio di raggio BUILDING_HUT_RADIUS per quasi tutto il giro,
# tranne nello spicchio della porta (centrato sull'angolo di `direction`, ampiezza 2×half_angle),
# dove al posto dell'arco rientra fino a un apice più vicino al centro (BUILDING_DOOR_NOTCH_DEPTH)
# — lo spicchio mancante viene poi riempito a parte col colore del bordo (vedi _draw_buildings),
# non lasciato trasparente. half_angle è un'approssimazione ad angolo piccolo (corda/raggio),
# accettabile per una porta stretta rispetto al raggio della capanna. Stessa funzione (duplicata
# apposta, vedi commento su _draw_buildings) in BuildingGhost._hut_polygon, così l'anteprima
# durante il piazzamento e l'edificio finito mostrano la porta esattamente nello stesso punto.
func _building_hut_polygon(ground: Vector2, direction: GameTypes.Direction) -> PackedVector2Array:
	var dir_vector := _direction_vector(direction)
	var door_center_angle: float = dir_vector.angle()
	var half_angle: float = BUILDING_DOOR_NOTCH_HALF_WIDTH / BUILDING_HUT_RADIUS
	var start_angle: float = door_center_angle + half_angle
	var sweep: float = TAU - half_angle * 2.0
	var points := PackedVector2Array()
	for i in range(BUILDING_CIRCLE_SEGMENTS + 1):
		var t: float = float(i) / float(BUILDING_CIRCLE_SEGMENTS)
		var angle: float = start_angle + sweep * t
		points.append(ground + Vector2(cos(angle), sin(angle)) * BUILDING_HUT_RADIUS)
	points.append(ground + dir_vector * (BUILDING_HUT_RADIUS - BUILDING_DOOR_NOTCH_DEPTH))
	return points


# Terreno in terra battuta (2026-09-19, richiesta utente) — superficie color sabbia che copre la
# microcella, "sporcata" con chiazze e puntini casuali di altro colore (vedi DirtGroundPattern per
# colori e macchie). Nessuna rotazione di edificio né porta (has_door=false in dirt_ground.tres).
#
# UNA SOLA MESH PER CELLA, UN SOLO draw call (2026-09-19, richiesta utente — "una sola mesh per
# cella, 1 draw call"): tutti i tile completi della cella sono cotti in un unico ArrayMesh (colori
# nei vertici) ricostruito in set_buildings e disegnato con un solo draw_mesh. Il contorno di ogni
# tile è calcolato QUI, alla costruzione della mesh, mai a ogni _draw, ed è deterministico dalla
# posizione (hash per lato e per angolo, indipendente dai vicini: costruire un tile accanto non
# cambia la forma degli altri lati) — quindi non sfarfalla tra i redraw.
#
# Contorno: un lato che confina con un altro tile di terra battuta (bit della maschera
# "dirt_neighbors" passata da GameScene, calcolata anche oltre il confine di macrocella) resta
# DRITTO e con gli angoli esatti, così tile adiacenti combaciano senza cuciture. Un lato che confina
# con altro è IRREGOLARE: DIRT_GROUND_SIDE_POINT_COUNT punti intermedi spostati verso l'interno di
# una profondità casuale (0 .. DIRT_GROUND_NOTCH_MAX_DEPTH_RATIO × CELL_SIZE, ogni tanto 0) — nelle
# rientranze non c'è geometria, quindi si vede il terreno sotto. Un angolo tra DUE lati irregolari è
# smussato di un raggio casuale (chamfer). Le macchie stanno a distanza >=
# DIRT_GROUND_SPECKLE_INNER_MARGIN dal bordo (maggiore della rientranza massima), così non spuntano
# fuori sagoma.
#
# Triangoli per tile: fan dal centro sul contorno (al massimo circa 24) + 13 macchie × 4 = 52,
# cioè ~76 al massimo, non più degli 80 (2 + 13 × 6) del vecchio tile a MultiMesh.
const DIRT_GROUND_CIRCLE_SEGMENTS: int = 4
const DIRT_GROUND_SIDE_POINT_COUNT: int = 4
const DIRT_GROUND_NOTCH_MAX_DEPTH_RATIO: float = 0.13
const DIRT_GROUND_CHAMFER_MIN_RATIO: float = 0.06
const DIRT_GROUND_CHAMFER_MAX_RATIO: float = 0.16
const DIRT_GROUND_SPECKLE_INNER_MARGIN: float = 0.16
# Lati nell'ordine N, E, S, W (senso orario sullo schermo, y verso il basso): direzione di marcia
# e verso l'interno del tile. Bit della maschera dei vicini: 1 << indice del lato.
const DIRT_GROUND_SIDE_DIRECTIONS := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
const DIRT_GROUND_SIDE_INWARD := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]

var _dirt_ground_mesh: ArrayMesh = null
# Macchie per variante (DirtGroundPattern.speckles con il margine interno), calcolate al primo uso.
var _dirt_ground_speckles_by_variant: Dictionary = {}

# Tipi di edificio con un fondo di terra battuta sotto la sagoma (2026-09-24, richiesta utente —
# prima si vedeva il verde del terreno attorno a tenda, cerchio di sassolini e focolare): stesso
# tile irregolare della terra battuta, stessi identici colori. Solo a edificio completo. Bordi come la terra
# battuta: dritti verso un edificio completo confinante ("dirt_neighbors", calcolata da GameScene),
# irregolari verso le celle senza nulla.
const GROUND_UNDER_BUILDING_TYPES: Array[String] = [
	"stick_tent", "hide_tent", "pebble_circle", "campfire", "drying_rack", "smokehouse", "burial", "earthwork", "stacked_stones",
	# Capanna dell'attrezzista (2026-10-04, richiesta utente: si vedeva il verde sotto, come gli altri edifici).
	"toolmaker_hut",
]


# Ricostruita da set_buildings (ogni volta che GameScene rinfresca gli edifici della cella): un
# tile per ogni terra battuta COMPLETA (un cantiere non ancora completo è disegnato dal cartello
# "lavori in corso" in _draw_buildings, non da qui).
func _rebuild_dirt_ground_mesh() -> void:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for entry in buildings:
		if not entry.get("is_complete", true):
			continue
		var building_type_name: String = entry.get("building_type_name", "")
		# Edifici lineari (2026-10-04): niente quadrato pieno, il fondo è la striscia lungo il tracciato
		# (_draw_linear_grounds).
		if bool(entry.get("is_linear", false)):
			continue
		if building_type_name == "dirt_ground":
			_append_dirt_ground_tile(entry["position"], int(entry.get("dirt_neighbors", 0)), vertices, colors)
		elif GROUND_UNDER_BUILDING_TYPES.has(building_type_name) or bool(entry.get("dirt_ground_under", false)):
			# "dirt_ground_under" (2026-10-04): fondo chiesto dalla voce stessa (oggi solo la capanna di stoccaggio, vedi
			# GameScene._buildings_for_cell), fuori dalla lista per tipo.
			_append_dirt_ground_tile(entry["position"], int(entry.get("dirt_neighbors", 0)), vertices, colors)
	if _dirt_ground_mesh != null:
		_dirt_ground_mesh.clear_surfaces()
	if vertices.is_empty():
		return
	if _dirt_ground_mesh == null:
		_dirt_ground_mesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_dirt_ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _append_dirt_ground_tile(pos: Vector2i, neighbor_mask: int, vertices: PackedVector2Array, colors: PackedColorArray) -> void:
	var half: float = CELL_SIZE / 2.0
	var center := Vector2(pos.x * CELL_SIZE + half, pos.y * CELL_SIZE + half)
	var corners: Array[Vector2] = [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]

	# Contorno in senso orario, coordinate locali al centro del tile. L'angolo `side` è l'inizio del
	# lato `side` e la fine del lato precedente.
	var boundary := PackedVector2Array()
	for side in range(4):
		var previous_side: int = (side + 3) % 4
		var side_irregular: bool = (neighbor_mask & (1 << side)) == 0
		var previous_irregular: bool = (neighbor_mask & (1 << previous_side)) == 0
		var corner: Vector2 = corners[side]
		if side_irregular and previous_irregular:
			var corner_rng := RandomNumberGenerator.new()
			corner_rng.seed = hash(Vector3i(pos.x, pos.y, 200 + side))
			var chamfer: float = CELL_SIZE * corner_rng.randf_range(DIRT_GROUND_CHAMFER_MIN_RATIO, DIRT_GROUND_CHAMFER_MAX_RATIO)
			boundary.append(corner - DIRT_GROUND_SIDE_DIRECTIONS[previous_side] * chamfer)
			boundary.append(corner + DIRT_GROUND_SIDE_DIRECTIONS[side] * chamfer)
		else:
			boundary.append(corner)
		if side_irregular:
			var side_rng := RandomNumberGenerator.new()
			side_rng.seed = hash(Vector3i(pos.x, pos.y, 100 + side))
			for i in range(DIRT_GROUND_SIDE_POINT_COUNT):
				# t in circa [0.2, 0.8] del lato con piccolo sfalsamento: i punti restano lontani
				# dagli angoli (dove c'è l'eventuale smusso) e in ordine crescente.
				var t: float = 0.2 + 0.6 * (float(i) + 0.5 + side_rng.randf_range(-0.3, 0.3)) / float(DIRT_GROUND_SIDE_POINT_COUNT)
				var depth: float = CELL_SIZE * DIRT_GROUND_NOTCH_MAX_DEPTH_RATIO * maxf(0.0, side_rng.randf_range(-0.25, 1.0))
				boundary.append(corner + DIRT_GROUND_SIDE_DIRECTIONS[side] * (t * CELL_SIZE) + DIRT_GROUND_SIDE_INWARD[side] * depth)

	# Base: fan dal centro sul contorno (il contorno è "a stella" rispetto al centro: rientranze
	# poco profonde, angoli al più smussati).
	for i in range(boundary.size()):
		vertices.append(center)
		vertices.append(center + boundary[i])
		vertices.append(center + boundary[(i + 1) % boundary.size()])
		for k in range(3):
			colors.append(DirtGroundPattern.BASE_COLOR)

	# Macchie: variante per hash della posizione, ciascuna un piccolo fan a DIRT_GROUND_CIRCLE_SEGMENTS.
	var variant: int = posmod(hash(pos * 31 + Vector2i(11, 5)), DirtGroundPattern.VARIANT_COUNT)
	if not _dirt_ground_speckles_by_variant.has(variant):
		_dirt_ground_speckles_by_variant[variant] = DirtGroundPattern.speckles(variant, DIRT_GROUND_SPECKLE_INNER_MARGIN)
	for speckle in _dirt_ground_speckles_by_variant[variant]:
		var speckle_center: Vector2 = center + (Vector2(speckle["x"], speckle["y"]) - Vector2(0.5, 0.5)) * CELL_SIZE
		var radius: float = float(speckle["r"]) * CELL_SIZE
		var speckle_color: Color = speckle["color"]
		for i in range(DIRT_GROUND_CIRCLE_SEGMENTS):
			var angle_a: float = TAU * float(i) / float(DIRT_GROUND_CIRCLE_SEGMENTS)
			var angle_b: float = TAU * float(i + 1) / float(DIRT_GROUND_CIRCLE_SEGMENTS)
			vertices.append(speckle_center)
			vertices.append(speckle_center + Vector2(cos(angle_a), sin(angle_a)) * radius)
			vertices.append(speckle_center + Vector2(cos(angle_b), sin(angle_b)) * radius)
			for k in range(3):
				colors.append(speckle_color)


# Fondo chiaro sotto gli edifici lineari finiti (2026-10-04, richiesta utente): una striscia lungo il tracciato, del colore
# di base della terra battuta, più la metà di microcella verso i vicini con il proprio fondo ("linear_ground_fill", da
# GameScene). Tutti i fondi prima di tutti gli argini, così il fondo di un pezzo non copre l'argine del vicino. Un nuovo
# edificio lineare aggiunge qui il proprio ramo con il proprio stile.
func _draw_linear_grounds() -> void:
	var half: float = CELL_SIZE / 2.0
	for entry in buildings:
		if not bool(entry.get("is_linear", false)) or not entry.get("is_complete", true):
			continue
		var pos: Vector2i = entry["position"]
		var ground := Vector2(pos.x * CELL_SIZE + half, pos.y * CELL_SIZE + half)
		match String(entry.get("building_type_name", "")):
			"earthwork":
				EarthworkShape.draw_ground(
					self, ground, int(entry.get("linear_neighbors", 0)), int(entry.get("linear_clip", 0)),
					int(entry.get("linear_ground_fill", 0)), DirtGroundPattern.BASE_COLOR
				)


func _draw_dirt_ground_tiles() -> void:
	if _dirt_ground_mesh == null or _dirt_ground_mesh.get_surface_count() == 0:
		return
	draw_mesh(_dirt_ground_mesh, null)
	_debug_draw_primitive_count += 1


# Sito di deposito: chiazza di terra battuta con lati irregolari e angoli smussati attorno al centro
# della microcella — nessuna porta/rotazione da rispettare (has_door=false per questo tipo),
# geometria fissa (seed fisso in DepositSiteShape, la stessa di BuildingGhost._draw_deposit_site).
# Chiamata SOLO a edificio completo (vedi commento su _draw_pebble_circle sopra).
#
# Poligono e contorno vengono dalla CACHE di DepositSiteShape (2026-09-19, richiesta utente: non
# ricalcolarli a ogni _draw) in coordinate locali centrate su (0,0); qui basta traslare il sistema di
# disegno su `ground` — nessun nuovo array per deposito, nessun draw call in più (1 poligono + 1
# polilinea come prima). Il transform torna a identità subito dopo, prima di _draw_deposit_site_
# storage_grid e di ogni altro disegno.
func _draw_deposit_site(ground: Vector2) -> void:
	draw_set_transform(ground)
	draw_colored_polygon(DepositSiteShape.get_polygon(DEPOSIT_SITE_HALF_SIDE), DEPOSIT_SITE_COLOR)
	draw_polyline(DepositSiteShape.get_closed_outline(DEPOSIT_SITE_HALF_SIDE), DEPOSIT_SITE_OUTLINE_COLOR, DEPOSIT_SITE_OUTLINE_WIDTH)
	draw_set_transform(Vector2.ZERO)


# Focolare (2026-09-23, richiesta utente) — forma provvisoria: anello di CAMPFIRE_STONE_COUNT pietre
# scure attorno a una fiamma (cerchio arancio + nucleo giallo). Più piccolo e più scuro del Pebble
# Circle (anello di raggio 4 di sassolini chiari), così i due non si confondono. Nessuna porta né
# rotazione (has_door=false in campfire.tres). Stessa geometria (duplicata apposta) di
# BuildingGhost._draw_campfire. Chiamata SOLO a edificio completo (vedi _draw_buildings).
const CAMPFIRE_STONE_COLOR := Color(0.35, 0.33, 0.30, 1.0)
const CAMPFIRE_FLAME_COLOR := Color(0.95, 0.45, 0.10, 1.0)
const CAMPFIRE_FLAME_CORE_COLOR := Color(1.0, 0.85, 0.30, 1.0)
const CAMPFIRE_RING_RADIUS: float = 2.6
const CAMPFIRE_STONE_RADIUS: float = 0.6
const CAMPFIRE_STONE_COUNT: int = 8
const CAMPFIRE_FLAME_RADIUS: float = 1.4
const CAMPFIRE_FLAME_CORE_RADIUS: float = 0.7

func _draw_campfire(ground: Vector2) -> void:
	for i in range(CAMPFIRE_STONE_COUNT):
		var angle: float = TAU * float(i) / float(CAMPFIRE_STONE_COUNT)
		draw_circle(ground + Vector2(cos(angle), sin(angle)) * CAMPFIRE_RING_RADIUS, CAMPFIRE_STONE_RADIUS, CAMPFIRE_STONE_COLOR)
	draw_circle(ground, CAMPFIRE_FLAME_RADIUS, CAMPFIRE_FLAME_COLOR)
	draw_circle(ground, CAMPFIRE_FLAME_CORE_RADIUS, CAMPFIRE_FLAME_CORE_COLOR)


# Un mucchietto per SLOT occupato di `slot_breakdown` (Array di {"resource_name","quantity",
# "space_used","space_capacity"}, vedi BuildingStorageService.get_slot_breakdown) — vedi il
# commento esteso su DEPOSIT_SITE_STORAGE_GRID_COLUMNS sopra per il principio. Griglia 3×3 in
# ordine RIGA per riga (indice i -> row=i/3, col=i%3), centrata su `ground`: offset colonna/riga in
# {-1,0,1} × DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING, così il mucchietto centrale (i=4) cade
# esattamente su `ground`. `i >= 9` (mai raggiungibile oggi: get_slot_breakdown non supera mai
# storage_slot_count=9 per deposit_site, ma questo file non deve assumerlo silenziosamente)
# interrompe il ciclo invece di continuare a disegnare fuori dalla chiazza del deposito.
func _draw_deposit_site_storage_grid(ground: Vector2, slot_breakdown: Array) -> void:
	for i in range(slot_breakdown.size()):
		if i >= DEPOSIT_SITE_STORAGE_GRID_COLUMNS * DEPOSIT_SITE_STORAGE_GRID_COLUMNS:
			break
		var slot_data: Dictionary = slot_breakdown[i]
		var resource_name: String = String(slot_data.get("resource_name", ""))
		if resource_name == "":
			continue
		var row: int = i / DEPOSIT_SITE_STORAGE_GRID_COLUMNS
		var col: int = i % DEPOSIT_SITE_STORAGE_GRID_COLUMNS
		var offset := Vector2(
			(float(col) - 1.0) * DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING,
			(float(row) - 1.0) * DEPOSIT_SITE_STORAGE_GRID_CELL_SPACING
		)
		var marker_center: Vector2 = ground + offset
		var top_left: Vector2 = marker_center - Vector2(DEPOSIT_SITE_STORAGE_SQUARE_SIDE, DEPOSIT_SITE_STORAGE_SQUARE_SIDE) * 0.5
		# Sfondo quadrato nello STESSO colore del deposito (lo "stratagemma" chiesto dall'utente al
		# posto della trasparenza vera) — disegnato SEMPRE, anche per una risorsa senza replica
		# dedicata sotto (fallback), così il quadrato resta comunque coerente con lo sfondo.
		draw_rect(Rect2(top_left, Vector2(DEPOSIT_SITE_STORAGE_SQUARE_SIDE, DEPOSIT_SITE_STORAGE_SQUARE_SIDE)), DEPOSIT_SITE_COLOR)
		# Icona magazzino della risorsa (DepositStorageIcons, condivisa con i mucchi a terra — GroundPileView).
		if not DepositStorageIcons.draw_icon(self, resource_name, top_left, DEPOSIT_SITE_STORAGE_SQUARE_SIDE):
			# Fallback per un'eventuale risorsa futura senza geometria replicata qui — un
			# semplice pallino nel colore della risorsa (IconRegistry.get_resource_color, stessa
			# fonte già in uso altrove), niente sfondo proprio oltre al quadrato sopra.
			draw_circle(marker_center, DEPOSIT_SITE_STORAGE_SQUARE_SIDE * 0.25, IconRegistry.get_resource_color(resource_name))


func _direction_vector(direction: GameTypes.Direction) -> Vector2:
	match direction:
		GameTypes.Direction.NORTH:
			return Vector2(0, -1)
		GameTypes.Direction.EAST:
			return Vector2(1, 0)
		GameTypes.Direction.WEST:
			return Vector2(-1, 0)
		_: # SOUTH, anche default
			return Vector2(0, 1)


func _draw_stone_positions() -> void:
	for mm in _stone_multimeshes:
		if mm.instance_count <= 0:
			continue
		draw_multimesh(mm, null)
		_debug_draw_primitive_count += 1


# Ogni sagoma-variante è un poligono a raggio irregolare (non un cerchio perfetto) per un
# aspetto più "roccioso": ogni vertice ha una propria variazione di raggio, derivata da
# hash(variante, indice vertice) — stessa formula di jitter di sempre, solo seminata per
# variante invece che per posizione (vedi commento su _stone_variant_meshes sopra). Il colore è
# cotto direttamente nei vertici della mesh (bianco * COLOR_STONE), quindi ogni pietra risulta
# comunque più larga della cella e le forme sovrapposte si fondono per alpha come prima.
const STONE_BLOB_VERTEX_COUNT: int = 9
const STONE_BLOB_VERTEX_JITTER: float = 0.18 # ±18% del raggio base, per vertice
const STONE_VARIANT_COUNT: int = 12
# Rocce contenute nella microcella (2026-09-27, richiesta utente — prima sbordavano fino a ~5,5 px): raggio base più
# piccolo, sagoma tagliata a un quadrato di lato 2 × STONE_SHAPE_AXIS_LIMIT, centro poco scostato, rotazioni solo a
# multipli di 90° (il quadrato di taglio resta allineato alla cella). Bordo a <= ~6 px dal centro della cella.
const STONE_RADIUS_MIN: float = 4.5
const STONE_RADIUS_MAX: float = 5.0
const STONE_SHAPE_AXIS_LIMIT: float = 5.2
const STONE_CENTER_JITTER: float = 0.3
const STONE_SCALE_MIN: float = 0.9
const STONE_SCALE_MAX: float = 1.1
# Distanza massima di un vertice dal centro della roccia, già scalata (contorno di selezione): raggio massimo ×
# (1 + scostamento dei vertici) × scala massima.
const STONE_MAX_EXTENT: float = STONE_RADIUS_MAX * (1.0 + STONE_BLOB_VERTEX_JITTER) * STONE_SCALE_MAX


func _ensure_stone_multimeshes() -> void:
	if not _stone_multimeshes.is_empty():
		return

	for variant in range(STONE_VARIANT_COUNT):
		_stone_variant_meshes.append(_build_stone_variant_mesh(variant))

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _stone_variant_meshes[variant]
		mm.instance_count = 0
		_stone_multimeshes.append(mm)


func _build_stone_variant_mesh(variant: int) -> ArrayMesh:
	var radius_variation: float = float(hash(Vector2i(variant, 977)) % 1000) / 1000.0
	var radius: float = lerp(STONE_RADIUS_MIN, STONE_RADIUS_MAX, radius_variation)

	var points := PackedVector2Array()
	for i in range(STONE_BLOB_VERTEX_COUNT):
		var angle: float = (float(i) / float(STONE_BLOB_VERTEX_COUNT)) * TAU
		var vertex_t: float = float(hash(Vector2i(variant, i) * 41 + Vector2i(i * 13 + 3, 7)) % 1000) / 1000.0
		var vertex_jitter: float = lerp(-STONE_BLOB_VERTEX_JITTER, STONE_BLOB_VERTEX_JITTER, vertex_t)
		var vertex_radius: float = radius * (1.0 + vertex_jitter)
		var vertex := Vector2(cos(angle), sin(angle)) * vertex_radius
		# Taglio al quadrato (2026-09-27): una volta sola, nella sagoma condivisa da tutte le rocce di questa variante.
		vertex.x = clampf(vertex.x, -STONE_SHAPE_AXIS_LIMIT, STONE_SHAPE_AXIS_LIMIT)
		vertex.y = clampf(vertex.y, -STONE_SHAPE_AXIS_LIMIT, STONE_SHAPE_AXIS_LIMIT)
		points.append(vertex)

	return _build_fan_mesh(points, COLOR_STONE)


# Ricalcola i buffer istanza (posizione/rotazione/scala per-pietra) ogni volta che le posizioni
# stone cambiano — stesso momento in cui prima si ridisegnava tutto, solo che ora il lavoro
# O(N) produce dati per MultiMesh invece di emettere subito un draw_polygon per pietra.
func _rebuild_stone_multimeshes() -> void:
	_ensure_stone_multimeshes()

	var buckets: Array = []
	for i in range(STONE_VARIANT_COUNT):
		buckets.append([]) # Array[Transform2D]

	for pos in stone_positions:
		var variant: int = posmod(hash(pos), STONE_VARIANT_COUNT)

		# Stesso identico centro-con-jitter di get_stone_screen_position (2026-09-08, estratta lì
		# per essere riusata anche da StoneSelectorController) — mai due formule che potrebbero
		# disallinearsi tra disegno e hit-test.
		var center := get_stone_screen_position(pos)

		# Rotazione + specchiatura + lieve variazione di scala per-istanza: disguisano la ripetizione tra le
		# STONE_VARIANT_COUNT sagome condivise, oltre alla posizione già unica per pietra. Rotazione solo a multipli di
		# 90° e specchiatura su un asse (2026-09-27): la sagoma tagliata al quadrato resta allineata alla cella. Stessi
		# hash di prima (la specchiatura ne usa uno nuovo), quindi deterministica.
		var quarter_turns: int = int(float(hash(pos * 13 + Vector2i(31, 17)) % 1000) / 250.0) % 4
		var rotation: float = float(quarter_turns) * PI / 2.0
		var mirror: float = -1.0 if hash(pos * 29 + Vector2i(11, 53)) % 2 == 0 else 1.0
		var scale_variation: float = lerp(STONE_SCALE_MIN, STONE_SCALE_MAX, float(hash(pos * 19 + Vector2i(3, 41)) % 1000) / 1000.0)

		var transform := Transform2D(rotation, Vector2.ZERO).scaled(Vector2(scale_variation * mirror, scale_variation))
		transform.origin = center

		buckets[variant].append(transform)

	for variant in range(STONE_VARIANT_COUNT):
		var transforms: Array = buckets[variant]
		var mm: MultiMesh = _stone_multimeshes[variant]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform_2d(i, transforms[i])


# Sassi/pebble (2026-09-08, richiesta utente) — puntini più piccoli sparsi ATTORNO a ciascuna
# posizione stone (non sovrapposti al masso principale), il cui NUMERO dipende dalla quantità
# pebble di quella posizione a 3 livelli: >PEBBLE_TIER_MANY_THRESHOLD "molti"
# (PEBBLE_COUNT_MANY), tra PEBBLE_TIER_NORMAL_THRESHOLD e la soglia sopra "quantità normale"
# (PEBBLE_COUNT_NORMAL), sotto "pochi" (PEBBLE_COUNT_FEW), 0 = nessun puntino disegnato. Stesso
# principio MultiMesh-con-varianti-condivise di stone sopra (PEBBLE_VARIANT_COUNT sagome
# pre-generate, mai una per puntino) — qui però un solo blob-base è comune anche a stone/pebble
# concettualmente diversi solo per dimensione, quindi una seconda mesh più piccola invece di
# riusare quella di stone.
const PEBBLE_TIER_MANY_THRESHOLD: int = 100
const PEBBLE_TIER_NORMAL_THRESHOLD: int = 50
# Rivisti (2026-09-08, richiesta utente: "un po' più numerosi... un po' più piccoli") — conteggi
# più alti, raggio ridotto (vedi PEBBLE_RADIUS_MIN/MAX sotto), stessi 3 scaglioni.
const PEBBLE_COUNT_FEW: int = 4
const PEBBLE_COUNT_NORMAL: int = 8
const PEBBLE_COUNT_MANY: int = 14
const PEBBLE_BLOB_VERTEX_COUNT: int = 7
const PEBBLE_BLOB_VERTEX_JITTER: float = 0.2
const PEBBLE_RADIUS_MIN: float = 0.6
const PEBBLE_RADIUS_MAX: float = 1.0
const PEBBLE_VARIANT_COUNT: int = 6
# Anello (non un disco pieno da 0) verso il BORDO della microcella (2026-09-08, richiesta utente:
# "verso il lato della microcella") — half-cell = CELL_SIZE/2 = 5, quindi 4.0-4.8 resta appena
# dentro il bordo: i puntini si leggono come sparsi attorno al masso principale invece che ammassati/nascosti
# sotto di esso al centro.
# Ridotto (2026-09-27, rocce contenute nella microcella) a 3,6–4,2: centro del ciottolo + raggio massimo del ciottolo
# (1,0 × 1,2 × 1,15 ≈ 1,38) + scostamento del centro della roccia (0,3 per asse, ~0,42) <= 6 px dal centro della cella.
const PEBBLE_SCATTER_MIN_RADIUS: float = 3.6
const PEBBLE_SCATTER_MAX_RADIUS: float = 4.2


# >0 = "pochi"/"quantità normale"/"molti" secondo le soglie sopra, 0 = quantity<=0 (nessun sasso
# raccoglibile in quella posizione, nessun puntino da disegnare).
func _pebble_tier_count(quantity: int) -> int:
	if quantity <= 0:
		return 0
	if quantity > PEBBLE_TIER_MANY_THRESHOLD:
		return PEBBLE_COUNT_MANY
	if quantity >= PEBBLE_TIER_NORMAL_THRESHOLD:
		return PEBBLE_COUNT_NORMAL
	return PEBBLE_COUNT_FEW


func _ensure_pebble_multimeshes() -> void:
	if not _pebble_multimeshes.is_empty():
		return

	for variant in range(PEBBLE_VARIANT_COUNT):
		_pebble_variant_meshes.append(_build_pebble_variant_mesh(variant))

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _pebble_variant_meshes[variant]
		mm.instance_count = 0
		_pebble_multimeshes.append(mm)


# Stessa identica tecnica di _build_stone_variant_mesh (poligono a raggio irregolare, jitter
# seminato per variante), solo raggio più piccolo (PEBBLE_RADIUS_MIN/MAX contro STONE_RADIUS_MIN/MAX)
# e seed diverso (moltiplicatori diversi nell'hash) così le due sagome-base non risultano
# identiche a parità di indice variante.
func _build_pebble_variant_mesh(variant: int) -> ArrayMesh:
	var radius_variation: float = float(hash(Vector2i(variant, 419)) % 1000) / 1000.0
	var radius: float = lerp(PEBBLE_RADIUS_MIN, PEBBLE_RADIUS_MAX, radius_variation)

	var points := PackedVector2Array()
	for i in range(PEBBLE_BLOB_VERTEX_COUNT):
		var angle: float = (float(i) / float(PEBBLE_BLOB_VERTEX_COUNT)) * TAU
		var vertex_t: float = float(hash(Vector2i(variant, i) * 29 + Vector2i(i * 7 + 11, 5)) % 1000) / 1000.0
		var vertex_jitter: float = lerp(-PEBBLE_BLOB_VERTEX_JITTER, PEBBLE_BLOB_VERTEX_JITTER, vertex_t)
		var vertex_radius: float = radius * (1.0 + vertex_jitter)
		points.append(Vector2(cos(angle), sin(angle)) * vertex_radius)

	return _build_fan_mesh(points, COLOR_PEBBLE)


# Ricalcola i buffer istanza dei pebble — chiamato da set_stone_positions/set_pebble_availability
# (2026-09-08). Per ogni posizione stone con tier>0, sparge `tier` puntini attorno al centro
# (get_stone_screen_position, STESSO ancoraggio del masso principale) con angolo/distanza/
# rotazione/scala deterministici per (posizione, indice puntino) — stabili tra un redraw e il
# successivo, stesso principio hash-based già in uso per stone/vegetazione ovunque nel progetto.
func _rebuild_pebble_multimeshes() -> void:
	_ensure_pebble_multimeshes()

	var buckets: Array = []
	for i in range(PEBBLE_VARIANT_COUNT):
		buckets.append([]) # Array[Transform2D]

	for pos in stone_positions:
		var quantity: int = int(pebble_availability.get(pos, 0))
		var tier_count := _pebble_tier_count(quantity)
		if tier_count <= 0:
			continue

		var center := get_stone_screen_position(pos)
		for i in range(tier_count):
			# Tipo esplicito (Vector2i), non := — stone_positions è un Array non tipizzato (Variant
			# per elemento, stesso motivo già commentato altrove nel file per questo campo), quindi
			# l'inferenza su un'espressione aritmetica a partire da `pos` non può dedurre un tipo a
			# compile-time pur essendo sempre un Vector2i a runtime.
			var seed_base: Vector2i = pos * 23 + Vector2i(i * 7 + 1, i * 13 + 4)
			var variant: int = posmod(hash(seed_base), PEBBLE_VARIANT_COUNT)

			var angle: float = (float(hash(seed_base + Vector2i(3, 9)) % 1000) / 1000.0) * TAU
			var dist: float = lerp(PEBBLE_SCATTER_MIN_RADIUS, PEBBLE_SCATTER_MAX_RADIUS, float(hash(seed_base + Vector2i(9, 3)) % 1000) / 1000.0)
			var offset := Vector2(cos(angle), sin(angle)) * dist

			var rotation: float = (float(hash(seed_base + Vector2i(5, 17)) % 1000) / 1000.0) * TAU
			var scale_variation: float = lerp(0.85, 1.15, float(hash(seed_base + Vector2i(17, 5)) % 1000) / 1000.0)

			var transform := Transform2D(rotation, Vector2.ZERO).scaled(Vector2(scale_variation, scale_variation))
			transform.origin = center + offset

			buckets[variant].append(transform)

	for variant in range(PEBBLE_VARIANT_COUNT):
		var transforms: Array = buckets[variant]
		var mm: MultiMesh = _pebble_multimeshes[variant]
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform_2d(i, transforms[i])


func _draw_pebble_positions() -> void:
	for mm in _pebble_multimeshes:
		if mm.instance_count <= 0:
			continue
		draw_multimesh(mm, null)
		_debug_draw_primitive_count += 1


# Bastoni/stick a terra (2026-09-08, richiesta utente) — 3 livelli di densità per lotto, stessa
# idea dei pebble ma sulla quantità DISPONIBILE (capacity - harvested) invece che sulla quantità
# grezza, così un lotto già raccolto smette di mostrare bastoni anche se capacity resta alta fino
# al prossimo checkpoint. Nessuna variante multipla di mesh (a differenza di stone/pebble): un
# bastone è solo un rettangolo sottile, rotazione + scala-lunghezza per-istanza bastano per la
# varietà visiva, un'unica mesh condivisa è sufficiente.
const STICK_TIER_MANY_THRESHOLD: int = 10
const STICK_TIER_NORMAL_THRESHOLD: int = 5
const STICK_COUNT_FEW: int = 2
const STICK_COUNT_NORMAL: int = 4
const STICK_COUNT_MANY: int = 6
const COLOR_STICK := Color(0.42, 0.30, 0.16, 0.95)
const STICK_HALF_LENGTH: float = 1.1
const STICK_HALF_WIDTH: float = 0.16
const STICK_LENGTH_VARIATION_MIN: float = 0.75
const STICK_LENGTH_VARIATION_MAX: float = 1.3
const STICK_SCATTER_RADIUS: float = 4.0


func _stick_tier_count(available_quantity: int) -> int:
	if available_quantity <= 0:
		return 0
	if available_quantity > STICK_TIER_MANY_THRESHOLD:
		return STICK_COUNT_MANY
	if available_quantity > STICK_TIER_NORMAL_THRESHOLD:
		return STICK_COUNT_NORMAL
	return STICK_COUNT_FEW


func _ensure_stick_mesh() -> void:
	if _stick_mesh != null:
		return
	var points := PackedVector2Array([
		Vector2(-STICK_HALF_LENGTH, -STICK_HALF_WIDTH), Vector2(STICK_HALF_LENGTH, -STICK_HALF_WIDTH),
		Vector2(STICK_HALF_LENGTH, STICK_HALF_WIDTH), Vector2(-STICK_HALF_LENGTH, STICK_HALF_WIDTH),
	])
	_stick_mesh = _build_fan_mesh(points, COLOR_STICK)
	_stick_multimesh = MultiMesh.new()
	_stick_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_stick_multimesh.mesh = _stick_mesh
	_stick_multimesh.instance_count = 0


# Ricostruita da set_stick_availability ogni volta che GameScene/MacroCellScene rinfrescano la
# disponibilità (macrocella ridisegnata) — mai qui in modo autonomo. Ogni lotto con quantità
# disponibile > 0 genera N bastoni (N = _stick_tier_count) sparpagliati con hash deterministico
# attorno al centro del lotto, stesso principio dei pebble attorno alla stone (jitter stabile tra
# un redraw e l'altro finché la quantità non cambia). Vector2i tipizzato esplicitamente (non :=)
# perché `lot` proviene da un ciclo su Dictionary.keys() non tipizzato — stesso errore di
# inferenza già incontrato con pebble_availability.
func _rebuild_stick_multimesh() -> void:
	_ensure_stick_mesh()
	var half: float = CELL_SIZE / 2.0
	var transforms: Array = []
	for lot in stick_availability.keys():
		var available: int = int(stick_availability[lot])
		var count := _stick_tier_count(available)
		if count <= 0:
			continue
		var lot_pos: Vector2i = lot
		var ground: Vector2 = Vector2(lot_pos.x * CELL_SIZE + half, lot_pos.y * CELL_SIZE + half)
		for i in range(count):
			var seed_base: Vector2i = lot_pos * 31 + Vector2i(i * 9 + 2, i * 17 + 5)
			var angle: float = (float(hash(seed_base + Vector2i(7, 3)) % 1000) / 1000.0) * TAU
			var dist: float = STICK_SCATTER_RADIUS * (float(hash(seed_base + Vector2i(3, 7)) % 1000) / 1000.0)
			var offset: Vector2 = Vector2(cos(angle), sin(angle)) * dist
			var stick_rotation: float = (float(hash(seed_base + Vector2i(11, 13)) % 1000) / 1000.0) * TAU
			var length_scale: float = lerp(STICK_LENGTH_VARIATION_MIN, STICK_LENGTH_VARIATION_MAX, float(hash(seed_base + Vector2i(13, 11)) % 1000) / 1000.0)
			var stick_transform := Transform2D(stick_rotation, Vector2.ZERO).scaled(Vector2(length_scale, 1.0))
			stick_transform.origin = ground + offset
			transforms.append(stick_transform)
	_stick_multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		_stick_multimesh.set_instance_transform_2d(i, transforms[i])


func _draw_stick_positions() -> void:
	if _stick_multimesh == null or _stick_multimesh.instance_count <= 0:
		return
	draw_multimesh(_stick_multimesh, null)
	_debug_draw_primitive_count += 1


# Nidi/eggs a terra (2026-09-18/19, richiesta utente — "anche il rendering sulla microcella
# disegna le tre ovette come nel magazzino"): MIRROR ESATTO del pattern stick per il MECCANISMO
# (un solo mesh unitario condiviso, UN SOLO MultiMesh con N istanze, rotazione per-istanza per la
# varietà visiva — MAI una primitiva di disegno per nido: niente draw_circle/draw_polygon dentro
# _draw(), un pattern immediate-mode del genere ha già esaurito il command buffer e fatto
# crashare il gioco altrove nel progetto, vedi FogOfWarRenderer), ma la FORMA della mesh unitaria
# è ora la STESSA composizione a tre uova (due color-ombra, una color-base — DEPOSIT_STORAGE_EGGS
# più sotto in questo file) già usata per l'icona del magazzino, non un singolo ovale generico
# scalato per tier di quantità (rimosso, con _egg_tier_count/EGG_TIER_*/EGG_COUNT_*: un nido è
# UNA nidiata, non "1, 2 o 3 oggetti separati" — la composizione a tre uova non cambia con la
# quantità disponibile, esattamente come l'icona di magazzino non scala con essa). Il mesh
# UNITARIO qui è quindi COMPOSITO (tre ellissi, ciascuna col proprio colore cotto nei vertici via
# SurfaceTool.set_color() — chiamato una volta per uovo PRIMA di aggiungerne i vertici, ogni
# add_vertex successivo eredita il colore corrente, stesso principio di _build_fan_mesh ma con più
# di un colore in una singola mesh), riusando DIRETTAMENTE i dati DEPOSIT_STORAGE_EGGS (stessa
# fonte di verità per le due rappresentazioni della risorsa, mai una copia separata che potrebbe
# disallinearsi). Un solo instance PER NIDO con disponibilità > 0 (nessuna variazione di conteggio
# per quantità), con una rotazione deterministica per nido (hash su posizione) per varietà visiva
# tra un nido e l'altro — altrimenti ogni nido sulla mappa avrebbe l'identica orientazione.
const EGG_CLUSTER_SCALE: float = 2.6
const EGG_ROTATION_JITTER_MAX: float = 0.35


# Punto sul contorno di un "uovo" (ovale asimmetrico, più stretto verso l'alto/y negativo) dato
# raggio e angolo — STESSA formula già usata per l'icona di magazzino (DepositStorageIcons._draw_deposit_storage_egg), duplicata apposta qui: due contesti di disegno diversi (mesh cotta vs poligono
# immediate-mode), stesso principio "nessuna funzione condivisa tra usi diversi" già seguito
# altrove in questo file per le ellissi di berry/mushroom.
static func _egg_shape_point(radius: Vector2, angle: float) -> Vector2:
	var width_scale: float = lerp(0.72, 1.0, (1.0 - cos(angle)) * 0.5)
	return Vector2(sin(angle) * radius.x * width_scale, -cos(angle) * radius.y)


func _ensure_egg_mesh() -> void:
	if _egg_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for egg in DepositStorageIcons.DEPOSIT_STORAGE_EGGS:
		# Da spazio [0,1] relativo a un lato quadrato (convenzione dell'icona di magazzino) a
		# spazio centrato in (0,0) scalato per EGG_CLUSTER_SCALE — l'unica conversione necessaria
		# per riusare DIRETTAMENTE cx/cy/rx/ry/rot di DEPOSIT_STORAGE_EGGS qui.
		var center := Vector2(float(egg["cx"]) - 0.5, float(egg["cy"]) - 0.5) * EGG_CLUSTER_SCALE
		var radius := Vector2(float(egg["rx"]), float(egg["ry"])) * EGG_CLUSTER_SCALE
		var egg_rotation: float = float(egg["rot"])
		st.set_color(egg["color"])
		var center3 := Vector3(center.x, center.y, 0.0)
		for i in range(DepositStorageIcons.DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS):
			var angle_a: float = TAU * float(i) / float(DepositStorageIcons.DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS)
			var angle_b: float = TAU * float(i + 1) / float(DepositStorageIcons.DEPOSIT_STORAGE_EGG_ELLIPSE_SEGMENTS)
			var point_a: Vector2 = center + _egg_shape_point(radius, angle_a).rotated(egg_rotation)
			var point_b: Vector2 = center + _egg_shape_point(radius, angle_b).rotated(egg_rotation)
			st.add_vertex(center3)
			st.add_vertex(Vector3(point_a.x, point_a.y, 0.0))
			st.add_vertex(Vector3(point_b.x, point_b.y, 0.0))
	_egg_mesh = st.commit()
	_egg_multimesh = MultiMesh.new()
	_egg_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_egg_multimesh.mesh = _egg_mesh
	_egg_multimesh.instance_count = 0


# Ricostruita da set_egg_nest_availability ogni volta che GameScene rinfresca la disponibilità
# (checkpoint stagionale/raccolta/movimento con filtro FoW cambiato) — MAI qui in modo autonomo,
# stesso principio di _rebuild_stick_multimesh. Un'istanza per nido con disponibilità > 0 (nessuna
# variazione di conteggio, vedi commento di testa sopra), centrata sulla SUA microcella con una
# rotazione deterministica per varietà visiva. Vector2i tipizzato esplicitamente (non :=) perché
# `nest_pos` proviene da un ciclo su Dictionary.keys() non tipizzato — stesso trattamento già
# riservato a `lot` in _rebuild_stick_multimesh.
func _rebuild_egg_multimesh() -> void:
	_ensure_egg_mesh()
	var half: float = CELL_SIZE / 2.0
	var transforms: Array = []
	for nest_pos in egg_nest_availability.keys():
		var available: int = int(egg_nest_availability[nest_pos])
		if available <= 0:
			continue
		var nest_lot: Vector2i = nest_pos
		var ground: Vector2 = Vector2(nest_lot.x * CELL_SIZE + half, nest_lot.y * CELL_SIZE + half) + _lot_marker_offset(nest_lot, "eggs")
		var seed_base: Vector2i = nest_lot * 41 + Vector2i(5, 11)
		var jitter_rotation: float = lerp(-EGG_ROTATION_JITTER_MAX, EGG_ROTATION_JITTER_MAX, float(hash(seed_base + Vector2i(7, 3)) % 1000) / 1000.0)
		var egg_transform := Transform2D(jitter_rotation, Vector2.ZERO)
		egg_transform.origin = ground
		transforms.append(egg_transform)
	_egg_multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		_egg_multimesh.set_instance_transform_2d(i, transforms[i])


# Offset deterministico dal centro della microcella per il marker a terra di `resource_name`
# (2026-09-19, richiesta utente — uova/verdure/erbe medicinali disegnate tutte al centro si
# sovrapponevano quando più risorse coesistono nello stesso lotto). Hash su posizione + NOME
# RISORSA (due assi con suffisso diverso, quindi indipendenti): stessa posizione + stessa risorsa
# -> sempre lo stesso offset, stabile tra redraw/sessioni (hash() di una String è deterministico,
# nessun randf()); risorse diverse sullo stesso lotto -> offset diversi. Limitato a ±
# LOT_MARKER_OFFSET_MAX_FRACTION × CELL_SIZE per asse, quindi il PUNTO DI ANCORAGGIO resta sempre
# dentro la microcella (mai sul bordo: frazione < 0.5). NB: la FORMA disegnata (scala 2.4-3.6 ×
# CELL_SIZE) è più grande della microcella, come già prima di questo offset — l'offset separa i
# centri, non contiene i contorni. posmod, non %: hash() può essere negativo.
const LOT_MARKER_OFFSET_MAX_FRACTION: float = 0.4

func _lot_marker_offset(lot: Vector2i, resource_name: String) -> Vector2:
	var max_offset: float = CELL_SIZE * LOT_MARKER_OFFSET_MAX_FRACTION
	var unit_x: float = float(posmod(hash("%d_%d_%s_offset_x" % [lot.x, lot.y, resource_name]), 1000)) / 999.0
	var unit_y: float = float(posmod(hash("%d_%d_%s_offset_y" % [lot.x, lot.y, resource_name]), 1000)) / 999.0
	return Vector2(lerp(-max_offset, max_offset, unit_x), lerp(-max_offset, max_offset, unit_y))


func _draw_egg_nest_positions() -> void:
	if _egg_multimesh == null or _egg_multimesh.instance_count <= 0:
		return
	draw_multimesh(_egg_multimesh, null)
	_debug_draw_primitive_count += 1


# Marker a terra dei lotti GRASS_PATCH (wild_vegetables dal 2026-09-19, GENERALIZZATO lo stesso
# giorno per medicinal_herbs — richiesta utente: "un dizionario resource_name → multimesh, così
# vale per entrambe e per le prossime, invece di duplicarlo"): un MultiMesh PER RISORSA (mesh
# COMPOSITA cotta una volta sola con SurfaceTool a partire dalla sua forma), UN SOLO instance per
# lotto con disponibilità > 0, nessuna variazione di conteggio, rotazione deterministica per
# varietà visiva — stessa struttura del blocco eggs sopra. Le forme riusano DIRETTAMENTE le liste
# DEPOSIT_STORAGE_*_LEAVES delle icone di magazzino (stessa fonte di verità, mai una copia
# separata). Aggiungere una risorsa GRASS_PATCH nuova = una riga qui (+ la sua lista di ellissi);
# una risorsa senza riga NON viene disegnata (warning una tantum, mai un marker generico che
# sembra un'altra risorsa). Le foglie sono ellissi semplici (cos/sin diretti, nessun width_scale).
const GRASS_PATCH_MARKER_SHAPES := {
	"wild_vegetables": DepositStorageIcons.DEPOSIT_STORAGE_WILD_VEGETABLES_LEAVES,
	"medicinal_herbs": DepositStorageIcons.DEPOSIT_STORAGE_MEDICINAL_HERBS_LEAVES,
}
const GRASS_PATCH_CLUSTER_SCALE: float = 2.4
# Scala per-risorsa che sostituisce GRASS_PATCH_CLUSTER_SCALE (2026-09-19, richiesta utente — "le
# erbe medicinali un po' più grandi": le loro foglioline sono ellissi basse, a parità di scala
# risultano molto più piccole delle foglie delle verdure). Una risorsa assente qui usa il default.
const GRASS_PATCH_CLUSTER_SCALE_BY_RESOURCE := {
	"medicinal_herbs": 3.6,
}
const GRASS_PATCH_ROTATION_JITTER_MAX: float = 0.4
const GRASS_PATCH_ELLIPSE_SEGMENTS: int = 12


# MultiMesh del marker di `resource_name`, creato al primo uso. null se la risorsa non ha una forma
# in GRASS_PATCH_MARKER_SHAPES (warning una tantum per risorsa, questa funzione è chiamata a ogni
# refresh).
func _get_grass_patch_multimesh(resource_name: String) -> MultiMesh:
	if _grass_patch_multimeshes.has(resource_name):
		return _grass_patch_multimeshes[resource_name]
	if not GRASS_PATCH_MARKER_SHAPES.has(resource_name):
		if not _grass_patch_missing_shape_warned.has(resource_name):
			_grass_patch_missing_shape_warned[resource_name] = true
			push_warning("MicroCellRenderer: nessuna forma in GRASS_PATCH_MARKER_SHAPES per '%s' — marker a terra non disegnato." % resource_name)
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cluster_scale: float = GRASS_PATCH_CLUSTER_SCALE_BY_RESOURCE.get(resource_name, GRASS_PATCH_CLUSTER_SCALE)
	for leaf in GRASS_PATCH_MARKER_SHAPES[resource_name]:
		# Da spazio [0,1] relativo a un lato quadrato (convenzione dell'icona di magazzino) a
		# spazio centrato in (0,0) scalato per cluster_scale — stessa conversione già usata per
		# _ensure_egg_mesh sopra.
		var center := Vector2(float(leaf["cx"]) - 0.5, float(leaf["cy"]) - 0.5) * cluster_scale
		var radius := Vector2(float(leaf["rx"]), float(leaf["ry"])) * cluster_scale
		var leaf_rotation: float = float(leaf["rot"])
		st.set_color(leaf["color"])
		var center3 := Vector3(center.x, center.y, 0.0)
		for i in range(GRASS_PATCH_ELLIPSE_SEGMENTS):
			var angle_a: float = TAU * float(i) / float(GRASS_PATCH_ELLIPSE_SEGMENTS)
			var angle_b: float = TAU * float(i + 1) / float(GRASS_PATCH_ELLIPSE_SEGMENTS)
			var point_a: Vector2 = center + Vector2(cos(angle_a) * radius.x, sin(angle_a) * radius.y).rotated(leaf_rotation)
			var point_b: Vector2 = center + Vector2(cos(angle_b) * radius.x, sin(angle_b) * radius.y).rotated(leaf_rotation)
			st.add_vertex(center3)
			st.add_vertex(Vector3(point_a.x, point_a.y, 0.0))
			st.add_vertex(Vector3(point_b.x, point_b.y, 0.0))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = st.commit()
	multimesh.instance_count = 0
	_grass_patch_multimeshes[resource_name] = multimesh
	return multimesh


# Ricostruita da set_grass_patch_availability ogni volta che GameScene rinfresca la disponibilità
# — STESSO principio di _rebuild_egg_multimesh: un'istanza per lotto con disponibilità > 0,
# centrata sulla SUA microcella con una rotazione deterministica per varietà visiva. Vector2i
# tipizzato esplicitamente (non :=) perché `lot_pos` proviene da un ciclo su Dictionary.keys() non
# tipizzato.
func _rebuild_grass_patch_multimesh(resource_name: String) -> void:
	var multimesh := _get_grass_patch_multimesh(resource_name)
	if multimesh == null:
		return
	var availability: Dictionary = grass_patch_availability.get(resource_name, {})
	var half: float = CELL_SIZE / 2.0
	var transforms: Array = []
	for lot_pos in availability.keys():
		var available: int = int(availability[lot_pos])
		if available <= 0:
			continue
		var lot: Vector2i = lot_pos
		var ground: Vector2 = Vector2(lot.x * CELL_SIZE + half, lot.y * CELL_SIZE + half) + _lot_marker_offset(lot, resource_name)
		var seed_base: Vector2i = lot * 43 + Vector2i(13, 29)
		var jitter_rotation: float = lerp(-GRASS_PATCH_ROTATION_JITTER_MAX, GRASS_PATCH_ROTATION_JITTER_MAX, float(hash(seed_base + Vector2i(7, 3)) % 1000) / 1000.0)
		var lot_transform := Transform2D(jitter_rotation, Vector2.ZERO)
		lot_transform.origin = ground
		transforms.append(lot_transform)
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform_2d(i, transforms[i])


func _draw_grass_patch_positions() -> void:
	for multimesh: MultiMesh in _grass_patch_multimeshes.values():
		if multimesh.instance_count <= 0:
			continue
		draw_multimesh(multimesh, null)
		_debug_draw_primitive_count += 1


# Triangola a ventaglio (dal centro locale 0,0) un poligono convesso/quasi-convesso come quello
# degli stone blob, cuocendo color direttamente nei vertici — così una MultiMesh che riusa
# questa mesh non ha bisogno di colore per-istanza. Riusabile per qualunque forma a ventaglio
# futura (es. i cerchi unitari di tree/shrub/bacche saranno costruiti allo stesso modo).
static func _build_fan_mesh(points: PackedVector2Array, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)

	var center := Vector3.ZERO
	var count := points.size()
	for i in range(count):
		var a := Vector3(points[i].x, points[i].y, 0.0)
		var b := Vector3(points[(i + 1) % count].x, points[(i + 1) % count].y, 0.0)
		st.add_vertex(center)
		st.add_vertex(a)
		st.add_vertex(b)

	return st.commit()


# Guard economico prima di ogni draw_polygon/draw_colored_polygon con un array di punti
# generato dinamicamente: serve almeno 3 vertici, e ognuno deve avere coordinate finite (non
# NaN/Inf). Oggi nessuna chiamata del renderer può produrre un array del genere (i conteggi di
# vertici sono costanti fisse, i valori sempre derivati da lerp con estremi finiti), ma il
# controllo resta economico da avere come rete di sicurezza se quei presupposti cambiano.
static func _is_valid_polygon_points(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	for p in points:
		if not (is_finite(p.x) and is_finite(p.y)):
			return false
	return true


# Ordine di disegno preservato (dal più diffuso al più dominante, così TREE resta sopra):
# grass (draw_multiline_colors) -> shrub blobs -> bacche -> tree trunk -> tree canopy (tonda,
# non-conifer) -> tree canopy conifer (abete) -> dot frutto wild -> dot frutto domesticable
# (sopra la chioma, altrimenti invisibili; mai per le posizioni conifer, escluse a monte). Ogni
# gruppo è oggi al più UNA chiamata di disegno, indipendentemente da quante istanze contiene —
# i buffer (transform/colore per MultiMesh, punti/colori per grass) sono già pronti, ricalcolati
# nei setter (_rebuild_*) quando le posizioni cambiano, non qui.
func _draw_vegetation_positions() -> void:
	if _tree_stump_multimesh != null and _tree_stump_multimesh.instance_count > 0:
		draw_multimesh(_tree_stump_multimesh, null)
		_debug_draw_primitive_count += 1

	if _shrub_stump_multimesh != null and _shrub_stump_multimesh.instance_count > 0:
		draw_multimesh(_shrub_stump_multimesh, null)
		_debug_draw_primitive_count += 1

	if _dead_multimesh != null and _dead_multimesh.instance_count > 0:
		draw_multimesh(_dead_multimesh, null)
		_debug_draw_primitive_count += 1

	if _dead_tree_multimesh != null and _dead_tree_multimesh.instance_count > 0:
		draw_multimesh(_dead_tree_multimesh, null)
		_debug_draw_primitive_count += 1

	if not _grass_points.is_empty():
		# Spessore ridotto da 1.1 a 0.5: alla lunghezza attuale dei fili (vedi height in
		# _rebuild_grass_buffers, accorciata di recente) 1.1px li faceva leggere come tronconi
		# tozzi invece che fili sottili.
		draw_multiline_colors(_grass_points, _grass_colors, 0.5)
		_debug_draw_primitive_count += 1

	if _shrub_multimesh != null and _shrub_multimesh.instance_count > 0:
		draw_multimesh(_shrub_multimesh, null)
		_debug_draw_primitive_count += 1

	var fruit_in_season: bool = current_season in FRUITING_SEASONS

	if fruit_in_season and _berry_multimesh != null and _berry_multimesh.instance_count > 0:
		draw_multimesh(_berry_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_trunk_multimesh != null and _tree_trunk_multimesh.instance_count > 0:
		draw_multimesh(_tree_trunk_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_canopy_multimesh != null and _tree_canopy_multimesh.instance_count > 0:
		draw_multimesh(_tree_canopy_multimesh, null)
		_debug_draw_primitive_count += 1

	if _tree_conifer_canopy_multimesh != null and _tree_conifer_canopy_multimesh.instance_count > 0:
		draw_multimesh(_tree_conifer_canopy_multimesh, null)
		_debug_draw_primitive_count += 1

	if fruit_in_season and _tree_fruit_wild_multimesh != null and _tree_fruit_wild_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_wild_multimesh, null)
		_debug_draw_primitive_count += 1

	if fruit_in_season and _tree_fruit_domesticable_multimesh != null and _tree_fruit_domesticable_multimesh.instance_count > 0:
		draw_multimesh(_tree_fruit_domesticable_multimesh, null)
		_debug_draw_primitive_count += 1


const VEGETATION_CIRCLE_SEGMENTS: int = 12

var _tree_trunk_mesh: ArrayMesh
var _tree_canopy_mesh: ArrayMesh # bianca: il colore stagionale arriva per-istanza (use_colors)
var _tree_conifer_canopy_mesh: ArrayMesh # forma ad abete, colore fisso (mai stagionale)
var _tree_fruit_wild_mesh: ArrayMesh
var _tree_fruit_domesticable_mesh: ArrayMesh
var _shrub_blob_mesh: ArrayMesh # bianca: il colore per-lobo arriva per-istanza (use_colors)
var _berry_mesh: ArrayMesh
var _bramble_mesh: ArrayMesh # sagoma a stella per il taglio SHRUB, vedi _build_bramble_mesh
var _dead_mesh: ArrayMesh # cerchio generico, ora usato solo per SHRUB morto
var _dead_tree_mesh: ArrayMesh # riusa la forma quad del tronco, colore COLOR_DEAD invece di COLOR_TREE_TRUNK
var _vegetation_meshes_ready: bool = false

var _tree_trunk_multimesh: MultiMesh
var _tree_canopy_multimesh: MultiMesh
var _tree_conifer_canopy_multimesh: MultiMesh
var _tree_fruit_wild_multimesh: MultiMesh
var _tree_fruit_domesticable_multimesh: MultiMesh
var _shrub_multimesh: MultiMesh
var _berry_multimesh: MultiMesh
var _tree_stump_multimesh: MultiMesh # riusa _tree_trunk_mesh, istanza separata dal tronco vivo
var _shrub_stump_multimesh: MultiMesh # riusa _bramble_mesh
var _dead_multimesh: MultiMesh # SHRUB morto (cerchio generico)
var _dead_tree_multimesh: MultiMesh # TREE morto (tronco spoglio inclinato)


func _ensure_vegetation_meshes() -> void:
	if _vegetation_meshes_ready:
		return
	_vegetation_meshes_ready = true

	_tree_trunk_mesh = _build_quad_mesh(COLOR_TREE_TRUNK)
	_tree_canopy_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, Color.WHITE)
	_tree_conifer_canopy_mesh = _build_conifer_mesh(COLOR_TREE_CONIFER_CANOPY)
	_tree_fruit_wild_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_WILD)
	_tree_fruit_domesticable_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_TREE_FRUIT_DOMESTICABLE)
	_shrub_blob_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, Color.WHITE)
	_berry_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_SHRUB_BERRY)
	_bramble_mesh = _build_bramble_mesh(COLOR_BRAMBLE)
	_dead_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_DEAD)
	_dead_tree_mesh = _build_dead_tree_mesh(COLOR_TREE_TRUNK)


func _ensure_vegetation_multimeshes() -> void:
	if _tree_trunk_multimesh != null:
		return

	_tree_trunk_multimesh = _make_multimesh(_tree_trunk_mesh, false)
	_tree_canopy_multimesh = _make_multimesh(_tree_canopy_mesh, true)
	_tree_stump_multimesh = _make_multimesh(_tree_trunk_mesh, false)
	_shrub_stump_multimesh = _make_multimesh(_bramble_mesh, false)
	_dead_multimesh = _make_multimesh(_dead_mesh, false)
	_dead_tree_multimesh = _make_multimesh(_dead_tree_mesh, false)
	_tree_conifer_canopy_multimesh = _make_multimesh(_tree_conifer_canopy_mesh, false)
	_tree_fruit_wild_multimesh = _make_multimesh(_tree_fruit_wild_mesh, false)
	_tree_fruit_domesticable_multimesh = _make_multimesh(_tree_fruit_domesticable_mesh, false)
	_shrub_multimesh = _make_multimesh(_shrub_blob_mesh, true)
	_berry_multimesh = _make_multimesh(_berry_mesh, false)


static func _make_multimesh(mesh: ArrayMesh, use_colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = 0
	return mm


static func _apply_transforms(mm: MultiMesh, transforms: Array) -> void:
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform_2d(i, transforms[i])


# Transform completo di un ceppo TREE — riusa ESATTAMENTE la formula del tronco vivo
# (_compute_tree_visual, campo "ground": dipende solo da lotto/indice/quanti individui condividono
# il lotto, MAI da sottotipo/età, quindi resta valida anche per un individuo di cui sottotipo/età
# sono già stati dimenticati) per l'ancoraggio, ma altezza/larghezza scalate dal size_multiplier
# PERSISTITO al momento del taglio (vedi PlayerHarvestService.cut_individual) invece che da uno
# risolto ora (che sarebbe sempre il default neutro 1.0, avendo perso l'età) — TREE_STUMP_HEIGHT_
# RATIO tronca l'altezza a un ceppo invece di un tronco intero senza chioma. size_variation
# ricalcolato dalla sola chiave (hash puro di lotto+indice, indipendente da tutto il resto):
# nessun bisogno di persisterlo separatamente, è già deterministico.
func _build_tree_stump_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var ground: Vector2 = _compute_tree_visual(key, lot_counts)["ground"]
	var jitter_pos := Vector2i(key.x, key.y) + Vector2i(key.z * 619, key.z * 823)
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	var trunk_width: float = 1.6 * size_multiplier
	var stub_height: float = lerp(3.0, 4.0, size_variation) * size_multiplier * TREE_STUMP_HEIGHT_RATIO
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(trunk_width, stub_height))
	t.origin = Vector2(ground.x - trunk_width / 2.0, ground.y - stub_height)
	return t


# Transform completo di un cespuglio SHRUB tagliato (rovi) — stesso principio del tronco sopra,
# ma centrato su "center" (_compute_shrub_visual) e scalato in modo uniforme (nessuna forma
# direzionale come il tronco, la stella dei rovi è isotropa).
func _build_shrub_stump_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var center: Vector2 = _compute_shrub_visual(key, lot_counts)["center"]
	var radius: float = BRAMBLE_BASE_RADIUS * size_multiplier
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
	t.origin = center
	return t


# Transform di un marker "pianta morta" generico (cerchio, vedi commento su COLOR_DEAD) — usato
# oggi solo per SHRUB (TREE ha una sagoma dedicata, vedi _build_dead_tree_transform sotto). Stessa
# logica di ancoraggio ("center", vedi _compute_shrub_visual) e stesso scaling per size_multiplier
# persistito degli altri marker statici.
func _build_dead_marker_transform(object_type: GameTypes.WorldObjectType, key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var center: Vector2 = _compute_shrub_visual(key, lot_counts)["center"]
	var radius: float = DEAD_RADIUS_BY_TYPE.get(object_type, 1.5) * size_multiplier
	var t := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
	t.origin = center
	return t


# Transform di un albero morto in piedi (mortalità naturale, TREE) — richiesta estetica esplicita
# dell'utente: non un cerchio generico né una linea dritta (si confondeva con un filo d'erba), ma
# una sagoma SPEZZATA (vedi _build_dead_tree_mesh/DEAD_TREE_BEND_POINTS) color tronco, più
# allungata del tronco vivo e un po' storta. A differenza del ceppo da taglio
# (_build_tree_stump_transform, troncato in altezza a TREE_STUMP_HEIGHT_RATIO — lì l'albero è
# stato abbattuto), qui l'albero è morto ma ancora in piedi, spoglio (nessuna chioma).
# L'inclinazione ruota attorno alla base (il punto "ground", coordinate locali (0.5, 1.0) nella
# mesh — vedi DEAD_TREE_BEND_POINTS) componendo gli assi x/y ruotati direttamente invece di usare
# .rotated() sul Transform2D già traslato (che ruoterebbe attorno all'origine sbagliata).
# size_variation e tilt derivano da due hash indipendenti sulla stessa chiave (salt diversi) così
# le due variazioni non correlano tra loro.
func _build_dead_tree_transform(key: Vector3i, size_multiplier: float, lot_counts: Dictionary) -> Transform2D:
	var ground: Vector2 = _compute_tree_visual(key, lot_counts)["ground"]
	var jitter_pos := Vector2i(key.x, key.y) + Vector2i(key.z * 619, key.z * 823)
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	var tilt_hash: float = float(hash(jitter_pos * 7 + Vector2i(311, 947)) % 1000) / 1000.0

	var trunk_width: float = DEAD_TREE_TRUNK_WIDTH_RATIO * size_multiplier
	# Più allungato del tronco vivo (che usa lerp(3.0, 4.0)) — la spezzata letta da lontano deve
	# leggersi come un albero morto in piedi, non un filo d'erba alto quanto un tronco normale.
	var trunk_height: float = lerp(4.5, 6.5, size_variation) * size_multiplier
	var tilt_angle: float = deg_to_rad(lerp(-DEAD_TREE_MAX_TILT_DEGREES, DEAD_TREE_MAX_TILT_DEGREES, tilt_hash))

	var x_axis := Vector2(cos(tilt_angle), sin(tilt_angle)) * trunk_width
	var y_axis := Vector2(-sin(tilt_angle), cos(tilt_angle)) * trunk_height
	var t := Transform2D(x_axis, y_axis, Vector2.ZERO)
	# Il quad unitario ha il piede (bottom-center, coordinate locali (0.5, 1.0)) su questo pivot:
	# sottraendolo dall'origine si ottiene che la base del tronco ruoti attorno a `ground`, non il
	# suo angolo in alto a sinistra.
	t.origin = ground - (x_axis * 0.5 + y_axis)
	return t


# Ricalcola i marker statici di cut_positions/dead_positions — chiamata dai rispettivi setter,
# indipendente dal rebuild dei blob vivi (vegetation_positions non li contiene, vedi
# IndividualVegetationService._is_blocked), ma ne condivide la stessa geometria di ancoraggio
# (vedi le tre funzioni sopra). Ogni entry porta già "size_multiplier" (vedi
# IndividualVegetationService.get_cut_positions/get_dead_positions) — nessun bisogno di risolverlo
# qui, viene passato così com'è.
func _rebuild_cut_dead_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var tree_stump_transforms: Array = []
	var shrub_stump_transforms: Array = []
	for object_type in cut_positions:
		var lot_counts := _lot_extent_counts(object_type)
		for entry in cut_positions[object_type]:
			var key: Vector3i = entry["key"]
			var size_multiplier: float = entry["size_multiplier"]
			if object_type == GameTypes.WorldObjectType.TREE:
				tree_stump_transforms.append(_build_tree_stump_transform(key, size_multiplier, lot_counts))
			else:
				shrub_stump_transforms.append(_build_shrub_stump_transform(key, size_multiplier, lot_counts))
	_apply_transforms(_tree_stump_multimesh, tree_stump_transforms)
	_apply_transforms(_shrub_stump_multimesh, shrub_stump_transforms)

	var dead_transforms: Array = []
	var dead_tree_transforms: Array = []
	for object_type in dead_positions:
		var lot_counts := _lot_extent_counts(object_type)
		for entry in dead_positions[object_type]:
			if object_type == GameTypes.WorldObjectType.TREE:
				dead_tree_transforms.append(_build_dead_tree_transform(entry["key"], entry["size_multiplier"], lot_counts))
			else:
				dead_transforms.append(_build_dead_marker_transform(object_type, entry["key"], entry["size_multiplier"], lot_counts))
	_apply_transforms(_dead_multimesh, dead_transforms)
	_apply_transforms(_dead_tree_multimesh, dead_tree_transforms)


# Quanti individui (vivi O bloccati da un'eccezione di taglio/morte) condividono ciascun lotto —
# a differenza di _count_individuals_per_lot su un solo Array, questa combina vegetation_positions
# (vivi, Array[Vector3i]) con le sole CHIAVI di cut_positions/dead_positions (bloccati, Array
# [Dictionary] — vedi IndividualVegetationService.get_cut_positions/get_dead_positions) PRIMA di
# contare, così local_count non scende mai solo perché un individuo è stato tagliato/è morto:
# esattamente la stessa "estensione nota" calcolata da
# IndividualVegetationService._count_known_extent_by_lot lato generazione — le due devono restare
# in accordo, altrimenti un lotto affollato apparirebbe diverso da quanto la generazione ha
# davvero deciso. SENZA questo, tagliare un individuo cambierebbe local_count per i suoi vicini di
# lotto ancora vivi, e sia il disk-offset di TREE sia l'offset_range di SHRUB dipendono da
# local_count — i vicini si sposterebbero pur non avendo perso la propria identità.
func _lot_extent_counts(object_type: GameTypes.WorldObjectType) -> Dictionary:
	var combined: Array = vegetation_positions.get(object_type, []).duplicate()
	for entry in cut_positions.get(object_type, []):
		combined.append(entry["key"])
	for entry in dead_positions.get(object_type, []):
		combined.append(entry["key"])
	return _count_individuals_per_lot(combined)


# Quadrato unitario ancorato in alto a sinistra (0,0)-(1,1): scalato per (trunk_width,
# trunk_height) e traslato in (trunk_x, trunk_y) riproduce esattamente il vecchio
# Rect2(trunk_x, trunk_y, trunk_width, trunk_height).
static func _build_quad_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(1, 1, 0)
	var d := Vector3(0, 1, 0)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
	return st.commit()


# Sagoma SPEZZATA per l'albero morto in piedi (vedi DEAD_TREE_BEND_POINTS/_build_dead_tree_
# transform) — non un quad pieno come il tronco vivo: una linea spessa che segue DEAD_TREE_BEND_
# POINTS (base -> piega -> cima), costruita segmento per segmento da _add_thick_line_segment.
# Stessa convenzione di spazio unitario (0..1) del quad del tronco vivo, cosicché la stessa
# formula di transform (basi x/y scalate per trunk_width/trunk_height, origine ancorata al punto
# base) resti valida senza modifiche.
static func _build_dead_tree_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	for i in range(DEAD_TREE_BEND_POINTS.size() - 1):
		_add_thick_line_segment(st, DEAD_TREE_BEND_POINTS[i], DEAD_TREE_BEND_POINTS[i + 1], DEAD_TREE_LINE_HALF_THICKNESS)
	return st.commit()


# Aggiunge un segmento spesso (due triangoli, spessore costante perpendicolare al segmento) tra
# due punti — usato da _build_dead_tree_mesh per costruire la spezzata senza dover ricorrere a
# un'unica forma piena rettangolare come il tronco vivo.
static func _add_thick_line_segment(st: SurfaceTool, from: Vector2, to: Vector2, half_thickness: float) -> void:
	var direction: Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-direction.y, direction.x) * half_thickness
	var a := Vector3(from.x + perp.x, from.y + perp.y, 0)
	var b := Vector3(to.x + perp.x, to.y + perp.y, 0)
	var c := Vector3(to.x - perp.x, to.y - perp.y, 0)
	var d := Vector3(from.x - perp.x, from.y - perp.y, 0)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# Cerchio unitario (raggio 1, centrato all'origine): scalato per il raggio reale per-istanza
# riproduce esattamente il vecchio draw_circle(center, radius, color).
static func _build_circle_mesh(segments: int, color: Color) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)))
	return _build_fan_mesh(points, color)


# Punti (spazio unitario, origine (0,0) = canopy_center prima dello scale per canopy_radius)
# della sagoma conifer — condivisi tra _build_conifer_mesh (il blob disegnato) e
# _draw_conifer_selection_outline (il contorno di selezione), così le due forme non possono mai
# disallinearsi. Array normale (non PackedVector2Array: il parser non accetta un
# PackedVector2Array come espressione costante) — convertito dove serve un PackedVector2Array
# vero (vedi _build_conifer_mesh).
const CONIFER_SHAPE_POINTS := [
	Vector2(0.0, -1.3),
	Vector2(-1.0, 0.9),
	Vector2(1.0, 0.9),
]

# Sagoma stilizzata ad abete/conifera (triangolo isoscele, apice in alto): più alta e stretta
# del cerchio unitario (apice a -1.3 invece di -1.0) per leggersi come "sempreverde a punta"
# anche alla scala minuscola di una singola microcella, distinguendosi a colpo d'occhio dal
# blob tondo usato per gli altri sottotipi. Origine (0,0) del ventaglio comunque interna al
# triangolo (centroide ~ (0, 0.17)), quindi la triangolazione di _build_fan_mesh resta piena.
static func _build_conifer_mesh(color: Color) -> ArrayMesh:
	return _build_fan_mesh(PackedVector2Array(CONIFER_SHAPE_POINTS), color)


# Sagoma a stella (raggio esterno/interno alternati, BRAMBLE_POINT_COUNT punte) invece del blob
# tondo dei lobi vivi — legge come un cespuglio raso, intricato di rametti spinosi, a colpo
# d'occhio distinguibile dal cerchio pieno usato ovunque altrove in questo file. Stessa
# triangolazione a ventaglio di _build_circle_mesh/_build_conifer_mesh, solo con raggio non
# costante lungo il perimetro.
static func _build_bramble_mesh(color: Color) -> ArrayMesh:
	var points := PackedVector2Array()
	var point_total: int = BRAMBLE_POINT_COUNT * 2
	for i in range(point_total):
		var angle: float = (float(i) / float(point_total)) * TAU
		var radius: float = 1.0 if i % 2 == 0 else BRAMBLE_INNER_RADIUS_RATIO
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return _build_fan_mesh(points, color)


# Anno di nascita virtuale per individuo TREE — Dictionary[Vector3i, int] di PROPRIETÀ del
# chiamante (MacroCellState.tree_virtual_birth_year, vedi set_tree_age_params), non del renderer:
# passato per riferimento (i Dictionary in GDScript lo sono sempre). Il congelamento vero e
# proprio avviene in IndividualVegetationService (alla nascita dell'individuo, mai più qui) —
# questo renderer lo legge soltanto, ma essendo lo STESSO oggetto di MacroCellState il
# congelamento sopravvive comunque a save/load e alla ricreazione dell'istanza renderer nello
# streaming multi-cella. Tenuto separato da shrub_birth_year_store: una stessa cella griglia può
# ospitare SHRUB in un anno e TREE in un altro (successione ecologica), le due mappe non vanno
# mai confuse.
var tree_birth_year_store: Dictionary = {}

# Calcolo COMPLETO di un individuo TREE — geometria a schermo, a partire da un sottotipo/età già
# NOTI (mai più decisi qui, vedi IndividualVegetationService: il sottotipo è congelato una sola
# volta alla nascita dell'individuo in tree_individual_subtype, l'età in tree_birth_year_store) —
# riusato sia da _rebuild_tree_multimeshes (che ne ricava i Transform2D per il MultiMesh) sia
# dalle query pubbliche get_individual_screen_position/get_individual_info (click-detection, vedi
# VegetationSelectorController): mai una seconda copia della formula.
func _compute_tree_visual(individual_key: Vector3i, lot_counts: Dictionary) -> Dictionary:
	var pos := Vector2i(individual_key.x, individual_key.y)
	var index: int = individual_key.z
	# Salt indipendente da qualunque altro hash del renderer: il jitter visivo di un individuo
	# entro il footprint 10x10px del lotto non deve dipendere dagli stessi bit hash del suo
	# sottotipo, altrimenti un dato offset visivo finirebbe sistematicamente correlato ad esso.
	var jitter_pos := pos + Vector2i(index * 619, index * 823)

	# Letto da tree_individual_subtype (congelato da IndividualVegetationService alla nascita
	# dell'individuo) invece di ritestato ogni volta contro un rapporto corrente — un individuo non
	# "cambia specie" se le proporzioni della cella si spostano nel frattempo. "wood_only" è solo un
	# fallback difensivo (non dovrebbe mai servire: un individuo in vegetation_positions ha sempre
	# già un sottotipo congelato).
	var subtype_name: String = tree_individual_subtype.get(individual_key, "wood_only")
	var is_conifer: bool = subtype_name == "conifer"
	var is_domesticable: bool = subtype_name == "domesticable_fruit"
	var is_fruit_bearing: bool = is_domesticable or subtype_name == "wild_fruit"

	var resolved := _resolve_age_band_and_size(individual_key, subtype_name, tree_age_params, tree_birth_year_store, tree_current_year)
	var age_band: GameTypes.AgeBand = resolved["age_band"]
	var age_size_multiplier: float = resolved["size_multiplier"]

	# Due scale indipendenti e moltiplicative, mai in conflitto: age_size_multiplier (sopra) segna
	# la fascia d'età, density_scale segna quanto questo lotto è affollato — vedi
	# _resolve_density_scale_and_offset_range per la formula. A local_count=1 (il caso comune, un
	# solo individuo per lotto) density_scale=1.0: comportamento visivo IDENTICO a prima
	# dell'introduzione degli individui multipli per lotto.
	var local_count: int = int(lot_counts.get(pos, 1))
	var density_scale: float = float(_resolve_density_scale_and_offset_range(local_count)["density_scale"])
	var size_multiplier: float = age_size_multiplier * density_scale

	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0
	var size_variation: float = float(hash(jitter_pos) % 1000) / 1000.0
	# Wobble organico piccolo, stessa ampiezza di BASE_OFFSET_RANGE (il range pre-esistente quando
	# ogni lotto ospitava un solo individuo) — dà varietà, ma la SEPARAZIONE vera tra più individui
	# è garantita dal termine deterministico sotto (_fibonacci_disk_offset), non da questo wobble
	# indipendente per individuo (vedi il commento lì sul perché per TREE non basta allargare un
	# range casuale).
	var offset_variation: float = float(hash(jitter_pos * 7 + Vector2i(3, 11)) % 1000) / 1000.0
	var vertical_variation: float = float(hash(jitter_pos * 13 + Vector2i(29, 5)) % 1000) / 1000.0
	var wobble := Vector2(
		lerp(-BASE_OFFSET_RANGE, BASE_OFFSET_RANGE, offset_variation),
		lerp(-BASE_OFFSET_RANGE, BASE_OFFSET_RANGE, vertical_variation)
	)
	var disk_offset := _fibonacci_disk_offset(index, local_count, MAX_OFFSET_RANGE)
	# `ground` = punto in cui QUESTO individuo "poggia", disperso su tutto il footprint 10x10px via
	# disk_offset/wobble esattamente come center per SHRUB (base + half + offset).
	var ground := Vector2(
		base.x + half + disk_offset.x + wobble.x,
		base.y + half + disk_offset.y + wobble.y
	)

	var trunk_width: float = 1.6 * size_multiplier
	var trunk_height: float = lerp(3.0, 4.0, size_variation) * size_multiplier
	var trunk_y: float = ground.y - trunk_height
	var canopy_radius: float = lerp(2.8, 3.8, size_variation) * size_multiplier
	var canopy_center := Vector2(ground.x, trunk_y - canopy_radius * 0.6)

	return {
		"is_conifer": is_conifer, "is_fruit_bearing": is_fruit_bearing, "is_domesticable": is_domesticable,
		"subtype_name": subtype_name, "age_band": age_band, "size_multiplier": size_multiplier,
		"years_lived": tree_current_year - int(tree_birth_year_store.get(individual_key, tree_current_year)),
		"jitter_pos": jitter_pos, "ground": ground,
		"trunk_width": trunk_width, "trunk_height": trunk_height, "trunk_y": trunk_y,
		"canopy_center": canopy_center, "canopy_radius": canopy_radius,
	}


# Albero stilizzato: tronco (rettangolo) + chioma (cerchio) sopra — vedi _compute_tree_visual per
# tutta la geometria/identità di un individuo, qui resta solo la costruzione dei Transform2D per
# il MultiMesh e lo smistamento nei buffer giusti (conifer vs chioma tonda, dot frutto
# wild/domesticable).
func _rebuild_tree_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.TREE, []) # Array[Vector3i]: lotto x,y + indice individuo
	var trunk_transforms: Array = []
	var canopy_transforms: Array = []
	var canopy_colors: Array = []
	var conifer_canopy_transforms: Array = []
	var wild_fruit_transforms: Array = []
	var domesticable_fruit_transforms: Array = []

	var deciduous_canopy_color: Color = TREE_CANOPY_PALETTE_BY_SEASON.get(current_season, VEGETATION_COLORS[GameTypes.WorldObjectType.TREE])

	# Rimontaggio a gruppi (2026-10-04, richiesta utente — vedi _rebuild_tree_multimeshes_grouped): solo col metodo a
	# buffer e con una disposizione dei gruppi appena passata da GameScene (set_tree_group_layout) e coerente con
	# l'elenco corrente. La disposizione vale per UNA ricostruzione: qualunque altra ricostruzione usa il giro di sempre.
	var group_layout_ok: bool = _tree_group_layout_fresh and _tree_group_starts.size() >= 1 \
		and int(_tree_group_starts[0]) == 0 and int(_tree_group_starts[_tree_group_starts.size() - 1]) == positions.size()
	_tree_group_layout_fresh = false
	if group_layout_ok and _multimesh_buffer_layout_ok():
		_rebuild_tree_multimeshes_grouped(positions, deciduous_canopy_color)
		return

	# Estensione nota (vivi+bloccati), non il solo conteggio dei vivi — vedi _lot_extent_counts:
	# altrimenti tagliare un individuo cambierebbe il local_count (quindi il disk-offset) dei suoi
	# vicini di lotto ancora vivi, spostandoli pur non avendo perso la propria identità.
	# Misure (2026-10-03, richiesta utente — solo diagnostica, nessun effetto): tree_lot_counts, tree_loop, tree_apply, in
	# last_batch_timings_ms (tree_append tolta il 2026-10-04: leggeva l'orologio per ogni pianta e gonfiava i tempi).
	var measure_start_usec := Time.get_ticks_usec()
	var lot_counts: Dictionary = _lot_extent_counts(GameTypes.WorldObjectType.TREE)
	last_batch_timings_ms["tree_lot_counts"] = (Time.get_ticks_usec() - measure_start_usec) / 1000.0
	_tree_fruit_entries.clear()

	# Geometria in memoria (2026-10-03, passo B — vedi _tree_geometry_cache): ricalcolata solo per gli individui nuovi o
	# con una firma diversa; il colore della chioma (stagione) e il test dei frutti (rapporto del lotto) si applicano
	# qui, a ogni ricostruzione, come prima.
	_check_geometry_cache_globals()
	# Rimontaggio a blocchi di dati (2026-10-03, richiesta utente — passo 2): con il formato del buffer verificato
	# (_multimesh_buffer_layout_ok) i dati già impacchettati di ogni individuo si concatenano e si assegnano in un colpo
	# a MultiMesh.buffer; altrimenti il metodo di prima, un'istanza alla volta. Stesso ordine delle istanze in entrambi.
	var use_buffer := _multimesh_buffer_layout_ok()
	var trunk_buffer := PackedFloat32Array()
	var canopy_buffer := PackedFloat32Array()
	var conifer_buffer := PackedFloat32Array()
	var wild_fruit_buffer := PackedFloat32Array()
	var domesticable_fruit_buffer := PackedFloat32Array()
	var computed_count := 0
	var reused_count := 0
	var loop_start_usec := Time.get_ticks_usec()
	# Campo che una geometria valida per il metodo in uso deve avere: dati impacchettati (buffer) o trasformazioni.
	var required_field := "trunk_packed" if use_buffer else "trunk_transform"
	for individual_key in positions:
		var signature := _tree_geometry_signature(individual_key, lot_counts)
		var geometry: Dictionary = _tree_geometry_cache.get(individual_key, {})
		# Dati del metodo in uso mancanti = geometria non valida: si ricalcola (ripiego per il singolo individuo).
		if geometry.is_empty() or geometry["signature"] != signature or not geometry.has(required_field):
			geometry = _compute_tree_geometry(individual_key, lot_counts, use_buffer)
			geometry["signature"] = signature
			_tree_geometry_cache[individual_key] = geometry
			computed_count += 1
		else:
			reused_count += 1
		if use_buffer:
			trunk_buffer.append_array(geometry["trunk_packed"])
		else:
			trunk_transforms.append(geometry["trunk_transform"])
		# Ramo esclusivo: un individuo è O conifer (chioma ad abete, sempre verde piena, MAI frutti) O uno degli altri
		# sottotipi (chioma tonda, colore per stagione, idonea al test frutta).
		if geometry["is_conifer"]:
			if use_buffer:
				conifer_buffer.append_array(geometry["canopy_packed"])
			else:
				conifer_canopy_transforms.append(geometry["canopy_transform"])
			continue
		if use_buffer:
			canopy_buffer.append_array(_tree_canopy_packed_with_color(geometry, deciduous_canopy_color))
		else:
			canopy_transforms.append(geometry["canopy_transform"])
			canopy_colors.append(deciduous_canopy_color)
		# "fruit" (domesticable_fruit) o "acorn" (wild_fruit); "" = nessun frutto (non fruttifero o YOUNG). Stesso gate
		# hash-vs-ratio di sempre (_fruit_stock_shows).
		var fruit_resource: String = geometry["fruit_resource"]
		if fruit_resource == "":
			continue
		_tree_fruit_entries.append({
			"key": individual_key, "lot": Vector2i(individual_key.x, individual_key.y), "jitter_pos": geometry["jitter_pos"],
			"canopy_center": geometry["canopy_center"], "canopy_radius": geometry["canopy_radius"],
			"resource_name": fruit_resource,
		})
		if _fruit_stock_shows(fruit_resource, individual_key, geometry["jitter_pos"]):
			if fruit_resource == "fruit":
				if use_buffer:
					domesticable_fruit_buffer.append_array(geometry["fruit_packed"])
				else:
					domesticable_fruit_transforms.append_array(geometry["fruit_transforms"])
			else:
				if use_buffer:
					wild_fruit_buffer.append_array(geometry["fruit_packed"])
				else:
					wild_fruit_transforms.append_array(geometry["fruit_transforms"])
	last_geometry_stats["tree"] = {"computed": computed_count, "reused": reused_count}
	last_batch_timings_ms["tree_loop"] = (Time.get_ticks_usec() - loop_start_usec) / 1000.0

	measure_start_usec = Time.get_ticks_usec()
	if use_buffer:
		_apply_buffer(_tree_trunk_multimesh, trunk_buffer, BUFFER_STRIDE_TRANSFORM)
		_apply_buffer(_tree_canopy_multimesh, canopy_buffer, BUFFER_STRIDE_TRANSFORM_COLOR)
		_apply_buffer(_tree_conifer_canopy_multimesh, conifer_buffer, BUFFER_STRIDE_TRANSFORM)
		_apply_buffer(_tree_fruit_wild_multimesh, wild_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
		_apply_buffer(_tree_fruit_domesticable_multimesh, domesticable_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
	else:
		_apply_transforms(_tree_trunk_multimesh, trunk_transforms)
		_apply_transforms(_tree_canopy_multimesh, canopy_transforms)
		for i in range(canopy_colors.size()):
			_tree_canopy_multimesh.set_instance_color(i, canopy_colors[i])
		_apply_transforms(_tree_conifer_canopy_multimesh, conifer_canopy_transforms)
		_apply_transforms(_tree_fruit_wild_multimesh, wild_fruit_transforms)
		_apply_transforms(_tree_fruit_domesticable_multimesh, domesticable_fruit_transforms)
	last_batch_timings_ms["tree_apply"] = (Time.get_ticks_usec() - measure_start_usec) / 1000.0
	_tree_fruit_entries_valid = true


# RIMONTAGGIO A GRUPPI DEGLI ALBERI (2026-10-04, richiesta utente). L'elenco NON filtrato degli alberi (posizioni della
# cella, nell'ordine di sempre) è diviso in gruppi consecutivi di TREE_GROUP_SIZE; l'elenco filtrato per la nebbia, che
# ne conserva l'ordine, è quindi la concatenazione delle "fette visibili" dei gruppi. GameScene calcola dove comincia la
# fetta di ogni gruppo nello stesso giro del filtro e la passa qui (set_tree_group_layout). Per ogni gruppo si
# conservano tronchi, chiome (col colore), chiome conifer, voci dei frutti e puntini dei frutti già concatenati; a ogni
# rimontaggio si rifanno solo i gruppi da rifare e si concatenano i blocchi nell'ordine dei gruppi: stesso ordine
# delle istanze del giro di sempre.
#
# Un gruppo si rifà se la sua fetta visibile è diversa da quella conservata (confronto nativo di array). Si rifanno
# TUTTI se cambia anche uno solo di: versione delle posizioni (rigenerazione), anno, parametri d'età, colore stagionale
# delle chiome, ceppi o piante morte degli alberi (contano nel numero di individui del lotto), numero di gruppi; se il
# motivo del ridisegno non è movimento/nebbia (allow_reuse false); se la memoria della geometria viene svuotata.
# I puntini dei frutti di un gruppo si rifanno anche quando cambiano i rapporti dei frutti per lotto (ghiande, frutta).
const TREE_GROUP_SIZE := 256

var _tree_group_layout_version: int = -1
var _tree_group_starts: Array = []
var _tree_group_allow_reuse: bool = false
var _tree_group_layout_fresh: bool = false
var _tree_groups: Array = []
var _tree_groups_globals: Array = []
var _tree_groups_fruit_stamp: Array = []
# Diagnostica: {"rebuilt": int, "reused": int} dell'ultimo rimontaggio a gruppi (vuoto = giro di sempre).
var last_tree_group_stats: Dictionary = {}


# Da GameScene prima di set_vegetation_positions: `layout_version` sale a ogni rigenerazione delle posizioni, `starts`
# ha un inizio per gruppo più la fine (indici nell'elenco filtrato), `allow_reuse` false = rifai tutti i gruppi.
func set_tree_group_layout(layout_version: int, starts: Array, allow_reuse: bool) -> void:
	_tree_group_layout_version = layout_version
	_tree_group_starts = starts
	_tree_group_allow_reuse = allow_reuse
	_tree_group_layout_fresh = true


func _rebuild_tree_multimeshes_grouped(positions: Array, deciduous_canopy_color: Color) -> void:
	_check_geometry_cache_globals()
	var group_count: int = _tree_group_starts.size() - 1
	var globals: Array = [
		_tree_group_layout_version, tree_current_year, tree_age_params.hash(), deciduous_canopy_color,
		cut_positions.get(GameTypes.WorldObjectType.TREE, []), dead_positions.get(GameTypes.WorldObjectType.TREE, []),
		group_count,
	]
	if not _tree_group_allow_reuse or globals != _tree_groups_globals or _tree_groups.size() != group_count:
		_tree_groups.clear()
		_tree_groups.resize(group_count)
		_tree_groups_globals = globals
		_tree_groups_fruit_stamp = []
	var fruit_stamp: Array = [
		fruit_stock_available_ratio_by_lot.get("acorn", {}), fruit_stock_available_ratio_by_lot.get("fruit", {}),
	]
	var fruit_changed: bool = fruit_stamp != _tree_groups_fruit_stamp
	_tree_groups_fruit_stamp = fruit_stamp

	var loop_start_usec := Time.get_ticks_usec()
	var lot_counts: Variant = null
	var trunk_buffer := PackedFloat32Array()
	var canopy_buffer := PackedFloat32Array()
	var conifer_buffer := PackedFloat32Array()
	var wild_fruit_buffer := PackedFloat32Array()
	var domesticable_fruit_buffer := PackedFloat32Array()
	_tree_fruit_entries.clear()
	var rebuilt_count := 0
	var reused_count := 0
	var computed_individuals := 0
	var reused_individuals := 0
	for group_index in range(group_count):
		var members: Array = positions.slice(int(_tree_group_starts[group_index]), int(_tree_group_starts[group_index + 1]))
		var group: Variant = _tree_groups[group_index]
		if group == null or group["members"] != members:
			if lot_counts == null:
				var lot_counts_start_usec := Time.get_ticks_usec()
				lot_counts = _lot_extent_counts(GameTypes.WorldObjectType.TREE)
				last_batch_timings_ms["tree_lot_counts"] = (Time.get_ticks_usec() - lot_counts_start_usec) / 1000.0
			group = _build_tree_group(members, lot_counts, deciduous_canopy_color)
			_tree_groups[group_index] = group
			rebuilt_count += 1
			computed_individuals += int(group["computed"])
			reused_individuals += int(group["reused"])
		else:
			reused_count += 1
			if fruit_changed:
				_refresh_tree_group_fruit(group)
		trunk_buffer.append_array(group["trunk"])
		canopy_buffer.append_array(group["canopy"])
		conifer_buffer.append_array(group["conifer"])
		wild_fruit_buffer.append_array(group["wild_fruit"])
		domesticable_fruit_buffer.append_array(group["domesticable_fruit"])
		_tree_fruit_entries.append_array(group["fruit_entries"])
	last_batch_timings_ms["tree_loop"] = (Time.get_ticks_usec() - loop_start_usec) / 1000.0
	last_geometry_stats["tree"] = {"computed": computed_individuals, "reused": reused_individuals}
	last_tree_group_stats = {"rebuilt": rebuilt_count, "reused": reused_count}

	var apply_start_usec := Time.get_ticks_usec()
	_apply_buffer(_tree_trunk_multimesh, trunk_buffer, BUFFER_STRIDE_TRANSFORM)
	_apply_buffer(_tree_canopy_multimesh, canopy_buffer, BUFFER_STRIDE_TRANSFORM_COLOR)
	_apply_buffer(_tree_conifer_canopy_multimesh, conifer_buffer, BUFFER_STRIDE_TRANSFORM)
	_apply_buffer(_tree_fruit_wild_multimesh, wild_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
	_apply_buffer(_tree_fruit_domesticable_multimesh, domesticable_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
	last_batch_timings_ms["tree_apply"] = (Time.get_ticks_usec() - apply_start_usec) / 1000.0
	_tree_fruit_entries_valid = true


# Un gruppo da zero: lo stesso corpo del giro di sempre (_rebuild_tree_multimeshes, ramo a buffer) sui soli `members`,
# con la geometria in memoria del passo B.
func _build_tree_group(members: Array, lot_counts: Dictionary, deciduous_canopy_color: Color) -> Dictionary:
	var trunk := PackedFloat32Array()
	var canopy := PackedFloat32Array()
	var conifer := PackedFloat32Array()
	var fruit_entries: Array = []
	var computed := 0
	var reused := 0
	for individual_key in members:
		var signature := _tree_geometry_signature(individual_key, lot_counts)
		var geometry: Dictionary = _tree_geometry_cache.get(individual_key, {})
		if geometry.is_empty() or geometry["signature"] != signature or not geometry.has("trunk_packed"):
			geometry = _compute_tree_geometry(individual_key, lot_counts, true)
			geometry["signature"] = signature
			_tree_geometry_cache[individual_key] = geometry
			computed += 1
		else:
			reused += 1
		trunk.append_array(geometry["trunk_packed"])
		if geometry["is_conifer"]:
			conifer.append_array(geometry["canopy_packed"])
			continue
		canopy.append_array(_tree_canopy_packed_with_color(geometry, deciduous_canopy_color))
		var fruit_resource: String = geometry["fruit_resource"]
		if fruit_resource == "":
			continue
		fruit_entries.append({
			"key": individual_key, "lot": Vector2i(individual_key.x, individual_key.y), "jitter_pos": geometry["jitter_pos"],
			"canopy_center": geometry["canopy_center"], "canopy_radius": geometry["canopy_radius"],
			"resource_name": fruit_resource,
		})
	var group := {
		"members": members, "trunk": trunk, "canopy": canopy, "conifer": conifer, "fruit_entries": fruit_entries,
		"computed": computed, "reused": reused,
	}
	_refresh_tree_group_fruit(group)
	return group


# Puntini dei frutti di un gruppo dalle sue voci: stesso test (_fruit_stock_shows) e stessi dati (_cached_tree_fruit_packed)
# del giro di sempre, nell'ordine delle voci.
func _refresh_tree_group_fruit(group: Dictionary) -> void:
	var wild := PackedFloat32Array()
	var domesticable := PackedFloat32Array()
	for entry in group["fruit_entries"]:
		var fruit_resource: String = entry["resource_name"]
		if not _fruit_stock_shows(fruit_resource, entry["key"], entry["jitter_pos"]):
			continue
		if fruit_resource == "fruit":
			domesticable.append_array(_cached_tree_fruit_packed(entry))
		else:
			wild.append_array(_cached_tree_fruit_packed(entry))
	group["wild_fruit"] = wild
	group["domesticable_fruit"] = domesticable


# Chioma decidua impacchettata con il colore della stagione (12 valori: trasformazione + colore). Rifatta solo quando il
# colore cambia (una volta per stagione per individuo), poi tenuta nella geometria.
func _tree_canopy_packed_with_color(geometry: Dictionary, color: Color) -> PackedFloat32Array:
	if not geometry.has("canopy_packed_color") or geometry["canopy_packed_color"] != color:
		var colored: PackedFloat32Array = (geometry["canopy_packed"] as PackedFloat32Array).duplicate()
		colored.append_array(PackedFloat32Array([color.r, color.g, color.b, color.a]))
		geometry["canopy_packed_colored"] = colored
		geometry["canopy_packed_color"] = color
	return geometry["canopy_packed_colored"]


# FORMATO DEL BUFFER DEI MULTIMESH 2D (2026-10-03, passo 2). Per istanza, in ordine: trasformazione 2D in 8 valori
# [x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y] (due righe di una matrice 2x4), poi il colore in 4 valori [r, g, b, a]
# se use_colors; nessun dato personalizzato (use_custom_data non è mai attivo qui). È la disposizione del motore
# (RenderingServer.multimesh_set_buffer); non potendola leggere dai sorgenti, la si VERIFICA in gioco alla prima
# ricostruzione (_multimesh_buffer_layout_ok): se non corrisponde, tutti i rimontaggi usano il metodo di prima.
const BUFFER_STRIDE_TRANSFORM := 8
const BUFFER_STRIDE_TRANSFORM_COLOR := 12
# 0 = non ancora verificato, 1 = formato confermato, -1 = formato diverso (metodo di prima ovunque).
static var _buffer_layout_state: int = 0


static func _packed_transform_2d(transform: Transform2D) -> PackedFloat32Array:
	return PackedFloat32Array([
		transform.x.x, transform.y.x, 0.0, transform.origin.x,
		transform.x.y, transform.y.y, 0.0, transform.origin.y,
	])


static func _packed_transforms(transforms: Array) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	for transform in transforms:
		packed.append_array(_packed_transform_2d(transform))
	return packed


static func _packed_transforms_with_colors(transforms: Array, colors: Array) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	for i in range(transforms.size()):
		packed.append_array(_packed_transform_2d(transforms[i]))
		var color: Color = colors[i]
		packed.append_array(PackedFloat32Array([color.r, color.g, color.b, color.a]))
	return packed


# "sì" / "no" / "non verificato" — stato della verifica del formato, per il log di GameScene.
static func buffer_mode_text() -> String:
	if _buffer_layout_state == 1:
		return "sì"
	if _buffer_layout_state == -1:
		return "no"
	return "non verificato"


static func _apply_buffer(mm: MultiMesh, buffer: PackedFloat32Array, stride: int) -> void:
	mm.instance_count = buffer.size() / stride
	if mm.instance_count > 0:
		mm.buffer = buffer


# Verifica in gioco del formato (una volta per sessione): un MultiMesh di prova riceve una trasformazione e un colore
# con i metodi di sempre, poi si confronta il suo buffer con quello impacchettato qui (lettura); infine si scrive un
# buffer impacchettato e si rilegge la trasformazione (scrittura). Con e senza colore. Le posizioni di riempimento
# (indici 2 e 6) non si confrontano.
static func _multimesh_buffer_layout_ok() -> bool:
	if _buffer_layout_state != 0:
		return _buffer_layout_state == 1
	var transform := Transform2D(Vector2(1.25, -2.5), Vector2(3.75, 0.5), Vector2(-7.0, 11.0))
	var color := Color(0.1, 0.2, 0.3, 0.4)
	var ok := _check_buffer_layout(false, transform, color) and _check_buffer_layout(true, transform, color)
	_buffer_layout_state = 1 if ok else -1
	if not ok:
		push_warning("MicroCellRenderer: formato del buffer dei MultiMesh 2D diverso da quello atteso — rimontaggio con il metodo di prima.")
	return ok


static func _check_buffer_layout(with_color: bool, transform: Transform2D, color: Color) -> bool:
	var stride: int = BUFFER_STRIDE_TRANSFORM_COLOR if with_color else BUFFER_STRIDE_TRANSFORM
	var expected := _packed_transform_2d(transform)
	if with_color:
		expected.append_array(PackedFloat32Array([color.r, color.g, color.b, color.a]))
	# Lettura: istanza 1 (non 0) per verificare anche il passo tra un'istanza e l'altra.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = with_color
	mm.instance_count = 2
	mm.set_instance_transform_2d(1, transform)
	if with_color:
		mm.set_instance_color(1, color)
	var read_back: PackedFloat32Array = mm.buffer
	if read_back.size() != 2 * stride:
		return false
	for i in range(stride):
		if i == 2 or i == 6:
			continue
		if absf(read_back[stride + i] - expected[i]) > 0.0001:
			return false
	# Scrittura: buffer impacchettato qui, trasformazione e colore riletti con i metodi di sempre.
	var written := MultiMesh.new()
	written.transform_format = MultiMesh.TRANSFORM_2D
	written.use_colors = with_color
	written.instance_count = 2
	var buffer := PackedFloat32Array()
	buffer.resize(stride)
	buffer.append_array(expected)
	written.buffer = buffer
	var back: Transform2D = written.get_instance_transform_2d(1)
	if not back.is_equal_approx(transform):
		return false
	if with_color and not written.get_instance_color(1).is_equal_approx(color):
		return false
	return true


# MEMORIA DELLA GEOMETRIA (2026-10-03, richiesta utente — passo B: non ricalcolare ciò che non è cambiato, soprattutto
# nei ridisegni per movimento/nebbia, dove cambia solo QUALI individui sono visibili). Chiave individuo (Vector3i) ->
# geometria già calcolata + "signature". La geometria di un individuo dipende SOLO da:
#   - la chiave (lotto e indice: posizione di base, scostamenti, hash);
#   - il sottotipo (tree/shrub_individual_subtype) e l'anno di nascita (tree/shrub_birth_year_store) -> nella firma
#     dell'individuo;
#   - il numero di individui del lotto (vivi visibili + tagliati + morti, _lot_extent_counts: densità e disco) -> nella
#     firma dell'individuo;
#   - anno corrente e parametri d'età per sottotipo (fascia d'età e taglia) -> firma globale
#     (_check_geometry_cache_globals): se cambia, memoria svuotata;
#   - costanti del file (CELL_SIZE, intervalli, sali degli hash).
# NON ne dipendono (applicati a ogni ricostruzione): colore stagionale della chioma, test dei frutti per rapporto.
# GameScene svuota tutto (clear_vegetation_geometry_cache) a ogni rigenerazione delle posizioni
# (needs_full_vegetation_recompute: checkpoint stagionale, taglio, edificio, attivazione cella) — nel dubbio.
var _tree_geometry_cache: Dictionary = {}
var _shrub_geometry_cache: Dictionary = {}
var _tree_geometry_globals: Array = []
var _shrub_geometry_globals: Array = []


func clear_vegetation_geometry_cache() -> void:
	_tree_geometry_cache.clear()
	_shrub_geometry_cache.clear()
	_tree_geometry_globals = []
	_shrub_geometry_globals = []
	_tree_groups.clear()
	_tree_groups_globals = []
	_tree_groups_fruit_stamp = []
	_shrub_groups.clear()
	_shrub_groups_globals = []
	_shrub_groups_berry_stamp = []


# Svuota la memoria di un tipo se anno corrente o parametri d'età sono cambiati dall'ultima ricostruzione.
func _check_geometry_cache_globals() -> void:
	var tree_globals: Array = [tree_current_year, tree_age_params.hash()]
	if tree_globals != _tree_geometry_globals:
		_tree_geometry_cache.clear()
		_tree_geometry_globals = tree_globals
	var shrub_globals: Array = [shrub_current_year, shrub_age_params.hash()]
	if shrub_globals != _shrub_geometry_globals:
		_shrub_geometry_cache.clear()
		_shrub_geometry_globals = shrub_globals


func _tree_geometry_signature(individual_key: Vector3i, lot_counts: Dictionary) -> Array:
	return [
		tree_individual_subtype.get(individual_key, "wood_only"),
		tree_birth_year_store.get(individual_key, null),
		int(lot_counts.get(Vector2i(individual_key.x, individual_key.y), 1)),
	]


func _shrub_geometry_signature(individual_key: Vector3i, lot_counts: Dictionary) -> Array:
	return [
		shrub_individual_subtype.get(individual_key, "wood_only"),
		shrub_birth_year_store.get(individual_key, null),
		int(lot_counts.get(Vector2i(individual_key.x, individual_key.y), 1)),
	]


# Geometria di un albero: le stesse formule della ricostruzione di prima del passo B (tronco, chioma, frutti).
# `packed_only` (2026-10-03, richiesta utente — correzione del ricalcolo completo): con il metodo a buffer si tengono solo
# i dati impacchettati; le trasformazioni (che servono solo al metodo di prima) si tengono solo senza buffer. Il metodo è
# deciso una volta per sessione (_multimesh_buffer_layout_ok), e una geometria senza i dati del metodo in uso viene
# ricalcolata (_rebuild_tree_multimeshes, required_field).
func _compute_tree_geometry(individual_key: Vector3i, lot_counts: Dictionary, packed_only: bool = false) -> Dictionary:
	var visual: Dictionary = _compute_tree_visual(individual_key, lot_counts)
	var ground: Vector2 = visual["ground"]
	var trunk_width: float = visual["trunk_width"]
	var trunk_y: float = visual["trunk_y"]
	var canopy_center: Vector2 = visual["canopy_center"]
	var canopy_radius: float = visual["canopy_radius"]

	var trunk_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(trunk_width, visual["trunk_height"]))
	trunk_transform.origin = Vector2(ground.x - trunk_width / 2.0, trunk_y)
	var canopy_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(canopy_radius, canopy_radius))
	canopy_transform.origin = canopy_center

	# YOUNG non produce mai frutti; conifer non ha mai frutti.
	var fruit_resource := ""
	if not visual["is_conifer"] and visual["is_fruit_bearing"] and visual["age_band"] != GameTypes.AgeBand.YOUNG:
		fruit_resource = "fruit" if visual["is_domesticable"] else "acorn"
	var fruit_transforms: Array = _build_tree_fruit_transforms(visual["jitter_pos"], canopy_center, canopy_radius) if fruit_resource != "" else []
	var geometry := {
		"is_conifer": visual["is_conifer"], "fruit_resource": fruit_resource, "jitter_pos": visual["jitter_pos"],
		"canopy_center": canopy_center, "canopy_radius": canopy_radius,
	}
	if packed_only:
		# Dati impacchettati nel formato del buffer (passo 2): tronco, chioma senza colore (il colore stagionale si
		# aggiunge in _tree_canopy_packed_with_color; la chioma conifer non ha colore), puntini dei frutti.
		geometry["trunk_packed"] = _packed_transform_2d(trunk_transform)
		geometry["canopy_packed"] = _packed_transform_2d(canopy_transform)
		geometry["fruit_packed"] = _packed_transforms(fruit_transforms)
	else:
		geometry["trunk_transform"] = trunk_transform
		geometry["canopy_transform"] = canopy_transform
		geometry["fruit_transforms"] = fruit_transforms
	return geometry


# Piante da frutto dell'ultima ricostruzione completa (2026-10-03, richiesta utente — ricostruire solo i frutti):
# alberi decidui fruttiferi non YOUNG, con quanto serve a ridisegnarne i frutti senza ricalcolare tronchi e chiome —
# {"key": Vector3i, "lot": Vector2i, "jitter_pos": Vector2i, "canopy_center": Vector2, "canopy_radius": float,
#  "resource_name": "acorn"/"fruit"}. Svuotato e rifatto a ogni _rebuild_tree_multimeshes; `valid` torna false a ogni
# cambio dei dati degli alberi (_defer_or_rebuild_tree). Stesso schema per gli arbusti (bacche).
var _tree_fruit_entries: Array = []
var _tree_fruit_entries_valid: bool = false
var _shrub_fruit_entries: Array = []
var _shrub_fruit_entries_valid: bool = false


# Soli MultiMesh dei frutti degli alberi, dall'elenco: stesso test (_fruit_stock_shows) e stesse trasformazioni
# (_build_tree_fruit_transforms) della ricostruzione completa. Elenco non valido -> ripiego sulla completa.
func _rebuild_tree_fruit_multimeshes() -> void:
	if not _tree_fruit_entries_valid or _tree_fruit_wild_multimesh == null or _tree_fruit_domesticable_multimesh == null:
		last_fruit_rebuild_paths["tree"] = "ripiego completo"
		_rebuild_tree_multimeshes()
		return
	last_fruit_rebuild_paths["tree"] = "solo frutti"
	# Dalla memoria (2026-10-04, richiesta utente): col metodo a buffer i puntini già impacchettati della geometria in
	# memoria (passo B) invece di ricalcolarli per ogni albero; ricalcolati solo se la geometria non c'è o non
	# corrisponde a questa voce (_cached_tree_fruit_packed). Senza buffer, il metodo di prima.
	if _multimesh_buffer_layout_ok():
		var wild_fruit_buffer := PackedFloat32Array()
		var domesticable_fruit_buffer := PackedFloat32Array()
		for entry in _tree_fruit_entries:
			var fruit_resource: String = entry["resource_name"]
			if not _fruit_stock_shows(fruit_resource, entry["key"], entry["jitter_pos"]):
				continue
			if fruit_resource == "fruit":
				domesticable_fruit_buffer.append_array(_cached_tree_fruit_packed(entry))
			else:
				wild_fruit_buffer.append_array(_cached_tree_fruit_packed(entry))
		_apply_buffer(_tree_fruit_wild_multimesh, wild_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
		_apply_buffer(_tree_fruit_domesticable_multimesh, domesticable_fruit_buffer, BUFFER_STRIDE_TRANSFORM)
		return
	var wild_fruit_transforms: Array = []
	var domesticable_fruit_transforms: Array = []
	for entry in _tree_fruit_entries:
		var resource_name: String = entry["resource_name"]
		if not _fruit_stock_shows(resource_name, entry["key"], entry["jitter_pos"]):
			continue
		var transforms := _build_tree_fruit_transforms(entry["jitter_pos"], entry["canopy_center"], entry["canopy_radius"])
		if resource_name == "fruit":
			domesticable_fruit_transforms.append_array(transforms)
		else:
			wild_fruit_transforms.append_array(transforms)
	_apply_transforms(_tree_fruit_wild_multimesh, wild_fruit_transforms)
	_apply_transforms(_tree_fruit_domesticable_multimesh, domesticable_fruit_transforms)


# Puntini impacchettati di un albero da frutto: dalla geometria in memoria se esiste e ha la stessa chioma della voce
# (centro e raggio, da cui dipendono i puntini), altrimenti ricalcolati con la formula di sempre.
func _cached_tree_fruit_packed(entry: Dictionary) -> PackedFloat32Array:
	var geometry: Dictionary = _tree_geometry_cache.get(entry["key"], {})
	if geometry.has("fruit_packed") and geometry["canopy_center"] == entry["canopy_center"] \
			and geometry["canopy_radius"] == entry["canopy_radius"] and geometry["jitter_pos"] == entry["jitter_pos"]:
		return geometry["fruit_packed"]
	return _packed_transforms(_build_tree_fruit_transforms(entry["jitter_pos"], entry["canopy_center"], entry["canopy_radius"]))


const TREE_FRUIT_SALTS := [
	Vector2i(59, 5),
	Vector2i(23, 61),
	Vector2i(37, 89),
]

# Raggio dot proporzionale a canopy_radius (che arriva già scalato per età*densità — vedi
# _rebuild_tree_multimeshes) invece di una dimensione fissa: 0.18 è tarato sul canopy_radius
# medio pre-esistente (~3.3, tra 2.8 e 3.8) così un albero non rimpicciolito per affollamento dà
# lo stesso dot di prima (~0.6) — un albero rimpicciolito (lotto affollato o giovane) ha ora dot
# proporzionalmente più piccoli invece di restare fissi e sproporzionati rispetto alla chioma.
const FRUIT_DOT_RADIUS_RATIO: float = 0.18

# 1-2 piccoli dot (colore assegnato dal chiamante in base a wild/domesticable) lungo il bordo
# della chioma — stesso principio geometrico delle bacche shrub, angolo/distanza per-dot
# derivati da hash(pos).
func _build_tree_fruit_transforms(pos: Vector2i, canopy_center: Vector2, canopy_radius: float) -> Array:
	var transforms: Array = []
	var dot_count: int = 2 + (hash(pos * 17 + Vector2i(4, 90)) % 2) # 2 o 3 dot
	var dot_radius: float = canopy_radius * FRUIT_DOT_RADIUS_RATIO
	for i in range(dot_count):
		var salt: Vector2i = TREE_FRUIT_SALTS[i % TREE_FRUIT_SALTS.size()]
		var angle: float = (float(hash(pos * salt.x + Vector2i(salt.y, i + 200)) % 1000) / 1000.0) * TAU
		var distance: float = lerp(0.5, 1.0, float(hash(pos * salt.y + Vector2i(i + 200, salt.x)) % 1000) / 1000.0) * canopy_radius
		var dot_center := canopy_center + Vector2(cos(angle), sin(angle)) * distance

		var dot_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(dot_radius, dot_radius))
		dot_transform.origin = dot_center
		transforms.append(dot_transform)
	return transforms


# Shrub stilizzato: 3-4 piccoli cerchi sovrapposti e sfalsati attorno al centro della cella
# (colore per-istanza via MultiMesh.use_colors, gradiente verde/marrone come sempre) + le
# eventuali bacche (il sottotipo fruit_bearing/wood_only arriva già congelato in
# shrub_individual_subtype, vedi IndividualVegetationService). Ricalcolato anche quando cambia
# solo il sottotipo (set_shrub_subtypes), non solo le posizioni.
const SHRUB_BLOB_SALTS := [
	Vector2i(5, 13),
	Vector2i(17, 3),
	Vector2i(11, 23),
	Vector2i(29, 7),
]
const SHRUB_BERRY_SALTS := [
	Vector2i(41, 19),
	Vector2i(7, 37),
	Vector2i(53, 3),
]
# Salt per il test hash-vs-ratio "questo individuo mostra ancora il frutto?" (2026-09-17, richiesta
# utente — vedi fruit_stock_available_ratio_by_lot sopra), UNO per resource_name (GENERALIZZATO lo
# stesso giorno in preparazione di fruit/acorn, nessun cambio di comportamento per berry: il valore
# per "berry" resta IDENTICO — Vector2i(59, 101), STESSA formula hash di prima). Un salt DEDICATO
# per risorsa (non un hash di resource_name mescolato in un salt condiviso, che cambierebbe la
# selezione degli individui per berry) — stesso principio già in uso ovunque nel progetto per i
# test hash-based (es. IndividualVegetationService.TREE_FRUIT_BEARING_SALT vs
# SHRUB_FRUIT_BEARING_SALT, mai un salt unico derivato dal nome). Indipendente dagli altri salt
# SHRUB_*/TREE_* così la selezione di CHI viene spento non correla con nessun'altra decisione
# visiva (blob/bacche-count/posizione) già presa sullo stesso individuo. Stesso principio "hash
# stabile, non randf()" già in uso ovunque in questo file — un individuo con percentile basso resta
# visibile finché il ratio tiene, solo i marginali si spengono/riaccendono quando il ratio scende/
# risale.
const FRUIT_STOCK_VISIBILITY_SALT_BY_RESOURCE := {
	"berry": Vector2i(59, 101),
	# "acorn" (2026-09-17, richiesta utente) — salt indipendente da quello di berry: nessun
	# individuo può mai essere sia SHRUB fruit_bearing sia TREE wild_fruit, quindi non c'è un
	# rischio di correlazione reale oggi, ma un salt dedicato per risorsa resta il principio
	# corretto (vedi commento sopra) anche quando, in futuro, più risorse TREE (es. fruit)
	# condivideranno lo stesso spazio di individui.
	"acorn": Vector2i(83, 149),
	# "fruit" (2026-09-17, richiesta utente) — salt indipendente da berry/acorn, stesso principio:
	# nessun individuo domesticable_fruit è mai anche wild_fruit/fruit_bearing, ma un salt dedicato
	# per risorsa resta il principio corretto a prescindere (vedi commento sopra).
	"fruit": Vector2i(127, 211),
}
# Anno di nascita virtuale per individuo SHRUB — stesso principio di tree_birth_year_store sopra
# (Dictionary di proprietà del chiamante, MacroCellState.shrub_virtual_birth_year, passato per
# riferimento da set_shrub_age_params): il congelamento vero avviene in IndividualVegetationService,
# questo renderer lo legge soltanto (vedi _resolve_age_band_and_size). Tenuta separata da
# tree_birth_year_store: stessa posizione griglia può ospitare risorse diverse in anni diversi,
# le due mappe non vanno mai confuse.
var shrub_birth_year_store: Dictionary = {}

# Calcolo COMPLETO di un individuo SHRUB — geometria a schermo, a partire da un sottotipo/età già
# NOTI (mai più decisi qui, vedi IndividualVegetationService) — riusato sia da
# _rebuild_shrub_multimeshes (che vi costruisce sopra i singoli blob/bacche) sia dalle query
# pubbliche get_individual_screen_position/get_individual_info.
func _compute_shrub_visual(individual_key: Vector3i, lot_counts: Dictionary) -> Dictionary:
	var pos := Vector2i(individual_key.x, individual_key.y)
	var index: int = individual_key.z
	# Stesso principio di decorrelazione di _compute_tree_visual.
	var jitter_pos := pos + Vector2i(index * 619, index * 823)

	# Letto da shrub_individual_subtype (congelato alla nascita dell'individuo, vedi
	# IndividualVegetationService) invece di ritestato ogni volta contro un rapporto corrente.
	var subtype_name: String = shrub_individual_subtype.get(individual_key, "wood_only")
	var is_fruit_bearing: bool = subtype_name == "fruit_bearing"

	var resolved := _resolve_age_band_and_size(individual_key, subtype_name, shrub_age_params, shrub_birth_year_store, shrub_current_year)
	var age_band: GameTypes.AgeBand = resolved["age_band"]
	var age_size_multiplier: float = resolved["size_multiplier"]

	# Stesse due scale indipendenti di _compute_tree_visual — vedi il commento lì.
	var spacing := _resolve_density_scale_and_offset_range(int(lot_counts.get(pos, 1)))
	var offset_range: float = spacing["offset_range"]
	var density_scale: float = spacing["density_scale"]
	var size_multiplier: float = age_size_multiplier * density_scale

	var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	var half: float = CELL_SIZE / 2.0
	# `center` per-individuo (non fisso al centro esatto del lotto): senza di esso più shrub nello
	# stesso lotto ancorerebbero l'intero cluster di blob allo stesso identico punto,
	# sovrapponendosi per costruzione indipendentemente da quanto i singoli blob si disperdono
	# attorno al centro.
	var center_offset_x: float = lerp(-offset_range, offset_range, float(hash(jitter_pos * 17 + Vector2i(53, 9)) % 1000) / 1000.0)
	var center_offset_y: float = lerp(-offset_range, offset_range, float(hash(jitter_pos * 19 + Vector2i(9, 53)) % 1000) / 1000.0)
	var center := base + Vector2(half, half) + Vector2(center_offset_x, center_offset_y)

	return {
		"is_fruit_bearing": is_fruit_bearing, "subtype_name": subtype_name, "age_band": age_band,
		"years_lived": shrub_current_year - int(shrub_birth_year_store.get(individual_key, shrub_current_year)),
		"jitter_pos": jitter_pos, "center": center, "density_scale": density_scale, "size_multiplier": size_multiplier,
	}


func _rebuild_shrub_multimeshes() -> void:
	_ensure_vegetation_meshes()
	_ensure_vegetation_multimeshes()

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.SHRUB, []) # Array[Vector3i]: lotto x,y + indice individuo
	var blob_transforms: Array = []
	var blob_colors: Array = []
	var berry_transforms: Array = []

	# Rimontaggio a gruppi degli arbusti (2026-10-04, richiesta utente — vedi _rebuild_shrub_multimeshes_grouped): stesse
	# condizioni degli alberi (metodo a buffer, disposizione appena passata e coerente), consumata da questa ricostruzione.
	var group_layout_ok: bool = _shrub_group_layout_fresh and _shrub_group_starts.size() >= 1 \
		and int(_shrub_group_starts[0]) == 0 and int(_shrub_group_starts[_shrub_group_starts.size() - 1]) == positions.size()
	_shrub_group_layout_fresh = false
	if group_layout_ok and _multimesh_buffer_layout_ok():
		_rebuild_shrub_multimeshes_grouped(positions)
		return

	# Estensione nota (vivi+bloccati), vedi commento in _rebuild_tree_multimeshes.
	var lot_counts: Dictionary = _lot_extent_counts(GameTypes.WorldObjectType.SHRUB)
	_shrub_fruit_entries.clear()

	# Geometria in memoria (2026-10-03, passo B — vedi _tree_geometry_cache): lobi (trasformazioni e colori) e bacche
	# ricalcolati solo per gli individui nuovi o con firma diversa; il test delle bacche si applica a ogni ricostruzione.
	_check_geometry_cache_globals()
	# Rimontaggio a blocchi di dati (passo 2, vedi _rebuild_tree_multimeshes).
	var use_buffer := _multimesh_buffer_layout_ok()
	var blob_buffer := PackedFloat32Array()
	var berry_buffer := PackedFloat32Array()
	var computed_count := 0
	var reused_count := 0
	for individual_key in positions:
		var signature := _shrub_geometry_signature(individual_key, lot_counts)
		var geometry: Dictionary = _shrub_geometry_cache.get(individual_key, {})
		if geometry.is_empty() or geometry["signature"] != signature or not geometry.has("blob_packed" if use_buffer else "blob_transforms"):
			geometry = _compute_shrub_geometry(individual_key, lot_counts, use_buffer)
			geometry["signature"] = signature
			_shrub_geometry_cache[individual_key] = geometry
			computed_count += 1
		else:
			reused_count += 1
		if use_buffer:
			blob_buffer.append_array(geometry["blob_packed"])
		else:
			blob_transforms.append_array(geometry["blob_transforms"])
			blob_colors.append_array(geometry["blob_colors"])
		# YOUNG non produce mai bacche: il gate è già dentro "has_berries".
		if geometry["has_berries"]:
			_shrub_fruit_entries.append({
				"key": individual_key, "jitter_pos": geometry["jitter_pos"], "center": geometry["center"],
				"density_scale": geometry["density_scale"], "size_multiplier": geometry["size_multiplier"],
			})
			if _fruit_stock_shows("berry", individual_key, geometry["jitter_pos"]):
				if use_buffer:
					berry_buffer.append_array(geometry["berry_packed"])
				else:
					berry_transforms.append_array(geometry["berry_transforms"])
	last_geometry_stats["shrub"] = {"computed": computed_count, "reused": reused_count}

	if use_buffer:
		_apply_buffer(_shrub_multimesh, blob_buffer, BUFFER_STRIDE_TRANSFORM_COLOR)
		_apply_buffer(_berry_multimesh, berry_buffer, BUFFER_STRIDE_TRANSFORM)
		_shrub_fruit_entries_valid = true
		return

	_apply_transforms(_shrub_multimesh, blob_transforms)
	for i in range(blob_colors.size()):
		_shrub_multimesh.set_instance_color(i, blob_colors[i])

	_apply_transforms(_berry_multimesh, berry_transforms)
	_shrub_fruit_entries_valid = true


# Geometria di un arbusto: le stesse formule della ricostruzione di prima del passo B (lobi con colore, bacche).
# `packed_only`: stesso schema di _compute_tree_geometry (solo dati impacchettati col metodo a buffer).
func _compute_shrub_geometry(individual_key: Vector3i, lot_counts: Dictionary, packed_only: bool = false) -> Dictionary:
	var visual: Dictionary = _compute_shrub_visual(individual_key, lot_counts)
	var jitter_pos: Vector2i = visual["jitter_pos"]
	var center: Vector2 = visual["center"]
	var density_scale: float = visual["density_scale"]
	var size_multiplier: float = visual["size_multiplier"]

	var blob_transforms: Array = []
	var blob_colors: Array = []
	var blob_count: int = 3 + (hash(jitter_pos) % 2) # 3 o 4 lobi, variabile per shrub
	for i in range(blob_count):
		var salt: Vector2i = SHRUB_BLOB_SALTS[i]
		var angle: float = (float(hash(jitter_pos * salt.x + Vector2i(salt.y, i)) % 1000) / 1000.0) * TAU
		# distance scala per density_scale (non per size_multiplier pieno, età esclusa): la COMPATTEZZA del cluster
		# segue quanto il lotto è affollato, non la fascia d'età di questo singolo individuo.
		var distance: float = lerp(0.8, 1.8, float(hash(jitter_pos * salt.y + Vector2i(i, salt.x)) % 1000) / 1000.0) * density_scale
		var radius: float = lerp(1.4, 2.2, float(hash(jitter_pos * (salt.x + salt.y) + Vector2i(i, i)) % 1000) / 1000.0) * size_multiplier
		var hue_t: float = float(hash(jitter_pos * (salt.x + salt.y + 41) + Vector2i(i, i + 1)) % 1000) / 1000.0
		var blob_color: Color = COLOR_SHRUB_GREEN.lerp(COLOR_SHRUB_BROWN, hue_t)
		var blob_center := center + Vector2(cos(angle), sin(angle)) * distance

		var blob_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(radius, radius))
		blob_transform.origin = blob_center
		blob_transforms.append(blob_transform)
		blob_colors.append(blob_color)

	# YOUNG non produce mai bacche (production_coefficient_young = 0.0, stesso coefficiente usato dal calcolo calorico).
	var has_berries: bool = visual["is_fruit_bearing"] and visual["age_band"] != GameTypes.AgeBand.YOUNG
	var berry_transforms: Array = _build_shrub_berry_transforms(jitter_pos, center, density_scale, size_multiplier) if has_berries else []
	var geometry := {
		"has_berries": has_berries,
		"jitter_pos": jitter_pos, "center": center, "density_scale": density_scale, "size_multiplier": size_multiplier,
	}
	if packed_only:
		# Dati impacchettati nel formato del buffer (passo 2): lobi con il loro colore (fisso, non stagionale), bacche.
		geometry["blob_packed"] = _packed_transforms_with_colors(blob_transforms, blob_colors)
		geometry["berry_packed"] = _packed_transforms(berry_transforms)
	else:
		geometry["blob_transforms"] = blob_transforms
		geometry["blob_colors"] = blob_colors
		geometry["berry_transforms"] = berry_transforms
	return geometry


# RIMONTAGGIO A GRUPPI DEGLI ARBUSTI (2026-10-04, richiesta utente) — stesso schema degli alberi (vedi
# _rebuild_tree_multimeshes_grouped e il commento su TREE_GROUP_SIZE): gruppi di SHRUB_GROUP_SIZE arbusti consecutivi
# dell'elenco NON filtrato, fette visibili da GameScene (set_shrub_group_layout), per gruppo lobi (con colore), voci
# delle bacche e bacche già concatenati. Un gruppo si rifà se la sua fetta visibile cambia; tutti se cambiano versione
# delle posizioni, anno, parametri d'età, ceppi o piante morte degli arbusti, numero di gruppi, se il motivo non è
# movimento/nebbia o se la memoria della geometria viene svuotata (gli arbusti non hanno colore stagionale). Le bacche
# dei gruppi riusati si rifanno quando cambiano i rapporti delle bacche per lotto (stessa scelta dei frutti degli alberi).
const SHRUB_GROUP_SIZE := 256

var _shrub_group_layout_version: int = -1
var _shrub_group_starts: Array = []
var _shrub_group_allow_reuse: bool = false
var _shrub_group_layout_fresh: bool = false
var _shrub_groups: Array = []
var _shrub_groups_globals: Array = []
var _shrub_groups_berry_stamp: Array = []
# Diagnostica: {"rebuilt": int, "reused": int} dell'ultimo rimontaggio a gruppi degli arbusti (vuoto = giro di sempre).
var last_shrub_group_stats: Dictionary = {}


func set_shrub_group_layout(layout_version: int, starts: Array, allow_reuse: bool) -> void:
	_shrub_group_layout_version = layout_version
	_shrub_group_starts = starts
	_shrub_group_allow_reuse = allow_reuse
	_shrub_group_layout_fresh = true


func _rebuild_shrub_multimeshes_grouped(positions: Array) -> void:
	_check_geometry_cache_globals()
	var group_count: int = _shrub_group_starts.size() - 1
	var globals: Array = [
		_shrub_group_layout_version, shrub_current_year, shrub_age_params.hash(),
		cut_positions.get(GameTypes.WorldObjectType.SHRUB, []), dead_positions.get(GameTypes.WorldObjectType.SHRUB, []),
		group_count,
	]
	if not _shrub_group_allow_reuse or globals != _shrub_groups_globals or _shrub_groups.size() != group_count:
		_shrub_groups.clear()
		_shrub_groups.resize(group_count)
		_shrub_groups_globals = globals
		_shrub_groups_berry_stamp = []
	var berry_stamp: Array = [fruit_stock_available_ratio_by_lot.get("berry", {})]
	var berry_changed: bool = berry_stamp != _shrub_groups_berry_stamp
	_shrub_groups_berry_stamp = berry_stamp

	var lot_counts: Variant = null
	var blob_buffer := PackedFloat32Array()
	var berry_buffer := PackedFloat32Array()
	_shrub_fruit_entries.clear()
	var rebuilt_count := 0
	var reused_count := 0
	var computed_individuals := 0
	var reused_individuals := 0
	for group_index in range(group_count):
		var members: Array = positions.slice(int(_shrub_group_starts[group_index]), int(_shrub_group_starts[group_index + 1]))
		var group: Variant = _shrub_groups[group_index]
		if group == null or group["members"] != members:
			if lot_counts == null:
				lot_counts = _lot_extent_counts(GameTypes.WorldObjectType.SHRUB)
			group = _build_shrub_group(members, lot_counts)
			_shrub_groups[group_index] = group
			rebuilt_count += 1
			computed_individuals += int(group["computed"])
			reused_individuals += int(group["reused"])
		else:
			reused_count += 1
			if berry_changed:
				_refresh_shrub_group_berries(group)
		blob_buffer.append_array(group["blobs"])
		berry_buffer.append_array(group["berries"])
		_shrub_fruit_entries.append_array(group["fruit_entries"])
	last_geometry_stats["shrub"] = {"computed": computed_individuals, "reused": reused_individuals}
	last_shrub_group_stats = {"rebuilt": rebuilt_count, "reused": reused_count}
	_apply_buffer(_shrub_multimesh, blob_buffer, BUFFER_STRIDE_TRANSFORM_COLOR)
	_apply_buffer(_berry_multimesh, berry_buffer, BUFFER_STRIDE_TRANSFORM)
	_shrub_fruit_entries_valid = true


# Un gruppo di arbusti da zero: lo stesso corpo del giro di sempre (ramo a buffer) sui soli `members`.
func _build_shrub_group(members: Array, lot_counts: Dictionary) -> Dictionary:
	var blobs := PackedFloat32Array()
	var fruit_entries: Array = []
	var computed := 0
	var reused := 0
	for individual_key in members:
		var signature := _shrub_geometry_signature(individual_key, lot_counts)
		var geometry: Dictionary = _shrub_geometry_cache.get(individual_key, {})
		if geometry.is_empty() or geometry["signature"] != signature or not geometry.has("blob_packed"):
			geometry = _compute_shrub_geometry(individual_key, lot_counts, true)
			geometry["signature"] = signature
			_shrub_geometry_cache[individual_key] = geometry
			computed += 1
		else:
			reused += 1
		blobs.append_array(geometry["blob_packed"])
		if geometry["has_berries"]:
			fruit_entries.append({
				"key": individual_key, "jitter_pos": geometry["jitter_pos"], "center": geometry["center"],
				"density_scale": geometry["density_scale"], "size_multiplier": geometry["size_multiplier"],
			})
	var group := {"members": members, "blobs": blobs, "fruit_entries": fruit_entries, "computed": computed, "reused": reused}
	_refresh_shrub_group_berries(group)
	return group


# Bacche di un gruppo dalle sue voci: stesso test e stessi dati del giro di sempre, nell'ordine delle voci.
func _refresh_shrub_group_berries(group: Dictionary) -> void:
	var berries := PackedFloat32Array()
	for entry in group["fruit_entries"]:
		if _fruit_stock_shows("berry", entry["key"], entry["jitter_pos"]):
			berries.append_array(_cached_shrub_berry_packed(entry))
	group["berries"] = berries


# Bacche di un arbusto (estratta il 2026-10-03 da _rebuild_shrub_multimeshes, formula invariata, per riusarla nella
# ricostruzione dei soli frutti).
func _build_shrub_berry_transforms(jitter_pos: Vector2i, center: Vector2, density_scale: float, size_multiplier: float) -> Array:
	var berry_transforms: Array = []
	var berry_count: int = 2 + (hash(jitter_pos * 61 + Vector2i(3, 8)) % 2) # 2 o 3 bacche
	for i in range(berry_count):
		var berry_salt: Vector2i = SHRUB_BERRY_SALTS[i % SHRUB_BERRY_SALTS.size()]
		var berry_angle: float = (float(hash(jitter_pos * berry_salt.x + Vector2i(berry_salt.y, i + 100)) % 1000) / 1000.0) * TAU
		# distance scala per density_scale, stesso principio della distanza dei blob (compattezza del cluster legata
		# all'affollamento del lotto, non alla fascia età).
		var berry_distance: float = lerp(0.6, 1.6, float(hash(jitter_pos * berry_salt.y + Vector2i(i + 100, berry_salt.x)) % 1000) / 1000.0) * density_scale
		var berry_center := center + Vector2(cos(berry_angle), sin(berry_angle)) * berry_distance
		# Raggio scalato per size_multiplier (età*densità), stesso principio del raggio dei blob.
		var berry_radius: float = 0.55 * size_multiplier
		var berry_transform := Transform2D(0, Vector2.ZERO).scaled(Vector2(berry_radius, berry_radius))
		berry_transform.origin = berry_center
		berry_transforms.append(berry_transform)
	return berry_transforms


# Solo il MultiMesh delle bacche, dall'elenco (stesso schema di _rebuild_tree_fruit_multimeshes). Elenco non valido ->
# ripiego sulla ricostruzione completa degli arbusti.
func _rebuild_shrub_fruit_multimesh() -> void:
	if not _shrub_fruit_entries_valid or _berry_multimesh == null:
		last_fruit_rebuild_paths["shrub"] = "ripiego completo"
		_rebuild_shrub_multimeshes()
		return
	last_fruit_rebuild_paths["shrub"] = "solo frutti"
	# Dalla memoria (2026-10-04): stesso schema degli alberi (_cached_shrub_berry_packed).
	if _multimesh_buffer_layout_ok():
		var berry_buffer := PackedFloat32Array()
		for entry in _shrub_fruit_entries:
			if _fruit_stock_shows("berry", entry["key"], entry["jitter_pos"]):
				berry_buffer.append_array(_cached_shrub_berry_packed(entry))
		_apply_buffer(_berry_multimesh, berry_buffer, BUFFER_STRIDE_TRANSFORM)
		return
	var berry_transforms: Array = []
	for entry in _shrub_fruit_entries:
		if _fruit_stock_shows("berry", entry["key"], entry["jitter_pos"]):
			berry_transforms.append_array(_build_shrub_berry_transforms(
				entry["jitter_pos"], entry["center"], entry["density_scale"], entry["size_multiplier"]
			))
	_apply_transforms(_berry_multimesh, berry_transforms)


# Bacche impacchettate di un arbusto: dalla geometria in memoria se esiste e ha gli stessi dati della voce (centro,
# scala di densità, taglia, scostamento), altrimenti ricalcolate con la formula di sempre.
func _cached_shrub_berry_packed(entry: Dictionary) -> PackedFloat32Array:
	var geometry: Dictionary = _shrub_geometry_cache.get(entry["key"], {})
	if geometry.has("berry_packed") and geometry["center"] == entry["center"] and geometry["density_scale"] == entry["density_scale"] \
			and geometry["size_multiplier"] == entry["size_multiplier"] and geometry["jitter_pos"] == entry["jitter_pos"]:
		return geometry["berry_packed"]
	return _packed_transforms(_build_shrub_berry_transforms(entry["jitter_pos"], entry["center"], entry["density_scale"], entry["size_multiplier"]))


# Disponibilità residua del LOTTO che ospita `individual_key`, PER RISORSA (2026-09-17, richiesta
# utente — "quando get_berry_available_at è 0 l'arbusto non deve mostrare bacche... se ci sono più
# arbusti fruit_bearing, spegni le bacche su una quota proporzionale al raccolto invece che su
# tutti in una volta"; GENERALIZZATO lo stesso giorno per resource_name, in preparazione dei due
# multimesh frutto degli alberi — nessun cambio di comportamento per berry, stessa formula/stesso
# salt di prima): fruit_stock_available_ratio_by_lot[resource_name][lot] (1.0 se la risorsa o il
# lotto non sono nel Dictionary, vedi commento sul campo) è la frazione [0.0,1.0] di quanto resta
# della quota nominale di QUELLA risorsa nel lotto. Un test hash-vs-ratio stabile per individuo
# (salt dedicato per risorsa — FRUIT_STOCK_VISIBILITY_SALT_BY_RESOURCE, decorrelato da ogni altro
# test hash sullo stesso individuo — blob/berry_count/posizione) decide chi tra gli individui del
# sottotipo giusto nel lotto continua a mostrare il frutto: con ratio=0.6 e 5 individui idonei
# nello stesso lotto, ~3 lo mostrano ancora e ~2 no — non un taglio "tutto o niente" sull'intero
# lotto insieme, e stabile tra un redraw e l'altro (stesso principio "i marginali si spengono per
# primi" già usato per _is_shrub_fruit_bearing altrove nel progetto). Chiamata SOLO per individui
# già filtrati fruit_bearing/non-YOUNG (o l'equivalente TREE, in futuro) dal chiamante — nessun
# costo per gli individui non idonei.
func _fruit_stock_shows(resource_name: String, individual_key: Vector3i, jitter_pos: Vector2i) -> bool:
	var lot := Vector2i(individual_key.x, individual_key.y)
	var ratios: Dictionary = fruit_stock_available_ratio_by_lot.get(resource_name, {})
	var ratio: float = float(ratios.get(lot, 1.0))
	if ratio <= 0.0:
		return false
	var salt: Vector2i = FRUIT_STOCK_VISIBILITY_SALT_BY_RESOURCE.get(resource_name, Vector2i(59, 101))
	var percentile: float = float(hash(
		jitter_pos * salt.x + Vector2i(salt.y, individual_key.z)
	) % 100000) / 100000.0
	return percentile < ratio


# Quanti individui condividono lo stesso lotto (microcella) — serve a _resolve_density_scale_and_
# offset_range sotto per decidere quanto rimpicciolire/disperdere ciascun individuo. Pre-pass
# leggero (O(n)): una passata sola su `positions` prima del loop principale, non ricalcolato
# individuo per individuo.
func _count_individuals_per_lot(positions: Array) -> Dictionary:
	var counts: Dictionary = {}
	for individual_key in positions:
		var lot_pos := Vector2i(individual_key.x, individual_key.y)
		counts[lot_pos] = int(counts.get(lot_pos, 0)) + 1
	return counts


# A local_count=1 (il caso comune) offset_range=BASE_OFFSET_RANGE e density_scale=1.0: nessuna
# regressione visiva rispetto a prima dell'introduzione degli individui multipli per lotto — sono
# esattamente i valori hard-coded che il rendering usava quando ogni lotto ospitava un solo
# individuo. Oltre 1: offset_range cresce linearmente con local_count fino a SPREAD_REFERENCE_
# COUNT (il caso "lotto affollato" osservato in editor), poi resta al massimo; density_scale
# scala per 1/sqrt(local_count) — un raggio ∝ 1/√N mantiene l'area complessiva disegnata da N
# individui piccoli paragonabile a quella di 1 individuo grande — con un floor MIN_DENSITY_SCALE
# così anche un lotto molto affollato resta visibile/cliccabile. Le due scale sono indipendenti
# tra loro E indipendenti da age_size_multiplier (fascia d'età, calcolato altrove): il chiamante
# le compone moltiplicandole, mai l'una al posto dell'altra.
const SPREAD_REFERENCE_COUNT: int = 5
const BASE_OFFSET_RANGE: float = 1.0
const MAX_OFFSET_RANGE: float = 3.0
const MIN_DENSITY_SCALE: float = 0.4

func _resolve_density_scale_and_offset_range(local_count: int) -> Dictionary:
	var jitter_scale: float = clamp(float(local_count - 1) / float(SPREAD_REFERENCE_COUNT - 1), 0.0, 1.0)
	var offset_range: float = lerp(BASE_OFFSET_RANGE, MAX_OFFSET_RANGE, jitter_scale)
	var density_scale: float = clamp(1.0 / sqrt(float(local_count)), MIN_DENSITY_SCALE, 1.0)
	return {"offset_range": offset_range, "density_scale": density_scale}


# Disposizione deterministica "a girasole" (Fibonacci disk, angolo aureo ~137.5°) usata SOLO da
# TREE (vedi _rebuild_tree_multimeshes) — SHRUB continua a usare offset_range sopra con due hash
# indipendenti per X/Y, e lì funziona bene: la chioma di uno shrub è già un cluster di blob
# sovrapposti per design, tollerante alla vicinanza. TREE invece ha una forma riconoscibile
# (tronco sottile + chioma), dove due hash indipendenti possono per puro caso concentrare più
# individui vicini (un problema di impacchettamento statistico, non risolvibile solo allargando
# il range) — anche una lieve vicinanza casuale si legge chiaramente come "due tronchi
# appiccicati". Questa disposizione garantisce GEOMETRICAMENTE che gli indici 0..local_count-1
# riempiano il disco disponibile in modo uniforme, mai per fortuna del hash: ogni individuo
# riceve un raggio crescente (∝ √((index+0.5)/local_count), distribuzione a densità areale
# costante — gli stessi semi di girasole usano questa costruzione in natura per riempirsi senza
# sovrapporsi) e un angolo che avanza dell'angolo aureo ad ogni indice (evita allineamenti
# periodici che un angolo "rotondo" produrrebbe). A local_count<=1 nessun offset — individuo
# unico, resta centrato come prima di questo cambiamento (il piccolo wobble organico si aggiunge
# comunque sopra, vedi il chiamante).
const GOLDEN_ANGLE: float = 2.399963229728653 # ~137.5077 gradi in radianti

func _fibonacci_disk_offset(index: int, local_count: int, max_radius: float) -> Vector2:
	if local_count <= 1:
		return Vector2.ZERO
	var radius: float = max_radius * sqrt((float(index) + 0.5) / float(local_count))
	var angle: float = float(index) * GOLDEN_ANGLE
	return Vector2(cos(angle), sin(angle)) * radius


# Fascia età + moltiplicatore dimensione per un INDIVIDUO (granularità per-individuo), condiviso
# da qualunque risorsa con age bands (oggi SHRUB e TREE) — PURA LETTURA: l'anno di nascita è già
# stato congelato una volta per sempre da IndividualVegetationService al momento della nascita
# dell'individuo (vedi shrub_birth_year_store/tree_birth_year_store, persistiti su MacroCellState,
# chiave Vector3i = lotto x,y + indice individuo locale), questa funzione non scrive mai più nulla
# lì — a differenza di prima di questa sessione, quando il congelamento avveniva qui al primo
# render reale. Nessuna entry per l'individuo (non ancora congelato per qualche motivo, o
# sottotipo con track_age_bands=false) => resta neutro, età ADULT/dimensione 1.0 di default.
func _resolve_age_band_and_size(
	individual_key: Vector3i,
	subtype_name: String,
	params_by_subtype: Dictionary,
	birth_year_store: Dictionary,
	current_year: int
) -> Dictionary:
	var params: Dictionary = params_by_subtype.get(subtype_name, {})
	if params.is_empty() or not birth_year_store.has(individual_key):
		return {"age_band": GameTypes.AgeBand.ADULT, "size_multiplier": 1.0}

	var years_lived: int = current_year - int(birth_year_store[individual_key])
	var age_band: GameTypes.AgeBand = AgeBandVisualService.band_for_age(
		years_lived, params["youth_duration_years"], params["adult_duration_years"]
	)
	return {"age_band": age_band, "size_multiplier": params["size_multiplier_by_age"][age_band]}


# Ciuffo d'erba stilizzato: 5-8 fili sottili (linee) sparsi su quasi tutta la larghezza della
# cella, ciascuno con angolo/altezza/colore leggermente diversi — stessa formula di sempre, ma
# accumulata in un'unica coppia di buffer punti/colori invece di un draw_line per filo: tutti i
# fili della cella vengono poi disegnati con una sola draw_multiline_colors in _draw().
var _grass_points: PackedVector2Array = PackedVector2Array()
var _grass_colors: PackedColorArray = PackedColorArray()

func _rebuild_grass_buffers() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	var palette: Dictionary = GRASS_PALETTE_BY_SEASON.get(current_season, {"base": COLOR_GRASS_BASE, "tip": COLOR_GRASS_TIP})
	var grass_base: Color = palette["base"]
	var grass_tip: Color = palette["tip"]

	var positions: Array = vegetation_positions.get(GameTypes.WorldObjectType.GRASS, [])
	for pos in positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var blade_count: int = 5 + (hash(pos) % 4) # 5-8 fili

		for i in range(blade_count):
			var salt: int = i * 19 + 7
			var blade_x: float = lerp(0.5, CELL_SIZE - 0.5, float(hash(pos * salt + Vector2i(i, salt)) % 1000) / 1000.0)
			var blade_y_inset: float = lerp(0.3, 1.2, float(hash(pos * (salt + 3) + Vector2i(salt, i)) % 1000) / 1000.0)
			var blade_base := Vector2(base.x + blade_x, base.y + CELL_SIZE - blade_y_inset)

			var angle_variation: float = lerp(-0.5, 0.5, float(hash(pos * (salt + 11) + Vector2i(i, salt)) % 1000) / 1000.0)
			var angle: float = -PI / 2.0 + angle_variation # verso l'alto, con oscillazione laterale
			var height: float = lerp(1.3, 2.4, float(hash(pos * (salt + 17) + Vector2i(salt, i)) % 1000) / 1000.0)
			var hue_t: float = float(hash(pos * (salt + 23) + Vector2i(i, salt + 5)) % 1000) / 1000.0
			var color: Color = grass_base.lerp(grass_tip, hue_t)

			var tip: Vector2 = blade_base + Vector2(cos(angle), sin(angle)) * height
			points.append(blade_base)
			points.append(tip)
			# draw_multiline_colors vuole un colore per SEGMENTO (colors.size() == points.size()/2),
			# non uno per punto — un'unica append qui, non due.
			colors.append(color)

	_grass_points = points
	_grass_colors = colors


# Pesce stilizzato: corpo a ellisse (cerchio unitario scalato in modo anisotropo *nello spazio
# locale* — scaled_local, non scaled: con scaled() la scala verrebbe applicata nello spazio
# globale DOPO la rotazione, e un cerchio è invariante per rotazione, quindi l'ellisse
# risulterebbe sempre allineata agli assi invece che orientata secondo heading — poi ruotato
# come corpo rigido) + una piccola coda triangolare agganciata dietro, stessa rotazione del
# corpo. Un solo heading casuale per pesce (da hash(pos)) dà varietà di orientamento senza
# bisogno di più primitive — stesso principio "poche forme condivise, trasformo per istanza"
# già usato per stone/tree/shrub.
const FISH_BODY_LENGTH_RANGE := Vector2(2.0, 3.0) # semiasse lungo (direzione di marcia)
const FISH_BODY_WIDTH_RANGE := Vector2(0.8, 1.2)  # semiasse corto (fianchi)
const FISH_TAIL_LENGTH_RATIO: float = 0.6 # relativo a body_length
const FISH_TAIL_WIDTH_RATIO: float = 1.3  # la coda è più larga della sezione del corpo

var _fish_body_mesh: ArrayMesh
var _fish_tail_mesh: ArrayMesh
var _fish_meshes_ready: bool = false

var _fish_body_multimesh: MultiMesh
var _fish_tail_multimesh: MultiMesh


func _ensure_fish_meshes() -> void:
	if _fish_meshes_ready:
		return
	_fish_meshes_ready = true

	_fish_body_mesh = _build_circle_mesh(VEGETATION_CIRCLE_SEGMENTS, COLOR_FISH_BODY)
	# Triangolo unitario: punta a sinistra (-1, 0), base sul lato destro (0, -1)/(0, 1) — il
	# lato destro è il punto di aggancio dietro al corpo (vedi tail_local_offset sotto).
	var tail_points := PackedVector2Array([Vector2(-1, 0), Vector2(0, -1), Vector2(0, 1)])
	_fish_tail_mesh = _build_fan_mesh(tail_points, COLOR_FISH_TAIL)


func _ensure_fish_multimeshes() -> void:
	if _fish_body_multimesh != null:
		return

	_fish_body_multimesh = _make_multimesh(_fish_body_mesh, false)
	_fish_tail_multimesh = _make_multimesh(_fish_tail_mesh, false)


func _rebuild_fish_multimeshes() -> void:
	_ensure_fish_meshes()
	_ensure_fish_multimeshes()

	var body_transforms: Array = []
	var tail_transforms: Array = []

	for pos in fish_positions:
		var base := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
		var half: float = CELL_SIZE / 2.0

		var offset_x: float = lerp(-1.0, 1.0, float(hash(pos * 5 + Vector2i(4, 12)) % 1000) / 1000.0)
		var offset_y: float = lerp(-1.0, 1.0, float(hash(pos * 5 + Vector2i(12, 4)) % 1000) / 1000.0)
		var center := base + Vector2(half, half) + Vector2(offset_x, offset_y)

		var heading: float = (float(hash(pos * 7 + Vector2i(31, 53)) % 1000) / 1000.0) * TAU
		var size_t: float = float(hash(pos) % 1000) / 1000.0
		var body_length: float = lerp(FISH_BODY_LENGTH_RANGE.x, FISH_BODY_LENGTH_RANGE.y, size_t)
		var body_width: float = lerp(FISH_BODY_WIDTH_RANGE.x, FISH_BODY_WIDTH_RANGE.y, size_t)

		var body_transform := Transform2D(heading, Vector2.ZERO).scaled_local(Vector2(body_length, body_width))
		body_transform.origin = center
		body_transforms.append(body_transform)

		var tail_length: float = body_length * FISH_TAIL_LENGTH_RATIO
		var tail_width: float = body_width * FISH_TAIL_WIDTH_RATIO
		# Punto dietro il corpo (bordo posteriore dell'ellisse, local (-body_length, 0) prima
		# della rotazione), ruotato dello stesso heading: qui la coda viene agganciata.
		var tail_local_offset: Vector2 = Vector2(-body_length, 0).rotated(heading)
		var tail_transform := Transform2D(heading, Vector2.ZERO).scaled_local(Vector2(tail_length, tail_width))
		tail_transform.origin = center + tail_local_offset
		tail_transforms.append(tail_transform)

	_apply_transforms(_fish_body_multimesh, body_transforms)
	_apply_transforms(_fish_tail_multimesh, tail_transforms)


func _draw_fish_positions() -> void:
	if _fish_body_multimesh != null and _fish_body_multimesh.instance_count > 0:
		draw_multimesh(_fish_body_multimesh, null)
		_debug_draw_primitive_count += 1
	if _fish_tail_multimesh != null and _fish_tail_multimesh.instance_count > 0:
		draw_multimesh(_fish_tail_multimesh, null)
		_debug_draw_primitive_count += 1


# Fascia di fiume al centro della cella, orientata secondo river_shape — stessa geometria
# di WorldRenderer._draw_river_cell ma scalata all'intera griglia 100x100 invece di una
# singola cella da 10px.
func _draw_river(grid_size: int) -> void:
	var thickness: float = max(grid_size * river_thickness_ratio, 1.0)
	var half: float = grid_size / 2.0
	var center: float = half

	if CORNER_ARC_DATA.has(river_shape):
		var data: Dictionary = CORNER_ARC_DATA[river_shape]
		var pivot: Vector2 = data["pivot"] * grid_size
		_draw_river_arc(pivot, data["from"], data["to"], half - thickness / 2.0, half + thickness / 2.0)
		return

	match river_shape:
		GameTypes.RiverShape.VERTICAL:
			draw_rect(Rect2(center - thickness / 2.0, 0, thickness, grid_size), TerrainColors.RIVER)

		GameTypes.RiverShape.HORIZONTAL:
			draw_rect(Rect2(0, center - thickness / 2.0, grid_size, thickness), TerrainColors.RIVER)

		GameTypes.RiverShape.FULL:
			draw_rect(Rect2(0, 0, grid_size, grid_size), TerrainColors.RIVER)

		_:
			draw_rect(Rect2(center - thickness / 2.0, 0, thickness, grid_size), TerrainColors.RIVER)


# Fascia ad anello (settore di corona circolare) tra due raggi, imperniata sull'angolo vero
# della cella: dà alla curva un bordo esterno arrotondato invece che a blocchi.
func _draw_river_arc(pivot: Vector2, angle_from: float, angle_to: float, inner_radius: float, outer_radius: float) -> void:
	var points := PackedVector2Array()
	for i in range(CORNER_ARC_SEGMENTS + 1):
		var t: float = float(i) / float(CORNER_ARC_SEGMENTS)
		var angle: float = lerp(angle_from, angle_to, t)
		points.append(pivot + Vector2(cos(angle), sin(angle)) * outer_radius)
	for i in range(CORNER_ARC_SEGMENTS + 1):
		var t: float = float(i) / float(CORNER_ARC_SEGMENTS)
		var angle: float = lerp(angle_to, angle_from, t)
		points.append(pivot + Vector2(cos(angle), sin(angle)) * inner_radius)

	if not _is_valid_polygon_points(points):
		push_warning("MicroCellRenderer: arco fiume scartato, punti non validi (size=%d)" % points.size())
		return

	draw_colored_polygon(points, TerrainColors.RIVER)


func _draw_neighbor_previews(grid_size: int) -> void:
	var center: float = grid_size / 2.0

	for direction in DIRECTIONS:
		var neighbor: MacroCellData = neighbor_cells.get(direction, null)
		if neighbor == null:
			continue

		var rect: Rect2
		match direction:
			Vector2i(0, -1):
				rect = Rect2(0, -NEIGHBOR_STRIP_DEPTH, grid_size, NEIGHBOR_STRIP_DEPTH)
			Vector2i(0, 1):
				rect = Rect2(0, grid_size, grid_size, NEIGHBOR_STRIP_DEPTH)
			Vector2i(1, 0):
				rect = Rect2(grid_size, 0, NEIGHBOR_STRIP_DEPTH, grid_size)
			Vector2i(-1, 0):
				rect = Rect2(-NEIGHBOR_STRIP_DEPTH, 0, NEIGHBOR_STRIP_DEPTH, grid_size)

		# Il vicino è controllato per conto suo, a prescindere da cosa sia la cella centrale
		# (fiume, lago, montagna...): se QUEL vicino è davvero un fiume, la sua striscia mostra
		# il suo terreno più una fascia sottile con lo spessore del SUO river_space, non il
		# pieno colore acqua. Lago/mare restano un riempimento pieno, sono già acqua per intero.
		if neighbor.water_type == GameTypes.WaterType.RIVER:
			draw_rect(rect, TerrainColors.get_land_color(neighbor))
			_draw_river_connector(direction, grid_size, center, _neighbor_river_thickness(direction, grid_size))
		else:
			draw_rect(rect, TerrainColors.get_cell_color(neighbor))


func _neighbor_river_thickness(direction: Vector2i, grid_size: int) -> float:
	var state: MacroCellState = neighbor_states.get(direction, null)
	var ratio: float = 0.0
	if state != null:
		ratio = float(state.get_river_space()) / float(MacroCellState.TOTAL_SPACE)
	return max(grid_size * ratio, 1.0)


# Piccolo prolungamento del fiume dentro la striscia di anteprima del vicino, per far
# vedere che il fiume continua (o finisce) in quella direzione.
func _draw_river_connector(direction: Vector2i, grid_size: int, center: float, thickness: float) -> void:
	var rect: Rect2
	match direction:
		Vector2i(0, -1):
			rect = Rect2(center - thickness / 2.0, -NEIGHBOR_STRIP_DEPTH, thickness, NEIGHBOR_STRIP_DEPTH)
		Vector2i(0, 1):
			rect = Rect2(center - thickness / 2.0, grid_size, thickness, NEIGHBOR_STRIP_DEPTH)
		Vector2i(1, 0):
			rect = Rect2(grid_size, center - thickness / 2.0, NEIGHBOR_STRIP_DEPTH, thickness)
		Vector2i(-1, 0):
			rect = Rect2(-NEIGHBOR_STRIP_DEPTH, center - thickness / 2.0, NEIGHBOR_STRIP_DEPTH, thickness)

	draw_rect(rect, TerrainColors.RIVER)


# Riempimento piatto del vicino diagonale in ciascuno dei 4 angoli — stesso pattern di
# _draw_neighbor_previews ma un quadrato NEIGHBOR_STRIP_DEPTH x NEIGHBOR_STRIP_DEPTH invece di
# una fascia intera, e sempre get_land_color (mai get_cell_color): un vicino-fiume qui mostra
# solo il suo terreno di base, senza fascia fluviale — l'angolo è troppo piccolo perché quella
# fascia sia percepibile/rilevante a questo livello di zoom (a differenza delle fasce cardinali
# sopra, dove il fiume attraversa l'intero lato ed è quindi sempre visibile). get_land_color
# resta comunque corretta anche per SEA/LAKE (terrain_base == WATER ci finisce comunque dentro),
# quindi un angolo davvero tutto-acqua si vede comunque blu.
# Riga tratteggiata sul perimetro del quadrato 100x100 reale: segna dove finisce la
# cella "giocabile" e comincia la sola anteprima dei vicini.
func _draw_boundary(grid_size: int) -> void:
	draw_dashed_line(Vector2(0, 0), Vector2(grid_size, 0), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, grid_size), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(0, 0), Vector2(0, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
	draw_dashed_line(Vector2(grid_size, 0), Vector2(grid_size, grid_size), BOUNDARY_DASH_COLOR, BOUNDARY_DASH_WIDTH, BOUNDARY_DASH_LENGTH)
