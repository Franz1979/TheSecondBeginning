class_name LookAroundAction
extends Action

# Sottoclasse concreta di Action per la Wander Task (2026-09-12, richiesta utente — sequenza
# Walk→LookAround→Walk→LookAround→Walk) — stesso principio TEMPORALE di ThinkAction (un
# accumulatore di tempo trascorso confrontato con una durata fissa, vedi _elapsed sotto), ma senza
# alcun effetto collaterale su on_complete() (nessun pending_*, a differenza di ThinkAction —
# "guardarsi in giro" non produce nulla da consumare dopo). Nessun target spaziale (stesso pattern
# di RestAction/ThinkAction — vedi _init sotto): l'individuo resta fermo dov'è (is_moving=false
# ereditato dal default di Action.activate, mai sovrascritto qui).
#
# facing_direction (2026-09-12, richiesta utente — "cambia individual.facing_direction... per dare
# l'effetto si guarda in giro") — campo VERIFICATO leggendo HumanIndividual.gd: `var
# facing_direction: Vector2 = Vector2.RIGHT` (un Vector2 normalizzato, NON un enum — letto da
# HumanIndividualView._process come `rotation = individual.facing_direction.angle()`). Scritto
# QUI in modo sicuro perché HumanIndividualMovementService.advance_movement fa `return` immediato
# se `not individual.is_moving` (vedi lì) — durante un LookAroundAction is_moving resta sempre
# false, quindi quel servizio non tocca mai facing_direction nel frattempo, nessuna corsa tra i
# due scrittori.

# Drain di stamina al GIORNO (2026-09-12, richiesta utente: "drain 50.0/giorno") — STESSO valore
# di RestAction.STAMINA_REGEN_PER_DAY (50.0) ma in segno opposto: "guardarsi in giro" è uno sforzo
# comparabile a camminare piano, non un vero e proprio Walk (che con STAMINA_DRAIN_PER_MICROCELL_
# BASE=5.0 × move_speed=10.0 arriva anch'esso a 50.0/giorno a pieno ritmo) — coerente con gli altri
# drain già calibrati in questo sistema.
const STAMINA_DRAIN_PER_DAY: float = 50.0

# Durata NON più fissa (2026-09-13, richiesta utente) — tirata a caso UNA VOLTA in _init() tra TRE
# valori discreti esatti (1.0/1.5/2.0 giorni, probabilità uguale — NON un range continuo, mai
# randf_range), risultato salvato in _duration sotto. Il resto della logica (soglie di cambio
# facing_direction a 1/3 e 2/3, drain/giorno) resta parametrizzato su _duration invece che sulla
# vecchia costante DURATION_DAYS — si adatta da sé al valore tirato, nessun altro cambio necessario.
const DURATION_DAYS_OPTIONS: Array[float] = [1.0, 1.5, 2.0]

# Durata EFFETTIVA di QUESTA istanza — tirata una volta in _init() (mai ricalcolata dopo: questa
# classe non sovrascrive activate(), a differenza di PickUpAction/RetrieveAction/UnloadAction che
# ricalcolano _duration lì in base a stato runtime — qui il tiro è puramente casuale, indipendente
# da qualunque cosa, quindi nessun bisogno di un guard _restored_from_save: load_save_data() sotto
# sovrascrive semplicemente questo valore col progresso persistito, senza rischio di essere
# ri-sovrascritta da un secondo tiro).
var _duration: float = 0.0

# Recupero di HAPPINESS al giorno (2026-09-13, richiesta utente: "+5.0/day") — guardarsi in giro è
# un piccolo svago, tasso fisso incondizionato.
const HAPPINESS_REGEN_PER_DAY: float = 5.0

# Tempo trascorso in QUESTO step, in frazioni di giorno di gioco — stesso principio di
# ThinkAction._elapsed (parte da 0.0, nessun caso speciale per il primo frame).
var _elapsed: float = 0.0

# Due soglie (1/3 e 2/3 della durata) invece di un cambio ad ogni chiamata (richiesta esplicita
# utente: "se activate()/get_stamina_delta viene chiamato ogni frame, gestisci il cambio con un
# timer interno o una soglia di tempo trascorso, non ad ogni singola chiamata") — un flag booleano
# per soglia, cosicché ciascun cambio di direzione scatti ESATTAMENTE una volta quando _elapsed la
# supera per la prima volta, non ripetutamente sui frame successivi che restano oltre quella
# soglia.
var _direction_change_1_done: bool = false
var _direction_change_2_done: bool = false


func _init() -> void:
	target = null
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]
	# Tiro a caso tra i TRE valori discreti di DURATION_DAYS_OPTIONS (2026-09-13, richiesta utente)
	# — riga esatta richiesta: randi() % array.size() indicizza uno dei tre con probabilità uguale.
	_duration = DURATION_DAYS_OPTIONS[randi() % DURATION_DAYS_OPTIONS.size()]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	if not _direction_change_1_done and _elapsed >= _duration / 3.0:
		individual.facing_direction = Vector2.from_angle(randf() * TAU)
		_direction_change_1_done = true
	if not _direction_change_2_done and _elapsed >= _duration * 2.0 / 3.0:
		individual.facing_direction = Vector2.from_angle(randf() * TAU)
		_direction_change_2_done = true
	return -STAMINA_DRAIN_PER_DAY * delta


# NON incrementa _elapsed/i due flag di cambio direzione (2026-09-13) — già avanzati da
# get_stamina_delta sopra nello stesso frame, stesso motivo di JumpAction.get_happiness_delta.
# Tasso fisso incondizionato.
func get_happiness_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	return HAPPINESS_REGEN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= _duration


# _elapsed/i due flag/_duration persistiti (2026-09-12, esteso 2026-09-13 per _duration) — stesso
# principio di ThinkAction.get_save_data: un save a metà "guardarsi in giro" senza _elapsed/i due
# flag perderebbe il progresso E rischierebbe un terzo cambio di direzione spurio al reload; senza
# _duration (2026-09-13, ORA che non è più una costante fissa ma tirata a caso per istanza) un
# reload rifarebbe un NUOVO tiro in _init() prima di questo load_save_data() — persistendola qui,
# quel nuovo tiro viene semplicemente sovrascritto dal valore vero già deciso, mai un secondo tiro
# effettivo per la stessa istanza.
func get_save_data() -> Dictionary:
	return {
		"elapsed": _elapsed,
		"duration": _duration,
		"direction_change_1_done": _direction_change_1_done,
		"direction_change_2_done": _direction_change_2_done,
	}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	# Default DURATION_DAYS_OPTIONS[0] (1.0) per compatibilità con save precedenti a questo campo
	# (mai scritto "duration" prima di questo passo) — stesso principio ".get() con default" già
	# richiesto per ogni campo opzionale nel progetto; un save così vecchio riprenderebbe con la
	# durata più breve invece di un valore arbitrario non tra i tre ammessi.
	_duration = float(data.get("duration", DURATION_DAYS_OPTIONS[0]))
	_direction_change_1_done = bool(data.get("direction_change_1_done", false))
	_direction_change_2_done = bool(data.get("direction_change_2_done", false))
