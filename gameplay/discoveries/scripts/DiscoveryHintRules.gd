class_name DiscoveryHintRules
extends Resource

# Una "scoperta" spiegata al giocatore (2026-09-28, richiesta utente): un .tres per scoperta in
# gameplay/discoveries/data/, trovato per scansione da DiscoveryHintService (stesso schema degli eventi casuali).
# Solo DATI: quale milestone la fa scattare (trigger + filtro), cosa dice (chiavi tr()) e cosa fare dopo l'OK. Mostrata una volta
# per partita (GameData.seen_discovery_hints).

# Identificatore stabile (salvato in GameData.seen_discovery_hints).
@export var id: String = ""
# Chiave tr() del titolo della sezione nel DiscoveryPopup.
@export var title_key: String = ""
# Chiavi tr() dei paragrafi, uno per voce (possono contenere BBCode).
@export var paragraph_keys: Array[String] = []
@export var trigger_type: DiscoveryTypes.TriggerType = DiscoveryTypes.TriggerType.IDEA_COMPLETED
# Azione dopo l'OK (NONE = nessuna).
@export var close_action: DiscoveryTypes.CloseAction = DiscoveryTypes.CloseAction.NONE

@export_group("Filter")
# Filtri del trigger: vuoto = qualunque; quelli valorizzati devono valere TUTTI. Ognuno conta solo per il suo
# trigger_type (idea_id per IDEA_COMPLETED, building_* per BUILDING_COMPLETED).
@export var idea_id: String = ""
# Building.building_type_name (es. "pebble_circle").
@export var building_type_name: String = ""
# Nome di un campo bool di BuildingRules che deve essere true (es. "accepts_thoughts", "is_village_center").
@export var building_flag: String = ""


func matches(trigger: DiscoveryTypes.TriggerType, data: Dictionary) -> bool:
	if trigger != trigger_type:
		return false
	match trigger:
		DiscoveryTypes.TriggerType.IDEA_COMPLETED:
			return idea_id == "" or String(data.get("idea_id", "")) == idea_id
		DiscoveryTypes.TriggerType.BUILDING_COMPLETED:
			var building := data.get("building") as Building
			if building == null:
				return false
			if building_type_name != "" and building.building_type_name != building_type_name:
				return false
			if building_flag != "":
				if building.rules == null or not (building_flag in building.rules):
					return false
				return bool(building.rules.get(building_flag))
			return true
	return false
