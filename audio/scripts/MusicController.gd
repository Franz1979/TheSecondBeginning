class_name MusicController
extends Node

# Musica di sottofondo di GameScene (2026-10-09, richiesta utente). Figlio di GameScene, istanziato accanto ad
# AmbienceController da GameScene._setup_clock, che chiama start(). Tutto in tempo REALE: la musica continua anche in
# pausa e non dipende dalla velocità di gioco (timer con ignore_time_scale e nodo PROCESS_MODE_ALWAYS).
#
#   - carica tutti i brani di MUSIC_DIR (.ogg/.mp3/.wav); nel gioco esportato i file compaiono come "<nome>.import"/
#     ".remap": si toglie il suffisso e si carica il percorso originale. Cartella vuota = nessuna musica, nessun errore;
#   - primo brano FIRST_TRACK_DELAY_SEC dopo l'ingresso in partita;
#   - ordine casuale, mai lo stesso brano due volte di fila (con un solo brano, quello);
#   - ogni brano suona una volta sola (AudioManager.play_music_once), con dissolvenza in entrata e, FADE_OUT_SEC prima
#     della fine, in uscita;
#   - finito un brano, silenzio di durata casuale tra GAP_MIN_SEC e GAP_MAX_SEC, poi il successivo;
#   - mentre un brano suona, l'ambience scende ad AMBIENCE_DUCK_FACTOR (AudioManager.set_ambience_duck, un fattore
#     separato: volumi utente e dei layer stagionali invariati) e torna al 100% a brano finito;
#   - uscendo dalla scena: musica ferma, timer annullati, ambience ripristinata.

const MUSIC_DIR := "res://audio/assets/music/"
const EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]

# Ritardo del primo brano dall'ingresso in partita (secondi reali).
const FIRST_TRACK_DELAY_SEC: float = 15.0
# Silenzio musicale tra un brano e il successivo (secondi reali, estremi compresi).
const GAP_MIN_SEC: float = 120.0
const GAP_MAX_SEC: float = 240.0
# Dissolvenze del brano (secondi reali).
const FADE_IN_SEC: float = 3.0
const FADE_OUT_SEC: float = 4.0
# Ambience mentre suona un brano (fattore lineare) e durata della sua dissolvenza (secondi reali).
const AMBIENCE_DUCK_FACTOR: float = 0.65
const AMBIENCE_DUCK_FADE_SEC: float = 2.0
# Dissolvenza della musica uscendo dalla scena (secondi reali).
const EXIT_FADE_SEC: float = 1.0

var _tracks: Array[AudioStream] = []
var _last_index: int = -1
# Ogni timer porta la "generazione" in cui è nato: uscendo dalla scena la generazione cambia e i timer ancora in volo
# non fanno più nulla.
var _generation: int = 0
var _playing: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start() -> void:
	_load_tracks()
	if _tracks.is_empty():
		return
	_schedule(FIRST_TRACK_DELAY_SEC, _play_next)


func _exit_tree() -> void:
	_generation += 1
	if _playing:
		AudioManager.stop_music(EXIT_FADE_SEC)
	_playing = false
	AudioManager.set_ambience_duck(1.0, 0.0)


func _play_next() -> void:
	var index := _pick_index()
	if index < 0:
		return
	_last_index = index
	var stream := _tracks[index]
	_playing = true
	AudioManager.play_music_once(stream, FADE_IN_SEC)
	AudioManager.set_ambience_duck(AMBIENCE_DUCK_FACTOR, AMBIENCE_DUCK_FADE_SEC)
	var length := stream.get_length()
	_schedule(maxf(length - FADE_OUT_SEC, 0.0), _fade_out_track)


# Dissolvenza in uscita prima della fine del brano; a dissolvenza finita il brano è concluso.
func _fade_out_track() -> void:
	AudioManager.stop_music(FADE_OUT_SEC)
	_schedule(FADE_OUT_SEC, _on_track_ended)


func _on_track_ended() -> void:
	_playing = false
	AudioManager.set_ambience_duck(1.0, AMBIENCE_DUCK_FADE_SEC)
	_schedule(randf_range(GAP_MIN_SEC, GAP_MAX_SEC), _play_next)


# Brano a caso, mai l'ultimo suonato (se ce n'è più di uno). -1 se nessun brano.
func _pick_index() -> int:
	if _tracks.is_empty():
		return -1
	if _tracks.size() == 1:
		return 0
	var index := randi() % (_tracks.size() - 1)
	if index >= _last_index and _last_index >= 0:
		index += 1
	return index


# Timer in tempo reale (continua in pausa, ignora la velocità di gioco), annullato uscendo dalla scena.
func _schedule(seconds: float, callback: Callable) -> void:
	if not is_inside_tree():
		return
	var generation := _generation
	var timer := get_tree().create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		if generation == _generation and is_inside_tree():
			callback.call()
	)


# Tutti i brani di MUSIC_DIR, anche nel gioco esportato (dove la cartella elenca "<nome>.import" / "<nome>.remap").
func _load_tracks() -> void:
	_tracks.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	var seen: Dictionary = {}
	var file_names := Array(dir.get_files())
	file_names.sort()
	for raw_name in file_names:
		var file_name := String(raw_name).trim_suffix(".import").trim_suffix(".remap")
		if seen.has(file_name) or not EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		seen[file_name] = true
		var path := MUSIC_DIR + file_name
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			_tracks.append(stream)
