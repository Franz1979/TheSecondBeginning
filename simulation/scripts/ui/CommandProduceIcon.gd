class_name CommandProduceIcon
extends Node2D

# Icona del comando "produce" (2026-09-26, richiesta utente — icone di comando disegnate, stesso stile
# del mirino CrosshairIcon): due martelli incrociati, come l'emoji ⚒️ che sostituisce. Riusa la sagoma
# di CommandHammerIcon (draw_hammer) specchiata. Registrata in IconRegistry.COMMAND_ICON_NODES; origine
# = centro dell'icona, pixel locali della cella (10 px = 1 microcella).


func _draw() -> void:
	# Il secondo martello, ruotato di 90°, ha la testa in alto a sinistra: incrociato con il primo.
	CommandHammerIcon.draw_hammer(self, -PI / 2.0)
	CommandHammerIcon.draw_hammer(self, 0.0)
