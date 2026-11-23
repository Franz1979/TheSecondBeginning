class_name PlacementGhostSnapshot3D
extends RefCounted

# L'anteprima del piazzamento di un edificio (BuildingGhost del gioco) come la vede il 2D in questo fotogramma: tipo,
# rettangolo occupato, porta, valido o no. Rettangolo in microcelle locali della cella sotto il mouse (`coords`, angolo
# `origin` in coordinate della vista). active = false: nessun piazzamento in corso o mouse fuori dalle celle accese.

var active: bool = false
var type_name: String = ""
var coords: Vector2i = Vector2i.ZERO
var origin: Vector2 = Vector2.ZERO
var rect: Rect2 = Rect2()
# Direzione della porta come nel 2D (TentShapes.direction_vector): x = est, y = sud.
var door_direction: Vector2 = Vector2(0, 1)
# Punto a metà del lato della porta rispetto al centro del rettangolo; Vector2.INF = senza porta.
var door_offset: Vector2 = Vector2.INF
var buildable: bool = true
# Vicini del pezzo per gli edifici lineari (il vallo), dall'anteprima 2D (BuildingGhost._linear_mask); 0 per gli altri.
var linear_mask: int = 0


# Impronta: cambia quando va rifatto il rettangolo a terra (non a ogni fotogramma).
func signature() -> Array:
	return [active, type_name, coords, rect, door_direction, door_offset, buildable]
