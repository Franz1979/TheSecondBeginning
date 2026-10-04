class_name RiteRules
extends Resource

# Dati statici di UN rito (2026-10-02, richiesta utente — task Rite, passo 1): un file per rito in
# res://gameplay/rites/data/, caricati per convenzione da RiteService. Solo la definizione: lo stato di un rito in corso
# vive nella RiteAction della Task che lo celebra.

@export var id: String = ""
# Chiave tr() del nome mostrato nel popup di scelta (es. "rite_simple_name").
@export var display_name: String = ""
# BuildingRules/building_type_name degli edifici presso cui il rito si può celebrare (es. "stacked_stones").
@export var building_types: Array[String] = []
# Durata della celebrazione in giorni di gioco (RiteAction).
@export var duration_days: float = 0.25
# skill_ritual minima di chi celebra (0 = nessun requisito).
@export var min_skill: float = 0.0
# Restrizione FACOLTATIVA di età (HumanTypes.AgeBand) per chi celebra, in più a quella delle task rite/leisure_rite
# (TaskDefinition.allowed_age_bands, 2026-10-02); vuoto = nessuna restrizione oltre a quella della task.
@export var allowed_age_bands: Array[int] = []
# true = il rito può essere celebrato spontaneamente come task idle (leisure_rite.tres, IdleTaskAssignmentService);
# il comando manuale mostra comunque tutti i riti ammessi dall'edificio (2026-10-02).
@export var spontaneous: bool = true
# true = il rito si celebra SOLO dentro la task Seppellisci (2026-10-04, cumulo sepolcrale passo 3b — il funerale): mai
# proposto dalla task Rito, dal suo popup né come rito spontaneo (RiteService.get_rites_for_building lo esclude).
@export var bury_task_only: bool = false
# Numero minimo di sepolti (Building.buried) che l'edificio deve avere perché il rito sia celebrabile (2026-10-04 —
# ricordo dei defunti: 1). Rispettato da RiteService.get_rites_for_building, quindi da popup, riti spontanei e
# assegnazione. 0 = nessun requisito.
@export var min_buried: int = 0
# Fede guadagnata da chi celebra al completamento (RiteEffectService).
@export var faith_celebrant: float = 0.0
# Fede guadagnata da ogni presente entro il raggio religioso dell'edificio, moltiplicata per il fattore skill di chi
# celebra (SkillEffectService, chiave RiteAction.SKILL_EFFECT_KEY).
@export var faith_present: float = 0.0
# Fede guadagnata da ogni altro pipottino dello stesso HumanPopulationGroup di chi celebra (2026-10-02), ovunque si
# trovi e di qualunque età, moltiplicata per lo stesso fattore skill di faith_present. Chi celebra e i presenti non la
# ricevono: un solo bonus per pipottino e per rito (RiteEffectService).
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
# Suono a rito completato (2026-10-04, richiesta utente): id sonoro di un banco (audio/banks/*.tres), suonato tramite
# l'evento "rite_completed:<id>" di SoundEventMap. Vuoto = il suono predefinito dei riti (evento "rite_completed", rite_paleolithic dal 2026-10-04).
@export var completion_sound_id: StringName = &""
