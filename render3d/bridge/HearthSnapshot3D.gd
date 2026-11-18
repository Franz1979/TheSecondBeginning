class_name HearthSnapshot3D
extends RefCounted

# I focolari finiti di una cella, come li disegna il 2D (stesso elenco di edifici, stesso centro), con il loro stato
# letto dall'edificio del gioco. Posizioni in microcelle, coordinate locali della cella. Array paralleli.

# Spento: niente combustibile nel deposito.
const OUT := 0
# Braci: c'è combustibile, ma nessuno ci sta cucinando.
const EMBERS := 1
# Acceso: qualcuno ci sta facendo una ricetta che brucia combustibile (Building.smoking_now).
const BURNING := 2

var centers := PackedVector2Array()
var states := PackedByteArray()
# Seme fisso per focolare (id dell'edificio): forma e posizione delle pietre.
var seeds := PackedInt32Array()


func size() -> int:
	return centers.size()
