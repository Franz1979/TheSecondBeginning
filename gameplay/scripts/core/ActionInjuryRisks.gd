class_name ActionInjuryRisks
extends Resource

# Rischio di ferirsi per azione (2026-10-25, richiesta utente — ferite da lavoro): un unico file dati
# (res://gameplay/data/injury_risks/action_injury_risks.tres). Gemello di SkillActionEffects, con le stesse chiavi
# d'azione (Action.skill_effect_key / get_skill_effect_key, es. "hunt_throw"): la skill che migliora l'azione è la
# stessa che ne abbassa il rischio (skill e skill_max letti da skill_action_effects.tres).
#
# risks_by_action_key: chiave d'azione ->
#   {"wounds": {id condizione (HealthConditionRules.id): probabilità 0-1 per azione completata},
#    "skill_reduction": float 0-1, riduzione del rischio a skill_max (rischio × (1 − riduzione × clamp(skill/skill_max))),
#    "activity": chiave di traduzione dell'attività per il messaggio (es. "cacciando")}.
#   Es. {"hunt_throw": {"wounds": {"laceration": 0.02, "fracture": 0.01}, "skill_reduction": 0.6, "activity": "injury_activity_hunting"}}.
#
# Una chiave assente = nessun rischio.
@export var risks_by_action_key: Dictionary = {}
