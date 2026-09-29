class_name VegetationClearingService
extends RefCounted

# Regola UNICA "chi può liberare il terreno da alberi e cespugli" (2026-09-28, richiesta utente). Usata sia dal
# piazzamento degli edifici (GameScene._can_tribe_cut -> BuildingVerificationService criterio 10) sia dalla
# ClearAction del cantiere: cambiare qui i requisiti li cambia ovunque. Stateless, stesso pattern dei *Service.
#
# Oggi: serve un attrezzo che copra TUTTE le REQUIRED_TOOL_CATEGORIES — CHOPPING, non CUTTING: il coltello non basta —
# in cintura o nello zaino (ToolGateService.has_tool_for). Un attrezzo le copre se le elenca in SecondaryResourceRules.tool_categories: un
# nuovo .tres con CHOPPING tra le categorie viene riconosciuto senza toccare codice. L'erba non richiede nulla.

const REQUIRED_TOOL_CATEGORIES: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.CHOPPING]


# Categorie di attrezzo necessarie per ripulire QUESTA microcella: REQUIRED_TOOL_CATEGORIES se ci sono alberi o
# cespugli vivi, altrimenti nessuna (solo erba o microcella vuota).
static func get_required_tool_categories(macro_state: MacroCellState, pos: Vector2i) -> Array[TaskTypes.ToolCategory]:
	var required: Array[TaskTypes.ToolCategory] = []
	if BuildingSiteClearingService.has_woody_vegetation(macro_state, pos):
		required.assign(REQUIRED_TOOL_CATEGORIES)
	return required


# individual non null: può tagliare LUI. individual null: può tagliare almeno un membro di `tribe`.
static func can_clear_vegetation(individual: HumanIndividual, tribe: Array[HumanIndividual] = []) -> bool:
	if individual != null:
		return _has_required_tools(individual)
	for member in tribe:
		if _has_required_tools(member):
			return true
	return false


static func _has_required_tools(individual: HumanIndividual) -> bool:
	for category in REQUIRED_TOOL_CATEGORIES:
		if not ToolGateService.has_tool_for(individual, category):
			return false
	return true
