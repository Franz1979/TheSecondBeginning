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
var river_positions: Array = []
var river_exterior_occupied: Dictionary = {}

# Mappa SPARSA dei modificatori di movimento (2026-09-19, richiesta utente): SOLO le microcelle che
# deviano dalla norma, Vector2i (microcella) -> Vector2(moltiplicatore stamina, moltiplicatore
# velocità); l'assenza significa (1.0, 1.0). Costruita da MovementTerrainService.rebuild (chiamata da
# GameScene._refresh_building_visuals), mai da chi la interroga. movement_version: numero univoco
# (contatore globale del service) assegnato a ogni ricostruzione — serve al memo di
# HumanIndividual.terrain_cache_version per accorgersi che la mappa è cambiata, anche se la cella è
# stata disattivata e ricreata.
var movement_modifiers: Dictionary = {}
var movement_version: int = 0

# Griglia di pathfinding di QUESTA cella (2026-09-27, pathfinding step 1 — vedi PathfindingService, l'unico che la
# scrive): AStarGrid2D 100x100 (null = non ancora costruita), ostacoli raccolti una volta (path_obstacles), guadi
# (microcella -> true), pesi diversi da 1 (microcella -> peso), id di regione connessa per microcella (indice
# y * World.WIDTH + x, -1 = bloccata) e numero di regioni. path_grid_version cresce a ogni modifica (overlay di debug).
var path_grid: AStarGrid2D = null
var path_obstacles: MicrocellObstacles = null
var path_fords: Dictionary = {}
var path_weights: Dictionary = {}
var path_regions: PackedInt32Array = PackedInt32Array()
var path_region_count: int = 0
var path_grid_version: int = 0
# Specchio dei blocchi della griglia (2026-09-27, step 2): 1 = bloccata, indice y * World.WIDTH + x — letto dal flood
# fill delle regioni senza interrogare l'AStarGrid2D cella per cella. path_regions_dirty: regioni da ricalcolare alla
# prossima get_region (ricalcolo pigro). path_block_version cresce SOLO quando cambia un blocco: i pipottini in cammino
# lo confrontano per ricalcolare il percorso.
var path_solid: PackedByteArray = PackedByteArray()
var path_regions_dirty: bool = true
var path_block_version: int = 0

# Cache del risultato di VegetationPositionService.generate_positions (diagnostica lentezza,
# 2026-08-30) — quella chiamata è deterministica e COSTOSA (~90-190ms/cella): il suo output
# cambia SOLO quando dedicated_space/anno/eccezioni taglio-morte/edifici cambiano DAVVERO, mai per
# il solo spostamento del player. needs_full_vegetation_recompute parte true (forza il primo
# calcolo vero) e viene rimesso a true SOLO da chi sa che uno di questi eventi è successo — vedi
# GameScene._refresh_resource_visuals (consumatore + unico scrittore di cached_vegetation_
# positions), GameScene._on_day_advanced (checkpoint stagionale: crescita/mortalità/encroachment
# possono aver cambiato QUALUNQUE cella viva, anche quelle lontane mai rinfrescate per davvero —
# vedi il flag "prossimità" lì), _on_cut_requested/_place_building_at (evento puntuale su QUESTA
# cella). Un refresh da movimento (nessuno di questi eventi) trova il flag false e riusa
# cached_vegetation_positions senza richiamare generate_positions.
var needs_full_vegetation_recompute: bool = true
# Valore di FogOfWarRenderer.visible_set_version letto dall'ULTIMO _refresh_resource_visuals di questa cella
# (2026-09-20): il refresh da movimento in GameScene._process parte solo se la versione corrente e' diversa,
# cioe' se dall'ultimo refresh e' comparsa almeno una cella visibile nuova (o e' cambiato il giorno). -1 =
# mai rinfrescata: il primo confronto differisce sempre.
var last_refresh_visible_version: int = -1
# Ultimo insieme "visibile in dettaglio" del fog of war calcolato da GameScene._refresh_resource_visuals (2026-10-03,
# richiesta utente): lo riusa il ridisegno leggero dopo una raccolta (_refresh_collected_resource_visuals) senza
# ripassare le 10.000 microcelle. null = mai calcolato (o cella senza FogOfWarRenderer).
var last_visible_positions: Variant = null
var cached_vegetation_positions: Dictionary = {}

# Cache del ratio disponibilità "fruit stock" per lotto (2026-09-17, richiesta utente —
# ottimizzazione: GameScene._refresh_resource_visuals ricostruiva questo Dictionary da zero a
# OGNI refresh, iterando l'intero shrub_claimed_lots della macrocella — mai svuotato, quindi
# crescente per l'intera sessione — anche quando stock/composizione non erano cambiati dall'ultimo
# refresh, segnalato dall'utente come causa di scatti; GENERALIZZATO lo stesso giorno per risorsa,
# in preparazione di fruit/acorn — nessun cambio di comportamento per berry). Entrambi ANNIDATI
# per resource_name (oggi solo "berry", vedi TerrainScatteredResourceService.FRUIT_STOCK_SOURCES):
# cached_berry_ratio_by_lot[resource_name] è il Dictionary[Vector2i, float] passato l'ultima volta
# al renderer per quella risorsa; last_berry_signature[resource_name] è l'ultima firma leggera
# (TerrainScatteredResourceService.get_fruit_stock_recompute_signature) con cui è stato calcolato —
# se la firma corrente coincide, GameScene riusa il Dictionary di quella risorsa senza
# ricostruirlo né richiamare MicroCellRenderer.set_fruit_stock_available_ratio_by_lot. Entrambi
# vuoti di default: una risorsa mai vista in last_berry_signature non coincide mai con una firma
# reale (che ha sempre 4 elementi), quindi il primo refresh forza sempre il primo calcolo vero per
# quella risorsa, stesso principio di needs_full_vegetation_recompute.
var cached_berry_ratio_by_lot: Dictionary = {}
var last_berry_signature: Dictionary = {}


func coords() -> Vector2i:
	return Vector2i(macro_x, macro_y)
