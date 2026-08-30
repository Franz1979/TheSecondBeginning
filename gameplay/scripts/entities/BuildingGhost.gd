class_name BuildingGhost
extends Node2D

# Anteprima visiva "fantasma" di un edificio che segue il mouse — per ora SOLO estetica, nessuna
# azione di piazzamento reale (vedi BuildBar/GameScene: nessun sistema di materiali/spazio libero/
# tech esiste ancora, vedi discussione con l'utente). Disegna una capanna stilizzata con la stessa
# convenzione di VERTICALITÀ già usata per gli alberi in MicroCellRenderer._compute_tree_visual
# (tronco+chioma che si sviluppano VERSO L'ALTO da un punto di ancoraggio a terra) — non una vista
# dall'alto come un primo tentativo scartato: pareti (rettangolo) + tetto (triangolo) sopra,
# entrambi centrati sullo stesso punto di ancoraggio (0,0) = il "terreno" sotto il mouse.
# Semitrasparente apposta per leggersi chiaramente come anteprima, non un edificio già piazzato.
#
# Nodo puro (Node2D + _draw(), niente MultiMesh: qui ne esiste sempre e solo UNA istanza alla
# volta, a differenza degli individui vegetali/animali dove il MultiMesh serve a evitare migliaia
# di draw call). Posizione aggiornata dal chiamante (GameScene) ogni frame mentre il piazzamento è
# attivo — questo nodo non legge da solo il mouse, resta muto sul "quando", si limita a sapere
# "come disegnarsi".

const WALL_COLOR := Color(0.55, 0.42, 0.28, 0.75)
const WALL_OUTLINE_COLOR := Color(0.3, 0.22, 0.12, 0.85)
const ROOF_COLOR := Color(0.45, 0.28, 0.12, 0.8)
const ROOF_OUTLINE_COLOR := Color(0.25, 0.15, 0.06, 0.9)

# Palette alternativa quando is_buildable è false (terreno non edificabile — vedi GameScene.
# _is_position_buildable) — stesse forme, solo tinta rossa al posto del marrone, stessa alpha di
# semitrasparenza delle controparti sopra.
const INVALID_WALL_COLOR := Color(0.75, 0.15, 0.15, 0.75)
const INVALID_WALL_OUTLINE_COLOR := Color(0.4, 0.05, 0.05, 0.85)
const INVALID_ROOF_COLOR := Color(0.65, 0.1, 0.1, 0.8)
const INVALID_ROOF_OUTLINE_COLOR := Color(0.35, 0.05, 0.05, 0.9)

const WALL_WIDTH: float = 6.0
const WALL_HEIGHT: float = 4.0
const ROOF_WIDTH: float = 8.0
const ROOF_HEIGHT: float = 4.5

# Aggiornato da GameScene ogni frame insieme alla posizione (vedi _is_position_buildable) — questo
# nodo resta comunque muto sul PERCHÉ (acqua/fiume/pietra/fuori mappa), sa solo "disegnami di
# rosso oppure no". Setter con guard+queue_redraw: senza, ridisegnerebbe ad ogni frame anche
# quando il valore non cambia (il chiamante lo scrive ogni frame, non solo ai cambi di stato).
var is_buildable: bool = true:
	set(value):
		if is_buildable == value:
			return
		is_buildable = value
		queue_redraw()


func _draw() -> void:
	var wall_color := WALL_COLOR if is_buildable else INVALID_WALL_COLOR
	var wall_outline_color := WALL_OUTLINE_COLOR if is_buildable else INVALID_WALL_OUTLINE_COLOR
	var roof_color := ROOF_COLOR if is_buildable else INVALID_ROOF_COLOR
	var roof_outline_color := ROOF_OUTLINE_COLOR if is_buildable else INVALID_ROOF_OUTLINE_COLOR

	# Pareti: poggiano sul punto di ancoraggio (0,0 = il terreno) e si sviluppano verso l'alto
	# (Y negative in Godot = più in alto a schermo).
	var wall_rect := Rect2(-WALL_WIDTH / 2.0, -WALL_HEIGHT, WALL_WIDTH, WALL_HEIGHT)
	draw_rect(wall_rect, wall_color)
	draw_rect(wall_rect, wall_outline_color, false, 1.0)

	# Tetto: triangolo appoggiato sul bordo superiore delle pareti, leggermente più largo di esse.
	var roof_base_y: float = -WALL_HEIGHT
	var roof_points := PackedVector2Array([
		Vector2(-ROOF_WIDTH / 2.0, roof_base_y),
		Vector2(ROOF_WIDTH / 2.0, roof_base_y),
		Vector2(0, roof_base_y - ROOF_HEIGHT),
	])
	draw_colored_polygon(roof_points, roof_color)
	draw_polyline(PackedVector2Array([roof_points[0], roof_points[2], roof_points[1]]), roof_outline_color, 1.2)
