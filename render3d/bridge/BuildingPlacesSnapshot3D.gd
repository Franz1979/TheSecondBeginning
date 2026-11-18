class_name BuildingPlacesSnapshot3D
extends RefCounted

# Gli edifici finiti di UN tipo in una cella, come li disegna il 2D (stesso elenco, stesso centro): solo dove sono. Per
# gli edifici che in 3D non hanno bisogno d'altro (es. il sito di deposito vuoto). Posizioni in microcelle, coordinate
# locali della cella. Array paralleli.

var centers := PackedVector2Array()
# Seme fisso per edificio (id): variante di forma.
var seeds := PackedInt32Array()


func size() -> int:
	return centers.size()
