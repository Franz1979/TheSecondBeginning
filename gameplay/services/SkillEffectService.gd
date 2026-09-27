class_name SkillEffectService
extends RefCounted

# Traduce una skill in un fattore di rendimento per un'azione (2026-09-27, richiesta utente — passo 1 del servizio
# unico per gli effetti delle skill). I dati sono nel file res://gameplay/data/skill_effects/skill_action_effects.tres
# (vedi SkillActionEffects per il formato). Stateless (RefCounted, static), stesso pattern di
# TaskCompletionEffectService, che invece gestisce la CRESCITA delle skill a fine Task.
#
# Fattore = 1 + bonus × clamp(skill / skill_max, 0, 1). Chiave vuota o assente nella tabella: 1.0.
# Consumatori (letto a ogni uso, mai salvato negli step: una skill che cresce durante una Task lunga conta subito):
#   - "hunt_throw": probabilità di colpire (HuntService.compute_hit_chance);
#   - "produce": ProduceAction (lavoro richiesto diviso per il fattore, minimo 40% del lavoro base della ricetta);
#   - "build": BuildAction e DemolishAction (lavoro richiesto diviso per il fattore);
#   - "butcher": ButcherAction, "pickup": PickUpAction (durata divisa per il fattore);
#   - "walk_loaded": WalkAction a zaino carico (costo di stamina per microcella diviso per il fattore).

const EFFECTS_PATH := "res://gameplay/data/skill_effects/skill_action_effects.tres"

# Cache del file dati (i .tres non cambiano a runtime): stesso principio delle altre cache static.
static var _effects: SkillActionEffects = null
static var _effects_loaded: bool = false


# Fattore della skill per l'azione `action` eseguita da `individual`: la chiave arriva da
# Action.get_skill_effect_key (fissa o dipendente dallo stato dell'azione).
static func get_factor_for_action(action: Action, individual: Variant, context: Dictionary = {}) -> float:
	if action == null:
		return 1.0
	return get_factor(action.get_skill_effect_key(individual, context), individual)


# Fattore della skill per la chiave d'azione `action_key` e `individual`. 1.0 se la chiave è vuota, non è in
# tabella, la skill non esiste sull'individuo o skill_max non è positivo.
static func get_factor(action_key: String, individual: Variant) -> float:
	if action_key == "" or individual == null:
		return 1.0
	var effects := _get_effects()
	if effects == null or not effects.effects_by_action_key.has(action_key):
		return 1.0
	var entry: Dictionary = effects.effects_by_action_key[action_key]
	var skill_name := String(entry.get("skill", ""))
	var skill_max := float(entry.get("skill_max", 0.0))
	var bonus := float(entry.get("bonus", 0.0))
	if skill_name == "" or skill_max <= 0.0:
		return 1.0
	var skill_value: Variant = individual.get(skill_name)
	if skill_value == null:
		push_warning("SkillEffectService: '%s' non e' una property dell'individuo (chiave '%s')." % [skill_name, action_key])
		return 1.0
	return 1.0 + bonus * clampf(float(skill_value) / skill_max, 0.0, 1.0)


static func _get_effects() -> SkillActionEffects:
	if _effects_loaded:
		return _effects
	_effects_loaded = true
	if not ResourceLoader.exists(EFFECTS_PATH):
		push_warning("SkillEffectService: file dati non trovato: %s" % EFFECTS_PATH)
		return null
	_effects = load(EFFECTS_PATH) as SkillActionEffects
	return _effects
