class_name WorkAreaTypes
extends RefCounted

# Costanti delle zone di lavoro (2026-09-27, richiesta utente — work areas, passo 1a): elenco centrale dei lavori,
# dimensione massima, idea che sblocca lo strumento, tavolozza dei colori automatici.

# Lato massimo di una zona, in microcelle.
const MAX_SIDE: int = 10

# Idea che sblocca lo strumento "zone di lavoro" (bottone della barra in basso, IdeaUnlocksService).
const REQUIRED_IDEA_ID := "work_areas"
# Idea "Aree di lavoro" (2026-10-01, richiesta utente): estende le zone a tutte le risorse (e in futuro alla caccia).
# Per ora solo dato + voce tra gli sblocchi (IdeaUnlocksService.TOOLS); il limite al cibo senza di essa arriverà dopo.
const ADVANCED_REQUIRED_IDEA_ID := "work_areas_advanced"

# Lavori che una zona può abilitare: id stabile (salvato in WorkArea.enabled_jobs) -> dati del lavoro (2026-10-05:
# prima solo la chiave del nome). "name_key" = nome (spunta del pannello della zona); "required_idea_id" = idea che lo
# sblocca ("" = nessuna oltre a quella delle zone); "unlock_name_key" = voce tra gli sblocchi dell'idea nell'albero
# (IdeaUnlocksService). Un lavoro nuovo si aggiunge qui; is_job_unlocked è l'unico controllo dello sblocco.
const JOBS := {
	"haul": {"name_key": "work_area_job_haul", "required_idea_id": ""},
	"hunt": {"name_key": "work_area_job_hunt", "required_idea_id": ADVANCED_REQUIRED_IDEA_ID, "unlock_name_key": "unlock_job_hunt"},
	"quarry": {"name_key": "work_area_job_quarry", "required_idea_id": ADVANCED_REQUIRED_IDEA_ID, "unlock_name_key": "unlock_job_quarry"},
}


# true se il lavoro è sbloccato: nessuna idea richiesta, oppure idea completata dal popolo del giocatore. Lavoro
# sconosciuto = false.
static func is_job_unlocked(job_id: String) -> bool:
	if not JOBS.has(job_id):
		return false
	var idea_id := String(JOBS[job_id].get("required_idea_id", ""))
	if idea_id == "":
		return true
	var folk := GameSettings.active_human_folk
	return folk != null and folk.completed_ideas.has(idea_id)


# Chiave tr() del nome del lavoro.
static func get_job_name_key(job_id: String) -> String:
	return String(JOBS.get(job_id, {}).get("name_key", job_id))


# Idea che sblocca il lavoro ("" = nessuna).
static func get_job_required_idea_id(job_id: String) -> String:
	return String(JOBS.get(job_id, {}).get("required_idea_id", ""))

# Colori assegnati a rotazione alle zone nuove (WorkAreaService.create): ben distinguibili tra loro e dal terreno.
const PALETTE: Array[Color] = [
	Color(0.95, 0.35, 0.30),
	Color(0.25, 0.60, 0.95),
	Color(0.98, 0.80, 0.20),
	Color(0.65, 0.40, 0.90),
	Color(0.20, 0.80, 0.75),
	Color(0.98, 0.55, 0.15),
	Color(0.90, 0.40, 0.70),
	Color(0.55, 0.85, 0.30),
]
