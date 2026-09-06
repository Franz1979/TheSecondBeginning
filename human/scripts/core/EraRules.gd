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

@export_group("Reproduction")
# Moltiplicatori scalari (non per age band, a differenza di longevity_multiplier_by_age sopra —
# concepimento/sopravvivenza al parto riguardano sempre e solo FERTILE_ADULT per costruzione,
# nessun asse età da modulare qui) applicati ai corrispondenti campi *_base_probability di
# HumanRules (vedi lì, gruppo Reproduction) — stesso principio "base in HumanRules × moltiplicatore
# in EraRules" di longevity_multiplier_by_age. 1.0 = neutro, nessun effetto rispetto al dato base.
# SOLO dato per ora (richiesta utente, 2026-09-06) — nessuna logica li legge ancora in questo
# passo.
@export var conception_probability_multiplier: float = 1.0
@export var childbirth_survival_child_multiplier: float = 1.0
@export var childbirth_survival_mother_multiplier: float = 1.0
# Distanza minima (anni) da un parto precedente prima che la madre possa tornare candidabile per un
# nuovo concepimento (HumanConceptionIndividualService) — un numero puro/demografico, non un moltiplicatore
# su una base di HumanRules (nessun campo *_base_* corrispondente lì, a differenza dei tre sopra):
# per questo vive qui e non in HumanRules, legato all'Era (Paleolitico vs epoche successive) e non
# al Folk. Default di classe = 1 (richiesta utente, 2026-09-06) come fallback se un .tres futuro
# non lo valorizzasse esplicitamente — paleolithic.tres lo imposta comunque esplicitamente, mai
# lasciato al default implicito.
@export var min_birth_spacing_years: int = 1

@export_group("Workforce")
# Moltiplicatore applicato a HumanCalculator.get_base_workforce quando l'individuo ha un figlio a
# carico (dependent_child_id != -1) — SOLO display ancora (2026-09-06, nessun sistema di consumo
# workforce reale esiste), migliora l'accuratezza del numero mostrato nel pannello individuo.
# Legato all'Era (non a HumanRules) per lo stesso motivo di min_birth_spacing_years sopra: la
# fatica di portare un figlio dipende dalle condizioni di vita dell'Era, non dal Folk. Il
# moltiplicatore GRAVIDANZA invece è hardcoded (0.5, vedi HumanCalculator.get_base_workforce) —
# scelta deliberata dell'utente, non un dato di configurazione: i due stati sono comunque mutuamente
# esclusivi per costruzione (mai applicati insieme), quindi non serve nessuna logica di
# combinazione tra i due moltiplicatori.
@export var dependent_child_workforce_multiplier: float = 1.0
