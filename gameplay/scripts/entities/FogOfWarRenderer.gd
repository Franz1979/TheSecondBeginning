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

@export var visibility_radius: float = 6.0 # microcelle
# Overlay minimo per lo stato "ricordo recente ma non più in vista ora" (fuori dal raggio, ma
# ancora entro detail_memory_days) — @export separato (non un const come gli altri tre colori
# sopra) perché è il valore più speculativo, il più probabile da ritarare a vista una volta
# provato in editor.
@export var recent_overlay_alpha: float = 0.1

# Tre soglie di decadimento, qui e non su FogOfWarMemory per lo stesso motivo di
# visibility_radius sopra: sono soglie di percezione/gameplay (in futuro modificabili da
# tech/edifici, Step 4), la memoria resta agnostica sul perché di questi numeri. Ordine
# crescente per design (detail < resource < terrain — il tipo di terreno si dimentica più
# lentamente delle risorse, che a loro volta durano più delle posizioni esatte/entità in
# movimento): valori di partenza, pensati esplicitamente come parametri di bilanciamento da
# ritarare più avanti, specialmente quando i modificatori tech dello Step 4 allungheranno
# ulteriormente terrain_memory_days.
@export var detail_memory_days: int = 10
@export var resource_memory_days: int = 30
@export var terrain_memory_days: int = 90

var individual: Individual
var fog_of_war_memory: FogOfWarMemory

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
	_radius_squared = visibility_radius * visibility_radius
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


func _draw() -> void:
	if individual == null:
		return

	var center := individual.position
	for y in range(World.HEIGHT):
		for x in range(World.WIDTH):
			var pos := Vector2i(x, y)
			var cell_center := Vector2(x + 0.5, y + 0.5)
			var in_radius := cell_center.distance_squared_to(center) <= _radius_squared

			if fog_of_war_memory == null:
				# Nessuna memoria configurata (difensivo, non dovrebbe succedere in pratica):
				# stesso comportamento dello Step 0, nessun overlay dentro il raggio, nero pieno
				# fuori — nessuna interpretazione a tier possibile senza memoria da consultare.
				if not in_radius:
					draw_rect(Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE), OVERLAY_COLOR)
				continue

			if in_radius:
				# Dentro il raggio ORA: "live", nessun overlay — controllo ESPLICITO, non più
				# dedotto da is_detail_fresh (vedi FIX in testa al file). La vista aggiorna la
				# memoria nello stesso passaggio in cui poi valutiamo i tier per le altre celle —
				# singolo loop sulla griglia invece di due, stesso principio "calcola e aggiorna
				# la cache in un solo giro" già usato da MicroCellRenderer._rebuild_tree_multimeshes.
				fog_of_war_memory.mark_seen(pos, _current_absolute_day)
				continue # nessun overlay

			if fog_of_war_memory.is_detail_fresh(pos, _current_absolute_day, detail_memory_days):
				draw_rect(
					Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
					Color(0, 0, 0, recent_overlay_alpha)
				)
				continue

			var color := OVERLAY_COLOR
			if fog_of_war_memory.is_resource_fresh(pos, _current_absolute_day, resource_memory_days):
				color = LIGHT_OVERLAY_COLOR
			elif fog_of_war_memory.is_terrain_fresh(pos, _current_absolute_day, terrain_memory_days):
				color = FROZEN_OVERLAY_COLOR
			draw_rect(
				Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE),
				color
			)
