class_name JumpAction
extends Action

# Sottoclasse concreta di Action, stesso stile stazionario di LookAroundAction (nessun target,
# individuo fermo — is_moving resta false, ereditato dal default di Action.activate, mai
# sovrascritto qui) — introdotta 2026-09-13, richiesta utente, in preparazione della futura Task
# Play (non ancora costruita in questo passo: solo l'Action e il suo collegamento a TaskFactory/
# persistenza, nessun trigger).
#
# Durata CASUALE (a differenza di LookAroundAction.DURATION_DAYS, fissa) — tirata UNA VOLTA in
# _init tra DURATION_MIN_DAYS e DURATION_MAX_DAYS (richiesta utente: "tra 0.5 e 0.75 giorni") e mai
# più ricambiata per tutta la vita dell'istanza, stesso principio "risolto una volta, mai
# ricalcolato" già seguito da PickUpAction._quantity_to_collect. Persistita in get_save_data sotto
# (a differenza della durata FISSA di LookAroundAction, che non ha bisogno di essere salvata): senza
# persistenza, un reload a metà salto ririsolverebbe una _duration diversa in _init, disallineando
# il confronto in is_complete rispetto a _elapsed già maturato.
const DURATION_MIN_DAYS: float = 0.5
const DURATION_MAX_DAYS: float = 0.75

# Drain COSTANTE al giorno, indipendente dalla durata tirata (richiesta esplicita utente: "200.0
# stamina/giorno costante") — stesso schema drain-per-giorno di LookAroundAction.STAMINA_DRAIN_PER_
# DAY/RestAction.STAMINA_REGEN_PER_DAY, moltiplicato per `delta` in get_stamina_delta, MAI per
# `_duration`: una durata tirata più lunga costa proporzionalmente di più in totale (più giorni ×
# stesso tasso), ma il TASSO in sé resta sempre questo, non ricalibrato in base alla durata.
const STAMINA_DRAIN_PER_DAY: float = 200.0

# Recupero di HAPPINESS al giorno (2026-09-13, richiesta utente: "+10.0/day") — saltare è
# divertente: tasso fisso incondizionato, indipendente da _duration/_jump_count (stesso principio
# "il TASSO resta sempre questo" già dichiarato sopra per STAMINA_DRAIN_PER_DAY).
const HAPPINESS_REGEN_PER_DAY: float = 10.0

# Numero di salti — puramente per animazione/varietà (richiesta esplicita utente: "3 o 4 salti
# scelti a caso, nessun impatto su costo o durata") — tirato UNA VOLTA in _init insieme a
# _duration, mai ricalcolato.
const JUMP_COUNT_MIN: int = 3
const JUMP_COUNT_MAX: int = 4

# Feedback visivo MINIMO (2026-09-13, richiesta utente) — un signal, nessun parametro (il
# consumatore, HumanIndividualView, non ha bisogno di sapere QUALE salto tra i 3-4 stia scattando,
# solo CHE è scattato): emesso ad ogni soglia raggiunta, STESSO istante/STESSA soglia già usata dal
# log di debug sotto, mai un evento aggiuntivo separato. GameScene collega questo signal (vedi
# GameScene._reconnect_jump_action_signals) a un piccolo scatto verticale temporaneo sulla view
# dell'individuo (HumanIndividualView.trigger_jump_bounce) — stesso principio "placeholder, non un
# vero sistema di animazione" già seguito da LookAroundAction per facing_direction. Questa classe
# resta comunque ignara della view/del rendering (deliberato, come ogni altra Action): si limita a
# segnalare il FATTO, stesso schema già in uso per SetupSiteAction.site_setup_completed/
# ClearAction.site_cleared/PickUpAction.resource_collected.
signal jumped

var _duration: float
var _jump_count: int

# Tempo trascorso in QUESTO step, in frazioni di giorno di gioco — stesso principio di
# LookAroundAction._elapsed/ThinkAction._elapsed (parte da 0.0, nessun caso speciale per il primo
# frame).
var _elapsed: float = 0.0

# Quanti salti sono già scattati — generalizzazione a N soglie (N = _jump_count, variabile 3/4) del
# meccanismo a due flag fissi di LookAroundAction._direction_change_1/2_done: le soglie sono
# distribuite UNIFORMEMENTE su _duration (1/N, 2/N, ..., N/N), ciascuna scatta ESATTAMENTE una volta
# quando _elapsed la supera per la prima volta, mai ripetuta sui frame successivi che restano oltre
# quella soglia — stesso identico criterio "non ad ogni singola chiamata" richiesto esplicitamente
# per LookAroundAction, qui riusato.
var _jumps_triggered: int = 0


func _init() -> void:
	target = null
	_duration = randf_range(DURATION_MIN_DAYS, DURATION_MAX_DAYS)
	_jump_count = JUMP_COUNT_MIN if randf() < 0.5 else JUMP_COUNT_MAX
	# INFANT non può eseguire questa Action (stesso vincolo base di ogni altra Action — il vincolo
	# CHILD-only della futura Task Play vive lì, non qui).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	# `while`, non `if`, perché N è variabile (3 o 4, non due soglie fisse come LookAroundAction):
	# con un delta insolitamente grande più di una soglia potrebbe cadere nello stesso frame, il
	# ciclo le scatta tutte invece di perderne una.
	while _jumps_triggered < _jump_count and _elapsed >= _duration * float(_jumps_triggered + 1) / float(_jump_count):
		_jumps_triggered += 1
		if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_LOGS:
			print("[JUMP DEBUG] salto %d/%d a elapsed=%.3f/%.3fgg" % [_jumps_triggered, _jump_count, _elapsed, _duration])
		jumped.emit()
	return -STAMINA_DRAIN_PER_DAY * delta


# NON incrementa _elapsed/_jumps_triggered (2026-09-13) — quello stato è già avanzato da
# get_stamina_delta sopra nello STESSO frame (chiamato PRIMA da HumanIndividualActionService.
# apply_action): un secondo incremento qui raddoppierebbe silenziosamente la velocità con cui
# _elapsed matura, sfasando is_complete()/le soglie di salto. Tasso fisso incondizionato.
func get_happiness_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	return HAPPINESS_REGEN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= _duration


# _duration/_jump_count/_elapsed/_jumps_triggered persistiti (2026-09-13) — stesso principio di
# LookAroundAction.get_save_data: senza, un save a metà salto perderebbe sia il progresso reale
# (_elapsed) sia i due valori tirati a caso in _init (_duration/_jump_count), che al reload
# verrebbero ririsolti diversi, disallineando il confronto con _elapsed già maturato.
func get_save_data() -> Dictionary:
	return {
		"duration": _duration,
		"jump_count": _jump_count,
		"elapsed": _elapsed,
		"jumps_triggered": _jumps_triggered,
	}


func load_save_data(data: Dictionary) -> void:
	_duration = float(data.get("duration", _duration))
	_jump_count = int(data.get("jump_count", _jump_count))
	_elapsed = float(data.get("elapsed", 0.0))
	_jumps_triggered = int(data.get("jumps_triggered", 0))
