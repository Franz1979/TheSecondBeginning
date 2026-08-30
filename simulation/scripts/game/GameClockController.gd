class_name GameClockController
extends Node

# Play/pause + speed control for the day-granularity calendar. Owns the only
# _process-driven accumulator in the calendar system; WorldScene/MacroCellScene
# just instantiate this (add_child) and react to its signal — all actual
# day/year bookkeeping and the yearly simulation pipeline live in
# WorldTimeService/GameData, not here.

signal day_advanced(checkpoint_ran: bool, animals_changed: bool)

enum Speed { X1, X2, X3, X4 }

# seconds_per_day = 1.0 / N — Nx is literally N times faster than the 1x baseline.
const SECONDS_PER_DAY_BY_SPEED := {
	Speed.X1: 1.0,
	Speed.X2: 0.5,
	Speed.X3: 1.0 / 3.0,
	Speed.X4: 0.25,
}

var is_playing: bool = false
var speed: Speed = Speed.X1

var _world: World
var _game_data: GameData
var _time_service := WorldTimeService.new()

# Fraction (0..1) of the current day elapsed. Tracking progress as a
# fraction of the day — rather than raw accumulated seconds — is what lets a
# mid-day speed change take effect immediately: the already-elapsed portion
# of the day stays valid, and only the rate at which the remainder fills in
# changes, with no special-casing needed in set_speed().
var _day_progress: float = 0.0

func setup(world: World, game_data: GameData) -> void:
	_world = world
	_game_data = game_data

func _process(delta: float) -> void:
	if not is_playing:
		return
	var seconds_per_day: float = SECONDS_PER_DAY_BY_SPEED[speed]
	_day_progress += delta / seconds_per_day
	# Anti-"spirale della morte" (bug reale trovato in sessione: il log avanzava ma lo schermo
	# restava bloccato su un giorno vecchio) — `delta` è il tempo reale trascorso dall'ultimo
	# frame. Se advance_day() sotto costa più del budget di un giorno (un checkpoint stagionale
	# con più celle vive misurato fino a 13+ secondi, ben oltre l'1s di budget a 1x), QUESTA
	# chiamata a _process non torna mai a Godot per presentare un frame — quindi il `delta` del
	# PROSSIMO frame include anche quel tempo perso, spingendo _day_progress ancora più su e
	# facendo elaborare ancora più giorni in un colpo solo, il cui tempo speso allunga ancora il
	# prossimo delta: un ciclo che si autoalimenta e non si ferma mai da solo finché la
	# simulazione non torna sotto al budget di un frame (mai, se un checkpoint stagionale costa
	# sempre più di un secondo). Il tetto sotto impedisce l'accumulo: al massimo UN giorno viene
	# elaborato per chiamata, qualunque sia il delta — il calendario resta onestamente "indietro"
	# rispetto al tempo reale quando un giorno costa più del previsto (rallentamento visibile,
	# recuperabile), invece di tentare di recuperare tutto in un colpo e restare bloccato
	# indefinitamente. L'eventuale progresso in eccesso oltre un giorno viene scartato, non
	# accumulato per il frame successivo.
	_day_progress = min(_day_progress, 1.999)
	while _day_progress >= 1.0:
		_day_progress -= 1.0
		# TEMPORANEO (diagnostica lentezza) — a differenza di [DAY TIMING] (WorldTimeService, misura
		# SOLO i 4 passi animali dentro advance_day), questo cronometro avvolge advance_day() E
		# day_advanced.emit(): emit() esegue in modo SINCRONO tutti gli slot connessi nello stesso
		# frame (es. GameScene._on_day_advanced, che ai giorni con checkpoint_ran o con
		# flora_daily_updates_enabled attivo rigenera vegetazione/MultiMesh per OGNI cella viva —
		# costo mai visto da WorldTimeService, che non sa nulla di GameScene). Confronta questo
		# numero con la somma delle etichette in [DAY TIMING]: la differenza è il costo di
		# GameScene/MacroCellScene reagendo al segnale, non di WorldTimeService.
		var day_wall_clock_start_usec := Time.get_ticks_usec()
		var result := _time_service.advance_day(_world, _game_data)
		day_advanced.emit(result["checkpoint_ran"], result["animals_changed"])
		if DebugLogging.SHOW_DAILY_TIMING_LOGS:
			var day_wall_clock_ms: float = (Time.get_ticks_usec() - day_wall_clock_start_usec) / 1000.0
			print("[DAY TOTAL] tempo reale completo (advance_day + tutti gli handler di day_advanced, es. refresh vegetazione in GameScene) = %.1fms" % day_wall_clock_ms)

func toggle_play_pause() -> void:
	is_playing = not is_playing

func set_speed(new_speed: Speed) -> void:
	speed = new_speed

func force_advance_to_year_end() -> void:
	_time_service.force_advance_to_year_end(_world, _game_data)
	_day_progress = 0.0
	day_advanced.emit(true, false)
