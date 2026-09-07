class_name ExpiredObjectRules
extends Resource

# Regole per UN tipo di oggetto-scaduto — un .tres per tipo (oggi solo DEAD_BODY, in futuro
# BUILDING_RUIN/BROKEN_CART/ecc.), mai un file condiviso tra tipi diversi — stesso principio già
# seguito da ResourceGrowthRules/NaturalEventRules (un .tres per WorldObjectType/NaturalEventType).
# Data file per convenzione a res://gameplay/data/expired_objects/{tipo}_rules.tres.
#
# Vive sotto res://gameplay/ (non simulation/, dove era stato messo per errore) — sistema
# player-facing (corpi morti, ruderi, carri), non world-simulation validata/sigillata come il
# resto di simulation/ (spostato dietro segnalazione dell'utente, 2026-09-05).
#
# Solo dati in questo step — nessuna funzione di calcolo scadenza, nessun collegamento a
# HumanIndividual/morte/mondo di gioco (arriverà in uno step successivo).

# Giorni (non anni, richiesta utente 2026-09-05): la scadenza di questo sistema è pensata per un
# calcolo a giorno preciso via tick giornaliero, non arrotondata ad anno come la finestra di
# rientro della vegetazione tagliata (IndividualVegetationService.REENTRY_YEARS_BY_TYPE) — il
# campo è già nell'unità che il calcolo userà davvero, nessuna conversione anno->giorno necessaria
# altrove.
@export var days_to_expire: int
# Rinominato da workforce_cost_to_remove (2026-09-06, richiesta utente) — solo rename, nessuna
# modifica di valore/logica. Resta concettualmente separato dal sistema Stamina (HumanCalculator/
# HumanRules/EraRules): questo è "lavoro richiesto dal target" per essere rimosso, non "capacità
# dell'agente" — nessun collegamento tra i due, deliberatamente.
@export var required_work_to_remove: float
@export var material_recovery_percentage: float
@export var action_needed_to_remove: ExpiredObjectTypes.RemovalActionType
