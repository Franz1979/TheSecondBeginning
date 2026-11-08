class_name AutosaveService
extends RefCounted

# Salvataggio automatico a fine anno (2026-11-08, richiesta utente). Acceso o spento da UserOptions.autosave_enabled
# (menu Opzioni); lo scrive GameScene._autosave al cambio d'anno, con gli stessi passi del salvataggio a mano.
# Un file per anno in GameSettings.SAVES_DIR, col prefisso che lo distingue dai salvataggi fatti a mano (mai toccati).

const FILE_PREFIX := "autosave_anno_"
const FILE_EXTENSION := ".json"


static func next_autosave_path(game_data: GameData) -> String:
	DirAccess.make_dir_recursive_absolute(GameSettings.SAVES_DIR)
	return GameSettings.SAVES_DIR + FILE_PREFIX + str(game_data.year) + FILE_EXTENSION
