class_name World

const WIDTH: int = 100
const HEIGHT: int = 100

var cells: Array[MacroCellData] = []
var cell_states: Array[MacroCellState] = []
# Popolazioni animali "vere" (rabbit/deer) — world-level, non più proprietà della singola
# macrocella (vedi PopulationGroup). Ogni gruppo ha un Territory (vedi Territory.gd) di dimensione
# fissa scelta alla creazione (1 cella per rabbit, min_territory_cells celle via BFS per deer,
# vedi TerritoryBuilderService) — nessuna espansione/restringimento nel tempo ancora.
var population_groups: Array[PopulationGroup] = []
# Prossimo id progressivo da assegnare a un PopulationGroup appena creato (vedi
# allocate_population_group_id sotto) — permette a più gruppi della stessa specie di coesistere
# (es. due popolazioni rabbit in celle diverse) restando distinguibili nei log/pannello Fauna
# tramite un ID stabile per tutta la vita del gruppo, invece di un indice ricalcolato ogni volta
# che si mostra l'elenco. Persistito nei save solo indirettamente: GameLoadService lo ricalcola
# da max(id caricati)+1 dopo il caricamento, nessun campo dedicato nel JSON necessario.
var next_population_group_id: int = 1

# species_name -> contatore incrementato ogni volta che un territorio DI QUELLA SPECIE si libera
# davvero (un gruppo si estingue, vedi remove_extinct_population_groups sotto, o si contrae, vedi
# TerritoryDynamicsService._contract_by_one_cell) — mai su nascite/morti-senza-estinzione/split/
# espansioni, che non liberano nulla per un rivale della stessa specie in cerca di spazio. Letto da
# PopulationGroup.blocked_territory_search_version (vedi AnimalHungerService._attempt_expansion/
# TerritoryDynamicsService._update_group_territory) per evitare di ripetere una BFS costosa
# (TerritoryBuilderService.find_nearest_free_cell/expand_by_one_cell, più uno scan O(gruppi) su
# _collect_species_occupied_cells) ogni giorno per un gruppo già accertato bloccato, se nel
# frattempo nessun territorio della sua specie si è liberato da nessuna parte sulla mappa — non
# persistito nei save (puro dato di cache/ottimizzazione, mai storia reale: perderlo al
# caricamento costa al più un nuovo tentativo completo per i gruppi già bloccati al primo
# checkpoint dopo il load, poi il meccanismo si riallinea da solo).
var species_territory_release_version: Dictionary = {}

# Stato di focus del LOD (Parte B, Punto 2 — vedi LODOrchestrator), persistente per la durata
# della sessione ma MAI salvato: risultato di set_focus_region (le stesse 4 chiavi
# level_2_groups/level_1_groups/level_2_count_by_species/level_1_count_by_species), impostato da
# MacroCellScene all'apertura e azzerato alla chiusura (vedi _exit_tree lì). Dictionary VUOTO
# ({}) = nessun focus attivo (vista mondo, comportamento di oggi: nessuna distinzione di livello)
# — sentinella sicura perché set_focus_region valorizza sempre le sue 4 chiavi, anche con array
# vuoti dentro, quindi un {} senza chiavi non è mai confondibile con una classificazione reale.
# Stessa natura di species_territory_release_version sopra: puro dato di cache/sessione, mai
# storia di partita, non persistito nei save. Consumato da WorldTimeService (esclusione consumo/
# fame giornalieri) e ricalcolato periodicamente da WorldTimeService._run_lod_focus_refresh_
# checkpoint (vedi lod_focus_region sotto per l'input persistito necessario a quel ricalcolo).
var lod_focus_state: Dictionary = {}

# Region passata l'ultima volta a LODOrchestrator.set_focus_region — impostata da MacroCellScene
# insieme a lod_focus_state sopra, stessa natura (cache di sessione, mai salvata). Serve perché
# lod_focus_state non è più un calcolo "usa e getta" fatto una sola volta all'apertura della
# macrocella: WorldTimeService lo ricalcola periodicamente (ad ogni checkpoint stagionale) per
# accorgersi di nuovi PopulationGroup nati da split nel frattempo, e per farlo deve rieseguire
# set_focus_region con la STESSA region di partenza, senza doverla far ripassare ogni volta da
# MacroCellScene. Valore di default (Rect2i() = tutto zero) mai letto quando lod_focus_state è
# vuoto — nessuna ambiguità: l'unico sentinel "focus attivo o no" resta lod_focus_state.is_empty().
var lod_focus_region: Rect2i = Rect2i()

func allocate_population_group_id() -> int:
	var id := next_population_group_id
	next_population_group_id += 1
	return id


func release_species_territory(species_name: String) -> void:
	species_territory_release_version[species_name] = int(species_territory_release_version.get(species_name, 0)) + 1


func generate_empty_world() -> void:
	cells.clear()
	cell_states.clear()
	population_groups.clear()
	next_population_group_id = 1
	species_territory_release_version.clear()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cells.append(cell)
			cell_states.append(MacroCellState.new(x, y))

	print("Tipo mappa selezionato: ", GameSettings.selected_map_type)
	if GameSettings.selected_map_type == "random":
		var generator := RandomMapGenerator.new()
		generator.generate(self)
	elif GameSettings.selected_map_type == "island":
		var generator := PresetMapGenerator.new()
		generator.generate_island(self)
	elif GameSettings.selected_map_type == "valley":
		print("Mappa valle non ancora disponibile")
	elif GameSettings.selected_map_type == "mountain":
		print("Mappa montagna non ancora disponibile")
	elif GameSettings.selected_map_type == "empty":
		# MacroCellData._init lascia biome a NONE di default — GRASSLAND è un punto di partenza
		# molto più sensato per una mappa vuota da dipingere a mano nel Map Editor (stesso bioma
		# neutro già usato da RandomMapGenerator), invece di lasciare ogni cella mai ridipinta
		# bloccata a NONE (vedi MapEditorScene: il reset automatico del bioma ad ogni cambio
		# pennello rendeva facilissimo dimenticarsi di ridipingerlo altrove).
		for cell in cells:
			cell.biome = GameTypes.Biome.GRASSLAND
		print("Mappa vuota creata")
	print("World generated. Cells: ", cells.size())

func generate_uniform_terrain(
	terrain_base: GameTypes.TerrainBase,
	water_type: GameTypes.WaterType,
	coast_type: GameTypes.CoastType = GameTypes.CoastType.NONE
) -> void:
	cells.clear()
	cell_states.clear()
	population_groups.clear()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cell.terrain_base = terrain_base
			cell.water_type = water_type
			cell.coast_type = coast_type
			cells.append(cell)
			cell_states.append(MacroCellState.new(x, y))

func get_cell_at(x: int, y: int) -> MacroCellData:
	var index := y * WIDTH + x
	if index < 0 or index >= cells.size():
		return null
	var cell := cells[index]
	if cell.x != x or cell.y != y:
		return null
	return cell


func get_cell_state_at(x: int, y: int) -> MacroCellState:
	var index := y * WIDTH + x
	if index < 0 or index >= cell_states.size():
		return null
	var state := cell_states[index]
	if state.x != x or state.y != y:
		return null
	return state

# Stesso ruolo di get_cell_at/get_cell_state_at: fetch sempre tramite questi helper, mai a
# mano iterando population_groups altrove. null se nessun gruppo di quella specie occupa quella
# macrocella. territory.contains() (non un confronto diretto sulla singola cella) è già la query
# semanticamente corretta anche in vista del multi-cella futuro (Step 5+): oggi degenera
# comunque in un confronto su un solo elemento.
func find_population_group(species_name: String, coords: Vector2i) -> PopulationGroup:
	for group in population_groups:
		if group.species_name == species_name and group.territory.contains(coords):
			return group
	return null


# Tutti i gruppi (di qualunque specie) il cui Territory include questa cella — usato dalla UI
# (MacroCellDetailPanel) per elencare la fauna presente, senza dover conoscere in anticipo quali
# specie cercare.
func get_population_groups_at(coords: Vector2i) -> Array[PopulationGroup]:
	var groups: Array[PopulationGroup] = []
	for group in population_groups:
		if group.territory.contains(coords):
			groups.append(group)
	return groups


# Rimuove dall'array i gruppi estinti (population <= 0, morti per fame prolungata o vecchiaia —
# vedi AnimalHungerService/AnimalOldAgeMortalityService), così il loro Territory smette di
# risultare "occupato" per qualunque ricerca futura della stessa specie (TerritoryBuilderService.
# _collect_species_occupied_cells non ha mai controllato population, un gruppo morto ma ancora
# nell'array bloccava per sempre le proprie celle a qualunque altro gruppo — vedi anche
# find_population_group/get_population_groups_at sopra, stesso problema, qui risolto alla radice
# invece che con un controllo ripetuto in ogni chiamante). Chiamato una sola volta al giorno da
# WorldTimeService.advance_day, DOPO tutti i checkpoint che possono azzerare population in quel
# giorno — mai durante un loop su population_groups altrove, per non disallineare gli indici di
# un'iterazione in corso. Ogni gruppo rimosso qui libera davvero il proprio territorio per un
# rivale della stessa specie — release_species_territory va chiamata per ciascuno, PRIMA di
# scartarlo dall'array (mai dopo: non avremmo più modo di sapere quale specie fosse).
func remove_extinct_population_groups() -> void:
	for group in population_groups:
		if group.population <= 0:
			release_species_territory(group.species_name)
	population_groups = population_groups.filter(func(group): return group.population > 0)


func ensure_cell_states() -> void:
	if cell_states.size() == cells.size():
		return
	cell_states.clear()
	for cell in cells:
		cell_states.append(MacroCellState.new(cell.x, cell.y))
	print("cell_states dopo il fix: ", cell_states.size())
