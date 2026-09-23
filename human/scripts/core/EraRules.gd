class_name EraRules
extends Resource

# Regole di un'Era geologico/tecnologica (un file .tres per Era, stesso principio di HumanRules per
# Folk) — modulano l'aspettativa di vita fascia per fascia: HumanTypes.AgeBand ha 6 valori (INFANT,
# CHILD, TEENAGER, FERTILE_ADULT, MATURE_ADULT, OLD — INFANT AGGIUNTA 2026-09-12, richiesta utente:
# DECISIONE RIBALTATA rispetto alla nota storica di questo file, che escludeva esplicitamente una
# nuova age band per l'eccezione 0-1 anno, gestita allora fuori da questo enum — ora è una fascia
# a pieno titolo, dinamica per Era come le altre). Le fasce di gioventù/fertilità (CHILD/TEENAGER/
# FERTILE_ADULT) restano concettualmente invariate tra Ere — è l'aspettativa di vita ADULTA
# (MATURE_ADULT/OLD) a allungarsi/accorciarsi con l'Era, coerentemente con l'obiettivo dichiarato
# di questo passo.
#
# SOLO dato per ora — NESSUN collegamento esiste ancora, deliberatamente rimandato a una sessione
# futura: nessuna Era "attiva" (nessun current_era da nessuna parte), nessuna logica che applichi
# longevity_multiplier_by_age a HumanRules.age_band_durations_male/female, nessun trigger di
# avanzamento tech→era. HumanRules non referenzia questa classe, e viceversa. Il collegamento di
# INFANT al gameplay vero (movimento/aggancio alla madre) è stato fatto 2026-09-12 (vedi
# HumanIndividualController.gd/GameScene.gd/Action.gd) — min_birth_spacing_years sotto resta
# comunque un campo separato, mai letto per quel collegamento (vedi il commento lì per il perché).

@export_group("General")
# Posizione dell'Era nella sequenza (0 = prima) e nome per la UI (chiave tr(), MAI testo già
# tradotto — es. "era_paleolithic"). Fonte UNICA dell'ordine delle Ere: EraCalculator.list_era_names
# ordina i file .tres di questa cartella per era_order (l'ordine alfabetico dei nomi file non
# coincide con quello cronologico).
@export var era_order: int = 0
@export var display_name: String = ""

@export_group("Longevity")
# Moltiplicatore applicato (in una sessione futura) a HumanRules.age_band_durations_male/female —
# stessa indicizzazione per age band di size_multiplier_by_age/caloric_multiplier_by_age/
# stamina_multiplier_by_age in HumanRules (0=INFANT, 1=CHILD, 2=TEENAGER, 3=FERTILE_ADULT,
# 4=MATURE_ADULT, 5=OLD — ESTESO 2026-09-12 per la nuova fascia INFANT in testa). 1.0 = durata
# invariata rispetto al dato base di HumanRules, <1.0 = fascia accorciata.
@export var longevity_multiplier_by_age: Array[float] = [0.0, 1.0, 1.0, 1.0, 1.0, 1.0]

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
#
# NON toccato dall'introduzione di HumanTypes.AgeBand.INFANT (2026-09-12, richiesta esplicita
# utente) — concettualmente imparentato con la durata di HumanTypes.AgeBand.INFANT (entrambi oggi
# coincidono nel Paleolitico: 1 anno), ma sono due valori INDIPENDENTI — aggiornali entrambi con
# intenzione se li si vuole tenere sincronizzati, nessun collegamento automatico. Il collegamento al
# gameplay (movimento/aggancio alla madre) ORA passa per age_band == HumanTypes.AgeBand.INFANT
# (HumanIndividualController._try_set_target/GameScene._sync_dependent_child_position), MAI più da
# questo campo — min_birth_spacing_years continua a governare SOLO lo spacing tra nascite
# (HumanConceptionIndividualService), un consumo del tutto separato.
@export var min_birth_spacing_years: int = 1

@export_group("Stamina")
# Moltiplicatore applicato a HumanCalculator.get_max_stamina quando l'individuo ha un figlio a
# carico (dependent_child_id != -1) — SOLO display ancora (2026-09-06, nessun sistema di consumo
# stamina reale esiste), migliora l'accuratezza del numero mostrato nel pannello individuo.
# Legato all'Era (non a HumanRules) per lo stesso motivo di min_birth_spacing_years sopra: la
# fatica di portare un figlio dipende dalle condizioni di vita dell'Era, non dal Folk. Il
# moltiplicatore GRAVIDANZA invece è hardcoded (0.5, vedi HumanCalculator.get_max_stamina) —
# scelta deliberata dell'utente, non un dato di configurazione: i due stati sono comunque mutuamente
# esclusivi per costruzione (mai applicati insieme), quindi non serve nessuna logica di
# combinazione tra i due moltiplicatori.
#
# Rinominato da dependent_child_workforce_multiplier (2026-09-06, richiesta utente, rename completo
# Workforce->Stamina) — solo rename, nessuna modifica di valore/logica.
@export var dependent_child_stamina_multiplier: float = 1.0

# Costo calorico dell'allattamento (2026-09-19, richiesta utente): moltiplicatore del CONSUMO CALORICO
# giornaliero di chi ha un figlio a carico (dependent_child_id != -1), accanto a
# dependent_child_stamina_multiplier sopra. Il caloric_multiplier_by_age dell'INFANT resta 0.0: il
# neonato non consuma nulla di suo, il costo lo paga chi lo porta. Vedi
# HumanCalculator.get_daily_calorie_consumption.
@export var dependent_child_calorie_multiplier: float = 1.0

@export_group("Think")
# Moltiplicatore applicato alla durata BASE di ThinkAction (2026-09-07, richiesta utente, primo
# passo del futuro Daydream) — stesso principio "base altrove × moltiplicatore qui" già seguito da
# conception_probability_multiplier/dependent_child_stamina_multiplier sopra: il chiamante che crea
# ThinkAction (mai ThinkAction stessa, vedi Action.gd/ThinkAction.gd per il perché nessuna Action
# conosce EraRules/Folk) risolve base × questo moltiplicatore e passa il risultato già calcolato al
# costruttore. 1.0 = nessun effetto rispetto alla durata base, <1.0 = pensare più rapido in questa
# Era, >1.0 più lento.
@export var think_duration_multiplier: float = 1.0

@export_group("Ideas")
# Decadimento dei pensieri investiti in un'idea NON attiva e NON completata (2026-09-21, richiesta
# utente) — vedi IdeaDecayService. Anni di grazia dal momento in cui l'idea smette di essere
# attiva: la prima perdita avviene a (grace + 1) anni, poi una a ogni anniversario completo.
@export var idea_decay_grace_years: int = 1
# Quota del thoughts_cost dell'idea persa a ogni decadimento (0.10 = 10%), arrotondata per eccesso,
# minimo 1 pensiero. Mai frazionale nel corso dell'anno.
@export var idea_decay_percent_of_cost: float = 0.10
