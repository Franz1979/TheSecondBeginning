class_name BuildingConstructionStage
extends RefCounted

# Fase visibile del cantiere di un edificio (2026-11-19, richiesta utente — regola generale, prima per la vista 3D):
# il gioco decide la fase, chi disegna la mostra se ha il disegno di quella fase (altrimenti il cantiere generico).
#   COMPLETE (-1)  edificio finito
#   0              cantiere non ancora allestito (Building.site_setup_complete = false)
#   1..N           cantiere allestito: 1 + indice dell'ultima soglia di BuildingRules.construction_stage_thresholds
#                  raggiunta dal lavoro fatto (labor_accumulated / required_labor); senza soglie resta 1.
# Stateless, solo lettura.

const COMPLETE := -1
const NOT_SET_UP := 0


static func stage_of(building: Building) -> int:
	if building == null or building.is_complete:
		return COMPLETE
	if not building.site_setup_complete:
		return NOT_SET_UP
	var thresholds: Array[float] = building.rules.construction_stage_thresholds if building.rules != null else ([] as Array[float])
	var progress := labor_progress(building)
	var stage := 1
	for i in range(thresholds.size()):
		if progress >= thresholds[i]:
			stage = i + 1
	return stage


# true se l'edificio occupa già il terreno sotto di sé (2026-11-19, richiesta utente): finito, oppure cantiere con
# l'allestimento davvero partito (primo lavoro di SetupSiteAction) o già concluso. Prima la cella resta com'è: la
# vegetazione si vede, ricresce e si raccoglie. Usato da GameScene._building_positions_for_cell, dai selettori dei lotti
# e da PickUpAction (raccolta interrotta). Alberi e arbusti vivi del cantiere restano comunque fino alla pulizia.
static func occupies_ground(building: Building) -> bool:
	if building == null:
		return false
	if building.is_complete or building.site_setup_complete:
		return true
	return float(building.construction_progress.get("site_setup_days_done", 0.0)) > 0.0


# Lavoro fatto / lavoro richiesto, tra 0 e 1 (0 se il tipo non chiede lavoro).
static func labor_progress(building: Building) -> float:
	if building == null or building.rules == null or building.rules.required_labor <= 0:
		return 0.0
	var done := float(building.construction_progress.get("labor_accumulated", 0.0))
	return clampf(done / float(building.rules.required_labor), 0.0, 1.0)
