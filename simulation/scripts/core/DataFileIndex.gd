class_name DataFileIndex
extends RefCounted

# Indice nome -> percorso dei .tres sotto una cartella dati, sottocartelle comprese (2026-10-03, richiesta utente —
# riorganizzazione in sottocartelle per categoria di secondary_resources/ e buildings/). Il nome del file resta la
# chiave per tutto il resto del codice: CaloricCalculator/BuildingCalculator risolvono il percorso da qui invece di
# costruirlo come cartella + nome + ".tres", così la sottocartella in cui sta un file non conta per i chiamanti.
#
# Costruito UNA volta per cartella e tenuto in cache (static, stesso principio di _rules_cache nei calculator: i .tres
# non cambiano a runtime in una sessione di gioco). Build esportate: i .tres compaiono come "*.tres.remap" — stesso
# trattamento delle scansioni precedenti (trim_suffix(".remap"), percorso registrato senza il suffisso).
#
# Due controlli alla costruzione, solo avvisi in console (push_warning), mai bloccanti:
#   - stesso nome di file in due sottocartelle: vince il primo trovato, l'altro è ignorato;
#   - file in una sottocartella di primo livello che non corrisponde al suo campo `category`, secondo la mappa
#     `category_by_folder` passata dal chiamante (nome cartella -> valore dell'enum). I file direttamente nella
#     cartella radice non vengono controllati.

# root_dir -> {nome: percorso}
static var _indexes: Dictionary = {}


# Indice completo di `root_dir` (con "/" finale). Vuoto se la cartella non esiste.
static func get_index(root_dir: String, category_by_folder: Dictionary = {}) -> Dictionary:
	if _indexes.has(root_dir):
		return _indexes[root_dir]
	var index: Dictionary = {}
	_scan_dir(root_dir, "", index)
	_check_categories(root_dir, index, category_by_folder)
	_indexes[root_dir] = index
	return index


# Percorso del .tres di nome `file_name` sotto `root_dir`, "" se non esiste.
static func resolve_path(root_dir: String, file_name: String, category_by_folder: Dictionary = {}) -> String:
	return String(get_index(root_dir, category_by_folder).get(file_name, ""))


# Tutti i nomi indicizzati, in ordine alfabetico.
static func list_names(root_dir: String, category_by_folder: Dictionary = {}) -> Array[String]:
	var names: Array[String] = []
	for file_name in get_index(root_dir, category_by_folder).keys():
		names.append(String(file_name))
	names.sort()
	return names


static func _scan_dir(root_dir: String, relative_dir: String, index: Dictionary) -> void:
	var dir_path := root_dir + relative_dir
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_dir(root_dir, relative_dir + file_name + "/", index)
		else:
			var resource_file := file_name.trim_suffix(".remap")
			if resource_file.ends_with(".tres"):
				var name := resource_file.get_basename()
				var path := dir_path + resource_file
				if not index.has(name):
					index[name] = path
				elif String(index[name]) != path:
					push_warning("DataFileIndex: '%s.tres' presente in due cartelle (%s e %s) — uso il primo, ignoro il secondo." % [name, index[name], path])
		file_name = dir.get_next()
	dir.list_dir_end()


static func _check_categories(root_dir: String, index: Dictionary, category_by_folder: Dictionary) -> void:
	if category_by_folder.is_empty():
		return
	for name in index.keys():
		var path := String(index[name])
		var relative := path.trim_prefix(root_dir)
		if not relative.contains("/"):
			continue
		var folder := relative.get_slice("/", 0)
		var resource := load(path)
		if resource == null:
			continue
		var category: Variant = resource.get("category")
		if not category_by_folder.has(folder):
			push_warning("DataFileIndex: '%s' sta nella cartella '%s', che non corrisponde a nessuna categoria." % [path, folder])
		elif category == null or int(category) != int(category_by_folder[folder]):
			push_warning("DataFileIndex: '%s' sta nella cartella '%s' ma il suo campo category è %s." % [path, folder, str(category)])
