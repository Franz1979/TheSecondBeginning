class_name WorkArea
extends RefCounted

# Zona di lavoro (2026-09-27, richiesta utente — work areas, passo 1a): un rettangolo di microcelle disegnato dal
# giocatore dentro UNA macrocella (massimo WorkAreaTypes.MAX_SIDE × MAX_SIDE), con nome, colore, lavori abilitati e
# filtri. In questo passo nessun pipottino ci lavora ancora: solo dato, salvataggio, disegno e layer. Creata,
# eliminata e cercata da WorkAreaService; salvata in GameData.work_areas (GameSaveService "work_areas").

var id: int = 0
var name: String = ""
var color: Color = Color.WHITE
var macro_coords: Vector2i = Vector2i.ZERO
# Rettangolo in microcelle LOCALI alla macrocella (0..World.WIDTH-1), estremo escluso come ogni Rect2i.
var rect: Rect2i = Rect2i()
# Id dei lavori abilitati (WorkAreaTypes.JOBS), nessuno di default.
var enabled_jobs: Array[String] = []
# Filtri per lavoro: id lavoro -> Dictionary (contenuto definito dai lavori stessi, JSON-nativo). Vuoto = nessun filtro.
var filters: Dictionary = {}
# Contatore delle modifiche (runtime, non salvato): la vista si ridisegna quando cambia.
var revision: int = 0


# true se la microcella `microcell` (locale a `at_macro_coords`) è dentro la zona.
func contains(at_macro_coords: Vector2i, microcell: Vector2i) -> bool:
	return at_macro_coords == macro_coords and rect.has_point(microcell)


func to_save_data() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"color": color.to_html(true),
		"macro_x": macro_coords.x,
		"macro_y": macro_coords.y,
		"rect_x": rect.position.x,
		"rect_y": rect.position.y,
		"rect_w": rect.size.x,
		"rect_h": rect.size.y,
		"enabled_jobs": Array(enabled_jobs),
		"filters": filters,
	}


# null se i dati non sono una zona valida (vedi WorkAreaService.is_valid_rect).
static func from_save_data(data: Dictionary) -> WorkArea:
	var area := WorkArea.new()
	area.id = int(data.get("id", 0))
	area.name = String(data.get("name", ""))
	area.color = Color.from_string(String(data.get("color", "")), Color.WHITE)
	area.macro_coords = Vector2i(int(data.get("macro_x", 0)), int(data.get("macro_y", 0)))
	area.rect = Rect2i(int(data.get("rect_x", 0)), int(data.get("rect_y", 0)), int(data.get("rect_w", 0)), int(data.get("rect_h", 0)))
	for job_id in data.get("enabled_jobs", []):
		area.enabled_jobs.append(String(job_id))
	var raw_filters = data.get("filters", {})
	area.filters = raw_filters if raw_filters is Dictionary else {}
	# JSON non distingue int/float: le categorie dei filtri tornano int (confronti con SecondaryResourceTypes.Category).
	for job_id in area.filters.keys():
		var job_filters = area.filters[job_id]
		if job_filters is Dictionary and job_filters.has("categories"):
			var categories: Array = []
			for category in job_filters["categories"]:
				categories.append(int(category))
			job_filters["categories"] = categories
	if not WorkAreaService.is_valid_rect(area.rect):
		return null
	return area
