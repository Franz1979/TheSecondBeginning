class_name StoragePilesSnapshot3D
extends RefCounted

# I mucchietti delle scorte di UNA cella come li mostra il 2D: uno per posto occupato del magazzino (sito di deposito,
# deposito coperto: griglia 3×3 di MicroCellRenderer._draw_deposit_site_storage_grid). Solo "qui c'è questo", non la
# quantità. Più i mucchi a terra (GroundPileView: fino a 4 risorse sparse, più piccole). Posizioni in microcelle,
# coordinate locali della cella. Array paralleli.

var positions := PackedVector2Array()
var resource_names := PackedStringArray()
# Seme fisso per mucchietto (edificio + posto): rotazione e piccola variazione di taglia.
var seeds := PackedInt32Array()
# Taglia rispetto al mucchietto del magazzino (mucchi a terra: GroundPileView.ICON_SCALE).
var scales := PackedFloat32Array()

# --- Carcasse dei mucchi a terra (GroundPileView._draw_carcass): posizione, lunghezza in microcelle, rotazione del
# 2D, colore della specie, 1 = uccello (pernice e derivate) ---
var carcass_positions := PackedVector2Array()
var carcass_lengths := PackedFloat32Array()
var carcass_rotations := PackedFloat32Array()
var carcass_colors := PackedColorArray()
var carcass_bird := PackedByteArray()


func size() -> int:
	return positions.size()


func add(position: Vector2, resource_name: String, seed: int, scale := 1.0) -> void:
	positions.append(position)
	resource_names.append(resource_name)
	seeds.append(seed)
	scales.append(scale)


# Impronta per Cell3D.needs_refresh: cambia quando un posto si riempie, si svuota o cambia risorsa.
func is_empty() -> bool:
	return positions.is_empty() and carcass_positions.is_empty()


func add_carcass(position: Vector2, length: float, rotation: float, color: Color, bird: bool) -> void:
	carcass_positions.append(position)
	carcass_lengths.append(length)
	carcass_rotations.append(rotation)
	carcass_colors.append(color)
	carcass_bird.append(1 if bird else 0)


func signature() -> Array:
	return [positions, resource_names, carcass_positions, carcass_lengths]
