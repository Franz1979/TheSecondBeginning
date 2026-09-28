class_name CommandButtonIcon
extends Control

# Icona di un bottone della barra dei comandi del pipottino (2026-09-27, richiesta utente — work areas passo 3b): la
# STESSA icona disegnata che lampeggia sul bersaglio quando il comando parte (IconRegistry.COMMAND_ICON_NODES, un
# Node2D centrato in pixel di cella), qui centrata nel bottone. Così bottone e lampeggio del comando condividono un
# solo disegno. Solo disegno: i clic arrivano al bottone sotto.
#
# Nitidezza (2026-09-28): l'icona NON si ingrandisce con `scale` del nodo. Il disegno è vettoriale in unità di circa
# ±3 px e Godot costruisce il bordo antialiasato (sfumatura di ~1 px) e la suddivisione dei cerchi in coordinate locali,
# prima della trasformazione: con scale ≈ 4-5 quella sfumatura diventava 4-5 px sullo schermo, icona sfocata. Si passa
# invece il fattore all'icona (`icon_scale`), che moltiplica coordinate e spessori e disegna alla dimensione reale del
# bottone, come le icone degli strumenti (Control che disegnano nel proprio rettangolo). Un'icona senza `icon_scale`
# ripiega su `scale`.

# Lato (in pixel locali dell'icona di comando) che deve riempire il bottone: le icone di comando stanno in circa ±3 px.
const ICON_EXTENT_PX: float = 7.0
const FILL_RATIO: float = 0.8

var _icon: Node2D = null


func _init(command_icon_key: String) -> void:
	_icon = IconRegistry.get_command_icon_node(command_icon_key)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _icon != null:
		add_child(_icon)
	resized.connect(_fit_icon)
	_fit_icon()


func _fit_icon() -> void:
	if _icon == null:
		return
	# Centro su pixel intero: niente mezzi pixel che ammorbidiscono le linee.
	_icon.position = (size * 0.5).round()
	var factor := minf(size.x, size.y) * FILL_RATIO / ICON_EXTENT_PX
	if "icon_scale" in _icon:
		_icon.scale = Vector2.ONE
		_icon.set("icon_scale", factor)
		_icon.queue_redraw()
	else:
		_icon.scale = Vector2.ONE * factor
