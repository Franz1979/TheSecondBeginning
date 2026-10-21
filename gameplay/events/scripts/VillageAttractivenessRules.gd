class_name VillageAttractivenessRules
extends Resource

# Parametri dell'attrattiva del villaggio sugli eventi casuali (2026-10-13, richiesta utente — VillageAttractivenessService).
# Dati in res://gameplay/events/data/rules/village_attractiveness_rules.tres: UN solo file per tutti i parametri
# dell'attrattiva (cultura oggi; benessere e attrattiva generale qui quando saranno definiti).
#
# Attrattiva culturale (2026-10-18, richiesta utente — per abitante): moltiplicatore = 1 + sensibilità dell'evento ×
# culture_max_bonus × c / (c + culture_per_inhabitant_half_k), con c = valore culturale del villaggio / abitanti. Prima
# era il valore totale (K = 50): cresce senza tetto e il bonus arrivava al massimo già nei primi anni. Per abitante, un
# villaggio che cresce diluisce la sua cultura e deve produrne altra per restare attraente: la soglia si sposta da sola.
# culture_per_inhabitant_half_k = cultura a testa a metà bonus. Con K = 10 e bonus 1.0: 5 abitanti e C 50 -> ×1.5;
# 14 abitanti e C 77 -> ×1.35; 40 abitanti e C 200 -> ×1.33. K = 10 provvisorio, da ritarare giocando.
@export var culture_per_inhabitant_half_k: float = 10.0
@export var culture_max_bonus: float = 1.0
