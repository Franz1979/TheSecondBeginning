class_name RandomEventCategoryRules
extends Resource

# Dati di una CATEGORIA di eventi casuali (2026-09-27, richiesta utente — raffreddamento condiviso, primo uso: i
# visitatori). Un evento appartiene a una categoria con RandomEventRules.category; il file della categoria sta in
# gameplay/events/data/categories/{id}.tres, trovato per convenzione da RandomEventService.get_category_rules.
#
# Raffreddamento: quando un evento della categoria avviene, GameData.random_event_category_last_year[id] prende
# l'anno corrente; da lì la probabilità di TUTTI gli eventi della categoria è moltiplicata per il valore
# corrispondente agli anni trascorsi (indice 0 = stesso anno). Oltre la fine dell'array nessuna riduzione (1.0).

@export var id: String = ""
@export var cooldown_multiplier_by_years_elapsed: Array[float] = []


# Moltiplicatore dopo `years_elapsed` anni dall'ultimo evento della categoria. Negativo (non dovrebbe accadere:
# anno salvato nel futuro) o oltre la fine dell'array -> 1.0.
func get_cooldown_multiplier(years_elapsed: int) -> float:
	if years_elapsed < 0 or years_elapsed >= cooldown_multiplier_by_years_elapsed.size():
		return 1.0
	return cooldown_multiplier_by_years_elapsed[years_elapsed]
