class_name HumanEventSchedule
extends RefCounted

# Registro per giorno degli eventi umani programmati (2026-11-09, richiesta utente): invece di scorrere ogni
# giorno tutta la popolazione cercando chi ha l'evento oggi, il tiro annuale iscrive ciascuno nel suo giorno
# assoluto (GameData.get_absolute_day) e il giro giornaliero legge solo la voce di oggi.
#
# Non salvato: la verità resta nei campi scheduled_* di HumanIndividual (salvati), da cui il registro si
# ricostruisce al caricamento. Annullamenti pigri: nessuna rimozione quando un individuo muore prima o il suo
# evento cambia — chi legge la voce del giorno ricontrolla che l'individuo sia ancora nel roster e che il suo
# campo indichi ancora quel giorno, altrimenti lo salta.

enum Kind { DEATH, CONCEPTION, BIRTH }

# Kind -> { giorno assoluto: Array[HumanIndividual] }
var _by_kind: Dictionary = {}


func add(kind: Kind, absolute_day: int, individual: HumanIndividual) -> void:
	var days: Dictionary = _by_kind.get(kind, {})
	if not _by_kind.has(kind):
		_by_kind[kind] = days
	var list: Array = days.get(absolute_day, [])
	if not days.has(absolute_day):
		days[absolute_day] = list
	if not list.has(individual):
		list.append(individual)


# Toglie e restituisce gli iscritti di quel giorno (vuoto se nessuno).
func take(kind: Kind, absolute_day: int) -> Array:
	var days: Dictionary = _by_kind.get(kind, {})
	var list: Array = days.get(absolute_day, [])
	days.erase(absolute_day)
	return list


func clear() -> void:
	_by_kind.clear()
