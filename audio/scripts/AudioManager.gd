extends Node

# Infrastruttura audio — autoload "AudioManager", registrato dopo UserOptions. Tutto ciò che riguarda l'audio
# vive sotto res://audio/ (bus in audio/buses/, asset in audio/assets/{music,ambience,sfx}/, banchi sonori in
# audio/banks/, script in audio/scripts/). I volumi UTENTE per bus sono in UserOptions (applicati ai bus con
# AudioServer): qui i player lavorano solo con i propri livelli relativi e fade.
#
# EFFETTI SONORI A BANCHI (2026-09-26, richiesta utente — sostituisce il vecchio catalogo improvvisato):
#   - all'avvio carica tutti i SoundBank di audio/banks/ (*.tres, generati da audio/scripts/tools/
#     BuildSoundBanks.gd) in un unico indice id -> SoundDef. Nessuna scansione delle cartelle degli asset a
#     runtime: i banchi sono l'unica fonte;
#   - play(id, position) riproduce con i parametri del SoundDef (volume, pitch casuale, bus, spazialità);
#   - pool di voci che cresce su richiesta fino a MAX_VOICES, con cooldown_ms e max_voices per id, furto
#     della voce di priorità più bassa a pool pieno, variante scelta a shuffle bag;
#   - il codice di gioco usa play_event(evento) con la tabella di SoundEventMap, non gli id diretti.
#
# Loop (musica/ambience): play_music e set_ambience_layer forzano il loop sullo stream ricevuto
# (_prepare_looping): Ogg/MP3 loop = true, WAV loop_mode FORWARD con loop_end = fine del file se era 0. La
# modifica è fatta sulla risorsa stessa (non su una copia): resta idempotente e mantiene l'identità dello
# stream, che serve a riconoscere "stessa traccia/stesso layer" e non riavviarli.

const BUS_MUSIC := &"Music"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

# Livello "silenzio" usato come estremo dei fade (linear_to_db(0) sarebbe -inf).
const SILENT_DB: float = -80.0

# Cartella dei banchi sonori (SoundBank, *.tres), letta una sola volta all'avvio.
const BANKS_DIR := "res://audio/banks/"
# Tetto del pool di voci degli effetti (AudioStreamPlayer + AudioStreamPlayer2D insieme): il pool parte
# vuoto e cresce fino a qui; oltre, un suono nuovo ruba una voce (vedi _acquire_voice) o viene scartato.
const MAX_VOICES: int = 32


# Una voce del pool: un player (2D o non posizionale) e il suono che sta suonando.
class Voice:
	var player: Node = null # AudioStreamPlayer o AudioStreamPlayer2D, creato alla prima assegnazione
	var is_spatial: bool = false
	var sound_id: StringName = &""
	var priority: int = 0
	var started_msec: int = 0
	var fade_tween: Tween = null

	func is_busy() -> bool:
		if player == null:
			return false
		return player.playing or (fade_tween != null and fade_tween.is_valid())


# Indice unico id -> SoundDef, fuso da tutti i banchi all'avvio.
var _sound_index: Dictionary = {}
# Chiavi (id o eventi) già segnalate come sconosciute/vuote: un solo push_warning per chiave.
var _warned_ids: Dictionary = {}
# Pool di voci degli effetti (Voice), cresce fino a MAX_VOICES.
var _voices: Array = []
# Ultima riproduzione per id (Time.get_ticks_msec), per cooldown_ms.
var _last_play_msec: Dictionary = {}
# Shuffle bag per id: indici delle varianti ancora da usare nel giro corrente, e ultima variante suonata.
var _variant_bags: Dictionary = {}
var _last_variant: Dictionary = {}

var _music_players: Array[AudioStreamPlayer] = []
var _active_music_index: int = 0
var _music_tween: Tween

var _ambience_players: Dictionary = {}  # id -> AudioStreamPlayer
var _ambience_tweens: Dictionary = {}  # id -> Tween


func _ready() -> void:
	# Fade e player non devono fermarsi se in futuro il tree venisse messo in pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in 2:
		var music_player := AudioStreamPlayer.new()
		music_player.bus = BUS_MUSIC
		music_player.volume_db = SILENT_DB
		add_child(music_player)
		_music_players.append(music_player)

	_load_sound_banks()


# --- Banchi sonori ---

# Carica ogni SoundBank di BANKS_DIR (una sola lettura della cartella, all'avvio) e ne fonde gli indici. Un
# id presente in due banchi viene segnalato con push_error: vale il primo in ordine di nome del file.
# Nei progetti esportati le risorse testuali possono comparire come "*.tres.remap": il suffisso si toglie
# prima di caricarle.
func _load_sound_banks() -> void:
	_sound_index.clear()
	var dir := DirAccess.open(BANKS_DIR)
	if dir == null:
		push_warning("AudioManager: cartella dei banchi %s non trovata — nessun effetto sonoro disponibile." % BANKS_DIR)
		return
	var file_names := Array(dir.get_files())
	file_names.sort()
	for file_name in file_names:
		var bank_file := String(file_name).trim_suffix(".remap")
		if bank_file.get_extension() != "tres":
			continue
		var bank := load(BANKS_DIR + bank_file) as SoundBank
		if bank == null:
			push_error("AudioManager: %s non è un SoundBank — ignorato." % bank_file)
			continue
		var bank_index := bank.get_index()
		for sound_id in bank_index:
			if _sound_index.has(sound_id):
				push_error("AudioManager: id sonoro duplicato '%s' (anche in %s) — vale il primo banco." % [sound_id, bank_file])
				continue
			_sound_index[sound_id] = bank_index[sound_id]


# Il SoundDef dell'id, null se nessun banco lo contiene.
func get_sound_def(sound_id: StringName) -> SoundDef:
	return _sound_index.get(sound_id, null)


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


# --- Effetti sonori ---

# Riproduce il suono `sound_id` con i parametri del suo SoundDef. `position` (Vector2, coordinate globali 2D)
# rende il suono posizionale se il SoundDef è spatial; senza posizione, o con spatial false, il suono è non
# posizionale. Regole, nell'ordine:
#   - id sconosciuto o senza varianti: un solo push_warning per id, nessun suono;
#   - cooldown_ms: una richiesta più ravvicinata della precedente dello stesso id viene ignorata;
#   - max_voices: se l'id suona già in max_voices voci, la più vecchia viene riavviata col suono nuovo;
#   - altrimenti una voce libera; se non ce n'è, il pool cresce fino a MAX_VOICES; a pool pieno si ruba la
#     voce di priorità più bassa (fino a uguale a quella del suono, a parità la più vecchia), e se non ce
#     n'è il suono viene scartato.
func play(sound_id: StringName, position: Variant = null) -> void:
	var def: SoundDef = _sound_index.get(sound_id, null)
	if def == null or def.streams.is_empty():
		_warn_once(sound_id, "AudioManager: suono '%s' assente dai banchi (o senza varianti)." % sound_id)
		return
	var now_msec := Time.get_ticks_msec()
	if _last_play_msec.has(sound_id) and now_msec - int(_last_play_msec[sound_id]) < def.cooldown_ms:
		return
	var voice := _acquire_voice(def)
	if voice == null:
		return
	var use_spatial: bool = def.spatial and position is Vector2
	_prepare_voice(voice, use_spatial)
	var player = voice.player
	player.stream = _next_variant(sound_id, def)
	player.bus = def.bus
	player.volume_db = def.volume_db
	player.pitch_scale = randf_range(minf(def.pitch_min, def.pitch_max), maxf(def.pitch_min, def.pitch_max))
	if use_spatial:
		(player as AudioStreamPlayer2D).global_position = position
	voice.sound_id = sound_id
	voice.priority = def.priority
	voice.started_msec = now_msec
	player.play()
	_last_play_msec[sound_id] = now_msec


# Riproduce il suono associato a un evento di gioco (SoundEventMap.EVENTS). Evento non in tabella: un solo
# push_warning per evento.
func play_event(event: StringName, position: Variant = null) -> void:
	var sound_id := SoundEventMap.get_sound_id(event)
	if sound_id == &"":
		_warn_once(StringName("event:" + String(event)), "AudioManager: evento sonoro '%s' non presente in SoundEventMap." % event)
		return
	play(sound_id, position)


# Ferma le voci che suonano `sound_id`, con fade-out di `fade` secondi (<= 0: subito).
func stop(sound_id: StringName, fade: float = 0.1) -> void:
	for voice in _voices:
		if voice.sound_id == sound_id and voice.is_busy():
			_stop_voice(voice, fade)


# Ferma tutti gli effetti sonori (non musica né ambience), con fade-out di `fade` secondi.
func stop_all(fade: float = 0.1) -> void:
	for voice in _voices:
		if voice.is_busy():
			_stop_voice(voice, fade)


# Wrapper sottili su play(), mantenuti per i chiamanti. Bus, pitch e spazialità vengono dal SoundDef.
func play_sfx(sound_id: StringName) -> void:
	play(sound_id)


func play_sfx_at(sound_id: StringName, global_pos: Vector2) -> void:
	play(sound_id, global_pos)


func play_ui(sound_id: StringName) -> void:
	play(sound_id)


# Suono di selezione dell'interfaccia: l'evento &"ui_selection" di SoundEventMap.
func play_selection() -> void:
	play_event(&"ui_selection")


# --- Interni degli effetti ---

# Voce per il suono `def` secondo le regole di play(); null = suono scartato.
func _acquire_voice(def: SoundDef) -> Voice:
	# max_voices: l'id suona già troppe volte -> si riavvia la sua voce più vecchia.
	var same_id: Array = []
	for voice in _voices:
		if voice.sound_id == def.id and voice.is_busy():
			same_id.append(voice)
	if def.max_voices > 0 and same_id.size() >= def.max_voices:
		return _oldest(same_id)
	for voice in _voices:
		if not voice.is_busy():
			return voice
	if _voices.size() < MAX_VOICES:
		var new_voice := Voice.new()
		_voices.append(new_voice)
		return new_voice
	# Pool pieno: si ruba la voce di priorità più bassa, purché non superiore a quella del suono nuovo.
	var candidates: Array = []
	var lowest_priority: int = def.priority
	for voice in _voices:
		if voice.priority < lowest_priority:
			lowest_priority = voice.priority
			candidates = [voice]
		elif voice.priority == lowest_priority:
			candidates.append(voice)
	if candidates.is_empty():
		return null
	return _oldest(candidates)


func _oldest(voices: Array) -> Voice:
	var oldest: Voice = voices[0]
	for voice in voices:
		if voice.started_msec < oldest.started_msec:
			oldest = voice
	return oldest


# Dà alla voce un player del tipo giusto (2D o non posizionale), fermando ciò che suonava e annullando un
# eventuale fade in corso. Un player del tipo sbagliato viene sostituito.
func _prepare_voice(voice: Voice, spatial: bool) -> void:
	_kill_tween(voice.fade_tween)
	voice.fade_tween = null
	if voice.player != null and voice.is_spatial != spatial:
		voice.player.queue_free()
		voice.player = null
	if voice.player == null:
		voice.player = AudioStreamPlayer2D.new() if spatial else AudioStreamPlayer.new()
		voice.is_spatial = spatial
		add_child(voice.player)
	voice.player.stop()


func _stop_voice(voice: Voice, fade: float) -> void:
	_kill_tween(voice.fade_tween)
	voice.fade_tween = null
	if fade <= 0.0:
		voice.player.stop()
		return
	var tween := create_tween()
	tween.tween_property(voice.player, "volume_db", SILENT_DB, fade)
	tween.tween_callback(voice.player.stop)
	voice.fade_tween = tween


# Variante del suono a shuffle bag: ogni giro usa tutte le varianti in ordine casuale; il primo elemento di
# un giro nuovo non è mai l'ultima variante suonata (se ce n'è più d'una), così la stessa non esce mai due
# volte di fila.
func _next_variant(sound_id: StringName, def: SoundDef) -> AudioStream:
	var count := def.streams.size()
	if count == 1:
		return def.streams[0]
	var bag: Array = _variant_bags.get(sound_id, [])
	# Indici non più validi (varianti cambiate): scartati.
	bag = bag.filter(func(index: int) -> bool: return index < count)
	if bag.is_empty():
		for index in range(count):
			bag.append(index)
		bag.shuffle()
		# Si pesca da pop_back: l'ultimo elemento del sacchetto nuovo non deve essere l'ultima variante suonata.
		var last := int(_last_variant.get(sound_id, -1))
		if bag[bag.size() - 1] == last:
			var swap_with := randi_range(0, bag.size() - 2)
			bag[bag.size() - 1] = bag[swap_with]
			bag[swap_with] = last
	var chosen: int = bag.pop_back()
	_variant_bags[sound_id] = bag
	_last_variant[sound_id] = chosen
	return def.streams[chosen]


func _warn_once(key: StringName, message: String) -> void:
	if _warned_ids.has(key):
		return
	_warned_ids[key] = true
	push_warning(message)


# --- Interni condivisi ---

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
