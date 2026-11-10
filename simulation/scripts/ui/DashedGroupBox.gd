class_name DashedGroupBox
extends MarginContainer

# Riquadro tratteggiato con il nome sul bordo in alto, che interrompe il tratteggio (2026-11-09, richiesta utente —
# attrezzi raggruppati nel cassetto Scorte). Le righe vanno in `content`. Senza titolo niente bordo: stessi margini
# laterali, così le colonne restano allineate a quelle dei riquadri (righe senza gruppo in fondo alla linguetta).

const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const TITLE_COLOR := Color(1.0, 1.0, 1.0, 0.65)
const TITLE_FONT_SIZE: int = 10
const DASH_LENGTH: float = 3.0
const SIDE_INSET: int = 6
# Distanza del nome dall'angolo in alto a sinistra e spazio vuoto attorno al nome.
const TITLE_OFFSET: float = 8.0
const TITLE_PADDING: float = 3.0

var title: String = ""
var content: VBoxContainer


func _init(group_title: String = "") -> void:
	title = group_title
	mouse_filter = Control.MOUSE_FILTER_PASS
	var has_border := title != ""
	add_theme_constant_override("margin_left", SIDE_INSET)
	add_theme_constant_override("margin_right", SIDE_INSET)
	add_theme_constant_override("margin_top", TITLE_FONT_SIZE + 5 if has_border else 0)
	add_theme_constant_override("margin_bottom", SIDE_INSET - 2 if has_border else 0)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	add_child(content)


func _draw() -> void:
	if title == "":
		return
	var font := get_theme_default_font()
	var text_size := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE)
	var left := 0.5
	var right := size.x - 0.5
	var top := floorf(text_size.y * 0.5) + 0.5
	var bottom := size.y - 0.5
	var gap_start := left + TITLE_OFFSET
	var gap_end := gap_start + text_size.x + TITLE_PADDING * 2.0
	draw_dashed_line(Vector2(left, top), Vector2(gap_start, top), BORDER_COLOR, 1.0, DASH_LENGTH)
	draw_dashed_line(Vector2(gap_end, top), Vector2(right, top), BORDER_COLOR, 1.0, DASH_LENGTH)
	draw_dashed_line(Vector2(right, top), Vector2(right, bottom), BORDER_COLOR, 1.0, DASH_LENGTH)
	draw_dashed_line(Vector2(right, bottom), Vector2(left, bottom), BORDER_COLOR, 1.0, DASH_LENGTH)
	draw_dashed_line(Vector2(left, bottom), Vector2(left, top), BORDER_COLOR, 1.0, DASH_LENGTH)
	var baseline := top - text_size.y * 0.5 + font.get_ascent(TITLE_FONT_SIZE)
	draw_string(font, Vector2(gap_start + TITLE_PADDING, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, TITLE_COLOR)
