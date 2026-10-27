class_name CommandCouncilQuarrelIcon
extends Node2D

# Lite in una riunione politica (2026-10-26, gran consiglio): l'anello del consiglio (CommandCouncilIcon) con le teste
# scostate verso l'esterno e una saetta rossa al centro. Registrata in IconRegistry.COMMAND_ICON_NODES ("council_quarrel").

const BOLT := Color(0.88, 0.20, 0.14, 1.0)
const HEAD_RING_RADIUS: float = 1.4


func _draw() -> void:
	CommandCouncilIcon.draw_council(self, HEAD_RING_RADIUS)
	var bolt := PackedVector2Array([
		Vector2(0.3, -1.6), Vector2(-0.6, 0.1), Vector2(0.1, 0.1), Vector2(-0.4, 1.7), Vector2(0.8, -0.3), Vector2(0.1, -0.3),
	])
	draw_colored_polygon(bolt, BOLT)
	bolt.append(bolt[0])
	draw_polyline(bolt, CommandCouncilIcon.OUTLINE, CommandCouncilIcon.OUTLINE_WIDTH_PX, true)
