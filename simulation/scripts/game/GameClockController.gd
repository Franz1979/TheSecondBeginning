class_name GameClockController
extends Node

# Play/pause + speed control for the day-granularity calendar. Owns the only
# _process-driven accumulator in the calendar system; WorldScene/MacroCellScene
# just instantiate this (add_child) and react to its signal — all actual
# day/year bookkeeping and the yearly simulation pipeline live in
# WorldTimeService/GameData, not here.

signal day_advanced(checkpoint_ran: bool, animals_changed: bool)
# season_ended/year_rolled_over (richiesta utente, 2026-09-05, Opzione A dalla ricognizione
# GameClockController<->WorldTimeService): stessi due punti di emissione di day_advanced sopra,
# valorizzati dai campi già propagati da WorldTimeService.advance_day (vedi lì) — nessun nuovo
# confronto su SeasonCalculator qui, solo smistamento del Dictionary di ritorno in segnali
# distinti e già classificati, cosicché GameTimeService (e chiunque altro in futuro) non debba
# ricalcolare le soglie stagionali per conto proprio. season_ended NON scatta ogni giorno (solo ai
# 4 giorni di fine stagione/anno) — a differenza di day_advanced, emesso incondizionatamente ogni
# giorno.
signal season_ended(season: GameTypes.Season)
signal year_rolled_over()
# Decadimento risorse edifici (2026-09-09, richiesta utente, Step 3 decadimento) — stesso principio
# additivo di season_ended/year_rolled_over sopra: smistato dallo stesso Dictionary di ritorno di
# WorldTimeService.advance_day (chiave "decayed_building_resources"), emesso SOLO quando non vuoto
# (il caso comune, nessun edificio perde nulla quel giorno, non emette mai questo segnale). Ogni
# elemento di `events` è {"building","resource_name","quantity"} — vedi WorldTimeService.
# _run_daily_building_resource_decay per la forma esatta.
signal building_resources_decayed(events: Array)

# X3 rimosso (richiesta utente, 2026-09-04) — X1/X2/X4 restano gli UNICI tre step "normali" nella
# barra velocità. DEBUG è un quarto membro AGGIUNTO in coda (mai reinserito al posto di X3, per non
# far scivolare i valori interi di X4 su quello che prima era X3): un pulsante extra, visibile solo
# a DebugLogging.ENABLED (vedi *Scene._setup_clock), che scorre il tempo molto più rapidamente delle
# altre tre — stesso sec/day che X4 aveva PRIMA di questo passo (0.25, vedi sotto), recuperato prima
# di sovrascrivere X4 con la nuova mappatura.
# X8 aggiunto (richiesta utente, 2026-09-07) TRA X4 e DEBUG (non in coda dopo DEBUG): mantiene la
# progressione numerica leggibile (X1<X2<X4<X8) e lascia comunque DEBUG per ultimo come "quarto
# membro fuori scala" originale. Nessun consumatore nel progetto dipende dal valore ORDINALE intero
# di Speed.DEBUG restando stabile tra una sessione e l'altra (GameSettings.active_clock_speed è un
# plain int di sola sessione, mai persistito su disco — vedi commento lì — e il fallback a X1 in
# *Scene._setup_clock già gestisce un valore stantio/sconosciuto), quindi il suo slittamento da 3 a
# 4 è innocuo. NESSUN pulsante UI aggiunto per X8 in questo passo (richiesta esplicita utente): i
# tre script *Scene.gd (GameScene/WorldScene/MacroCellScene) e le rispettive .tscn non sono stati
# toccati, quindi X8 esiste nel sistema ma non è ancora selezionabile da UI.
enum Speed { X1, X2, X4, X8, DEBUG }

# seconds_per_day: quanti secondi REALI durano per avanzare di un giorno di gioco — NON più 1.0/N
# (formula abbandonata insieme a X3, richiesta utente 2026-09-04). Ritarati (richiesta utente,
# 2026-09-07, in coppia con l'aggiunta di X8): X1/X2/X4/X8 ora dimezzano da 8.0 a 1.0 secondi/giorno
# (X8 = X1 diviso 8, coerente col nome). DEBUG=0.25 invariato (non menzionato dalla richiesta).
const SECONDS_PER_DAY_BY_SPEED := {
	Speed.X1: 8.0,
	Speed.X2: 4.0,
	Speed.X4: 2.0,
	Speed.X8: 1.0,
	Speed.DEBUG: 0.25,
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

# Secondo punto d'accesso allo stesso calcolo già fatto internamente da _process sotto (2026-09-07,
# richiesta utente) — per chi sta FUORI da questo nodo e ha bisogno di convertire un delta reale in
# un "delta di tempo di gioco" che scali con is_playing/speed (es. GameScene._process per
# agganciarci Walk/Rest/azioni future). Stessa logica di _process, non un calcolo diverso: ritorna
# 0.0 se in pausa (stesso comportamento del return immediato lì), altrimenti real_delta diviso per
# gli stessi secondi/giorno della velocità corrente. _process stesso NON chiama questo metodo —
# resta un calcolo duplicato apposta, per non introdurre qui una dipendenza a un side-effect (il
# calcolo di _process avanza anche _day_progress, cosa che questo metodo deliberatamente non fa).
func get_game_day_delta(real_delta: float) -> float:
	if not is_playing:
		return 0.0
	return real_delta / SECONDS_PER_DAY_BY_SPEED[speed]

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
		# Smistamento nei due nuovi segnali classificati (vedi commento alle signal sopra) — letti
		# dal Dictionary appena tornato, nessun ricalcolo. season_ended solo se una stagione è
		# davvero terminata oggi (sentinel -1 di WorldTimeService._run_seasonal_checkpoints).
		if result["season_ended"] != -1:
			season_ended.emit(result["season_ended"])
		if result["year_rolled_over"]:
			year_rolled_over.emit()
		# building_resources_decayed (2026-09-09, richiesta utente) — stesso smistamento additivo di
		# sopra, .get() con default [] per compatibilità (questa chiave non esisteva prima di questo
		# passo, stesso principio già richiesto ovunque per campi opzionali).
		var decayed_building_resources: Array = result.get("decayed_building_resources", [])
		if not decayed_building_resources.is_empty():
			building_resources_decayed.emit(decayed_building_resources)
		# Filtrato ai soli dintorni di un checkpoint stagionale (richiesta utente, 2026-09-05 —
		# stesso motivo/helper di WorldTimeService.advance_day: un log per ogni giorno era
		# troppo rumoroso).
		if DebugLogging.SHOW_DAILY_TIMING_LOGS and SeasonCalculator.is_near_seasonal_checkpoint(_game_data.current_day):
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
	# year_rolled_over sempre vero qui: questo salto avanza sempre di esattamente
	# GameData.DAYS_PER_YEAR giorni da qualunque punto dell'anno, quindi attraversa sempre
	# esattamente un confine annuale. season_ended invece NON viene emesso apposta: a differenza
	# del ramo _process sopra, WorldTimeService.force_advance_to_year_end esegue i 365 advance_day()
	# uno per uno TUTTO AL PROPRIO INTERNO (mai richiamato da qui un giorno alla volta) e non
	# restituisce alcun risultato per-giorno — in un solo salto come questo si attraversano TUTTE e
	# 4 le fini-stagione, e un singolo segnale season_ended(season) non può rappresentarle senza
	# inventare un valore. Stessa scelta di semplificazione già presa da day_advanced.emit(true,
	# false) sopra, che appiattisce 365 giorni reali in un solo evento fittizio.
	year_rolled_over.emit()
