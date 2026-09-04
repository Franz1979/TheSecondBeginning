class_name EraRules
extends Resource

# Regole di un'Era geologico/tecnologica (un file .tres per Era, stesso principio di HumanRules per
# Folk) — modulano l'aspettativa di vita SENZA introdurre una nuova age band: HumanTypes.AgeBand
# resta a 5 valori (CHILD, TEENAGER, FERTILE_ADULT, MATURE_ADULT, OLD) in ogni Era, solo la durata
# reale di ciascuna fascia cambia. Le fasce di gioventù/fertilità (CHILD/TEENAGER/FERTILE_ADULT)
# restano concettualmente invariate tra Ere — è l'aspettativa di vita ADULTA (MATURE_ADULT/OLD) a
# allungarsi/accorciarsi con l'Era, coerentemente con l'obiettivo dichiarato di questo passo.
#
# SOLO dato per ora — NESSUN collegamento esiste ancora, deliberatamente rimandato a una sessione
# futura: nessuna Era "attiva" (nessun current_era da nessuna parte), nessuna logica che applichi
# longevity_multiplier_by_age a HumanRules.age_band_durations_male/female, nessun trigger di
# avanzamento tech→era. HumanRules non referenzia questa classe, e viceversa.

@export_group("Longevity")
# Moltiplicatore applicato (in una sessione futura) a HumanRules.age_band_durations_male/female —
# stessa indicizzazione per age band di size_multiplier_by_age/caloric_multiplier_by_age/
# workforce_multiplier_by_age in HumanRules (0=CHILD, 1=TEENAGER, 2=FERTILE_ADULT, 3=MATURE_ADULT,
# 4=OLD). 1.0 = durata invariata rispetto al dato base di HumanRules, <1.0 = fascia accorciata.
@export var longevity_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
