class_name SkillActionEffects
extends Resource

# Effetti delle skill sul RENDIMENTO delle azioni (2026-09-27, richiesta utente — passo 1 del servizio unico): un
# unico file dati (res://gameplay/data/skill_effects/skill_action_effects.tres) invece di costanti sparse nei
# servizi. Letto da SkillEffectService. Gemello di TaskCompletionEffects, che invece descrive come le skill
# CRESCONO a fine Task.
#
# effects_by_action_key: chiave d'azione (Action.skill_effect_key / get_skill_effect_key, es. "hunt_throw") ->
#   {"skill": nome property skill_* su HumanIndividual, "bonus": float, "skill_max": float}.
#   Fattore = 1 + bonus × clamp(skill / skill_max, 0, 1): 1.0 a skill 0, 1 + bonus da skill_max in su.
#   Es. {"hunt_throw": {"skill": "skill_hunting", "bonus": 0.5, "skill_max": 1000.0}}.
#
# Una chiave assente (o vuota) = fattore 1.0, nessun effetto della skill.
@export var effects_by_action_key: Dictionary = {}
