class_name AmbienceController
extends Node

# Ambience stagionale di GameScene (2026-09-21, richiesta utente). Figlio di GameScene, istanziato da
# GameScene._setup_clock, che chiama start(clock, game_data). Traduce la stagione corrente in un insieme di
# layer per AudioManager.set_ambience_layer; ad ogni season_ended sfuma verso la nuova stagione.
# Nessun suono è legato ad altri eventi: questo file gestisce solo l'ambience.

# Stagione -> lista di layer {id, volume_linear}. Il file di ciascun layer è
# res://audio/assets/ambience/<id>.ogg|.wav|.mp3 (primo che esiste, in quest'ordine).
const SEASON_LAYERS := {
	GameTypes.Season.SPRING: [
		{"id": &"wind_base", "volume_linear": 0.5},
		{"id": &"birds_day", "volume_linear": 0.8},
	],
	GameTypes.Season.SUMMER: [
		{"id": &"wind_base", "volume_linear": 0.4},
		{"id": &"birds_day", "volume_linear": 0.6},
		{"id": &"insects_summer", "volume_linear": 0.7},
	],
	GameTypes.Season.AUTUMN: [
		{"id": &"wind_base", "volume_linear": 0.7},
		{"id": &"birds_day", "volume_linear": 0.4},
	],
	GameTypes.Season.WINTER: [
		{"id": &"wind_winter", "volume_linear": 0.8},
	],
}

const AMBIENCE_DIR := "res://audio/assets/ambience/"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
# Fade all'ingresso in GameScene e nel passaggio di stagione (richiesta utente: 4 s) / all'uscita.
const ENTRY_FADE: float = 2.0
const SEASON_FADE: float = 4.0
const EXIT_FADE: float = 1.0

# id -> AudioStream caricato, o null se nessun file esiste (un solo push_warning per id).
var _streams: Dictionary = {}
# id dei layer attualmente attivi (quelli che abbiamo chiesto ad AudioManager).
var _active_ids: Array[StringName] = []


# Applica la stagione CORRENTE (ricavata da game_data.current_day con SeasonCalculator.get_season_for_day) e
# si aggancia a clock.season_ended.
func start(clock: GameClockController, game_data: GameData) -> void:
	_apply_season(SeasonCalculator.get_season_for_day(game_data.current_day), ENTRY_FADE)
	clock.season_ended.connect(_on_season_ended)


# season_ended(season) porta la stagione appena TERMINATA: la nuova è la successiva in
# SeasonCalculator.SEASON_ORDER (inverno -> primavera -> estate -> autunno -> inverno).
func _on_season_ended(ended_season: GameTypes.Season) -> void:
	var order := SeasonCalculator.SEASON_ORDER
	var next_season: GameTypes.Season = order[(order.find(ended_season) + 1) % order.size()]
	_apply_season(next_season, SEASON_FADE)


func _exit_tree() -> void:
	AudioManager.clear_ambience(EXIT_FADE)


# Confronta i layer attivi con quelli della stagione: assenti -> fade-out, nuovi -> fade-in, comuni -> solo
# cambio di volume (AudioManager non riavvia un layer che ha già lo stesso stream).
func _apply_season(season: GameTypes.Season, fade: float) -> void:
	var wanted: Dictionary = {}  # id -> {"stream", "volume_linear"}
	for layer in SEASON_LAYERS.get(season, []):
		var id: StringName = layer["id"]
		var stream := _get_stream(id)
		if stream == null:
			continue
		wanted[id] = {"stream": stream, "volume_linear": float(layer["volume_linear"])}

	for id in _active_ids:
		if not wanted.has(id):
			AudioManager.set_ambience_layer(id, null, 0.0, fade)
	for id in wanted.keys():
		AudioManager.set_ambience_layer(id, wanted[id]["stream"], wanted[id]["volume_linear"], fade)

	_active_ids.clear()
	for id in wanted.keys():
		_active_ids.append(id)


# Primo file esistente tra <id>.ogg/.wav/.mp3 in AMBIENCE_DIR; null (con un solo push_warning per id) se
# nessuno esiste — il layer viene saltato. Cachato (anche l'esito negativo).
func _get_stream(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var stream: AudioStream = null
	for extension in EXTENSIONS:
		var path := "%s%s.%s" % [AMBIENCE_DIR, id, extension]
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			if stream != null:
				break
	if stream == null:
		push_warning("AmbienceController: nessun file audio per il layer '%s' in %s (.ogg/.wav/.mp3) — layer saltato." % [id, AMBIENCE_DIR])
	_streams[id] = stream
	return stream
