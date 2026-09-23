extends Node

# Infrastruttura audio (2026-09-21, richiesta utente) — autoload "AudioManager", registrato dopo UserOptions.
# Nessun suono è collegato a eventi di gioco: questo file espone solo l'API (musica, ambienti, SFX, UI) e un
# catalogo vuoto. Tutto ciò che riguarda l'audio vive sotto res://audio/ (bus in audio/buses/, asset in
# audio/assets/{music,ambience,sfx,ui}/). I volumi UTENTE per bus sono in UserOptions (applicati ai bus con
# AudioServer): qui i player restano a 0 dB e lavorano solo con i propri fade/livelli relativi.
#
# Loop: play_music e set_ambience_layer forzano il loop sullo stream ricevuto (_prepare_looping): Ogg/MP3
# loop = true, WAV loop_mode FORWARD con loop_end = fine del file se era 0. La modifica è fatta sulla risorsa
# stessa (non su una copia): resta idempotente e mantiene l'identità dello stream, che serve a riconoscere
# "stessa traccia/stesso layer" e non riavviarli.

const BUS_MUSIC := &"Music"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

const SFX_POOL_SIZE: int = 8
const PITCH_MIN: float = 0.95
const PITCH_MAX: float = 1.05
# Livello "silenzio" usato come estremo dei fade (linear_to_db(0) sarebbe -inf).
const SILENT_DB: float = -80.0

# id -> Array[AudioStream]. Vuoto di proposito: ogni step successivo lo popola (register_sound o
# assegnazione diretta). Se un id ha più stream ne viene scelto uno a caso ad ogni riproduzione.
var catalog: Dictionary = {}

# id già segnalati come mancanti/vuoti: un solo push_warning per id.
var _warned_ids: Dictionary = {}

var _music_players: Array[AudioStreamPlayer] = []
var _active_music_index: int = 0
var _music_tween: Tween

var _ambience_players: Dictionary = {}  # id -> AudioStreamPlayer
var _ambience_tweens: Dictionary = {}  # id -> Tween

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0
var _sfx_2d_pool: Array[AudioStreamPlayer2D] = []
var _sfx_2d_pool_index: int = 0
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	# Fade e player non devono fermarsi se in futuro il tree venisse messo in pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in 2:
		var music_player := AudioStreamPlayer.new()
		music_player.bus = BUS_MUSIC
		music_player.volume_db = SILENT_DB
		add_child(music_player)
		_music_players.append(music_player)

	for i in SFX_POOL_SIZE:
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.bus = BUS_SFX
		add_child(sfx_player)
		_sfx_pool.append(sfx_player)

		var sfx_2d_player := AudioStreamPlayer2D.new()
		sfx_2d_player.bus = BUS_SFX
		add_child(sfx_2d_player)
		_sfx_2d_pool.append(sfx_2d_player)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_UI
	add_child(_ui_player)


# --- Catalogo ---

# Registra (o sostituisce) le varianti di un id. Comodo per popolare il catalogo da codice.
func register_sound(id: StringName, streams: Array[AudioStream]) -> void:
	catalog[id] = streams
	_warned_ids.erase(id)


# --- Musica ---

# Crossfade verso `stream` in `fade` secondi: la traccia corrente sfuma fino al silenzio mentre la nuova
# entra da zero. Stessa traccia già in riproduzione = no-op; stream null = stop_music(fade).
func play_music(stream: AudioStream, fade: float = 2.0) -> void:
	if stream == null:
		stop_music(fade)
		return
	stream = _prepare_looping(stream)
	var outgoing := _music_players[_active_music_index]
	if outgoing.playing and outgoing.stream == stream:
		return
	var incoming_index := 1 - _active_music_index
	var incoming := _music_players[incoming_index]

	_kill_tween(_music_tween)
	incoming.stream = stream
	incoming.volume_db = SILENT_DB if fade > 0.0 else 0.0
	incoming.play()
	_active_music_index = incoming_index

	if fade <= 0.0:
		outgoing.stop()
		outgoing.volume_db = SILENT_DB
		return
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade)
	_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade)
	_music_tween.chain().tween_callback(outgoing.stop)


# Sfuma e ferma la musica corrente (fade <= 0: stop immediato).
func stop_music(fade: float = 2.0) -> void:
	_kill_tween(_music_tween)
	for player in _music_players:
		if not player.playing:
			continue
		if fade <= 0.0:
			player.stop()
			player.volume_db = SILENT_DB
	if fade <= 0.0:
		return
	_music_tween = create_tween().set_parallel(true)
	for player in _music_players:
		if player.playing:
			_music_tween.tween_property(player, "volume_db", SILENT_DB, fade)
	_music_tween.chain().tween_callback(func() -> void:
		for player in _music_players:
			player.stop()
	)


# --- Ambience ---

# Un layer per id, ciascuno con il proprio player sul bus Ambience. Crea il layer se manca, altrimenti ne
# aggiorna stream/volume (relativo, lineare 0-1; il volume utente è sul bus). Il livello raggiunge
# `volume_linear` in `fade` secondi. stream null = rimuove il layer con fade-out.
func set_ambience_layer(id: StringName, stream: AudioStream, volume_linear: float = 1.0, fade: float = 2.0) -> void:
	if stream == null:
		_remove_ambience_layer(id, fade)
		return
	stream = _prepare_looping(stream)
	var target_db := _linear_to_db_safe(volume_linear)
	var player: AudioStreamPlayer = _ambience_players.get(id)
	_kill_tween(_ambience_tweens.get(id))
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = BUS_AMBIENCE
		player.volume_db = SILENT_DB if fade > 0.0 else target_db
		add_child(player)
		_ambience_players[id] = player
	if player.stream != stream or not player.playing:
		player.stream = stream
		player.play()
	if fade <= 0.0:
		player.volume_db = target_db
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, fade)
	_ambience_tweens[id] = tween


# Rimuove tutti i layer con fade-out.
func clear_ambience(fade: float = 2.0) -> void:
	for id in _ambience_players.keys():
		_remove_ambience_layer(id, fade)


func _remove_ambience_layer(id: StringName, fade: float) -> void:
	var player: AudioStreamPlayer = _ambience_players.get(id)
	if player == null:
		return
	_kill_tween(_ambience_tweens.get(id))
	_ambience_tweens.erase(id)
	var finish := func() -> void:
		# Se nel frattempo l'id è stato ricreato, il player nuovo è un altro: non toccarlo.
		if _ambience_players.get(id) == player:
			_ambience_players.erase(id)
			_ambience_tweens.erase(id)
		player.stop()
		player.queue_free()
	if fade <= 0.0:
		finish.call()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, fade)
	tween.tween_callback(finish)
	_ambience_tweens[id] = tween


# --- SFX / UI ---

# Riproduce una variante casuale di `id` con pitch casuale in [0.95, 1.05] sul bus SFX (pool di 8 player
# a rotazione: il più vecchio viene ripreso se sono tutti occupati).
func play_sfx(id: StringName) -> void:
	var stream := _pick_stream(id)
	if stream == null:
		return
	var player := _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	player.play()


# Come play_sfx ma posizionale (AudioStreamPlayer2D, coordinate globali 2D) sul bus SFX.
func play_sfx_at(id: StringName, global_pos: Vector2) -> void:
	var stream := _pick_stream(id)
	if stream == null:
		return
	var player := _sfx_2d_pool[_sfx_2d_pool_index]
	_sfx_2d_pool_index = (_sfx_2d_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.global_position = global_pos
	player.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	player.play()


# Suono di interfaccia: player dedicato sul bus UI (un solo suono alla volta, il nuovo sostituisce il
# precedente).
func play_ui(id: StringName) -> void:
	var stream := _pick_stream(id)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	_ui_player.play()


# --- Interni ---

# Variante casuale di `id`; null (con UN solo push_warning per id) se l'id manca o non ha stream.
func _pick_stream(id: StringName) -> AudioStream:
	var variants: Array = catalog.get(id, [])
	if variants.is_empty():
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			push_warning("AudioManager: suono '%s' non presente nel catalogo (o senza stream)." % id)
		return null
	return variants[randi() % variants.size()] as AudioStream


# Forza il loop sullo stream (musica/ambience): Ogg e MP3 -> loop = true; WAV -> LOOP_FORWARD (se non già in
# un altro tipo di loop) con loop_end = fine del file quando è 0. Altri tipi di stream restano invariati.
func _prepare_looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if wav.loop_end == 0:
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream


func _linear_to_db_safe(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
