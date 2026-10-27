class_name CommandCouncilSuccessIcon
extends Node2D

# Esito riuscito di una riunione politica (2026-10-26, lite del gran consiglio): l'anello del consiglio (CommandCouncilIcon)
# con le tre teste e una spunta verde sopra. Registrata in IconRegistry.COMMAND_ICON_NODES ("council_success").

const CHECK := Color(0.30, 0.78, 0.30, 1.0)
const CHECK_WIDTH_PX: float = 0.7


func _draw() -> void:
	CommandCouncilIcon.draw_council(self)
	var points := PackedVector2Array([Vector2(-1.4, -3.6), Vector2(-0.4, -2.6), Vector2(1.6, -4.8)])
	draw_polyline(points, CommandCouncilIcon.OUTLINE, CHECK_WIDTH_PX + 0.5, true)
	draw_polyline(points, CHECK, CHECK_WIDTH_PX, true)
