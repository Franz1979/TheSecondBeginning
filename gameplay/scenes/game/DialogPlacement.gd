class_name DialogPlacement
extends RefCounted

# Posizione dei popup dei comandi aperti dalla lista degli individui (2026-10-09, richiesta utente — Raccogli nelle zone di
# lavoro, Caccia, Taglia, Estrai): la finestra resta identica, cambia solo dove compare. `anchor` = {"right": x del
# bordo da allineare (il bordino azzurro interno dell'info panel, cioè il bordo destro della sua area scura), "top": y
# della riga cliccata}, in coordinate della finestra di gioco; {} = al centro dello schermo, come sempre (comandi dalla
# mappa). Con un anchor il bordo VISIBILE della finestra (cornice compresa: lo stile "embedded_border" sporge oltre
# position/size, a destra di expand_margin_right e in alto della barra del titolo) ha il lato destro su "right" (la
# finestra, più larga del pannello, sporge a sinistra) e la barra del titolo che parte all'altezza di "top"; poi viene
# spostata quanto basta per restare tutta nello schermo, cornice compresa. Stateless, statica.
static func place(window: Window, anchor: Dictionary) -> void:
	if window == null:
		return
	if anchor.is_empty():
		window.move_to_center()
		return
	var frame := Vector4(0.0, 0.0, 0.0, 0.0)  # sporgenze della cornice: sinistra, sopra, destra, sotto
	var border := window.get_theme_stylebox("embedded_border") as StyleBoxFlat
	if border != null:
		frame = Vector4(border.expand_margin_left, border.expand_margin_top, border.expand_margin_right, border.expand_margin_bottom)
	else:
		frame.y = float(window.get_theme_constant("title_height"))
	var screen := window.get_tree().root.get_visible_rect().size
	var width := float(window.size.x)
	var height := float(window.size.y)
	var x := float(anchor.get("right", screen.x)) - frame.z - width
	var y := float(anchor.get("top", 0.0)) + frame.y
	x = clampf(x, frame.x, maxf(screen.x - frame.z - width, frame.x))
	y = clampf(y, frame.y, maxf(screen.y - frame.w - height, frame.y))
	window.position = Vector2i(roundi(x), roundi(y))
