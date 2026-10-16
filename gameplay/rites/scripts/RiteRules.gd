class_name RiteRules
extends Resource

# Dati statici di UN rito (2026-10-02, richiesta utente — task Rite, passo 1): un file per rito in
# res://gameplay/rites/data/, caricati per convenzione da RiteService. Solo la definizione: lo stato di un rito in corso
# vive nella RiteAction della Task che lo celebra.
# Base generica di ogni rito (2026-10-14, richiesta utente — base + specializzazione): i campi dei riti religiosi stanno
# in ReligiousRiteRules, quelli dei riti sociali in SocialRiteRules (e del banchetto in BanquetRiteRules).

# Tipo del rito (2026-10-14, richiesta utente — riti religiosi, politici, culturali e sociali nella stessa famiglia).
# Valori salvati per numero nei .tres: aggiungere solo in coda. Default RELIGIOUS (i riti esistenti).
enum RiteType { RELIGIOUS, POLITICAL, CULTURAL, SOCIAL }

@export var id: String = ""
@export var rite_type: RiteType = RiteType.RELIGIOUS
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
# Suono a rito completato (2026-10-04, richiesta utente): id sonoro di un banco (audio/banks/*.tres), suonato tramite
# l'evento "rite_completed:<id>" di SoundEventMap. Vuoto = il suono predefinito dei riti (evento "rite_completed", rite_paleolithic dal 2026-10-04).
@export var completion_sound_id: StringName = &""
