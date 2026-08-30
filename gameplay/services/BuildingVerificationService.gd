class_name BuildingVerificationService
extends RefCounted

# Verifica se una posizione mondo è edificabile — oggi copre solo i vincoli di terreno più
# semplici (acqua/fiume/pietra), spostati qui da un primo tentativo diretto in GameScene.
# DORMIENTE di proposito: nessun chiamante lo invoca ancora (GameScene ha disattivato la verifica
# mentre è in debug sul discorso "quanti individui calcolo se costruisco" — vedi discussione con
# l'utente). Quando servirà una verifica più accurata (edifici già esistenti, altri ostacoli), è
# qui che va estesa — stesso principio "un solo Service stateless per compito" già in uso ovunque
# nel progetto (RefCounted, .new() per uso, nessun autoload).
#
# Vegetazione NON controllata (deliberatamente): un albero/arbusto può essere tagliato per far
# posto, a differenza di pietra/fiume/acqua che sono permanenti — se in futuro vorremo bloccare
# anche lì, è un'estensione separata di is_position_buildable, non un nuovo file.

static func is_position_buildable(live_cells: Dictionary, macro_cell_pixels: int, cell_size: int, world_position: Vector2) -> bool:
	for cell in live_cells.values():
		var local_pos: Vector2 = cell.container.to_local(world_position)
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= macro_cell_pixels or local_pos.y >= macro_cell_pixels:
			continue
		if cell.macro_cell == null:
			return false
		if cell.macro_cell.terrain_base == GameTypes.TerrainBase.WATER:
			return false
		var microcell := Vector2i(int(local_pos.x / cell_size), int(local_pos.y / cell_size))
		if cell.river_positions.has(microcell):
			return false
		if cell.macro_state != null and cell.macro_state.stone_positions.has(microcell):
			return false
		return true
	# Nessuna cella viva sotto il punto (fuori dall'area caricata) -> non edificabile per
	# definizione, non c'è nulla di noto lì su cui costruire.
	return false


# Applica il feedback visivo di edificabilità a un BuildingGhost — un solo punto che decide "come
# mostrare" true/false (rosso/verde, vedi BuildingGhost.is_buildable), cosicché il futuro sistema
# più accurato (edifici esistenti/altri ostacoli) debba solo estendere is_position_buildable
# sopra, mai duplicare la parte visiva.
static func set_buildable_appearance(ghost: BuildingGhost, is_buildable: bool) -> void:
	ghost.is_buildable = is_buildable
