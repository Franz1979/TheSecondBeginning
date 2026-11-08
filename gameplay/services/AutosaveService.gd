class_name AutosaveService
extends RefCounted

# Salvataggio automatico a fine anno (2026-11-08, richiesta utente). Acceso o spento da UserOptions.autosave_enabled
# (menu Opzioni); lo scrive GameScene._autosave al cambio d'anno, con gli stessi passi del salvataggio a mano.
# Un file per anno in GameSettings.SAVES_DIR, con il nome del popolo: autosave_<popolo>_anno_N.json. Se ne tengono solo gli
# ultimi KEEP_PER_FOLK per popolo. I salvataggi fatti a mano non vengono mai toccati.
# Il nome del popolo non è univoco: due partite con lo stesso nome condividono i file (raro, accettato).

const KEEP_PER_FOLK := 3
const FILE_PREFIX := "autosave_"
const YEAR_PREFIX := "anno_"
const FILE_EXTENSION := ".json"


static func next_autosave_path(game_data: GameData, folk: Folk) -> String:
	DirAccess.make_dir_recursive_absolute(GameSettings.SAVES_DIR)
	return GameSettings.SAVES_DIR + _folk_file_prefix(folk) + str(game_data.year) + FILE_EXTENSION


# Da chiamare prima di scrivere new_path: il file nuovo arriva dal thread dopo, quindi qui se ne lasciano KEEP_PER_FOLK - 1
# oltre a lui. "Più vecchi" per data del file e non per anno: dopo aver ricaricato una partita indietro nel tempo, gli
# autosave nuovi hanno anni più bassi ma sono quelli da tenere.
static func delete_old_autosaves(new_path: String, folk: Folk) -> void:
	var prefix := _folk_file_prefix(folk)
	var others: Array[String] = []
	for file_name in DirAccess.get_files_at(GameSettings.SAVES_DIR):
		if not file_name.begins_with(prefix) or not file_name.ends_with(FILE_EXTENSION):
			continue
		if not file_name.trim_prefix(prefix).trim_suffix(FILE_EXTENSION).is_valid_int():
			continue
		var path := GameSettings.SAVES_DIR + file_name
		if path != new_path:
			others.append(path)
	others.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b)
	)
	for i in range(KEEP_PER_FOLK - 1, others.size()):
		DirAccess.remove_absolute(others[i])


# Senza un popolo (folk null o senza nome): autosave_anno_.
static func _folk_file_prefix(folk: Folk) -> String:
	var folk_part := ""
	if folk != null and folk.name != "":
		folk_part = folk.name.validate_filename() + "_"
	return FILE_PREFIX + folk_part + YEAR_PREFIX
