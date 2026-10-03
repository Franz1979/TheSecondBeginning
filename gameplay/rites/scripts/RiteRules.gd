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
# Fede guadagnata da chi celebra al completamento (RiteEffectService).
@export var faith_celebrant: float = 0.0
# Fede guadagnata da ogni presente entro il raggio religioso dell'edificio, moltiplicata per il fattore skill di chi
# celebra (SkillEffectService, chiave RiteAction.SKILL_EFFECT_KEY).
@export var faith_present: float = 0.0
# Fede guadagnata da ogni altro pipottino dello stesso HumanPopulationGroup di chi celebra (2026-10-02), ovunque si
# trovi e di qualunque età, moltiplicata per lo stesso fattore skill di faith_present. Chi celebra e i presenti non la
# ricevono: un solo bonus per pipottino e per rito (RiteEffectService).
@export var faith_population: float = 0.0
# Crescita del raggio RELIGIOUS dell'edificio al completamento (2026-10-02, passo 4c), moltiplicata per lo stesso
# fattore skill di faith_present (InfluenceService.add_radius).
@export var radius_gain: float = 0.0
