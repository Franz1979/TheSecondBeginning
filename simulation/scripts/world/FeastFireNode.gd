class_name FeastFireNode
extends Node2D

# Falò acceso nel cerchio di sassi dello Spiazzo delle feste durante il banchetto (2026-10-17, richiesta utente): un nodo a
# parte, figlio del contenitore della cella, come i rametti del cantiere — la fiamma si disegna una volta sola qui e il
# tremolio è un tween del solo nodo, così il disegno della cella (MicroCellRenderer) non si appesantisce e non si rifà.
# Acceso a inizio festa e spento a fine festa o all'annullo (GameScene, SocialRiteService.has_lit_bonfire); nome
# deterministico NAME_PREFIX + id edificio per ritrovarlo.

const NAME_PREFIX := "FeastFire_"
# Stessi colori del focolare (MicroCellRenderer.CAMPFIRE_FLAME_*), misure in pixel della mappa.
const FLAME_COLOR := Color(0.95, 0.45, 0.10, 1.0)
const FLAME_CORE_COLOR := Color(1.0, 0.85, 0.30, 1.0)
const FLAME_RADIUS: float = 2.0
const FLAME_CORE_RADIUS: float = 1.0
const TONGUE_COUNT: int = 5
const TONGUE_HEIGHT: float = 2.4
const TONGUE_HALF_WIDTH: float = 0.7
const FLICKER_SECONDS: float = 0.35


# Accende il falò di `building` nel contenitore della sua cella (no-op se è già acceso).
static func light(cell_container: Node2D, building: Building) -> void:
	if cell_container == null or building == null or cell_container.get_node_or_null(NAME_PREFIX + str(building.id)) != null:
		return
	var fire := FeastFireNode.new()
	fire.name = NAME_PREFIX + str(building.id)
	fire.position = BuildingFootprint.center_micro(building) * MicroCellRenderer.CELL_SIZE
	fire.z_index = 1
	cell_container.add_child(fire)


# Spegne il falò di `building` (no-op se non c'è).
static func put_out(cell_container: Node2D, building: Building) -> void:
	if cell_container == null or building == null:
		return
	var fire := cell_container.get_node_or_null(NAME_PREFIX + str(building.id))
	if fire != null:
		fire.queue_free()


func _ready() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "scale", Vector2(1.08, 0.92), FLICKER_SECONDS)
	tween.parallel().tween_property(self, "modulate:a", 0.85, FLICKER_SECONDS)
	tween.tween_property(self, "scale", Vector2(0.94, 1.06), FLICKER_SECONDS)
	tween.parallel().tween_property(self, "modulate:a", 1.0, FLICKER_SECONDS)


func _draw() -> void:
	# Lingue di fuoco a raggiera, poi il corpo arancio e il nucleo giallo (come il focolare).
	for i in range(TONGUE_COUNT):
		var angle: float = -PI / 2.0 + (float(i) - float(TONGUE_COUNT - 1) / 2.0) * 0.45
		var direction := Vector2(cos(angle), sin(angle))
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([
			side * TONGUE_HALF_WIDTH, direction * (FLAME_RADIUS + TONGUE_HEIGHT), -side * TONGUE_HALF_WIDTH,
		]), FLAME_COLOR)
	draw_circle(Vector2.ZERO, FLAME_RADIUS, FLAME_COLOR)
	draw_circle(Vector2.ZERO, FLAME_CORE_RADIUS, FLAME_CORE_COLOR)
