class_name CommandDynamiteIcon
extends Node2D

# Icona del comando "demolish" sulla mappa (2026-10-07, richiesta utente — prima il piccone, uguale a "Estrai"): la
# stessa dinamite del bottone "Demolisci" del pannello edificio (BuildingCommandIcon.KIND_DEMOLISH), un solo disegno.
# Registrata in IconRegistry.COMMAND_ICON_NODES; origine = centro dell'icona, pixel locali della cella (10 px = 1
# microcella), come le altre icone di comando. `icon_scale` come CommandPickaxeIcon (bottoni, CommandButtonIcon).

# Lato del riquadro del disegno sulla mappa (le icone di comando stanno in circa ±3-4 px).
const SIDE_PX: float = 8.0

var icon_scale: float = 1.0:
	set(value):
		icon_scale = value
		_fit()

var _icon: BuildingCommandIcon = null


func _init() -> void:
	_icon = BuildingCommandIcon.new()
	_icon.kind = BuildingCommandIcon.KIND_DEMOLISH
	add_child(_icon)
	_fit()


func _fit() -> void:
	if _icon == null:
		return
	var side := SIDE_PX * icon_scale
	_icon.size = Vector2(side, side)
	_icon.position = -Vector2(side, side) * 0.5
	_icon.queue_redraw()
