class_name VillageAttractivenessRules
extends Resource

# Parametri dell'attrattiva del villaggio sugli eventi casuali (2026-10-13, richiesta utente — VillageAttractivenessService).
# Dati in res://gameplay/events/data/village_attractiveness_rules.tres: UN solo file per tutti i parametri
# dell'attrattiva (cultura oggi; benessere e attrattiva generale qui quando saranno definiti).
#
# Attrattiva culturale: moltiplicatore = 1 + sensibilità dell'evento × culture_max_bonus × C / (C + culture_half_value_k),
# con C = valore assoluto culturale del villaggio. Curva che si appiattisce (C cresce senza tetto): culture_half_value_k
# è il C a cui si ottiene metà del bonus. Con K = 50 e bonus 1.0: C 50 -> ×1.5, C 200 -> ×1.8, C 500 -> ×1.91.
# DA RIVEDERE (2026-10-13, richiesta utente): K = 50 scelto provvisoriamente, la cultura si sente molto presto — va
# ritarato giocando.
@export var culture_half_value_k: float = 50.0
@export var culture_max_bonus: float = 1.0
