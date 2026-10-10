class_name CommandShovelIcon
extends Node2D

# Icona del comando "clear_rubble" sulla mappa (2026-10-10, richiesta utente — sgombero delle macerie): la stessa pala del
# bottone "Sgombera" del pannello edificio (BuildingCommandIcon.KIND_CLEAR_RUBBLE), al posto della dinamite della
# demolizione. Stessa forma di CommandDynamiteIcon. Registrata in IconRegistry.COMMAND_ICON_NODES.

# Lato del riquadro del disegno sulla mappa (le icone di comando stanno in circa ±3-4 px).
const SIDE_PX: float = 8.0

var icon_scale: float = 1.0:
	set(value):
		icon_scale = value
		_fit()

var _icon: BuildingCommandIcon = null


func _init() -> void:
	_icon = BuildingCommandIcon.new()
	_icon.kind = BuildingCommandIcon.KIND_CLEAR_RUBBLE
	add_child(_icon)
	_fit()


func _fit() -> void:
	if _icon == null:
		return
	var side := SIDE_PX * icon_scale
	_icon.size = Vector2(side, side)
	_icon.position = -Vector2(side, side) * 0.5
	_icon.queue_redraw()
