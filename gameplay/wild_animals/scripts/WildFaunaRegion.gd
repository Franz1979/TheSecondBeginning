class_name WildFaunaRegion
extends RefCounted

# Riquadro di una specie selvatica (2026-10-31, piano fauna ad hoc, passo 1a — WildFaunaService): blocco fisso di
# side×side macrocelle in cui vive al più una mandria della specie, tutta insieme. Creato una volta sola, la prima
# volta che una sua cella diventa viva; poi si va solo a riprenderlo. Dato di partita in GameData.wild_fauna, salvato
# (passo 4) con to_save_data/from_save_data.

enum Status {
	NEVER, # nessuna cella del riquadro va bene alla specie: qui non verrà mai
	ABSENT, # habitat adatto, ma la mandria non c'è (da extinct_since_day)
	PRESENT, # c'è una mandria (age_counts), oggi in current_cell
}

var species: String = ""
# Coordinate del riquadro (macrocella ÷ side) e lato in macrocelle.
var region: Vector2i = Vector2i.ZERO
var side: int = 1
var status: Status = Status.NEVER
# Mandria per fascia d'età (GameTypes.AgeBand -> int).
var age_counts: Dictionary = {}
# Macrocella del riquadro in cui sta la mandria, (-1, -1) se è altrove.
var current_cell: Vector2i = Vector2i(-1, -1)
# Macrocella da cui è arrivata (passo 7c, il bordo da cui entra), (-1, -1) se da nessuna del riquadro. Salvata dal
# 2026-11-11: chi segue la mandria la ritrova vicino al bordo da cui è entrata.
var previous_cell: Vector2i = Vector2i(-1, -1)
# Attraversamento (2026-11-11, richiesta utente): lato (una delle 4 direzioni) da cui la mandria uscirà da current_cell
# per entrare nella cella accanto, ZERO se nessuna cella accanto del riquadro le va bene (allora resta e vaga).
var exit_side: Vector2i = Vector2i.ZERO
# Giorni che restano alla mandria in current_cell, e ultimo giorno (assoluto) in cui il conto è stato fatto: più vecchio
# di ieri = nessuno guardava il riquadro, la mandria si rimette in una cella a caso (WildFaunaService).
var stay_remaining: int = 0
var last_move_day: int = 0
var last_update_day: int = 0
# Giorno (assoluto) da cui la specie manca dal riquadro, -1 se presente o mai.
var extinct_since_day: int = -1
# La mandria c'era ed è sparita (caccia, vecchiaia): torna dopo AnimalRules.recolonization_years. False per i riquadri
# vuoti fin dall'inizio, che restano vuoti.
var returns: bool = false


# Coordinate come [x, y] e conteggi come [giovani, adulti, vecchi]: il JSON non ha Vector2i né chiavi intere.
func to_save_data() -> Dictionary:
	return {
		"species": species,
		"region": [region.x, region.y],
		"side": side,
		"status": int(status),
		"age_counts": [int(age_counts.get(GameTypes.AgeBand.YOUNG, 0)), int(age_counts.get(GameTypes.AgeBand.ADULT, 0)),
			int(age_counts.get(GameTypes.AgeBand.OLD, 0))],
		"current_cell": [current_cell.x, current_cell.y],
		"previous_cell": [previous_cell.x, previous_cell.y],
		"exit_side": [exit_side.x, exit_side.y],
		"stay_remaining": stay_remaining,
		"last_move_day": last_move_day,
		"last_update_day": last_update_day,
		"extinct_since_day": extinct_since_day,
		"returns": returns,
	}


static func from_save_data(data: Dictionary) -> WildFaunaRegion:
	var entry := WildFaunaRegion.new()
	entry.species = String(data.get("species", ""))
	var saved_region: Array = data.get("region", [0, 0])
	entry.region = Vector2i(int(saved_region[0]), int(saved_region[1]))
	entry.side = int(data.get("side", 1))
	entry.status = int(data.get("status", Status.NEVER)) as Status
	var counts: Array = data.get("age_counts", [0, 0, 0])
	entry.age_counts = {
		GameTypes.AgeBand.YOUNG: int(counts[0]),
		GameTypes.AgeBand.ADULT: int(counts[1]),
		GameTypes.AgeBand.OLD: int(counts[2]),
	}
	var cell: Array = data.get("current_cell", [-1, -1])
	entry.current_cell = Vector2i(int(cell[0]), int(cell[1]))
	var previous: Array = data.get("previous_cell", [-1, -1])
	entry.previous_cell = Vector2i(int(previous[0]), int(previous[1]))
	var exit: Array = data.get("exit_side", [0, 0])
	entry.exit_side = Vector2i(int(exit[0]), int(exit[1]))
	entry.stay_remaining = int(data.get("stay_remaining", 0))
	entry.last_move_day = int(data.get("last_move_day", 0))
	entry.last_update_day = int(data.get("last_update_day", 0))
	entry.extinct_since_day = int(data.get("extinct_since_day", -1))
	entry.returns = bool(data.get("returns", false))
	return entry


func get_total() -> int:
	var total := 0
	for count in age_counts.values():
		total += int(count)
	return total
