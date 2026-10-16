class_name ReligiousRiteRules
extends RiteRules

# Riti religiosi (2026-10-14, richiesta utente — campi spostati da RiteRules, stessi nomi e valori): fede, corteo funebre,
# sacralità dell'edificio e valore religioso del villaggio. Effetti applicati da ReligiousRiteEffectService.

# Fede guadagnata da chi celebra al completamento (ReligiousRiteEffectService).
@export var faith_celebrant: float = 0.0
# Fede guadagnata da ogni presente entro il raggio religioso dell'edificio, moltiplicata per il fattore skill di chi
# celebra (SkillEffectService, chiave RiteAction.SKILL_EFFECT_KEY).
@export var faith_present: float = 0.0
# Fede guadagnata da ogni altro pipottino dello stesso Folk di chi celebra (2026-10-02), ovunque si
# trovi e di qualunque età, moltiplicata per lo stesso fattore skill di faith_present. Chi celebra e i presenti non la
# ricevono: un solo bonus per pipottino e per rito (ReligiousRiteEffectService).
@export var faith_population: float = 0.0
# Fede dei PARENTI del defunto presenti nel raggio (2026-10-04, funerale): partner, genitori e figli del morto che si
# trovano entro il raggio religioso ricevono il più alto tra questo valore e faith_present (stesso fattore skill); fuori
# dal raggio ricevono faith_population come tutti. Per un rito senza defunto (ricordo dei defunti) i parenti sono quelli
# dei sepolti nell'edificio (BodyBurialService.get_buried_relative_ids). 0 = nessun trattamento dei parenti.
@export var faith_relatives: float = 0.0
# Corteo dei parenti (2026-10-04, funerale): distanza massima in microcelle, in linea d'aria dal portatore, entro cui i
# parenti vivi del defunto vengono convocati quando il corpo viene preso (PickUpBodyAction, ProcessionService). 0 =
# nessun corteo.
@export var procession_max_distance: float = 0.0
# Corteo esteso dalla leadership del defunto (2026-10-04): leadership con cui vengono TUTTI gli abitanti candidati
# (stessa popolazione, non parenti, da adolescenti in su, entro procession_max_distance e convocabili); con meno ne
# viene la quota proporzionale, i più vicini alla guida. 0 = nessuna estensione (solo i parenti).
@export var procession_full_leadership: float = 0.0
# Richiamo dei parenti (2026-10-04): ogni quanti giorni di gioco, finché il corteo è in corso, si riprova a convocare i
# parenti che non ne fanno parte e non ne sono mai usciti (ProcessionService.tick). 0 = nessun richiamo.
@export var procession_recall_interval_days: float = 0.0
# Punti di influenza RELIGIOUS guadagnati dall'edificio al completamento (2026-10-03, punti e soglie — prima
# radius_gain del passo 4c), moltiplicati per lo stesso fattore skill di faith_present (InfluenceService.add_points).
@export var influence_gain: float = 0.0
# Da NON confondere con influence_gain sopra (punti dell'EDIFICIO, che ne alzano il raggio): valore assoluto del
# VILLAGGIO dell'edificio (2026-10-12, passo 4 Folk/Village — Village.influence_values), aggiunto al completamento
# × lo stesso fattore skill, solo se il villaggio ha un centro (ReligiousRiteEffectService). Sempre il valore R: i riti sono solo
# religiosi, eventi politici/culturali avranno regole proprie.
@export var village_religion_gain: float = 0.0
