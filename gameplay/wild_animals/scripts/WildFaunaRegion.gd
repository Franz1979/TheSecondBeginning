class_name WildFaunaRegion
extends RefCounted

# Riquadro di una specie selvatica (2026-10-31, piano fauna ad hoc, passo 1a — WildFaunaService): blocco fisso di
# side×side macrocelle in cui vive al più una mandria della specie, tutta insieme. Creato una volta sola, la prima
# volta che una sua cella diventa viva; poi si va solo a riprenderlo. Dato di partita in GameData.wild_fauna.

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


func get_total() -> int:
	var total := 0
	for count in age_counts.values():
		total += int(count)
	return total
