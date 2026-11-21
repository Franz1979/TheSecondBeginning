class_name WalkSteps3D
extends RefCounted

# Passi lunghi (2026-11-20, richiesta utente): nel 3D le gambe vanno con la strada fatta, non a tempo. Per ogni corpo
# (id) si tiene il punto dell'ultimo fotogramma e la fase: mezzo giro (una gamba avanti) ogni `stride` microcelle. Fermo
# = fase 0 (gambe dritte). Usato da persone e animali; a ogni fotogramma phase() per ogni corpo, poi end_frame().

# Salto più lungo di così in un fotogramma (cambio di cella, ritorno dal fuori mappa): niente passo.
const MAX_STEP_JUMP := 2.0

# id -> Vector3(x, y del punto dell'ultimo fotogramma, fase). Rifatto a ogni fotogramma con solo i corpi visti (due
# dizionari scambiati, niente allocazioni).
var _steps: Dictionary = {}
var _steps_next: Dictionary = {}


func phase(id: int, ground: Vector2, moving: bool, stride: float) -> float:
	var value := 0.0
	if moving and _steps.has(id):
		var last: Vector3 = _steps[id]
		var walked := ground.distance_to(Vector2(last.x, last.y))
		value = last.z
		if walked < MAX_STEP_JUMP:
			value = fmod(value + walked / maxf(stride, 0.01) * PI, TAU)
	_steps_next[id] = Vector3(ground.x, ground.y, value)
	return value


# Distanza fatta dall'ultimo fotogramma (0 per un corpo nuovo).
func walked(id: int, ground: Vector2) -> float:
	if not _steps.has(id):
		return 0.0
	var last: Vector3 = _steps[id]
	return ground.distance_to(Vector2(last.x, last.y))


func end_frame() -> void:
	var previous := _steps
	_steps = _steps_next
	_steps_next = previous
	_steps_next.clear()
