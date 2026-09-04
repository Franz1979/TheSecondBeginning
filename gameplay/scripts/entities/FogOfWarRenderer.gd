class_name FogOfWarRenderer
extends Node2D

# Step 3 (con fix) della fog of war: decadimento MULTI-LIVELLO (tre tier, velocità diverse)
# oltre alla persistenza (FogOfWarMemory) e al calcolo geometrico per-frame — ancora NESSUN
# modificatore esterno da tech/gossip (diverso dal piano "Step 4" del 2026-09-02 sotto, che è
# multi-sorgente umana, non modificatori — i modificatori tech restano scope futuro non iniziato).
# Cinque gradazioni di overlay:
#   - dentro visibility_radius ORA -> nessun overlay, stato "live" (e mark_seen aggiornato)
#   - FUORI dal raggio ma is_detail_fresh -> overlay minimo (recent_overlay_alpha): "ricordo
#     recente, non più osservato in tempo reale" — distinto dal live, non confuso con esso
#   - detail scaduto, is_resource_fresh ancora vero -> overlay leggero (dettaglio/entità in
#     movimento, es. animali, dimenticato per primo — decade più in fretta)
#   - anche resource scaduto, is_terrain_fresh ancora vero -> overlay medio (stesso valore del
#     "congelato" dello Step 2 — risorse/occupazione a grana media, velocità intermedia)
#   - anche terrain scaduto -> nero pieno (il tipo di cella/terreno è l'ultimo a essere
#     dimenticato, decade più lentamente)
#
# FIX rispetto alla prima versione dello Step 3: "dentro il raggio" ORA è un controllo esplicito
# PRIMA della catena sui tier, non più dedotto implicitamente dal fatto che is_detail_fresh sia
# sempre vera lì (con detail_memory_days alzato da 1 a 10, quel presupposto rendeva "sto
# guardando la cella adesso" e "l'ho vista negli ultimi 10 giorni ma non sono più lì"
# visivamente indistinguibili — entrambi "nessun overlay" per un'intera settimana e mezza).
# is_detail_fresh su FogOfWarMemory resta invariata (query pura): il fix è solo qui, in COME
# FogOfWarRenderer sceglie il colore.
#
# Il decadimento è calcolato PIGRAMENTE ad ogni _draw() (i tre getter di FogOfWarMemory), non
# ticchettato nel tempo: nessun processo periodico che aggiorna o rimuove entry scadute — vedi
# FogOfWarMemory.gd per il perché le entry scadute restano comunque nel dizionario, solo ignorate.
#
# NOTA: gli animali (AnimalGroupRenderer) restano visibili anche sotto overlay leggero/medio —
# gap noto, non risolto in questo step: verrà affrontato insieme al fix di visibilità animali
# già pianificato dopo il completamento della fog of war.
#
# Nodo separato da MicroCellRenderer (non baked nel suo _draw()) apposta: quel _draw() ridisegna
# anche il terreno (loop su tutte le 10.000 microcelle) e va richiamato solo sui cambi di stato
# reali del mondo. La fog invece deve aggiornarsi ad ogni frame in cui una sorgente rilevante si
# muove — tenerla qui evita di forzare un redraw dell'intera griglia terreno/vegetazione solo
# perché qualcuno ha fatto un passo. Deve essere l'ULTIMO figlio aggiunto in GameScene (l'ordine
# dei figli è l'ordine di disegno in Godot 2D): sopra renderer/animali/HumanIndividualView, così
# l'overlay copre davvero tutto quello che nasconde.
#
# raggio come campo di QUESTO nodo, non di HumanIndividual: la percezione è un concetto di
# rendering/gameplay (in futuro dipenderà da tech/edifici/modificatori esterni), HumanIndividual
# resta puro stato di posizione/movimento/selezione — stesso principio già applicato per
# HumanIndividualView/HumanIndividualController. Questo renderer (Step 4, 2026-09-02) non tiene
# nemmeno più un riferimento a HumanIndividual — vedi source_positions sotto: riceve solo posizioni
# già risolte, l'identità di chi le genera è affare di GameScene.
#
# FogOfWarMemory è posseduta da GameScene (non da questo renderer) e passata qui via setup() —
# vedi FogOfWarMemory.gd per il perché (un futuro step di persistenza su save dovrà passarla a
# GameSaveService/GameLoadService come già fa con game_data/world, mai scavando nello stato
# interno di un renderer).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/HumanIndividualView

# Nero pieno: tier terreno scaduto (o mai vista) — puro sconosciuto/non tracciato.
const OVERLAY_COLOR := Color(0, 0, 0, 1.0)
# Semi-trasparente scurito medio: tier risorse scaduto ma terreno ancora fresco — stesso valore
# del "congelato" dello Step 2, ora un gradino intermedio invece dello stato finale.
const FROZEN_OVERLAY_COLOR := Color(0, 0, 0, 0.5)
# Overlay leggero: solo il tier dettaglio (entità in movimento) è scaduto, risorse e terreno
# ancora freschi — il gradino più vicino alla piena visibilità.
const LIGHT_OVERLAY_COLOR := Color(0, 0, 0, 0.25)

# Trasparente ESPLICITO (Step 3.1, texture persistente) — a differenza del vecchio draw_rect() mai
# chiamato per le celle in raggio (trasparenza implicita quel frame, nessun comando emesso), la
# texture persistente mantiene l'ultimo valore scritto in un pixel finché qualcosa non lo
# sovrascrive di nuovo: una cella che entra in raggio deve ricevere ESPLICITAMENTE questo colore,
# altrimenti si porterebbe dietro il colore/alpha del giro precedente.
const TRANSPARENT_COLOR := Color(0, 0, 0, 0)

# Macchie verde-grigio sfocate disegnate SOPRA FROZEN_OVERLAY_COLOR (vedi _draw_stale_vegetation_
# hint) — non un colore di FogOfWarRules (quella risorsa resta per le sole soglie in giorni, non
# per costanti di rendering: stessa distinzione già valida per OVERLAY_COLOR/FROZEN_OVERLAY_COLOR/
# LIGHT_OVERLAY_COLOR sopra, mai spostate lì).
const STALE_VEGETATION_BLOB_COLOR := Color(0.28, 0.34, 0.2, 0.8)

@export var visibility_radius: float = 6.0 # microcelle
# Overlay minimo per lo stato "ricordo recente ma non più in vista ora" (fuori dal raggio, ma
# ancora entro detail_memory_days) — @export separato (non un const come gli altri tre colori
# sopra) perché è il valore più speculativo, il più probabile da ritarare a vista una volta
# provato in editor.
@export var recent_overlay_alpha: float = 0.1

# Tre soglie di decadimento — non più hardcoded qui: lette da FogOfWarRules (.tres) tramite
# FogOfWarCalculator dentro setup() sotto, con questi stessi valori come fallback se la risorsa
# manca. Campi di ISTANZA semplici (non @export: nessuna istanza di questo nodo viene mai creata
# da una scena con override nell'editor, sempre .new() da GameScene._activate_live_cell, quindi
# un @export qui non avrebbe mai avuto effetto reale) per lo stesso motivo di visibility_radius
# sopra: sono soglie di percezione/gameplay (in futuro modificabili da tech/edifici, Step 4), la
# memoria (FogOfWarMemory) resta agnostica sul perché di questi numeri. Ordine crescente per
# design (detail < resource < terrain — il tipo di terreno si dimentica più lentamente delle
# risorse, che a loro volta durano più delle posizioni esatte/entità in movimento): non imposto
# qui via codice, responsabilità di chi tara FogOfWarRules.
var detail_memory_days: int = 10
var resource_memory_days: int = 30
var terrain_memory_days: int = 90

# Posizioni (Vector2, LOCALI a questo renderer — cioè già nello spazio di QUESTA macrocella, non
# quello di partenza dell'individuo) di TUTTE le sorgenti di visibilità rilevanti per questa cella
# — Step 4 FoW multi-sorgente, 2026-09-02: SOSTITUISCE il vecchio singolo campo `individual`
# (HumanIndividual). Deliberatamente Array[Vector2], non Array[HumanIndividual]: un individuo
# fisicamente in una cella DIVERSA da questa contribuisce comunque alla visibilità di QUESTA cella
# (se abbastanza vicino, vedi GameScene._relevant_source_positions_for_cell), ma la sua posizione va
# TRADOTTA nello spazio locale di QUESTA cella prima di arrivare qui — mai mutare
# HumanIndividual.position stessa per farlo (romperebbe ogni altro consumatore, che si aspetta
# sempre la posizione vera locale a home_macro_coords). Questo renderer resta quindi agnostico su
# "chi" genera visibilità, sa solo "dove" — nessuna dipendenza da HumanIndividual qui dentro.
# Aggiornato ogni frame da GameScene tramite update_visibility() sotto (mai da questo file).
var source_positions: Array[Vector2] = []
var fog_of_war_memory: FogOfWarMemory

# Vector2i -> true, per le microcelle con almeno un individuo TREE/SHRUB/GRASS — vedi
# set_vegetation_presence/_draw_stale_vegetation_hint. Aggiornato da GameScene ogni volta che
# rigenera la vegetazione (attivazione cella o checkpoint stagionale) — sì, quindi con lo stesso
# ritardo di tutto il resto della vegetazione, ma qui va bene: serve solo "c'è più o meno
# vegetazione qui", non l'identità precisa di un singolo individuo, e le posizioni sono comunque
# stabili da un checkpoint all'altro (vedi ResourcePositionService, prefix-stabile). A differenza
# di "questo individuo preciso è ancora quello che ricordo", che dipende dal movimento del player
# minuto per minuto — per questo quella domanda NON vive più in MicroCellRenderer (vedi la
# discussione che ha portato a spostare l'Opzione B qui): qui il decadimento resta guidato dallo
# stesso ciclo per-frame di tutto il resto di questo renderer, mai dal rebuild a checkpoint.
#
# GRASS incluso (2026-09-04, prima escluso apposta): l'hint sintetico serve solo "c'è più o meno
# vegetazione qui", non l'identità di un individuo — esattamente il livello di dettaglio che GRASS
# offre già di suo (un lotto = un'unica entità senza identità individuale, vedi
# VegetationPositionService), quindi non c'era una ragione reale per escluderla da questo segnale
# grossolano, solo l'assenza di identità individuale che qui non serve comunque.
var _vegetation_presence: Dictionary = {}

# Vector2i -> true: microcelle entro rules.visibility_radius di un edificio presente in QUESTA
# macrocella (vedi GameScene._building_visible_positions_for_cell) — trattate esattamente come il
# raggio del player (vedi in_radius sotto): nessun overlay, mark_seen aggiornato ogni volta che
# questo renderer ridisegna. Permanente finché l'edificio esiste (World.buildings resta la fonte
# di verità, questo set è solo una cache di sessione ricalcolata da GameScene ad ogni cambio),
# indipendente dalla posizione del player — è esattamente ciò che permette a un edificio lontano
# di restare "conosciuto" anche quando il player è altrove, e impedisce a FogOfWarMemory di
# svuotarsi del tutto e far scattare IndividualVegetationService.forget_known_individuals per una
# macrocella che in realtà è ancora viva (vedi GameScene._forget_vegetation_identity).
var _building_visible_positions: Dictionary = {}

# Vector2i -> true: microcelle "visibili ORA via una qualunque sorgente" — cache dello "splat"
# (misurato 2026-09-02, richiesta utente: 25-30ms/redraw con 5 sorgenti, quasi ogni frame durante
# il movimento, sopra budget frame a 60/30fps). PRIMA il ciclo da 10.000 celle testava ogni cella
# contro le N sorgenti (O(10.000×N)); ORA, per ciascuna sorgente, si marcano solo le ~113 microcelle
# nel suo raggio (bounding box ± visibility_radius, poi distance check) — O(N×113) invece di
# O(10.000×N) — PRIMA del ciclo principale, che poi fa un lookup O(1) su questo dizionario invece
# del test a N vie per cella. Ricalcolata SOLO quando source_positions cambia davvero (vedi
# update_visibility() sotto — non ha senso rifare lo splat se nessuna sorgente si è mossa),
# _building_visible_positions sopra resta un dizionario a parte (già O(1), non dipende dalle
# sorgenti, nessun motivo di fonderli).
var _source_visible_positions: Dictionary = {}

# Vector2i -> Color: cache del tier/colore per le celle FUORI dal raggio splat (misurato
# 2026-09-02, richiesta utente: dentro "decisione" i lookup su FogOfWarMemory —
# is_detail_fresh/is_resource_fresh/is_terrain_fresh, fino a 3 per cella — dominavano davvero,
# 16-20ms su 21-25ms). Una cella fuori raggio ha un tier che dipende SOLO da (last_seen_by_
# position.get(pos), giorno corrente) — se nessuna delle due è cambiata dall'ultimo calcolo per
# quella cella, il risultato cacheato resta valido per costruzione, niente altro nel codice tocca
# last_seen_by_position al di fuori dei quattro punti che invalidano (vedi _mark_seen_and_
# invalidate/mark_positions_dirty). Popolamento PIGRO (mai precalcolata per l'intera griglia):
# _flush_position la consulta, e se assente calcola come prima e la scrive lì per il prossimo
# giro. Le celle IN_RADIUS non la consultano mai (il loro esito, "live", non passa mai da qui).
#
# AGGIORNAMENTO Step 3.4 (2026-09-03): valore ridotto da {"color": Color, "show_hint": bool} al
# solo Color — show_hint non è più una proprietà cacheata insieme al colore (vedi
# _frozen_tier_positions sotto per il perché: dipendeva da _vegetation_presence, che cambia a un
# ritmo diverso dal colore, quindi tenerli insieme costringeva a invalidare l'intera cache colore
# ad ogni refresh vegetazione anche se NESSUN colore era davvero cambiato — vedi
# set_vegetation_presence).
var _cell_color_cache: Dictionary = {}

# Sentinel (array vuoto, mai uguale a un source_positions valido finché non ne arriva uno) per
# forzare il primo _draw() anche se nessuna sorgente si è ancora mossa e il giorno non è ancora
# avanzato — vedi update_visibility().
var _last_drawn_positions: Array[Vector2] = []
var _last_drawn_absolute_day: int = -1
# Usato dentro _draw() per mark_seen — sempre in sync con _last_drawn_absolute_day (valorizzato
# insieme, mai altrove), tenuto separato solo per chiarezza di lettura in _draw().
var _current_absolute_day: int = -1
var _radius_squared: float = 0.0

# Contatore redraw/sec (richiesta utente, 2026-09-02 — TEMPORANEO, stesso gate SHOW_FOW_REDRAW_
# TIMING_LOGS) — incrementato in _draw() ad ogni esecuzione REALE (mai gated dall'early-out di
# update_visibility: se _draw() gira, è perché quello early-out ha già lasciato passare un cambio
# vero). Finestra di un secondo via Time.get_ticks_msec(), stampa+reset quando scaduta.
var _redraw_count_this_second: int = 0
var _redraw_count_window_start_msec: int = 0

# Step 3.1 (2026-09-03): overlay ora una texture persistente su uno Sprite2D figlio invece di
# N draw_rect()/draw_circle() immediate-mode dentro _draw() — vedi conversazione per il design
# completo (nessun documento a parte). _fog_sprite/_fog_image/_fog_texture portano SOLO il
# colore/alpha per cella (mai gli hint, vedi _hint_layer sotto): risoluzione 100x100 (1 texel =
# 1 microcella, stesse dimensioni di World.WIDTH/HEIGHT — vedi _draw() sotto) con
# texture_filter NEAREST esplicito e scale=CELL_SIZE, così lo stretch a 1000x1000px riproduce
# blocchi netti pixel-per-pixel identici ai vecchi draw_rect, senza sfumature (un default
# LINEAR erediterebbe la sfocatura del filtro di progetto). _fog_image è la copia CPU mutabile
# (set_pixel), _fog_texture è la texture GPU-side assegnata a _fog_sprite.texture, aggiornata con
# un solo .update(_fog_image) per redraw reale — Godot 4 non supporta upload parziale per
# regione, quindi anche in QUESTO passo (ancora scansione piena, nessun dirty-tracking) il costo
# di quell'update() è già lo stesso che avrà il passo 3.3: il dirty-tracking risparmierà la
# decisione per cella, non l'upload finale.
var _fog_sprite: Sprite2D
var _fog_image: Image
var _fog_texture: ImageTexture

# Nodo figlio separato per le macchie di vegetazione stantia (vedi _draw_stale_vegetation_hint) —
# aggiunto DOPO _fog_sprite in setup() (l'ordine dei figli è l'ordine di disegno in Godot 2D),
# così gli hint restano sempre sopra la texture invece di finire coperti da un blocco
# FROZEN_OVERLAY_COLOR pieno. Nessuna sottoclasse dedicata: un Node2D semplice con il segnale
# `draw` collegato a _on_hint_layer_draw sotto.
var _hint_layer: Node2D

# Vector2i -> true: MEMBERSHIP PERSISTENTE (non una lista "di questo giro" come nel passo 3.1) —
# tutte le posizioni per cui _cell_color_cache riporta ATTUALMENTE FROZEN_OVERLAY_COLOR (a
# prescindere da _vegetation_presence — vedi sotto per la differenza dal vecchio _hinted_
# positions del passo 3.3). Necessario a partire dal passo 3.3: col dirty-tracking vero, _draw()
# non rivisita più tutte le 10.000 celle ad ogni giro, quindi non può più ricostruire "quali celle
# sono a tier FROZEN ORA" da zero come faceva _pending_hint_positions nel passo 3.1. Mantenuto per
# COSTRUZIONE in ogni punto che scrive/cancella _cell_color_cache (vedi _flush_position/
# _mark_seen_and_invalidate/mark_positions_dirty), mai ricalcolato da zero.
#
# RINOMINATO da _hinted_positions al passo 3.4 (2026-09-03), con un cambio di significato reale,
# non solo cosmetico: PRIMA teneva la membership "questa cella mostra ATTUALMENTE l'hint"
# (show_hint già valutato contro _vegetation_presence al momento del cache-miss, poi cacheato
# insieme al colore) — per questo un refresh vegetazione doveva invalidare l'intera cache colore
# (nessun altro modo economico di sapere quali entry avevano uno show_hint ora stantio). ORA tiene
# solo l'appartenenza al TIER (indipendente da _vegetation_presence): _on_hint_layer_draw sotto
# incrocia questo insieme con _vegetation_presence LIVE ad ogni proprio redraw, quindi
# set_vegetation_presence non deve più toccare _cell_color_cache/_dirty_positions per niente — le
# uniche celle da ricontrollare per gli hint sono già tutte e sole quelle qui dentro.
var _frozen_tier_positions: Dictionary = {}

# Dirty-tracking vero (Step 3.3, 2026-09-03): Vector2i -> true, le posizioni il cui pixel deve
# essere riscritto nella texture al prossimo _draw() reale. Popolato SOLO nei punti che invalidano
# last_seen_by_position (vedi discussione con l'utente):
#   1. transizione in/fuori raggio (vedi _update_in_radius_dirty_delta) — SOLO il delta rispetto
#      al giro precedente, non l'intero insieme in-raggio ogni volta (quello resterebbe costoso
#      quanto oggi durante un movimento continuo, vanificando il punto di questo passo).
#   2. cambio giorno — non popola questo dizionario: usa _full_flush_pending sotto invece (vedi
#      perché lì).
#   3. prune_stale (vedi FogOfWarRenderer.mark_positions_dirty sotto, chiamato da GameScene.
#      _maybe_prune_fog_of_war_memories) — le posizioni potate esplicitamente, MAI affidandosi
#      all'invariante "terrain_memory_days è sempre il tier più lungo" (vedi commento lì).
# Il refresh vegetazione (set_vegetation_presence) NON è più un punto che invalida questo insieme
# dal passo 3.4 (2026-09-03) in poi: il colore di una cella non dipende mai da _vegetation_
# presence, solo il calcolo LIVE degli hint (vedi _frozen_tier_positions/_on_hint_layer_draw) —
# nessun pixel/texture da toccare per quel trigger, quindi nessun dirty da marcare.
# Svuotato ad ogni _draw() reale dopo il flush (vedi sotto), qualunque sia il percorso preso
# (dirty parziale o full flush).
var _dirty_positions: Dictionary = {}

# Vector2i -> true: l'insieme in-raggio (source ∪ building) COME ERA all'ultimo calcolo del delta
# (vedi _update_in_radius_dirty_delta) — confrontato contro l'insieme attuale per marcare dirty
# SOLO le celle che sono effettivamente entrate o uscite dal raggio, non l'intero insieme ad ogni
# giro (~113×N celle quasi identiche da un frame all'altro durante un movimento continuo: il caso
# più comune, e proprio quello che questo passo deve rendere economico).
var _previous_in_radius_positions: Dictionary = {}

# true = il prossimo _draw() deve ririscrivere TUTTE le 10.000 celle (ignora _dirty_positions),
# invece del solo insieme dirty — usato per gli eventi "clear totale" (cambio giorno, refresh
# vegetazione) dove capire ESATTAMENTE quali celle sono cambiate costerebbe quanto ricalcolare
# tutto (vedi _cell_color_cache = {} nei due punti che lo impostano). true di default: il primo
# _draw() reale (mai in early-out, vedi sentinel _last_drawn_positions) deve comunque scrivere
# ogni pixel la prima volta, texture appena creata da _setup_fog_texture_nodes().
var _full_flush_pending: bool = true

# Accumulatore ISTANZA (non più locale a _draw() come nei passi 3.1/3.2): il lavoro che finiva
# qui dentro ora avviene anche fuori da _draw() (mark_seen in update_visibility/
# set_building_visible_positions, vedi _mark_seen_and_invalidate) — un accumulatore locale a
# _draw() perderebbe quella quota. Letto e resettato a 0 dentro il print di _draw() sotto, così
# ogni stampa riflette esattamente il lavoro FogOfWarMemory svolto dall'ultima stampa, ovunque sia
# avvenuto. Sostituisce _decision_usec/_draw_call_usec dei passi 3.1/3.2: quella ripartizione
# perde senso ora che il grosso della decisione (mark_seen) non vive più dentro _draw() — il
# nuovo celle_processate nel print (vedi sotto) è la metrica comparabile che la sostituisce.
var _memory_lookup_usec: int = 0


# p_fog_of_war_memory: unico parametro rimasto (Step 4, 2026-09-02 — RIMOSSO p_individual: questo
# renderer non è più legato a un singolo individuo/proxy, vedi source_positions sopra). Chiamato
# UNA VOLTA per istanza, all'attivazione della cella (GameScene._activate_live_cell) — mai più
# ri-chiamato ad ogni cambio di bersaglio (il vecchio GameScene._rebind_fog_bindings, rimosso: non
# serve più, update_visibility() sotto riceve le posizioni corrette ogni frame indipendentemente da
# chi sia il bersaglio corrente).
func setup(p_fog_of_war_memory: FogOfWarMemory) -> void:
	fog_of_war_memory = p_fog_of_war_memory
	# Ri-letta ad ogni setup() (non solo alla creazione del nodo): FogOfWarCalculator cachea già il
	# caricamento, quindi rileggere qui è economico e garantisce che un cambio del .tres a runtime
	# (o un futuro moltiplicatore da tech, vedi FogOfWarRules) si propaghi senza bisogno di un
	# canale di aggiornamento a parte.
	var rules := FogOfWarCalculator.get_fog_of_war_rules()
	if rules != null:
		detail_memory_days = rules.detail_memory_days
		resource_memory_days = rules.resource_memory_days
		terrain_memory_days = rules.terrain_memory_days
	_radius_squared = visibility_radius * visibility_radius
	_setup_fog_texture_nodes()
	queue_redraw()


# Chiamato una sola volta da setup() sopra (mai da _ready(): questo nodo è sempre creato via
# .new() da GameScene._activate_live_cell, mai istanziato da una scena — vedi commento in testa
# al file). Crea i due figli del passo 3.1 (vedi campi sopra): _fog_sprite PRIMA (texture
# 100x100 = World.WIDTH/HEIGHT, NEAREST esplicito, scale=CELL_SIZE per coprire 1000x1000px con
# blocchi netti), _hint_layer DOPO (sopra nell'ordine di disegno). Immagine iniziale non
# riempita esplicitamente: il primo _draw() reale (mai in early-out, vedi sentinel
# _last_drawn_positions) scrive comunque OGNI pixel in questo passo (scansione piena invariata),
# quindi il default di Image.create() non è mai visibile.
func _setup_fog_texture_nodes() -> void:
	# create_empty(), non il deprecato Image.create() (Godot 4.3+) — stessa firma, solo il nome è
	# cambiato.
	_fog_image = Image.create_empty(World.WIDTH, World.HEIGHT, false, Image.FORMAT_RGBA8)
	_fog_texture = ImageTexture.create_from_image(_fog_image)

	_fog_sprite = Sprite2D.new()
	_fog_sprite.centered = false
	_fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fog_sprite.scale = Vector2(CELL_SIZE, CELL_SIZE)
	_fog_sprite.texture = _fog_texture
	add_child(_fog_sprite)

	_hint_layer = Node2D.new()
	_hint_layer.draw.connect(_on_hint_layer_draw)
	add_child(_hint_layer)


# Chiamato da GameScene._refresh_resource_visuals con le stesse vegetation_positions appena date
# a MicroCellRenderer.set_vegetation_positions — Vector3i (TREE/SHRUB) ridotto a Vector2i (lotto);
# GRASS (già Vector2i di suo, un lotto = un'unica entità, vedi VegetationPositionService) inclusa
# dal 2026-09-04 — vedi il campo _vegetation_presence sopra per il perché.
func set_vegetation_presence(positions: Dictionary) -> void:
	_vegetation_presence.clear()
	for individual_key in positions.get(GameTypes.WorldObjectType.TREE, []):
		_vegetation_presence[Vector2i(individual_key.x, individual_key.y)] = true
	for individual_key in positions.get(GameTypes.WorldObjectType.SHRUB, []):
		_vegetation_presence[Vector2i(individual_key.x, individual_key.y)] = true
	# GRASS (2026-09-04, vedi campo _vegetation_presence sopra per il perché) — entry già Vector2i
	# di suo (un lotto, vedi VegetationPositionService), la conversione Vector2i(...) qui sotto è
	# quindi un no-op innocuo, tenuta solo per restare identica alle due righe sopra.
	for individual_key in positions.get(GameTypes.WorldObjectType.GRASS, []):
		_vegetation_presence[Vector2i(individual_key.x, individual_key.y)] = true
	# Step 3.4 (2026-09-03): NESSUN tocco a _cell_color_cache/_dirty_positions/_full_flush_pending
	# — il colore di una cella non dipende MAI da _vegetation_presence (solo dai tre tier di
	# freshness), quindi la texture persistente resta valida esattamente com'è. Il solo hint può
	# dipendere da _vegetation_presence, ed è ora calcolato LIVE da _on_hint_layer_draw incrociando
	# _frozen_tier_positions (persistente, indipendente da questo campo) con _vegetation_presence
	# appena riscritta sopra — nessun bisogno di invalidare nulla qui per farlo scattare, basta
	# far ridisegnare il solo layer hint (immediate-mode, ricostruito da zero ad ogni suo
	# queue_redraw() comunque). Il padre (_draw(), pixel/texture/upload) NON viene invocato da
	# questo trigger: prima di questo passo lo era sempre, tramite _full_flush_pending.
	_hint_layer.queue_redraw()


func set_building_visible_positions(positions: Dictionary) -> void:
	_building_visible_positions = positions
	# Step 3.3: prima del passo 3.3, mark_seen per le celle in-raggio girava DENTRO _draw(), quindi
	# QUALUNQUE trigger di redraw (compreso questo, che chiama sempre queue_redraw() senza early-
	# out) lo eseguiva indirettamente. Ora che mark_seen vive fuori da _draw() (vedi
	# _mark_seen_for_current_in_radius_positions), questo punto deve chiamarlo esplicitamente —
	# altrimenti un edificio appena costruito coprirebbe correttamente le celle di pixel
	# trasparenti (vedi delta sotto) ma last_seen_by_position per quelle celle resterebbe stantio
	# fino al prossimo update_visibility() con posizione o giorno cambiati. Stesso principio per
	# _update_in_radius_dirty_delta: l'insieme in-raggio può essere cambiato anche qui, non solo
	# da update_visibility().
	_mark_seen_for_current_in_radius_positions()
	_update_in_radius_dirty_delta()
	queue_redraw()


# Step 3.3 (2026-09-03) — quarto trigger del dirty-tracking (FogOfWarMemory.prune_stale, tramite
# GameScene._maybe_prune_fog_of_war_memories, SOLO per macrocelle attualmente vive). `positions`
# sono le posizioni appena rimosse da last_seen_by_position: il loro tier/colore cacheato potrebbe
# essere stantio (in teoria sempre già corretto oggi, dato che prune_stale rimuove solo entry già
# oltre il tier più lungo — vedi discussione con l'utente — ma questo metodo non si affida a
# quell'invariante, la ricalcola sempre da zero).
func mark_positions_dirty(positions: Array[Vector2i]) -> void:
	if positions.is_empty():
		return
	for pos in positions:
		_cell_color_cache.erase(pos)
		_frozen_tier_positions.erase(pos)
		_dirty_positions[pos] = true
	queue_redraw()


# Da chiamare ogni frame da GameScene._process, con le posizioni LOCALI già tradotte per QUESTA
# cella (vedi GameScene._relevant_source_positions_for_cell) — Step 4 FoW multi-sorgente,
# 2026-09-02: `positions` sostituisce quello che prima era letto da `individual.position`.
# source_positions viene aggiornato SEMPRE (economico, un semplice assegnamento), anche quando il
# resto del metodo fa early-out — compute_visible_positions()/_draw() lo leggono entrambi come
# campo, mai come parametro (indispensabile per _draw(), richiamato dal motore di rendering via
# queue_redraw() senza poter passare argomenti), quindi deve restare sempre fresco indipendentemente
# da quando/se scatta un vero redraw.
#
# Early-out (confronto array, non un singolo Vector2 come prima) se NÉ le posizioni NÉ il giorno
# sono cambiati dall'ultimo redraw — il caso comune "nessuna sorgente vicina si è mossa, stesso
# giorno" non ridisegna nulla, non solo non ricalcola: queue_redraw() stesso non viene chiamato.
# Dato che oggi un solo individuo alla volta può muoversi (il bersaglio corrente — vedi
# GameScene._set_movement_target), questo early-out si comporta esattamente come prima: si rompe
# solo quando IL bersaglio si muove, non più spesso solo perché ora N sorgenti sono modellate.
#
# Il giorno, non solo le posizioni, fa scattare il redraw: senza questo, sorgenti ferme per
# più giorni marcherebbero last_seen_by_position una volta sola (al giorno di arrivo) invece di
# continuare ad aggiornarlo ogni giorno in cui stanno davvero ancora osservando quelle celle —
# essenziale ora che le tre soglie di decadimento confrontano proprio questo timestamp: senza
# il refresh giornaliero, restare fermi troppo a lungo farebbe scadere per errore anche i tier
# più veloci (detail/resource) sulle celle sotto i propri piedi.
func update_visibility(current_absolute_day: int, positions: Array[Vector2]) -> void:
	source_positions = positions
	var position_changed := not _positions_equal(positions, _last_drawn_positions)
	var day_changed := current_absolute_day != _last_drawn_absolute_day
	if not position_changed and not day_changed:
		return
	_last_drawn_positions = positions.duplicate()
	_last_drawn_absolute_day = current_absolute_day
	_current_absolute_day = current_absolute_day
	# Solo se le posizioni sono DAVVERO cambiate (non se è cambiato solo il giorno) — lo splat
	# dipende unicamente da source_positions, rifarlo quando sono identiche a prima sarebbe lavoro
	# sprecato (caso comune: sorgenti ferme, solo il giorno è avanzato).
	if position_changed:
		_source_visible_positions = _splat_source_visible_positions()
	# Clear totale della cache tier/colore (vedi _cell_color_cache) SOLO se è cambiato il giorno —
	# il decadimento dei tre tier dipende dal giorno corrente, determinare quali celle hanno appena
	# superato una soglia costerebbe quanto ricalcolare tutto, quindi più semplice svuotare tutto
	# (O(1), evento raro — una volta al giorno simulato) e lasciare che _draw() la ripopoli pigra.
	# Il solo position_changed (il caso comune, quasi ogni frame durante il movimento) NON tocca
	# questa cache: le celle fuori raggio non vengono mai riviste da mark_seen solo perché qualcuno
	# si è mosso altrove, il loro tier resta valido — è esattamente il costo che la cache elimina.
	#
	# Step 3.3: cambio giorno → _full_flush_pending (non _dirty_positions): sapere ESATTAMENTE
	# quali celle fuori raggio hanno appena superato una soglia costerebbe quanto ricalcolare tutto
	# (stesso ragionamento di sopra sulla cache), quindi un flush pieno resta la scelta più
	# semplice per un evento raro (una volta al giorno simulato) — vedi campo _full_flush_pending.
	if day_changed:
		_cell_color_cache = {}
		_full_flush_pending = true
	# mark_seen per l'insieme in-raggio CORRENTE — SEMPRE quando non c'è early-out (posizione O
	# giorno cambiati), mai gated da position_changed da solo: una sorgente ferma per più giorni
	# deve comunque continuare a rinfrescare last_seen_by_position ogni giorno simulato (vedi
	# commento originale su "Il giorno, non solo le posizioni..." più sotto in questo file/nella
	# cronologia). Step 3.3: non scrive più pixel qui dentro (quello è compito del delta sotto/del
	# flush in _draw()) — solo last_seen_by_position + invalidazione cache/hint mirata.
	_mark_seen_for_current_in_radius_positions()
	# Il delta in-raggio (vedi _update_in_radius_dirty_delta) dipende SOLO da quali posizioni sono
	# in raggio, non dal giorno — se è cambiato solo il giorno, l'insieme in-raggio è identico a
	# prima, nessun delta da calcolare (e comunque _full_flush_pending sopra copre già tutto se
	# day_changed).
	if position_changed:
		_update_in_radius_dirty_delta()
	queue_redraw()


# Step 3.3 — mark_seen per TUTTE le posizioni attualmente in raggio (source ∪ building), chiamato
# da ogni punto che prima si affidava a un _draw() imminente per farlo indirettamente (vedi
# update_visibility sopra e set_building_visible_positions sotto) — mark_seen stesso non vive più
# dentro _draw() dal passo 3.3 in poi, quindi ogni chiamante deve invocarlo esplicitamente.
# Building DOPO source con guardia (stesso principio già in uso nello splat) per non processare
# due volte una cella coperta da entrambe le sorgenti.
func _mark_seen_for_current_in_radius_positions() -> void:
	if fog_of_war_memory == null:
		return
	for pos in _source_visible_positions:
		_mark_seen_and_invalidate(pos)
	for pos in _building_visible_positions:
		if _source_visible_positions.has(pos):
			continue
		_mark_seen_and_invalidate(pos)


# mark_seen di UNA cella + invalidazione mirata di cache/tier (vedi _cell_color_cache/
# _frozen_tier_positions sopra) — questo è l'UNICO momento in cui last_seen_by_position[pos] di
# questa cella cambia per "è ora vista dal vivo": qualunque tier fosse cacheato da prima è ora
# stantio (quando la cella uscirà di nuovo dal raggio, dovrà essere ricalcolato da zero contro il
# nuovo last_seen, vedi _flush_position). Una cella in-raggio non può mai essere a tier FROZEN (è
# "live", nessun overlay) quindi _frozen_tier_positions.erase è sempre corretto qui, mai
# condizionale.
func _mark_seen_and_invalidate(pos: Vector2i) -> void:
	var _mem_start := Time.get_ticks_usec()
	fog_of_war_memory.mark_seen(pos, _current_absolute_day)
	_memory_lookup_usec += Time.get_ticks_usec() - _mem_start
	_cell_color_cache.erase(pos)
	_frozen_tier_positions.erase(pos)


# Step 3.3 — calcola il delta (entrate/uscite) tra l'insieme in-raggio (source ∪ building) di
# QUESTO giro e quello del giro precedente (_previous_in_radius_positions), marcando dirty SOLO le
# celle che sono davvero cambiate: una cella che resta in raggio per più frame di fila (il caso
# comune durante un movimento continuo) è già trasparente da prima, riscriverla ogni volta
# sarebbe lavoro sprecato — esattamente il costo che questo passo elimina. Chiamato da
# update_visibility() (quando position_changed) e da set_building_visible_positions() (sempre,
# l'insieme edifici può cambiare indipendentemente dalla posizione del player).
func _update_in_radius_dirty_delta() -> void:
	var current_in_radius: Dictionary = {}
	for pos in _source_visible_positions:
		current_in_radius[pos] = true
	for pos in _building_visible_positions:
		current_in_radius[pos] = true
	for pos in current_in_radius:
		if not _previous_in_radius_positions.has(pos):
			_dirty_positions[pos] = true # entrata nel raggio: da trasparente
	for pos in _previous_in_radius_positions:
		if not current_in_radius.has(pos):
			_dirty_positions[pos] = true # uscita dal raggio: da ricalcolare (cache già assente)
	_previous_in_radius_positions = current_in_radius


# Ottimizzazione "splat" (richiesta utente, 2026-09-02 — vedi _source_visible_positions sopra per
# il perché): invece di testare tutte le 10.000 celle contro ogni sorgente, per ciascuna sorgente
# si marcano SOLO le microcelle nel proprio bounding box ±visibility_radius (poi un test di
# distanza vero per scartare gli angoli del quadrato che escono dal cerchio) — O(N × ~113) invece
# di O(10.000 × N). `visible.has(pos): continue` evita di ri-testare una cella già marcata da una
# sorgente precedente (utile quando più sorgenti sono vicine tra loro, es. un gruppo appena nato).
func _splat_source_visible_positions() -> Dictionary:
	var visible: Dictionary = {}
	for source_pos in source_positions:
		var min_x := int(floor(source_pos.x - visibility_radius))
		var max_x := int(ceil(source_pos.x + visibility_radius))
		var min_y := int(floor(source_pos.y - visibility_radius))
		var max_y := int(ceil(source_pos.y + visibility_radius))
		for y in range(maxi(min_y, 0), mini(max_y + 1, World.HEIGHT)):
			for x in range(maxi(min_x, 0), mini(max_x + 1, World.WIDTH)):
				var pos := Vector2i(x, y)
				if visible.has(pos):
					continue
				var cell_center := Vector2(x + 0.5, y + 0.5)
				if cell_center.distance_squared_to(source_pos) <= _radius_squared:
					visible[pos] = true
	return visible


# Confronto per valore (non riferimento): due chiamate consecutive di update_visibility passano
# quasi sempre array NUOVI (GameScene._relevant_source_positions_for_cell ne costruisce uno fresco
# ogni frame), quindi `==` per riferimento non basterebbe mai a riconoscere "stesso contenuto".
# Ordine rilevante (non un confronto per insieme): human_individuals viene iterato sempre nello
# stesso ordine da GameScene, quindi due chiamate con lo stesso contenuto hanno sempre lo stesso
# ordine — nessun bisogno di un confronto più costoso order-independent.
func _positions_equal(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


# Proposta 2: insieme delle posizioni (Vector2i) in cui un individuo di vegetazione sarebbe
# comunque disegnato IN DETTAGLIO da _draw() — usato da GameScene._refresh_resource_visuals per
# filtrare cosa passare al rebuild MultiMesh, invece di costruire un'istanza per OGNI posizione
# anche quando il FoW la coprirebbe comunque. Una posizione FUORI da questo insieme finisce in uno
# dei due tier che nascondono per intero il blob vero, qualunque cosa ci sia sotto:
# FROZEN_OVERLAY_COLOR + hint sintetico (risorse scadute, terreno ancora fresco) o OVERLAY_COLOR
# pieno (anche terreno scaduto) — costruire il vero blob lì è lavoro sprecato. Replica ESATTAMENTE
# la stessa soglia di _draw() (in_radius O risorse fresche — mai bisogno di controllare anche
# "dettaglio fresco" a parte: stesso timestamp, soglia più corta, quindi già incluso quando risorse
# è fresco, vedi FogOfWarMemory._is_within_memory) — un'unica definizione di "visibile in
# dettaglio", mai una seconda copia della logica.
#
# ATTENZIONE ORDINE (bug reale trovato in sessione con l'individuo singolo, "tutto verde alla
# partita nuova" — la classe di bug NON esiste più con source_positions, vedi sotto, ma il
# principio resta): questo metodo legge SEMPRE source_positions così com'è in questo momento — chi
# chiama (GameScene._activate_live_cell) deve quindi aver già passato le posizioni vere tramite
# update_visibility() PRIMA del primo refresh vegetazione di una cella appena attivata, non un
# placeholder. Con lo Step 4 questo è garantito per costruzione (update_visibility() viene chiamato
# subito dopo setup(), sempre con le posizioni reali — non esiste più un binding "vuoto/proxy"
# intermedio come nel vecchio meccanismo a singolo individuo).
func compute_visible_positions(current_absolute_day: int) -> Dictionary:
	var visible: Dictionary = {}
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			var in_radius := _source_visible_positions.has(pos) or _building_visible_positions.has(pos)
			if in_radius:
				visible[pos] = true
				continue
			if fog_of_war_memory != null and fog_of_war_memory.is_resource_fresh(pos, current_absolute_day, resource_memory_days):
				visible[pos] = true
	return visible


func _draw() -> void:
	# TEMPORANEO (diagnostica Step 4 FoW multi-sorgente, vedi DebugLogging.SHOW_FOW_REDRAW_TIMING_
	# LOGS) — misura il costo reale del redraw ora che è guidato dal dirty-tracking (Step 3.3,
	# 2026-09-03) invece di una scansione piena delle 10.000 celle ad ogni giro.
	#
	# AGGIORNAMENTO Step 3.3: la vecchia ripartizione decisione/draw_calls (Step 3.1/3.2) non ha
	# più senso — il grosso del lavoro (mark_seen) non vive più dentro _draw() (vedi
	# update_visibility/set_building_visible_positions/_mark_seen_for_current_in_radius_positions),
	# e il costo per-cella residuo qui dentro è già proporzionale a quante celle sono DAVVERO
	# sporche, non più fisso a 10.000. Il numero comparabile ora è `celle_processate` (nuovo,
	# sotto): quante celle questo redraw ha effettivamente riscritto — durante un movimento
	# continuo ci si aspettano poche decine di celle, non 10.000; su un cambio giorno o un refresh
	# vegetazione (_full_flush_pending) resta 10.000, per costruzione. `memoria` resta
	# _memory_lookup_usec, ora un accumulatore di ISTANZA (vedi campo sopra) che copre anche il
	# lavoro di mark_seen svolto FUORI da questa funzione dall'ultima stampa.
	var _draw_start_usec := Time.get_ticks_usec()

	# Contatore redraw/sec (vedi _redraw_count_this_second sopra) — incrementato qui, PRIMA di
	# qualunque early-out interno a questa funzione (non ce ne sono: se _draw() è stata chiamata,
	# è già un redraw reale, l'unico early-out è a monte in update_visibility()).
	_redraw_count_this_second += 1
	var _now_msec := Time.get_ticks_msec()
	if _now_msec - _redraw_count_window_start_msec >= 1000:
		if DebugLogging.SHOW_FOW_REDRAW_TIMING_LOGS:
			print("[FOW REDRAW COUNT] %d redraw/sec" % _redraw_count_this_second)
		_redraw_count_this_second = 0
		_redraw_count_window_start_msec = _now_msec

	# Step 3.3 — il cuore del dirty-tracking: due percorsi mutuamente esclusivi.
	#   - _full_flush_pending (SOLO cambio giorno dal passo 3.4 in poi — vedi update_visibility,
	#     il refresh vegetazione non lo imposta più): riscrive tutte le 10.000 celle, esattamente
	#     come nei passi 3.1/3.2 — evento raro, il costo resta accettabile (vedi Step 2,
	#     discussione con l'utente sull'upload texture comunque fisso).
	#   - altrimenti: itera SOLO _dirty_positions (il delta in-raggio calcolato da
	#     _update_in_radius_dirty_delta, più le eventuali posizioni potate da mark_positions_dirty)
	#     — il caso comune durante un movimento continuo, quello che questo passo rende economico.
	# _flush_position() sotto contiene la logica per-cella condivisa da entrambi i percorsi
	# (trasparente se in-raggio, altrimenti cache hit/miss sul cascade dei tre tier) — UNA sola
	# definizione, mai duplicata tra i due rami.
	var _cells_processed := 0
	if _full_flush_pending:
		for y in range(World.HEIGHT):
			for x in range(World.WIDTH):
				_flush_position(Vector2i(x, y))
				_cells_processed += 1
		_full_flush_pending = false
	else:
		for pos in _dirty_positions:
			_flush_position(pos)
			_cells_processed += 1
	_dirty_positions.clear()

	_fog_texture.update(_fog_image)
	_hint_layer.queue_redraw()

	if DebugLogging.SHOW_FOW_REDRAW_TIMING_LOGS:
		var elapsed_ms: float = (Time.get_ticks_usec() - _draw_start_usec) / 1000.0
		print("[FOW REDRAW TIMING] totale=%.1fms | celle_processate=%d | memoria=%.1fms | sorgenti=%d" % [
			elapsed_ms, _cells_processed, _memory_lookup_usec / 1000.0, source_positions.size()
		])
		# Resettato QUI (non più a inizio funzione, vedi campo _memory_lookup_usec sopra): questa
		# stampa deve riflettere il lavoro svolto dall'ultima stampa, ovunque sia avvenuto
		# (update_visibility/set_building_visible_positions incluse), non solo dentro _draw().
		_memory_lookup_usec = 0


# Step 3.3 — logica per-cella condivisa dai due percorsi di _draw() sopra (flush pieno o solo
# dirty): decide il pixel corretto per `pos` e lo scrive in _fog_image. Mantiene
# _frozen_tier_positions in sincrono ad ogni ricalcolo di colore (vedi campo sopra) — è l'UNICO
# punto, insieme a _mark_seen_and_invalidate/mark_positions_dirty, che lo scrive, così
# _on_hint_layer_draw può sempre fidarsi che rifletta il tier ATTUALE anche se questa cella non
# viene rivisitata per molti redraw successivi.
#
# AGGIORNAMENTO Step 3.4 (2026-09-03): non calcola più show_hint/_vegetation_presence qui dentro
# — quella decisione è ora interamente di _on_hint_layer_draw (calcolo LIVE, vedi lì), questa
# funzione si occupa solo del colore/tier, mai di vegetazione.
func _flush_position(pos: Vector2i) -> void:
	# In-raggio: trasparente esplicito (vedi TRANSPARENT_COLOR sopra), nessun lookup di memoria —
	# lo stato "live" non passa mai dalla cache/dai tre tier. Una cella in-raggio non arriva mai
	# qui a tier FROZEN in _frozen_tier_positions: _mark_seen_and_invalidate lo rimuove sempre nel
	# momento stesso in cui la cella entra in raggio (vedi lì), quindi nessuna pulizia serve qui.
	if _source_visible_positions.has(pos) or _building_visible_positions.has(pos):
		_fog_image.set_pixel(pos.x, pos.y, TRANSPARENT_COLOR)
		return

	if fog_of_war_memory == null:
		# Nessuna memoria configurata (difensivo, non dovrebbe succedere in pratica): stesso
		# comportamento dello Step 0 — nero pieno (il ramo in-raggio è già coperto sopra).
		_fog_image.set_pixel(pos.x, pos.y, OVERLAY_COLOR)
		return

	# Cache tier/colore (vedi _cell_color_cache sopra) — hit: salta TUTTI e 3 i lookup su
	# FogOfWarMemory, riusa il colore calcolato l'ultima volta (nessun bisogno di ritoccare
	# _frozen_tier_positions: se il colore non è cambiato dall'ultima scrittura, l'appartenenza al
	# tier è già corretta). Miss: calcola come prima (detail -> resource -> terrain -> nero pieno,
	# in cascata, mai più controlli del necessario) e scrive il risultato in cache PLUS
	# _frozen_tier_positions per il prossimo giro.
	var color: Color
	if _cell_color_cache.has(pos):
		color = _cell_color_cache[pos]
	else:
		var _mem_start := Time.get_ticks_usec()
		if fog_of_war_memory.is_detail_fresh(pos, _current_absolute_day, detail_memory_days):
			color = Color(0, 0, 0, recent_overlay_alpha)
		elif fog_of_war_memory.is_resource_fresh(pos, _current_absolute_day, resource_memory_days):
			color = LIGHT_OVERLAY_COLOR
		elif fog_of_war_memory.is_terrain_fresh(pos, _current_absolute_day, terrain_memory_days):
			# true solo nel tier "risorse scadute ma terreno ancora fresco" (60-180gg coi valori
			# reali di FogOfWarRules — vedi _draw_stale_vegetation_hint/_on_hint_layer_draw: è il
			# gradino giusto per mostrare "c'era vegetazione ma non la ricordo più con
			# precisione", non il tier sopra (LIGHT_OVERLAY_COLOR, risorse ANCORA fresche — lì la
			# vegetazione vera resta visibile per intero sotto un velo leggero, nessuna sfocatura
			# necessaria).
			color = FROZEN_OVERLAY_COLOR
		else:
			color = OVERLAY_COLOR
		_memory_lookup_usec += Time.get_ticks_usec() - _mem_start
		_cell_color_cache[pos] = color
		# Membership PERSISTENTE del TIER (vedi _frozen_tier_positions sopra) — sincronizzata in
		# ENTRAMBE le direzioni SOLO qui, dove il colore viene effettivamente ricalcolato (un hit
		# di cache non cambia il colore, quindi non cambia nemmeno l'appartenenza al tier).
		if color == FROZEN_OVERLAY_COLOR:
			_frozen_tier_positions[pos] = true
		else:
			_frozen_tier_positions.erase(pos)

	_fog_image.set_pixel(pos.x, pos.y, color)


# Handler del segnale `draw` di _hint_layer (vedi campo sopra).
#
# AGGIORNAMENTO Step 3.4 (2026-09-03): show_hint non è più un bool cacheato insieme al colore —
# calcolato LIVE ad ogni redraw di questo layer, incrociando _frozen_tier_positions (membership
# persistente del tier, indipendente da _vegetation_presence — vedi campo sopra) con
# _vegetation_presence COSÌ COM'È in questo momento. È esattamente questo disaccoppiamento che
# permette a set_vegetation_presence() di non dover più invalidare _cell_color_cache/
# _dirty_positions per aggiornare gli hint: le uniche celle che possono avere uno show_hint
# diverso da prima sono già tutte e sole quelle in _frozen_tier_positions (il colore non cambia
# mai per un refresh vegetazione, quindi l'insieme stesso non ha bisogno di essere ricalcolato,
# solo riletto contro il nuovo _vegetation_presence). Iterare _frozen_tier_positions invece delle
# 10.000 celle resta comunque necessario per lo stesso motivo del passo 3.3: _draw() non rivisita
# più tutta la griglia ad ogni redraw. Le chiamate draw_circle() restano un passaggio
# immediate-mode indipendente sopra la texture persistente (mai baked nell'Image).
func _on_hint_layer_draw() -> void:
	for pos in _frozen_tier_positions:
		if _vegetation_presence.has(pos):
			_draw_stale_vegetation_hint(_hint_layer, pos)


# Macchia grande e coprente (quasi tutta la cella) + 1-2 accenti più piccoli ai bordi per rompere
# il contorno perfettamente tondo — deterministico (hash di pos, nessun rng), MAI legato a
# sottotipo/età/identità reale di un individuo: a differenza di MicroCellRenderer, questo nodo non
# sa (e non deve sapere) QUALE pianta ci sia, solo che ce n'è "più o meno una", disegnata alla
# bell'e meglio. Sopra FROZEN_OVERLAY_COLOR (ora sulla texture persistente di _fog_sprite, non più
# disegnato da questo stesso metodo).
#
# `target` (Step 3.1): il CanvasItem su cui emettere i draw_circle() — sempre _hint_layer oggi
# (vedi _on_hint_layer_draw), mai `self`: gli hint sono un figlio separato apposta per restare
# sopra la texture nell'ordine di disegno (vedi _hint_layer sopra). Parametro esplicito invece di
# un riferimento fisso a _hint_layer dentro il corpo per tenere questo metodo puro/testabile su
# qualunque CanvasItem, stesso principio già seguito altrove nel file per le funzioni pure.
func _draw_stale_vegetation_hint(target: CanvasItem, pos: Vector2i) -> void:
	var center := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE) + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	var seed: int = hash(pos * 13 + Vector2i(41, 7))

	# Macchia principale: raggio fino a poco più di metà cella, leggermente decentrata — copre la
	# gran parte del tile invece di un pallino decorativo in mezzo al nulla.
	var main_offset := Vector2(
		lerp(-1.5, 1.5, float(hash(seed) % 1000) / 1000.0),
		lerp(-1.5, 1.5, float(hash(seed * 3 + 1) % 1000) / 1000.0)
	)
	var main_radius: float = lerp(4.2, 5.4, float(hash(seed * 7 + 2) % 1000) / 1000.0)
	target.draw_circle(center + main_offset, main_radius, STALE_VEGETATION_BLOB_COLOR)

	var accent_count: int = 1 + (seed % 2) # 1 o 2 accenti
	for i in range(accent_count):
		var salt: int = seed + i * 97
		var angle: float = (float(hash(salt) % 1000) / 1000.0) * TAU
		var distance: float = lerp(2.5, 4.0, float(hash(salt * 5 + 3) % 1000) / 1000.0)
		var accent_radius: float = lerp(1.8, 2.8, float(hash(salt * 9 + 7) % 1000) / 1000.0)
		target.draw_circle(center + Vector2(cos(angle), sin(angle)) * distance, accent_radius, STALE_VEGETATION_BLOB_COLOR)
