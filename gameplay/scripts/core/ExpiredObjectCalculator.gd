class_name ExpiredObjectCalculator
extends RefCounted

# Calcoli scalari puri per il sistema oggetti-scaduti (Step 2, 2026-09-05) — stesso ruolo/stile di
# HumanCalculator/ResourceCalculator: RefCounted stateless, nessun accesso a liste di oggetti
# reali/GameData, solo funzioni di query su dati già passati dal chiamante.

# Step 4 (2026-09-05): risoluzione della risorsa giusta per object_type — per convenzione, stesso
# schema di NaturalEventCalculator.get_event_rules (nome enum minuscolo + suffisso, res://gameplay/
# data/expired_objects/{tipo}_rules.tres). Solo dead_body_rules.tres esiste oggi (DEAD_BODY); un
# futuro BUILDING_RUIN/BROKEN_CART funzionerà aggiungendo solo il .tres corrispondente, nessuna
# modifica di codice qui.
const RULES_DIR := "res://gameplay/data/expired_objects/"


static func get_object_rules(object_type: ExpiredObjectTypes.ExpiredObjectType) -> ExpiredObjectRules:
	var type_name: String = ExpiredObjectTypes.ExpiredObjectType.keys()[object_type].to_lower()
	var path := RULES_DIR + type_name + "_rules.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ExpiredObjectRules


# True se il record è scaduto secondo `rules.days_to_expire`, a current_year/current_day dati.
# Confronto per GIORNO ASSOLUTO (year * DAYS_PER_YEAR + day), non anno+giorno separati — stessa
# formula di GameData.get_absolute_day(), qui reimplementata inline perché non esiste
# un'istanza GameData per year/day arbitrari (record.appeared_at_year/day non sono "l'anno/giorno
# corrente di una partita", sono uno snapshot passato). Gestisce correttamente QUALUNQUE overflow
# oltre DAYS_PER_YEAR (non solo un singolo giro d'anno) — es. comparso al giorno 300 con
# days_to_expire=182 scade al giorno assoluto 300+182=482, cioè giorno 117 dell'anno successivo
# (482 - 365), mai un giorno >365 inesistente.
static func is_expired(record: Dictionary, rules: ExpiredObjectRules, current_year: int, current_day: int) -> bool:
	var appeared_absolute_day: int = (
		int(record["appeared_at_year"]) * GameData.DAYS_PER_YEAR + int(record["appeared_at_day"])
	)
	var current_absolute_day := current_year * GameData.DAYS_PER_YEAR + current_day
	return current_absolute_day - appeared_absolute_day >= rules.days_to_expire


# Step 6 (2026-09-05): giorni interi rimanenti prima di is_expired sopra — per un pannello info
# (DeadBodyInfoPanel), non una seconda fonte di verità: usa la STESSA formula a giorno assoluto,
# solo sottratta invece che confrontata. maxi(0, ...) perché un record già scaduto ma non ancora
# fisicamente rimosso (la pulizia annuale, Step 4, gira solo al giorno 10) deve mostrare 0, mai un
# numero negativo privo di senso per chi legge il pannello.
static func get_days_remaining(record: Dictionary, rules: ExpiredObjectRules, current_year: int, current_day: int) -> int:
	var appeared_absolute_day: int = (
		int(record["appeared_at_year"]) * GameData.DAYS_PER_YEAR + int(record["appeared_at_day"])
	)
	var current_absolute_day := current_year * GameData.DAYS_PER_YEAR + current_day
	return maxi(0, rules.days_to_expire - (current_absolute_day - appeared_absolute_day))
