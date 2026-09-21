class_name TaskRepeatRules
extends RefCounted

# Regole della RIPETIZIONE AUTOMATICA delle task di raccolta (PickUpAction) e trasporto (Transport) —
# 2026-09-20, richiesta utente: generalizzata dal solo pickup. Punto neutro per la costante e per le chiavi di
# context, cosi' nessuna delle due task "possiede" la regola.
#
# Regola: la prima esecuzione piu' al massimo MAX_REPEATS ripetizioni. Il flag ("ripeti") e il contatore delle
# ripetizioni gia' fatte viaggiano in Task.context (chiavi NON consumate da TaskFactory, quindi restano per la
# vita della Task e vengono salvate col context).

const MAX_REPEATS: int = 3

const CONTEXT_ENABLED := "repeat_enabled"
const CONTEXT_COUNT := "repeat_count"

# Chiavi di context della PRIMA generazione (solo raccolta): lette come ripiego, per i salvataggi fatti con task
# di raccolta gia' in coda/in corso. Mai piu' scritte.
const LEGACY_CONTEXT_ENABLED := "pickup_repeat_enabled"
const LEGACY_CONTEXT_COUNT := "pickup_repeat_count"


static func is_enabled(context: Dictionary) -> bool:
	return bool(context.get(CONTEXT_ENABLED, context.get(LEGACY_CONTEXT_ENABLED, false)))


# Ripetizioni gia' fatte (0 per la Task originale). int(): dopo un caricamento JSON i numeri sono float.
static func get_count(context: Dictionary) -> int:
	return int(context.get(CONTEXT_COUNT, context.get(LEGACY_CONTEXT_COUNT, 0)))


static func write(context: Dictionary, enabled: bool, count: int) -> void:
	context[CONTEXT_ENABLED] = enabled
	context[CONTEXT_COUNT] = count
