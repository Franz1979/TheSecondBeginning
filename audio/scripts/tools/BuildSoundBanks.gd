@tool
extends EditorScript

# Generatore dei banchi sonori (2026-09-26, richiesta utente). Da eseguire nell'editor: aprire questo file
# nello Script Editor e usare File > Run (Ctrl+Shift+X).
#
# Per ogni sottocartella audio/assets/sfx/<categoria>/ scrive o aggiorna audio/banks/sfx_<categoria>.tres
# (un SoundBank):
#   - raggruppa i file audio per id: nome senza estensione e senza il suffisso _N finale delle varianti
#     ("step_grass_1.wav", "step_grass_2.wav" -> id step_grass con due streams);
#   - voce già esistente: aggiorna SOLO la lista streams, tutti gli altri parametri tarati a mano restano;
#   - id nuovo: voce creata con i default di SoundDef (bus UI per la categoria "ui", SFX per le altre);
#   - voce i cui file non esistono più: rimossa;
#   - stampa un riepilogo per banco e totale: voci aggiunte, aggiornate, rimosse.
# Una categoria senza file e senza banco non produce nulla. Un banco di una categoria la cui cartella è stata
# cancellata non viene toccato: va eliminato a mano.

const SFX_ROOT := "res://audio/assets/sfx/"
const BANKS_DIR := "res://audio/banks/"
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
# Categorie il cui bus di default (per le voci nuove) è UI invece di SFX.
const UI_CATEGORIES: Array[String] = ["ui"]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BANKS_DIR)
	var root := DirAccess.open(SFX_ROOT)
	if root == null:
		push_error("BuildSoundBanks: cartella %s non trovata." % SFX_ROOT)
		return
	var categories := Array(root.get_directories())
	categories.sort()
	var total := {"added": 0, "updated": 0, "removed": 0}
	for category in categories:
		var result := _build_bank(String(category))
		for key in total:
			total[key] += int(result.get(key, 0))
	print("[BuildSoundBanks] TOTALE: %d aggiunte, %d aggiornate, %d rimosse." % [total["added"], total["updated"], total["removed"]])
	EditorInterface.get_resource_filesystem().scan()


# Costruisce/aggiorna il banco di una categoria. Ritorna i conteggi {"added","updated","removed"}.
func _build_bank(category: String) -> Dictionary:
	var counts := {"added": 0, "updated": 0, "removed": 0}
	var groups := _collect_groups(SFX_ROOT + category + "/")
	var bank_path := BANKS_DIR + "sfx_%s.tres" % category
	var bank: SoundBank = null
	if ResourceLoader.exists(bank_path):
		bank = ResourceLoader.load(bank_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SoundBank
		if bank == null:
			push_error("BuildSoundBanks: %s esiste ma non è un SoundBank — non toccato." % bank_path)
			return counts
	elif groups.is_empty():
		return counts
	else:
		bank = SoundBank.new()

	var kept: Array[SoundDef] = []
	var seen_ids: Dictionary = {}
	for def in bank.defs:
		if def == null:
			continue
		if not groups.has(def.id):
			counts["removed"] += 1
			print("[BuildSoundBanks] %s: rimossa '%s' (nessun file)." % [category, def.id])
			continue
		if seen_ids.has(def.id):
			counts["removed"] += 1
			print("[BuildSoundBanks] %s: rimossa voce duplicata '%s'." % [category, def.id])
			continue
		seen_ids[def.id] = true
		var new_paths: Array = groups[def.id]
		if _stream_paths(def.streams) != new_paths:
			def.streams = _load_streams(new_paths)
			counts["updated"] += 1
			print("[BuildSoundBanks] %s: aggiornata '%s' (%d varianti)." % [category, def.id, new_paths.size()])
		kept.append(def)

	var new_ids: Array = groups.keys()
	new_ids.sort()
	for sound_id in new_ids:
		if seen_ids.has(sound_id):
			continue
		var def := SoundDef.new()
		def.id = sound_id
		def.streams = _load_streams(groups[sound_id])
		if UI_CATEGORIES.has(category):
			def.bus = &"UI"
		kept.append(def)
		counts["added"] += 1
		print("[BuildSoundBanks] %s: aggiunta '%s' (%d varianti)." % [category, sound_id, def.streams.size()])

	bank.defs = kept
	bank.invalidate_index()
	var error := ResourceSaver.save(bank, bank_path)
	if error != OK:
		push_error("BuildSoundBanks: salvataggio di %s fallito (errore %d)." % [bank_path, error])
		return counts
	print("[BuildSoundBanks] %s -> %s: %d voci (%d aggiunte, %d aggiornate, %d rimosse)." % [
		category, bank_path, kept.size(), counts["added"], counts["updated"], counts["removed"]
	])
	return counts


# id (StringName) -> Array dei percorsi dei file audio della cartella, ordinati per nome.
func _collect_groups(folder: String) -> Dictionary:
	var groups: Dictionary = {}
	var dir := DirAccess.open(folder)
	if dir == null:
		return groups
	var files := Array(dir.get_files())
	files.sort()
	for file_name in files:
		var extension := String(file_name).get_extension().to_lower()
		if not AUDIO_EXTENSIONS.has(extension):
			continue
		var sound_id := StringName(_strip_variant_suffix(String(file_name).get_basename()))
		if not groups.has(sound_id):
			groups[sound_id] = []
		groups[sound_id].append(folder + String(file_name))
	return groups


# "step_grass_12" -> "step_grass"; un nome senza suffisso numerico resta invariato ("wind_base").
func _strip_variant_suffix(base_name: String) -> String:
	var underscore := base_name.rfind("_")
	if underscore <= 0:
		return base_name
	var suffix := base_name.substr(underscore + 1)
	if suffix.is_empty() or not suffix.is_valid_int():
		return base_name
	return base_name.substr(0, underscore)


func _stream_paths(streams: Array[AudioStream]) -> Array:
	var paths: Array = []
	for stream in streams:
		paths.append(stream.resource_path if stream != null else "")
	return paths


func _load_streams(paths: Array) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		var stream := load(String(path)) as AudioStream
		if stream == null:
			push_error("BuildSoundBanks: %s non è un AudioStream importato — saltato." % path)
			continue
		streams.append(stream)
	return streams
