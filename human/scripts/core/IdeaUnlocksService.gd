class_name IdeaUnlocksService
extends RefCounted

# "Cosa sblocca questa idea" (2026-09-21, richiesta utente) — calcolo puro, DERIVATO dai dati:
# nessun campo "sblocca" scritto a mano su Idea.gd, la relazione si legge dal lato opposto
# (Idea.prerequisites, BuildingRules.required_idea_id, SecondaryResourceRules.required_idea_id).
# Stateless (RefCounted, static func), stesso pattern degli altri *Service di questa cartella.
#
# Aggiungere un nuovo tipo di sbloccabile con required_idea_id (es. funzioni) = UNA sorgente in più
# in _sources() sotto (kind, chiave tr() dell'etichetta di gruppo, funzione di raccolta) + la
# funzione di raccolta stessa; get_unlocks/format_lines non cambiano.


# Gruppi NON vuoti, nell'ordine di _sources(): [{"kind": StringName, "label_key": String,
# "entries": [{"id": String, "display_name": String}]}]. display_name già tradotto
# (TranslationServer, non tr(): questo file è static, vedi IconRegistry.get_resource_display_name).
static func get_unlocks(idea_id: String) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for source in _sources():
		var entries: Array[Dictionary] = source["collect"].call(idea_id)
		if entries.is_empty():
			continue
		groups.append({"kind": source["kind"], "label_key": source["label_key"], "entries": entries})
	return groups


# Una riga per gruppo, "<etichetta>: <nome>, <nome>" — stesso formato per popup di sblocco e
# pannello di dettaglio del TechTreePanel, così non divergono. Array vuoto se non sblocca nulla.
# is_hidden (opzionale): Callable(kind: StringName, id: String) -> bool; per le voci nascoste il
# nome diventa "???" (il TechTreePanel copre così le idee non ancora visibili).
static func format_lines(idea_id: String, is_hidden: Callable = Callable()) -> Array[String]:
	var lines: Array[String] = []
	for group in get_unlocks(idea_id):
		var names: Array[String] = []
		for entry in group["entries"]:
			if is_hidden.is_valid() and is_hidden.call(group["kind"], entry["id"]):
				names.append("???")
			else:
				names.append(entry["display_name"])
		lines.append("%s: %s" % [TranslationServer.translate(group["label_key"]), ", ".join(names)])
	return lines


# Sola riga delle idee successive, "Prossima idea da ricercare: <nome>, <nome>" (2026-10-01 — sezione dell'idea
# regalata nel popup, GameScene._on_idea_completed). Stesso is_hidden di format_lines. "" se non apre altre idee.
static func format_next_ideas_line(idea_id: String, is_hidden: Callable = Callable()) -> String:
	var names: Array[String] = []
	for entry in _collect_ideas(idea_id):
		if is_hidden.is_valid() and is_hidden.call(&"idea", entry["id"]):
			names.append("???")
		else:
			names.append(entry["display_name"])
	if names.is_empty():
		return ""
	return "%s: %s" % [TranslationServer.translate("unlock_next_ideas"), ", ".join(names)]


# Elenco delle sorgenti di sblocco — l'UNICO punto da toccare per una nuova. Funzione (non const)
# perché i Callable statici non sono espressioni costanti.
static func _sources() -> Array[Dictionary]:
	return [
		{"kind": &"idea", "label_key": "unlock_kind_idea", "collect": IdeaUnlocksService._collect_ideas},
		{"kind": &"building", "label_key": "unlock_kind_building", "collect": IdeaUnlocksService._collect_buildings},
		{"kind": &"resource", "label_key": "unlock_kind_resource", "collect": IdeaUnlocksService._collect_resources},
		# Strumenti dell'interfaccia (2026-09-27, richiesta utente — zone di lavoro), vedi TOOLS.
		{"kind": &"tool", "label_key": "unlock_kind_tool", "collect": IdeaUnlocksService._collect_tools},
	]


# Strumenti dell'interfaccia sbloccati da un'idea (2026-09-27): id -> {"name_key", "required_idea_id"}. Un nuovo
# strumento legato a un'idea si aggiunge qui, così l'albero lo mostra tra gli sblocchi.
const TOOLS := {
	"work_areas": {"name_key": "unlock_tool_work_areas", "required_idea_id": WorkAreaTypes.REQUIRED_IDEA_ID},
	"work_areas_advanced": {"name_key": "unlock_tool_work_areas_advanced", "required_idea_id": WorkAreaTypes.ADVANCED_REQUIRED_IDEA_ID},
	# Assegnazione delle task (2026-10-07): bottone della riga del governo del villaggio (GameInfoPanel).
	"task_assignment": {"name_key": "unlock_tool_task_assignment", "required_idea_id": TaskAssignmentPanel.REQUIRED_IDEA_ID},
}


static func _collect_tools(idea_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for tool_id in TOOLS.keys():
		var tool: Dictionary = TOOLS[tool_id]
		if String(tool["required_idea_id"]) == idea_id:
			entries.append({"id": String(tool_id), "display_name": TranslationServer.translate(String(tool["name_key"]))})
	# Lavori delle zone sbloccati dall'idea (2026-10-05): derivati da WorkAreaTypes.JOBS ("Caccia nelle zone",
	# "Estrazione nelle zone"), un lavoro nuovo compare da solo.
	for job_id in WorkAreaTypes.JOBS.keys():
		var job: Dictionary = WorkAreaTypes.JOBS[job_id]
		if String(job.get("required_idea_id", "")) == idea_id and job.has("unlock_name_key"):
			entries.append({"id": "work_area_job_%s" % job_id, "display_name": TranslationServer.translate(String(job["unlock_name_key"]))})
	return entries


# Idee successive: quelle che hanno `idea_id` tra i prerequisites.
static func _collect_ideas(idea_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for other_id in IdeaCalculator.list_idea_ids():
		var other := IdeaCalculator.get_idea(other_id)
		if other != null and other.prerequisites.has(idea_id):
			entries.append({"id": other_id, "display_name": TranslationServer.translate(other.display_name)})
	return entries


static func _collect_buildings(idea_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules != null and rules.required_idea_id == idea_id:
			entries.append({"id": type_name, "display_name": TranslationServer.translate(rules.building_name)})
	return entries


static func _collect_resources(idea_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules != null and rules.required_idea_id == idea_id:
			entries.append({"id": resource_name, "display_name": IconRegistry.get_resource_display_name(resource_name)})
	return entries
