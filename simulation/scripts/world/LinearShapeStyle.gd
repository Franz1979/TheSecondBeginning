class_name LinearShapeStyle
extends RefCounted

# Stile di un edificio lineare per LinearShape.draw (2026-10-04, richiesta utente): metà larghezza del tracciato (raggio
# del centro e dei bracci), colore del corpo, ciglio (spessore 0 = nessun ciglio, es. una strada piatta), raggio del punto
# di ciglio di un pezzo isolato e tinta dell'anteprima non edificabile. Ogni edificio lineare ne tiene uno costante nella
# propria classe di forma (es. EarthworkShape.STYLE).
# ground_half_width (2026-10-04): metà larghezza della striscia di fondo chiaro sotto il tracciato (LinearShape.draw_ground),
# un po' più larga del corpo; 0 = nessun fondo.

var half_width: float
var body_color: Color
var crest_color: Color
var crest_width: float
var crest_dot_radius: float
var invalid_tint: Color
var ground_half_width: float


func _init(
	p_half_width: float, p_body_color: Color, p_crest_color: Color = Color.TRANSPARENT, p_crest_width: float = 0.0,
	p_crest_dot_radius: float = 0.0, p_invalid_tint: Color = Color(0.9, 0.25, 0.25, 0.55), p_ground_half_width: float = 0.0
) -> void:
	half_width = p_half_width
	body_color = p_body_color
	crest_color = p_crest_color
	crest_width = p_crest_width
	crest_dot_radius = p_crest_dot_radius
	invalid_tint = p_invalid_tint
	ground_half_width = p_ground_half_width
