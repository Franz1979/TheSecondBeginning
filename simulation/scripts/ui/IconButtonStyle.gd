class_name IconButtonStyle
extends RefCounted

# Stile dei bottoni a icona (2026-10-10, richiesta utente — prima la riga dei comandi del pannello edificio): su fondo
# scuro le icone devono leggersi come tasti, non come disegni appoggiati. Fondo un po' più chiaro del pannello, angoli
# arrotondati, bordo sottile più chiaro, ombra leggera sotto; al passaggio del mouse fondo e bordo si schiariscono, alla
# pressione si scuriscono; da spento fondo e bordo appena visibili, senza ombra (lo stato "disabled" del Button ha la
# precedenza sul passaggio del mouse, quindi nessun effetto). L'icona sbiadita da spento resta a cura di chi la disegna.
# Un punto solo, pensato per estenderlo poi agli altri bottoni a icona: apply(button). Non cambia la dimensione del
# bottone (margini interni fissi, piccoli: i bottoni a icona hanno la propria custom_minimum_size).

const CORNER_RADIUS: int = 4
const BORDER_WIDTH: int = 1
const CONTENT_MARGIN: float = 2.0

const BG_NORMAL := Color(0.27, 0.27, 0.30, 1.0)
const BORDER_NORMAL := Color(0.46, 0.46, 0.51, 1.0)
const BG_HOVER := Color(0.35, 0.35, 0.39, 1.0)
const BORDER_HOVER := Color(0.64, 0.64, 0.70, 1.0)
const BG_PRESSED := Color(0.19, 0.19, 0.21, 1.0)
const BORDER_PRESSED := Color(0.38, 0.38, 0.42, 1.0)
const BG_DISABLED := Color(0.25, 0.25, 0.27, 0.35)
const BORDER_DISABLED := Color(0.42, 0.42, 0.46, 0.30)

const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const SHADOW_SIZE: int = 2
const SHADOW_OFFSET := Vector2(0.0, 1.0)

static var _styles: Dictionary = {}


# Applica lo stile a `button` (normale, mouse sopra, premuto, spento; nessun riquadro di focus).
static func apply(button: Button) -> void:
	if button == null:
		return
	if _styles.is_empty():
		_styles = {
			"normal": _make(BG_NORMAL, BORDER_NORMAL, true),
			"hover": _make(BG_HOVER, BORDER_HOVER, true),
			"pressed": _make(BG_PRESSED, BORDER_PRESSED, false),
			"disabled": _make(BG_DISABLED, BORDER_DISABLED, false),
		}
	button.add_theme_stylebox_override("normal", _styles["normal"])
	button.add_theme_stylebox_override("hover", _styles["hover"])
	button.add_theme_stylebox_override("pressed", _styles["pressed"])
	button.add_theme_stylebox_override("hover_pressed", _styles["pressed"])
	button.add_theme_stylebox_override("disabled", _styles["disabled"])
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _make(bg: Color, border: Color, with_shadow: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(CONTENT_MARGIN)
	style.anti_aliasing = true
	if with_shadow:
		style.shadow_color = SHADOW_COLOR
		style.shadow_size = SHADOW_SIZE
		style.shadow_offset = SHADOW_OFFSET
	return style
