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

# Drain di stamina al GIORNO e durata FISSA (2026-09-12, richiesta utente: "duration fissa 0.5
# giorni, drain 50.0/giorno, quindi 25.0 totali") — STESSO valore di RestAction.STAMINA_REGEN_PER_
# DAY (50.0) ma in segno opposto: "guardarsi in giro" è uno sforzo comparabile a camminare piano,
# non un vero e proprio Walk (che con STAMINA_DRAIN_PER_MICROCELL_BASE=5.0 × move_speed=10.0
# arriva anch'esso a 50.0/giorno a pieno ritmo) — coerente con gli altri drain già calibrati in
# questo sistema.
const STAMINA_DRAIN_PER_DAY: float = 50.0
const DURATION_DAYS: float = 0.5

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


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	if not _direction_change_1_done and _elapsed >= DURATION_DAYS / 3.0:
		individual.facing_direction = Vector2.from_angle(randf() * TAU)
		_direction_change_1_done = true
	if not _direction_change_2_done and _elapsed >= DURATION_DAYS * 2.0 / 3.0:
		individual.facing_direction = Vector2.from_angle(randf() * TAU)
		_direction_change_2_done = true
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


# _elapsed/i due flag persistiti (2026-09-12) — stesso principio di ThinkAction.get_save_data: un
# save a metà "guardarsi in giro" senza questo perderebbe il progresso E rischierebbe un terzo
# cambio di direzione spurio al reload (se i flag non fossero salvati, entrambe le soglie
# scatterebbero di nuovo appena _elapsed supera 0 al primo frame post-reload, qualunque fosse il
# progresso reale).
func get_save_data() -> Dictionary:
	return {
		"elapsed": _elapsed,
		"direction_change_1_done": _direction_change_1_done,
		"direction_change_2_done": _direction_change_2_done,
	}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_direction_change_1_done = bool(data.get("direction_change_1_done", false))
	_direction_change_2_done = bool(data.get("direction_change_2_done", false))
