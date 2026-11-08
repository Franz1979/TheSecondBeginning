class_name SaveFileWriter
extends RefCounted

# Scrittura dei salvataggi su un thread a parte (2026-11-08, richiesta utente — il salvataggio fermava il gioco per più
# di un secondo a ogni fine anno). Testo JSON, compressione e scrittura del file girano qui; GameSaveService costruisce i
# dati sul thread principale e consegna un Dictionary che il gioco non tocca più (i dati vivi li copia prima).
# Un solo salvataggio alla volta: chi ne chiede un altro aspetta il precedente. Il caricamento (GameLoadService) e la
# chiusura del gioco (GameSettings._exit_tree) aspettano anche loro, così nessuno legge un file a metà.
# Si scrive su un file temporaneo e poi lo si rinomina: un'uscita brusca non rovina il salvataggio precedente.
# Il file resta .json ma è compresso; con COMPRESS_SAVES = false esce in chiaro e leggibile, per il debug. read_text legge
# entrambi, quindi anche i salvataggi di prima.

const COMPRESS_SAVES := true
const COMPRESSION_MODE := FileAccess.COMPRESSION_ZSTD
# Primi byte di ogni file scritto da FileAccess.open_compressed.
const COMPRESSED_MAGIC := "GCPF"
const TEMP_SUFFIX := ".tmp"

static var _task_id: int = -1


static func write_async(data: Dictionary, file_path: String) -> void:
	wait_for_completion()
	# Dentro un contenitore che il thread svuota subito: così è il thread a liberare i dati, e non il thread principale
	# quando più avanti raccoglie il lavoro finito (WorkerThreadPool tiene la Callable fino ad allora).
	_task_id = WorkerThreadPool.add_task(SaveFileWriter._write_task.bind([data], file_path), false, "Salvataggio")


# Vero mentre un salvataggio è in corso. Un lavoro finito viene raccolto qui (WorkerThreadPool lo chiede a ogni lavoro).
static func is_busy() -> bool:
	if _task_id == -1:
		return false
	if not WorkerThreadPool.is_task_completed(_task_id):
		return true
	wait_for_completion()
	return false


static func wait_for_completion() -> void:
	if _task_id == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1


# Il testo di un salvataggio, compresso o no. "" se il file non si apre.
static func read_text(file_path: String) -> String:
	var plain := FileAccess.open(file_path, FileAccess.READ)
	if plain == null:
		return ""
	var is_compressed := plain.get_buffer(COMPRESSED_MAGIC.length()) == COMPRESSED_MAGIC.to_ascii_buffer()
	plain.seek(0)
	if not is_compressed:
		return plain.get_as_text()
	plain.close()
	var compressed := FileAccess.open_compressed(file_path, FileAccess.READ, COMPRESSION_MODE)
	if compressed == null:
		push_error("Salvataggio compresso illeggibile: %s" % file_path)
		return ""
	return compressed.get_as_text()


static func _write_task(data_holder: Array, file_path: String) -> void:
	var measure_start_msec := Time.get_ticks_msec() # MISURA TEMPORANEA (autosave)
	var data: Dictionary = data_holder[0]
	data_holder.clear()
	var json_text := JSON.stringify(data)
	var measure_json_msec := Time.get_ticks_msec() # MISURA TEMPORANEA (autosave)
	data = {}
	var temp_path := file_path + TEMP_SUFFIX
	var file: FileAccess
	if COMPRESS_SAVES:
		file = FileAccess.open_compressed(temp_path, FileAccess.WRITE, COMPRESSION_MODE)
	else:
		file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Salvataggio non riuscito, file non scrivibile: %s" % temp_path)
		return
	file.store_string(json_text)
	file.close()
	var rename_error := DirAccess.rename_absolute(temp_path, file_path)
	if rename_error != OK:
		push_error("Salvataggio non riuscito, errore %d nel rinominare: %s" % [rename_error, temp_path])
		return
	print("Game saved to JSON: ", file_path)
	# MISURA TEMPORANEA (autosave): da togliere dopo la prova.
	print("[Save misura] thread: JSON %d ms, compressione e scrittura %d ms, testo %.1f MB, file %.1f MB" % [measure_json_msec - measure_start_msec, Time.get_ticks_msec() - measure_json_msec, json_text.length() / 1048576.0, FileAccess.get_size(file_path) / 1048576.0])
