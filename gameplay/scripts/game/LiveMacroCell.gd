class_name LiveMacroCell
extends RefCounted

# Bundle di tutto ciò che serve per render/simulare UNA macrocella "viva" in GameScene (streaming
# multi-cella: il centro dove si trova il player + al più un vicino cardinale nella direzione di
# avvicinamento, mai gli 8 circostanti — vedi GameScene.live_cells/_activate_live_cell). Nessuna
# delle classi Node referenziate qui (MicroCellRenderer/AnimalGroupRenderer/FogOfWarRenderer) è
# mai stata resa "consapevole" di più celle: ogni cella viva ha semplicemente la propria istanza
# INTERA di ciascuna, tutte figlie di `container` (un Node2D posizionato con l'offset macro della
# cella rispetto al centro corrente — vedi GameScene._reposition_live_cells), esattamente come se
# fosse l'unica cella della scena. È questo bundle, non le classi di rendering, a rendere GameScene
# multi-cella.

var macro_x: int
var macro_y: int
var macro_cell: MacroCellData
var macro_state: MacroCellState
var world: World # micro-mondo locale uniforme di QUESTA cella (100x100 microcelle)
var container: Node2D # genitore posizionato via offset; renderer/animali/fog sono suoi figli
var renderer: MicroCellRenderer
var animal_renderers: Dictionary = {} # species_name (String) -> AnimalGroupRenderer
var fog_of_war_renderer: FogOfWarRenderer
var fog_of_war_memory: FogOfWarMemory
# FogOfWarRenderer legge SEMPRE individual.position direttamente (setup() ne tiene un riferimento,
# mai una posizione passata a parte) — corretto per la cella CENTRALE, dove quello spazio locale
# è esattamente lo spazio di individual.position per definizione. Per una cella vicina viva, quella
# stessa posizione andrebbe tradotta nel suo spazio locale (sottraendo l'offset macro) — dato che
# FogOfWarRenderer/Individual non vanno toccati, questo "individuo ombra" (solo `.position`
# aggiornato ogni frame da GameScene, mai selezionato/mosso/letto da nessun altro) è il modo per
# darglielo senza cambiare la classe. Creato per OGNI cella (anche il centro, dove resta
# inutilizzato) per semplicità — vedi GameScene._rebind_fog_bindings per quale individuo (vero o
# ombra) viene davvero legato a fog_of_war_renderer, e GameScene._process per l'aggiornamento.
var fog_proxy_individual: Individual
var river_positions: Array = []
var river_exterior_occupied: Dictionary = {}


func coords() -> Vector2i:
	return Vector2i(macro_x, macro_y)
