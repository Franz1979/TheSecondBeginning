class_name GameTimeService
extends RefCounted

# Primo consumatore gameplay-side dei checkpoint temporali classificati esposti da
# GameClockController (season_ended/year_rolled_over, propagati da WorldTimeService.advance_day
# senza duplicare i confronti su SeasonCalculator — vedi ricognizione 2026-09-05). Placeholder:
# stabilisce solo il collegamento, nessuna logica di aging/nascite/morti umane ancora — quella
# arriverà come consumo futuro dello stesso segnale year_rolled_over.
#
# RefCounted come gli altri *Service del progetto, ma a differenza di quelli (stateless,
# "istanzia con .new() e chiama il metodo" — vedi CLAUDE.md) questa istanza deve restare VIVA per
# tutta la durata di GameScene: è la connessione ai segnali stessa a doverle sopravvivere. Il
# chiamante (GameScene) la tiene in un campo (game_time_service), esattamente come tiene clock
# (GameClockController) — se l'unico riferimento uscisse di scope, Godot libererebbe l'istanza e
# le connessioni smetterebbero di scattare senza errore visibile.

var _game_data: GameData


# Connessione UNA TANTUM (richiesta utente, 2026-09-05) — chiamata da GameScene._setup_clock
# subito dopo clock.day_advanced.connect(...), stesso punto di inizializzazione, nessun registry
# dedicato esiste ancora nel progetto per questo scopo (vedi ricognizione).
func connect_to_clock(clock: GameClockController, game_data: GameData) -> void:
	_game_data = game_data
	clock.year_rolled_over.connect(_on_year_rolled_over)
	clock.season_ended.connect(_on_season_ended)


func _on_year_rolled_over() -> void:
	print("GameTimeService: nuovo anno, year=%d" % _game_data.year)


# Placeholder: nessuna reazione ancora, solo il collegamento richiesto (vedi doc di testa al
# file). Prossimo consumo reale probabilmente qui, quando arriverà una logica per-stagione.
func _on_season_ended(season: GameTypes.Season) -> void:
	pass
