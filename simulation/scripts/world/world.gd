class_name World

const WIDTH: int = 100
const HEIGHT: int = 100

var cells: Array[MacroCellData] = []
# true quando la rete dei ruscelli è già stata generata per questo mondo (anche se l'esito è
# "nessun ruscello"): i mondi salvati prima dei ruscelli la ricevono una sola volta al caricamento.
var streams_generated: bool = false
var cell_states: Array[MacroCellState] = []
# Focus del LOD (vedi LODOrchestrator), solo di sessione e mai salvato: true mentre è aperta una scena con celle vive
# (GameScene/MacroCellScene), che lo azzerano uscendo. A false (vista mondo) nulla è congelato.
var lod_focus_active: bool = false

# Edifici piazzati — world-level (Array + contatore id
# dedicato). Persistito nei save (GameSaveService/GameLoadService, sezione "buildings") — oggi
# esiste solo per il piazzamento di debug da GameScene, vedi BuildingVerificationService/
# Building.gd per il perché manca ancora un vero flusso di costruzione (materiali/tech/tempo).
var buildings: Array[Building] = []
var next_building_id: int = 1

func allocate_building_id() -> int:
	var id := next_building_id
	next_building_id += 1
	return id


func generate_empty_world() -> void:
	cells.clear()
	cell_states.clear()
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
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := MacroCellData.new(x, y)
			cell.terrain_base = terrain_base
			cell.water_type = water_type
			cell.coast_type = coast_type
			cells.append(cell)
			cell_states.append(MacroCellState.new(x, y))


# Micro-mondo di una cella viva (2026-11-01, scatto all'attivazione): serve solo a MicroCellRenderer, che con terreno
# uniforme legge la prima cella. Una cella sola invece di 10.000 uguali: get_cell_at risponde solo per (0, 0).
func generate_single_cell_terrain(
	terrain_base: GameTypes.TerrainBase,
	water_type: GameTypes.WaterType,
	coast_type: GameTypes.CoastType = GameTypes.CoastType.NONE
) -> void:
	cells.clear()
	cell_states.clear()
	var cell := MacroCellData.new(0, 0)
	cell.terrain_base = terrain_base
	cell.water_type = water_type
	cell.coast_type = coast_type
	cells.append(cell)

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

func ensure_cell_states() -> void:
	if cell_states.size() == cells.size():
		return
	cell_states.clear()
	for cell in cells:
		cell_states.append(MacroCellState.new(cell.x, cell.y))
	print("cell_states dopo il fix: ", cell_states.size())
