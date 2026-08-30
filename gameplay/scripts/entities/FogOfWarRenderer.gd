class_name FogOfWarRenderer
extends Node2D

# Step 3 (con fix) della fog of war: decadimento MULTI-LIVELLO (tre tier, velocità diverse)
# oltre alla persistenza (FogOfWarMemory) e al calcolo geometrico per-frame — ancora NESSUN
# modificatore esterno (tech/edifici/gossip: Step 4). Cinque gradazioni di overlay:
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
# reali del mondo. La fog invece deve aggiornarsi ad ogni frame in cui l'individuo si muove —
# tenerla qui evita di forzare un redraw dell'intera griglia terreno/vegetazione solo perché il
# player ha fatto un passo. Deve essere l'ULTIMO figlio aggiunto in GameScene (l'ordine dei figli
# è l'ordine di disegno in Godot 2D): sopra renderer/animali/IndividualView, così l'overlay
# copre davvero tutto quello che nasconde.
#
# raggio come campo di QUESTO nodo, non di Individual: la percezione è un concetto di
# rendering/gameplay (in futuro dipenderà da tech/edifici/modificatori esterni), Individual resta
# puro stato di posizione/movimento/selezione — stesso principio già applicato per
# IndividualView/IndividualController.
#
# FogOfWarMemory è posseduta da GameScene (non da questo renderer) e passata qui via setup() —
# vedi FogOfWarMemory.gd per il perché (un futuro step di persistenza su save dovrà passarla a
# GameSaveService/GameLoadService come già fa con game_data/world, mai scavando nello stato
# interno di un renderer).

const CELL_SIZE: int = 10 # stesso fattore pixel/microcella di MicroCellRenderer/IndividualView

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

var individual: Individual
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

# Sentinel (mai valori validi) per forzare il primo _draw() anche se l'individuo non si è
# ancora mosso e il giorno non è ancora avanzato — vedi update_visibility().
var _last_drawn_center: Vector2 = Vector2(INF, INF)
var _last_drawn_absolute_day: int = -1
# Usato dentro _draw() per mark_seen — sempre in sync con _last_drawn_absolute_day (valorizzato
# insieme, mai altrove), tenuto separato solo per chiarezza di lettura in _draw().
var _current_absolute_day: int = -1
var _radius_squared: float = 0.0


func setup(p_individual: Individual, p_fog_of_war_memory: FogOfWarMemory) -> void:
	individual = p_individual
	fog_of_war_memory = p_fog_of_war_memory
	# Ri-letta ad ogni setup() (non solo alla creazione del nodo): FogOfWarCalculator cachea già il
	# caricamento, quindi rileggere qui è economico e garantisce che un cambio del .tres a runtime
	# (o un futuro moltiplicatore da tech, vedi FogOfWarRules) si propaghi al prossimo cambio di
	# centro (GameScene._rebind_fog_bindings) senza bisogno di un canale di aggiornamento a parte.
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
	queue_redraw()


func set_building_visible_positions(positions: Dictionary) -> void:
	_building_visible_positions = positions
	queue_redraw()


# Da chiamare ogni frame da GameScene._process, DOPO che il movimento dell'individuo è stato
# applicato (stessa posizione fresca che vedrà anche IndividualView questo frame). Early-out se
# né la posizione né il giorno sono cambiati dall'ultimo redraw — il caso comune "player fermo,
# stesso giorno" non ridisegna nulla, non solo non ricalcola: queue_redraw() stesso non viene
# proprio chiamato.
#
# Il giorno, non solo la posizione, fa scattare il redraw: senza questo, un player fermo per
# più giorni marcherebbe last_seen_by_position una volta sola (al giorno di arrivo) invece di
# continuare ad aggiornarlo ogni giorno in cui sta davvero ancora osservando quelle celle —
# essenziale ora che le tre soglie di decadimento confrontano proprio questo timestamp: senza
# il refresh giornaliero, restare fermi troppo a lungo farebbe scadere per errore anche i tier
# più veloci (detail/resource) sulle celle sotto i propri piedi.
func update_visibility(current_absolute_day: int) -> void:
	if individual == null:
		return
	var position_changed := individual.position != _last_drawn_center
	var day_changed := current_absolute_day != _last_drawn_absolute_day
	if not position_changed and not day_changed:
		return
	_last_drawn_center = individual.position
	_last_drawn_absolute_day = current_absolute_day
	_current_absolute_day = current_absolute_day
	queue_redraw()


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
# ATTENZIONE ORDINE (bug reale trovato in sessione, "tutto verde alla partita nuova"): `individual`
# deve essere già il vero Individual del player (via setup(), vedi GameScene._rebind_fog_bindings),
# non il fog_proxy_individual di default con cui ogni cella viva viene inizialmente legata in
# _activate_live_cell — chiamare questo metodo PRIMA di _rebind_fog_bindings() per la cella
# centrale calcolerebbe "visibile" attorno a una posizione placeholder (Vector2.ZERO), nascondendo
# tutto vicino alla vera posizione di spawn del player. Vedi GameScene._ready(), dove la cella
# centrale viene ri-rinfrescata subito DOPO _rebind_fog_bindings() apposta per questo.
func compute_visible_positions(current_absolute_day: int) -> Dictionary:
	var visible: Dictionary = {}
	if individual == null:
		return visible
	var center := individual.position
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			var cell_center := Vector2(x + 0.5, y + 0.5)
			var in_radius := cell_center.distance_squared_to(center) <= _radius_squared or _building_visible_positions.has(pos)
			if in_radius:
				visible[pos] = true
				continue
			if fog_of_war_memory != null and fog_of_war_memory.is_resource_fresh(pos, current_absolute_day, resource_memory_days):
				visible[pos] = true
	return visible


func _draw() -> void:
	if individual == null:
		return

	var center := individual.position
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			var cell_center := Vector2(x + 0.5, y + 0.5)
			# "live" ora include anche le microcelle coperte dal raggio di un edificio (vedi
			# _building_visible_positions sopra) — stesso identico trattamento del raggio del
			# player, indipendente da dove si trovi il player in questo momento.
			var in_radius := cell_center.distance_squared_to(center) <= _radius_squared or _building_visible_positions.has(pos)

			if fog_of_war_memory == null:
				# Nessuna memoria configurata (difensivo, non dovrebbe succedere in pratica):
				# stesso comportamento dello Step 0, nessun overlay dentro il raggio, nero pieno
				# fuori — nessuna interpretazione a tier possibile senza memoria da consultare.
				if not in_radius:
					draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), OVERLAY_COLOR)
				continue

			if in_radius:
				# Dentro il raggio ORA (player o edificio): "live", nessun overlay — controllo
				# ESPLICITO, non più dedotto da is_detail_fresh (vedi FIX in testa al file). La
				# vista aggiorna la memoria nello stesso passaggio in cui poi valutiamo i tier per
				# le altre celle — singolo loop sulla griglia invece di due, stesso principio
				# "calcola e aggiorna la cache in un solo giro" già usato da MicroCellRenderer.
				# _rebuild_tree_multimeshes.
				fog_of_war_memory.mark_seen(pos, _current_absolute_day)
				continue # nessun overlay

			if fog_of_war_memory.is_detail_fresh(pos, _current_absolute_day, detail_memory_days):
				draw_rect(
					Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
					Color(0, 0, 0, recent_overlay_alpha)
				)
				continue

			var color := OVERLAY_COLOR
			# true solo nel tier "risorse scadute ma terreno ancora fresco" (60-180gg con i valori
			# di default in FogOfWarRules) — vedi _draw_stale_vegetation_hint: è il gradino giusto
			# per mostrare "c'era vegetazione ma non la ricordo più con precisione", non quello
			# subito sopra (LIGHT_OVERLAY_COLOR, risorse ANCORA fresche — lì la vegetazione vera
			# resta visibile per intero sotto un velo leggero, nessuna sfocatura necessaria).
			var show_stale_vegetation_hint := false
			if fog_of_war_memory.is_resource_fresh(pos, _current_absolute_day, resource_memory_days):
				color = LIGHT_OVERLAY_COLOR
			elif fog_of_war_memory.is_terrain_fresh(pos, _current_absolute_day, terrain_memory_days):
				color = FROZEN_OVERLAY_COLOR
				show_stale_vegetation_hint = _vegetation_presence.has(pos)
			draw_rect(
				Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
				color
			)
			if show_stale_vegetation_hint:
				_draw_stale_vegetation_hint(pos)


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
