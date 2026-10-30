class_name WaitForSafetyAction
extends Action

# Attesa al riparo (2026-10-30, lupi L5a — fuga dal pericolo, flee.tres): secondo step della fuga, dopo la corsa al
# riparo. Finisce quando chi ha creato il pericolo lo chiude (DangerFleeService.end_danger mette
# DangerFleeService.CONTEXT_DANGER_OVER nel context della Task) o, per sicurezza, dopo max_wait_days (un pericolo
# che nessuno chiude più — per esempio dopo un caricamento, le visite non si salvano — non tiene la persona ferma per
# sempre). Nessun costo di stamina: si sta fermi.

var max_wait_days: float = 1.0
var _elapsed: float = 0.0


func _init(p_max_wait_days: float = 1.0) -> void:
	target = null
	max_wait_days = p_max_wait_days


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return bool(context.get(DangerFleeService.CONTEXT_DANGER_OVER, false)) or _elapsed >= max_wait_days


func get_save_data() -> Dictionary:
	return {"max_wait_days": max_wait_days, "elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
