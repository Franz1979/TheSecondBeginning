class_name GameClockController
extends Node

# Play/pause + speed control for the day-granularity calendar. Owns the only
# _process-driven accumulator in the calendar system; GameScene/MacroCellScene
# just instantiate this (add_child) and react to its signal — all actual
# day/year bookkeeping and the yearly simulation pipeline live in
# WorldTimeService/GameData, not here.

signal day_advanced(simulation_ran: bool)

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
	while _day_progress >= 1.0:
		_day_progress -= 1.0
		var simulation_ran := _time_service.advance_day(_world, _game_data)
		day_advanced.emit(simulation_ran)

func toggle_play_pause() -> void:
	is_playing = not is_playing

func set_speed(new_speed: Speed) -> void:
	speed = new_speed

func force_advance_to_year_end() -> void:
	_time_service.force_advance_to_year_end(_world, _game_data)
	_day_progress = 0.0
	day_advanced.emit(true)
