class_name TeachingRiteRules
extends SocialRiteRules

# Lezione (2026-10-16, richiesta utente — insegnamento orale, passo 2): rito culturale al Ceppo dell'insegnamento. Ai
# campi comuni dei riti sociali (raduno, attesa, durata, felicità e socialità, coesione) aggiunge la materia e i guadagni
# degli allievi, calcolati da TeachingRiteService. L'insegnante (organizzatore) è un adulto maturo o anziano
# (allowed_age_bands); gli allievi sono i convocati (SocialRiteRules.convoked_age_bands, solo CHILD).

# Skill insegnabile migliore minima dell'insegnante (scala 0-1000): sotto, non ha niente da insegnare.
@export var min_teach_skill: float = 100.0
# Skill che non si insegnano (si imparano vivendo: talk, feste, riti).
@export var excluded_subjects: Array[String] = ["skill_social", "skill_ritual"]
# Guadagno nella materia per ogni allievo: (insegnante − allievo) × gain_fraction × (1 + cognizione dell'insegnante /
# SKILL_MAX), intero, tra min_gain e max_gain; nessuno se l'allievo ne sa già quanto l'insegnante.
@export var gain_fraction: float = 0.02
@export var min_gain: int = 1
@export var max_gain: int = 10
# Cognizione in più per ogni allievo presente a fine lezione (non per l'insegnante).
@export var cognition_gain: float = 1.0
# Punti d'influenza culturale all'edificio (InfluenceService.add_points): base + per ogni allievo presente.
@export var influence_points_base: float = 5.0
@export var influence_points_per_student: float = 1.0
# Valore culturale del villaggio dell'edificio (Village.add_influence_value, come village_religion_gain dei riti religiosi;
# solo con un villaggio che ha un centro): base + per ogni allievo presente.
@export var village_culture_gain: float = 1.0
@export var village_culture_gain_per_student: float = 0.2
