class_name WorkAreaTypes
extends RefCounted

# Costanti delle zone di lavoro (2026-09-27, richiesta utente — work areas, passo 1a): elenco centrale dei lavori,
# dimensione massima, idea che sblocca lo strumento, tavolozza dei colori automatici.

# Lavori che una zona può abilitare: id stabile (salvato in WorkArea.enabled_jobs) -> chiave tr() del nome.
const JOBS := {
	"haul": "work_area_job_haul",
	"hunt": "work_area_job_hunt",
}

# Lato massimo di una zona, in microcelle.
const MAX_SIDE: int = 10

# Idea che sblocca lo strumento "zone di lavoro" (bottone della barra in basso, IdeaUnlocksService).
const REQUIRED_IDEA_ID := "work_areas"
# Idea "Aree di lavoro" (2026-10-01, richiesta utente): estende le zone a tutte le risorse (e in futuro alla caccia).
# Per ora solo dato + voce tra gli sblocchi (IdeaUnlocksService.TOOLS); il limite al cibo senza di essa arriverà dopo.
const ADVANCED_REQUIRED_IDEA_ID := "work_areas_advanced"

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
