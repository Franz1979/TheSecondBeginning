class_name BuildingFootprint
extends RefCounted

# Ingombro rettangolare degli edifici (2026-10-17, docs/design/building_footprint.md) — funzioni comuni senza stato.
# - BuildingRules.footprint è descritto con la porta a sud: x = larghezza (lato della porta), y = profondità;
# - la rotazione (Building.rotation, dove guarda la porta) gira tutto: con la porta a est o a ovest x e y si scambiano;
# - l'ancora (Building.micro_x/micro_y) è l'angolo in alto a sinistra del rettangolo già ruotato;
# - un edificio non esce dalla sua macrocella (fits_in_macrocell).
# Per un 1x1 ogni funzione restituisce ciò che si usava prima: la microcella dell'edificio e la cella accanto alla porta.


static func area(rules: BuildingRules) -> int:
	if rules == null:
		return 1
	return maxi(rules.footprint.x, 1) * maxi(rules.footprint.y, 1)


# Misura del rettangolo già ruotato, in microcelle.
static func size(rules: BuildingRules, rotation: GameTypes.Direction) -> Vector2i:
	if rules == null:
		return Vector2i(1, 1)
	var base := Vector2i(maxi(rules.footprint.x, 1), maxi(rules.footprint.y, 1))
	if rotation == GameTypes.Direction.EAST or rotation == GameTypes.Direction.WEST:
		return Vector2i(base.y, base.x)
	return base


static func size_of(building: Building) -> Vector2i:
	return size(building.rules, building.rotation)


static func is_large(rules: BuildingRules) -> bool:
	return area(rules) > 1


# Ancora dalla cella sotto il mouse, che sta al centro della sagoma (lato pari: la cella a destra/in basso del centro).
static func anchor_from_center(center_micro: Vector2i, rules: BuildingRules, rotation: GameTypes.Direction) -> Vector2i:
	return center_micro - size(rules, rotation) / 2


static func cells(anchor: Vector2i, rect_size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(rect_size.y):
		for dx in range(rect_size.x):
			result.append(anchor + Vector2i(dx, dy))
	return result


static func cells_of(building: Building) -> Array[Vector2i]:
	return cells(Vector2i(building.micro_x, building.micro_y), size_of(building))


# Quante microcelle del rettangolo stanno in `positions` (Array o Dictionary di Vector2i: basta .has()).
static func count_cells_in(building: Building, positions: Variant) -> int:
	var count := 0
	for cell in cells_of(building):
		if positions.has(cell):
			count += 1
	return count


# true se l'edificio occupa la microcella `micro` della macrocella `macro`.
static func covers(building: Building, macro: Vector2i, micro: Vector2i) -> bool:
	if building.macro_x != macro.x or building.macro_y != macro.y:
		return false
	var rect_size := size_of(building)
	return micro.x >= building.micro_x and micro.y >= building.micro_y \
		and micro.x < building.micro_x + rect_size.x and micro.y < building.micro_y + rect_size.y


# Centro del rettangolo in microcelle (1x1: micro + 0.5, il centro della microcella).
static func center_micro(building: Building) -> Vector2:
	return Vector2(building.micro_x, building.micro_y) + Vector2(size_of(building)) / 2.0


# Decisione 8: il rettangolo sta tutto dentro la macrocella.
static func fits_in_macrocell(anchor: Vector2i, rect_size: Vector2i) -> bool:
	return anchor.x >= 0 and anchor.y >= 0 \
		and anchor.x + rect_size.x - 1 < World.WIDTH and anchor.y + rect_size.y - 1 < World.HEIGHT


# Microcella davanti alla porta (fuori dal rettangolo): {"macro": Vector2i, "micro": Vector2i}, anche oltre il bordo
# di macrocella. La porta sta sul lato della larghezza, alla cella door_offset (-1 = centro) contando da sinistra con la
# porta a sud; poi si ruota a quarti di giro in senso orario (ordine di GameTypes.Direction: S -> W -> N -> E).
static func door_front(macro: Vector2i, anchor: Vector2i, rules: BuildingRules, rotation: GameTypes.Direction) -> Dictionary:
	return wrap_to_macro(macro, anchor + door_front_local(rules, rotation))


static func door_front_of(building: Building) -> Dictionary:
	return door_front(Vector2i(building.macro_x, building.macro_y), Vector2i(building.micro_x, building.micro_y), building.rules, building.rotation)


# Cella davanti alla porta rispetto all'ancora (può uscire dal rettangolo e dalla macrocella: non riportata).
static func door_front_local(rules: BuildingRules, rotation: GameTypes.Direction) -> Vector2i:
	var width: int = maxi(rules.footprint.x, 1) if rules != null else 1
	var depth: int = maxi(rules.footprint.y, 1) if rules != null else 1
	var offset: int = rules.door_offset if rules != null else -1
	if offset < 0:
		offset = (width - 1) / 2
	offset = mini(offset, width - 1)
	var point := Vector2i(offset, depth)
	var frame := Vector2i(width, depth)
	var steps: int = (int(rotation) - int(GameTypes.Direction.SOUTH) + 4) % 4
	for i in range(steps):
		point = Vector2i(frame.y - 1 - point.y, point.x)
		frame = Vector2i(frame.y, frame.x)
	return point


# Punto a metà del lato della porta, in microcelle e rispetto al centro del rettangolo (per il disegno della porta).
static func door_edge_offset(rules: BuildingRules, rotation: GameTypes.Direction) -> Vector2:
	var front_center := Vector2(door_front_local(rules, rotation)) + Vector2(0.5, 0.5)
	return front_center - Vector2(direction_vector(rotation)) * 0.5 - Vector2(size(rules, rotation)) / 2.0


static func direction_vector(direction: GameTypes.Direction) -> Vector2i:
	match direction:
		GameTypes.Direction.NORTH:
			return Vector2i(0, -1)
		GameTypes.Direction.EAST:
			return Vector2i(1, 0)
		GameTypes.Direction.WEST:
			return Vector2i(-1, 0)
		_:
			return Vector2i(0, 1)


# Fondo di terra battuta sotto un edificio grande (2026-10-17): per ogni microcella del rettangolo [microcella, maschera dei
# lati] con la stessa regola del tile singolo (GameScene._dirt_ground_neighbor_mask: bit 1 << lato, lati N, E, S, W, dritto
# verso una microcella in `tiles`). `tiles` = microcelle occupate da edifici completi, chiave Vector4i(macro, micro): le
# celle dello stesso rettangolo ci sono, quindi i lati interni sono dritti e il fondo è continuo.
static func ground_tile_masks(building: Building, tiles: Dictionary) -> Array:
	var result: Array = []
	var macro := Vector2i(building.macro_x, building.macro_y)
	var side_offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for cell in cells_of(building):
		var mask := 0
		for side in range(4):
			var neighbor := wrap_to_macro(macro, cell + side_offsets[side])
			var neighbor_macro: Vector2i = neighbor["macro"]
			var neighbor_micro: Vector2i = neighbor["micro"]
			if tiles.has(Vector4i(neighbor_macro.x, neighbor_macro.y, neighbor_micro.x, neighbor_micro.y)):
				mask |= 1 << side
		result.append([cell, mask])
	return result


# Riporta una microcella appena fuori dalla macrocella nella macrocella vicina (un passo, come la porta di prima).
static func wrap_to_macro(macro: Vector2i, micro: Vector2i) -> Dictionary:
	var target_macro := macro
	var target_micro := micro
	if target_micro.x < 0:
		target_macro.x -= 1
		target_micro.x += World.WIDTH
	elif target_micro.x >= World.WIDTH:
		target_macro.x += 1
		target_micro.x -= World.WIDTH
	if target_micro.y < 0:
		target_macro.y -= 1
		target_micro.y += World.HEIGHT
	elif target_micro.y >= World.HEIGHT:
		target_macro.y += 1
		target_micro.y -= World.HEIGHT
	return {"macro": target_macro, "micro": target_micro}
