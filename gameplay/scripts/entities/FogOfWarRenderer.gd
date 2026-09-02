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

# Vector2i -> true, SOLO per le microcelle con almeno un individuo TREE/SHRUB — vedi
# set_vegetation_presence/_draw_stale_vegetation_hint. Aggiornato da GameScene ogni volta che
# rigenera la vegetazione (attivazione cella o checkpoint stagionale) — sì, quindi con lo stesso
# ritardo di tutto il resto della vegetazione, ma qui va bene: serve solo "c'è più o meno
# vegetazione qui", non l'identità precisa di un singolo individuo, e le posizioni sono comunque
# stabili da un checkpoint all'altro (vedi ResourcePositionService, prefix-stabile). A differenza
# di "questo individuo preciso è ancora quello che ricordo", che dipende dal movimento del player
# minuto per minuto — per questo quella domanda NON vive più in MicroCellRenderer (vedi la
# discussione che ha portato a spostare l'Opzione B qui): qui il decadimento resta guidato dallo
# stesso ciclo per-frame di tutto il resto di questo renderer, mai dal rebuild a checkpoint.
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

# Vector2i -> {"color": Color, "show_hint": bool}: cache del tier/colore per le celle FUORI dal
# raggio splat (misurato 2026-09-02, richiesta utente: dentro "decisione" i lookup su
# FogOfWarMemory — is_detail_fresh/is_resource_fresh/is_terrain_fresh, fino a 3 per cella —
# dominavano davvero, 16-20ms su 21-25ms). Una cella fuori raggio ha un tier che dipende SOLO da
# (last_seen_by_position.get(pos), giorno corrente) — se nessuna delle due è cambiata dall'ultimo
# calcolo per quella cella, il risultato cacheato resta valido per costruzione, niente altro nel
# codice tocca last_seen_by_position/_vegetation_presence al di fuori dei tre punti che invalidano
# sotto. Popolamento PIGRO (mai precalcolata per l'intera griglia): _draw() la consulta, e se
# assente calcola come prima e la scrive lì per il prossimo giro. Le celle IN_RADIUS non la
# consultano mai (il loro esito, "live", non passa mai da qui).
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
	queue_redraw()


# Chiamato da GameScene._refresh_resource_visuals con le stesse vegetation_positions appena date
# a MicroCellRenderer.set_vegetation_positions — Vector3i (TREE/SHRUB) ridotto a Vector2i (lotto),
# GRASS escluso apposta (nessuna identità individuale da nascondere lì, vedi VegetationPositionService).
func set_vegetation_presence(positions: Dictionary) -> void:
	_vegetation_presence.clear()
	for individual_key in positions.get(GameTypes.WorldObjectType.TREE, []):
		_vegetation_presence[Vector2i(individual_key.x, individual_key.y)] = true
	for individual_key in positions.get(GameTypes.WorldObjectType.SHRUB, []):
		_vegetation_presence[Vector2i(individual_key.x, individual_key.y)] = true
	# Clear totale della cache tier/colore (vedi _cell_color_cache) — show_hint dipende da
	# _vegetation_presence appena riscritta sopra, un'entry cacheata potrebbe portarsi dietro un
	# hint stantio. Riassegnazione a {} (O(1), non un loop di erase) — evento non frequente
	# (refresh vegetazione), stesso principio già usato per il cambio giorno in update_visibility().
	_cell_color_cache = {}
	queue_redraw()


func set_building_visible_positions(positions: Dictionary) -> void:
	_building_visible_positions = positions
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
	if day_changed:
		_cell_color_cache = {}
	queue_redraw()


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
	# LOGS) — misura il costo reale del ciclo da 10.000 celle ora che in_radius è un lookup O(1) su
	# _source_visible_positions (splat pre-calcolato, vedi update_visibility) invece di un test a
	# N vie ripetuto per cella — confronto prima/dopo quell'ottimizzazione.
	#
	# Timing SEPARATO per fase (richiesta utente, 2026-09-02 — il miglioramento totale dallo splat
	# è stato modesto, va isolato quanto viene da "decidere" (in_radius/tier/colore per cella,
	# _decision_usec) contro quanto viene dalle chiamate draw_rect/draw_circle stesse
	# (_draw_call_usec, Godot immediate-mode — se questo secondo numero domina, non è la logica di
	# decisione a essere il collo di bottiglia, è il NUMERO di chiamate di disegno). Nessuna
	# modifica di logica qui sotto, solo `Time.get_ticks_usec()` attorno ai due tipi di lavoro.
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
	var _decision_usec := 0
	var _draw_call_usec := 0
	# Sotto-fetta di _decision_usec (richiesta utente, 2026-09-02 — isolare i lookup su
	# FogOfWarMemory, fino a 3 per cella — is_detail_fresh/is_resource_fresh/is_terrain_fresh, ognuno
	# un dictionary lookup con chiave Vector2i — dal resto del lavoro di decisione, che è solo gli
	# 2 lookup O(1) sullo splat/edifici per in_radius + branching/assegnazione colore, tutto molto
	# più leggero).
	var _memory_lookup_usec := 0
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var _phase_start := Time.get_ticks_usec()
			var pos := Vector2i(x, y)
			# "live" ora include anche le microcelle coperte dal raggio di un edificio (vedi
			# _building_visible_positions sopra) — stesso trattamento O(1) di _source_visible_
			# positions sopra (splat pre-calcolato per QUALUNQUE sorgente, vedi update_visibility).
			var in_radius := _source_visible_positions.has(pos) or _building_visible_positions.has(pos)

			if fog_of_war_memory == null:
				# Nessuna memoria configurata (difensivo, non dovrebbe succedere in pratica):
				# stesso comportamento dello Step 0, nessun overlay dentro il raggio, nero pieno
				# fuori — nessuna interpretazione a tier possibile senza memoria da consultare.
				_decision_usec += Time.get_ticks_usec() - _phase_start
				if not in_radius:
					var _draw_call_start := Time.get_ticks_usec()
					draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), OVERLAY_COLOR)
					_draw_call_usec += Time.get_ticks_usec() - _draw_call_start
				continue

			if in_radius:
				# Dentro il raggio ORA (player o edificio): "live", nessun overlay — controllo
				# ESPLICITO, non più dedotto da is_detail_fresh (vedi FIX in testa al file). La
				# vista aggiorna la memoria nello stesso passaggio in cui poi valutiamo i tier per
				# le altre celle — singolo loop sulla griglia invece di due, stesso principio
				# "calcola e aggiorna la cache in un solo giro" già usato da MicroCellRenderer.
				# _rebuild_tree_multimeshes.
				var _mem_start := Time.get_ticks_usec()
				fog_of_war_memory.mark_seen(pos, _current_absolute_day)
				_memory_lookup_usec += Time.get_ticks_usec() - _mem_start
				# Invalidazione MIRATA (vedi _cell_color_cache sopra): questo è l'UNICO momento in
				# cui last_seen_by_position[pos] di questa cella cambia — qualunque tier fosse
				# cacheato da prima è ora stantio (quando la cella uscirà di nuovo dal raggio,
				# dovrà essere ricalcolato da zero contro il nuovo last_seen). Costo limitato alle
				# sole celle nel raggio splat (~113×N), non alle 10.000.
				_cell_color_cache.erase(pos)
				_decision_usec += Time.get_ticks_usec() - _phase_start
				continue # nessun overlay

			# Cache tier/colore (vedi _cell_color_cache sopra) — hit: salta TUTTI e 3 i lookup su
			# FogOfWarMemory, riusa color/show_hint calcolati l'ultima volta. Miss: calcola come
			# prima (detail -> resource -> terrain -> nero pieno, in cascata, mai più controlli del
			# necessario) e scrive il risultato in cache per il prossimo giro.
			var color: Color
			var show_stale_vegetation_hint := false
			if _cell_color_cache.has(pos):
				var cached: Dictionary = _cell_color_cache[pos]
				color = cached["color"]
				show_stale_vegetation_hint = cached["show_hint"]
				_decision_usec += Time.get_ticks_usec() - _phase_start
			else:
				var _mem_start2 := Time.get_ticks_usec()
				if fog_of_war_memory.is_detail_fresh(pos, _current_absolute_day, detail_memory_days):
					color = Color(0, 0, 0, recent_overlay_alpha)
				elif fog_of_war_memory.is_resource_fresh(pos, _current_absolute_day, resource_memory_days):
					color = LIGHT_OVERLAY_COLOR
				elif fog_of_war_memory.is_terrain_fresh(pos, _current_absolute_day, terrain_memory_days):
					# true solo nel tier "risorse scadute ma terreno ancora fresco" (60-180gg con i
					# valori di default in FogOfWarRules) — vedi _draw_stale_vegetation_hint: è il
					# gradino giusto per mostrare "c'era vegetazione ma non la ricordo più con
					# precisione", non il tier sopra (LIGHT_OVERLAY_COLOR, risorse ANCORA fresche —
					# lì la vegetazione vera resta visibile per intero sotto un velo leggero,
					# nessuna sfocatura necessaria).
					color = FROZEN_OVERLAY_COLOR
					show_stale_vegetation_hint = _vegetation_presence.has(pos)
				else:
					color = OVERLAY_COLOR
				_memory_lookup_usec += Time.get_ticks_usec() - _mem_start2
				_cell_color_cache[pos] = {"color": color, "show_hint": show_stale_vegetation_hint}
				_decision_usec += Time.get_ticks_usec() - _phase_start

			var _draw_call_start2 := Time.get_ticks_usec()
			draw_rect(
				Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
				color
			)
			if show_stale_vegetation_hint:
				_draw_stale_vegetation_hint(pos)
			_draw_call_usec += Time.get_ticks_usec() - _draw_call_start2

	if DebugLogging.SHOW_FOW_REDRAW_TIMING_LOGS:
		var elapsed_ms: float = (Time.get_ticks_usec() - _draw_start_usec) / 1000.0
		print("[FOW REDRAW TIMING] totale=%.1fms | decisione=%.1fms (memoria=%.1fms) | draw_calls=%.1fms | sorgenti=%d" % [
			elapsed_ms, _decision_usec / 1000.0, _memory_lookup_usec / 1000.0, _draw_call_usec / 1000.0, source_positions.size()
		])


# Macchia grande e coprente (quasi tutta la cella) + 1-2 accenti più piccoli ai bordi per rompere
# il contorno perfettamente tondo — deterministico (hash di pos, nessun rng), MAI legato a
# sottotipo/età/identità reale di un individuo: a differenza di MicroCellRenderer, questo nodo non
# sa (e non deve sapere) QUALE pianta ci sia, solo che ce n'è "più o meno una", disegnata alla
# bell'e meglio. Sopra FROZEN_OVERLAY_COLOR, già disegnato dal chiamante prima di questa chiamata.
func _draw_stale_vegetation_hint(pos: Vector2i) -> void:
	var center := Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE) + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	var seed: int = hash(pos * 13 + Vector2i(41, 7))

	# Macchia principale: raggio fino a poco più di metà cella, leggermente decentrata — copre la
	# gran parte del tile invece di un pallino decorativo in mezzo al nulla.
	var main_offset := Vector2(
		lerp(-1.5, 1.5, float(hash(seed) % 1000) / 1000.0),
		lerp(-1.5, 1.5, float(hash(seed * 3 + 1) % 1000) / 1000.0)
	)
	var main_radius: float = lerp(4.2, 5.4, float(hash(seed * 7 + 2) % 1000) / 1000.0)
	draw_circle(center + main_offset, main_radius, STALE_VEGETATION_BLOB_COLOR)

	var accent_count: int = 1 + (seed % 2) # 1 o 2 accenti
	for i in range(accent_count):
		var salt: int = seed + i * 97
		var angle: float = (float(hash(salt) % 1000) / 1000.0) * TAU
		var distance: float = lerp(2.5, 4.0, float(hash(salt * 5 + 3) % 1000) / 1000.0)
		var accent_radius: float = lerp(1.8, 2.8, float(hash(salt * 9 + 7) % 1000) / 1000.0)
		draw_circle(center + Vector2(cos(angle), sin(angle)) * distance, accent_radius, STALE_VEGETATION_BLOB_COLOR)
