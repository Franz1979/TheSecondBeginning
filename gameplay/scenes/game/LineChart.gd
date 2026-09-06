class_name LineChart
extends Control

# Componente grafico a linea generico e riusabile (Step 1 del piano statistiche, 2026-09-06) —
# nessun plugin/addon di charting esiste nel progetto (verificato in ricognizione), scritto da
# zero con _draw() immediate-mode, stesso approccio già usato altrove per widget UI custom (vedi
# SeasonProgressBar). Riceve un Dictionary chiave(int)->valore(int/float) via set_data() e
# disegna una linea che collega i punti in ordine di chiave crescente — NESSUNA logica di dominio
# qui dentro: il chiamante decide cosa significano chiave/valore (anno->morti, anno->nascite,
# anno->popolazione, ecc.), questo componente si limita a disegnarli. Pensato per essere
# instanziato staticamente nel .tscn del pannello che lo usa (type="LineChart", stesso principio
# con cui SeasonProgressBar viene dichiarato inline nei .tscn che lo usano, nessuna scena .tscn
# propria per un widget così semplice).

const LINE_COLOR := Color(0.35, 0.65, 0.95, 1.0)
const POINT_COLOR := Color(0.9, 0.9, 0.9, 1.0)
const AXIS_COLOR := Color(0.5, 0.5, 0.5, 0.6)
const GRID_COLOR := Color(0.5, 0.5, 0.5, 0.22)
const LABEL_COLOR := Color(0.8, 0.8, 0.8, 1.0)
const GRID_LABEL_COLOR := Color(0.65, 0.65, 0.65, 0.85)
const PLACEHOLDER_COLOR := Color(0.6, 0.6, 0.6, 1.0)
const HOVER_LINE_COLOR := Color(0.9, 0.9, 0.9, 0.5)
const HOVER_POINT_COLOR := Color(1.0, 0.8, 0.3, 1.0)
const HOVER_BOX_BG_COLOR := Color(0.1, 0.1, 0.1, 0.85)
const HOVER_BOX_TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

const LINE_WIDTH: float = 2.0
const POINT_RADIUS: float = 3.0
const HOVER_POINT_RADIUS: float = 4.5
const LABEL_FONT_SIZE: int = 11
const GRID_LABEL_FONT_SIZE: int = 9

# Margini del riquadro di disegno dentro il Control — spazio per le etichette (sinistra per i
# valori Y + titolo asse verticale, sotto per le chiavi X + titolo asse orizzontale). PADDING_RIGHT
# (richiesta utente, 2026-09-06: "non ci sta bene in orizzontale... non ha abbastanza spacing a
# dx?") tenuto più largo del semplice raggio del punto (POINT_RADIUS/HOVER_POINT_RADIUS): senza
# margine il punto/cerchio dell'ultimo anno finiva tagliato a filo del bordo destro del Control.
# PADDING_LEFT ridotto rispetto alla versione precedente (era 34 — "troppo staccato dal margine
# sx", lo spazio tra le etichette Y e il bordo sinistro del riquadro era più largo del necessario).
const PADDING_LEFT: float = 28.0
const PADDING_RIGHT: float = 16.0
const PADDING_TOP: float = 10.0
const PADDING_BOTTOM: float = 32.0

# Riga riservata in basso per il titolo asse X, SOTTO le etichette numeriche anno min/max (che si
# spostano più in alto di questa quantità rispetto a prima) — vedi _draw_axis_labels.
const AXIS_TITLE_ROW_HEIGHT: float = 14.0
# Posizione X del titolo asse Y (verticale, ruotato) — a sinistra delle etichette numeriche
# valore 0/massimo (che si spostano più a destra di prima per fargli spazio).
const Y_AXIS_TITLE_X: float = 8.0
const Y_VALUE_LABEL_X: float = 16.0

# Griglia di riferimento (richiesta utente, 2026-09-06: "non solo il primo e l'ultimo... una tacca
# ogni 5 anni e ogni tot people... assi più sottili di quelli x e y") — tacche verticali a
# intervalli FISSI di 5 anni (GRID_YEAR_STEP), tacche orizzontali a un intervallo "arrotondato"
# calcolato da _compute_nice_step (mai un valore a caso tipo 137 — 100/50/20/10/5/... a seconda
# dell'ordine di grandezza del massimo), entrambe disegnate con GRID_COLOR (più tenue/sottile di
# AXIS_COLOR, che resta riservato alle due linee di base 0/0). GRID_LABEL_TARGET_COUNT è
# l'obiettivo di quante tacche orizzontali mostrare (non un vincolo esatto: l'arrotondamento a un
# passo "carino" può produrne una in più o in meno).
const GRID_YEAR_STEP: int = 5
const GRID_LABEL_TARGET_COUNT: int = 4

# Titoli assi (richiesta utente, 2026-09-06) — "Year"/"People" sono DEFAULT sensati per i tre usi
# attuali (morti/nascite/popolazione per anno, tutti "persone nel tempo"), non un'assunzione di
# dominio incastonata nel componente: set_axis_labels() sotto resta disponibile per un futuro
# consumatore con assi diversi (es. un ipotetico grafico risorse/anno), senza dover toccare questo
# file. Stringa vuota = titolo non disegnato (vedi _draw_x_axis_title/_draw_y_axis_title).
var _x_axis_label: String = "Year"
var _y_axis_label: String = "People"

var _data: Dictionary = {}

# Stato hover (richiesta utente, 2026-09-06: "se passo con mouse degli anni, mi dica come hoover,
# year e il valore") — null = nessun hover attivo. Aggiornato solo da _gui_input/_notification,
# mai letto/scritto da _draw() se non per disegnare l'overlay: _draw() resta altrimenti la stessa
# funzione pura-sui-dati di prima.
var _hover_key = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, 120)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


# Sostituisce interamente i dati mostrati e ridisegna — unico punto d'ingresso pubblico di questo
# componente. `data` può essere vuoto (nessun evento ancora) o avere una sola chiave (un solo
# anno con dati): entrambi i casi sono gestiti in _draw() senza eccezioni/divisioni per zero.
func set_data(data: Dictionary) -> void:
	_data = data
	_hover_key = null
	queue_redraw()


# Sovrascrive i titoli di default degli assi ("Year"/"People", vedi sopra) — mai richiamato dai
# tre usi attuali (i default vanno già bene per tutti e tre), disponibile per un futuro
# consumatore con semantica diversa. Stringa vuota su uno dei due per nasconderlo del tutto.
func set_axis_labels(x_label: String, y_label: String) -> void:
	_x_axis_label = x_label
	_y_axis_label = y_label
	queue_redraw()


# Tracciamento hover (richiesta utente, 2026-09-06) — ricalcola la chiave più vicina alla
# posizione X del mouse ad ogni movimento. Le chiavi qui sono sempre anni interi contigui (vedi
# StatisticsPanel._fill_missing_years/population_snapshots, mai un buco), quindi "chiave più
# vicina" può essere ricavata per interpolazione lineare + arrotondamento invece di una ricerca
# lineare sull'intero array ad ogni frame di movimento del mouse.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_key != null:
		_hover_key = null
		queue_redraw()


func _update_hover(mouse_position: Vector2) -> void:
	if _data.size() < 2:
		# Con 0 o 1 sola chiave non c'è nulla su cui "muoversi": 1 chiave resta comunque
		# raggiungibile al passaggio del mouse ovunque sul riquadro, gestita come caso singolo qui.
		var new_hover_key = _data.keys()[0] if _data.size() == 1 else null
		if new_hover_key != _hover_key:
			_hover_key = new_hover_key
			queue_redraw()
		return
	var keys := _data.keys()
	keys.sort()
	var min_key: float = float(keys[0])
	var max_key: float = float(keys[keys.size() - 1])
	var plot_left := PADDING_LEFT
	var plot_width := maxf(size.x - PADDING_LEFT - PADDING_RIGHT, 1.0)
	var x_fraction := clampf((mouse_position.x - plot_left) / plot_width, 0.0, 1.0)
	var key_estimate := min_key + x_fraction * (max_key - min_key)
	var nearest_key: int = int(round(key_estimate))
	nearest_key = clampi(nearest_key, int(min_key), int(max_key))
	if not _data.has(nearest_key):
		return
	if nearest_key != _hover_key:
		_hover_key = nearest_key
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font

	if _data.is_empty():
		_draw_placeholder_text("Dati insufficienti")
		return

	var keys := _data.keys()
	keys.sort()

	var plot_rect := Rect2(
		PADDING_LEFT, PADDING_TOP,
		maxf(size.x - PADDING_LEFT - PADDING_RIGHT, 1.0),
		maxf(size.y - PADDING_TOP - PADDING_BOTTOM, 1.0)
	)
	var baseline_y := plot_rect.position.y + plot_rect.size.y

	var min_key: float = float(keys[0])
	var max_key: float = float(keys[keys.size() - 1])
	# Origine Y SEMPRE a 0 (richiesta utente, 2026-09-06), MAI il valore minimo osservato nei
	# dati: se tutti i valori sono ben sopra zero (es. popolazione 10-14), lo spazio vuoto tra 0 e
	# il minimo osservato resta visibile di proposito — comunica quanto i dati sono lontani da
	# zero, non un difetto da correggere.
	var max_value := 0.0
	for key in keys:
		max_value = maxf(max_value, float(_data[key]))

	var single_key := keys.size() == 1
	# Caso degenere residuo (l'unico rimasto, ora che l'origine è fissa a 0): TUTTI i valori sono
	# 0 — evita la divisione per zero in value/max_value sotto. "Valori tutti uguali ma > 0" non è
	# più un caso speciale: con l'origine fissa, value/max_value resta ben definito e posiziona
	# correttamente il punto (es. tutti a 12 -> tutti in cima, non più centrati a metà per un
	# vecchio artefatto del min osservato).
	var all_zero := is_equal_approx(max_value, 0.0)

	# Griglia (richiesta utente, 2026-09-06) — disegnata PRIMA della linea/punti dati, così resta
	# sempre sotto di essi. Tacche verticali ogni GRID_YEAR_STEP anni, tacche orizzontali a un passo
	# "arrotondato" — vedi _draw_grid.
	_draw_grid(font, min_key, max_key, max_value, plot_rect, baseline_y, all_zero)

	# Assi X/Y — disegnati SEMPRE, anche con un solo punto: l'intersezione dei due è sempre (0,0)
	# (richiesta utente, 2026-09-06 — vedi max_value/y_fraction sotto: l'origine NON è più il
	# valore minimo osservato nei dati, è fissa). Prima veniva disegnata solo la linea di base X;
	# aggiunta anche la Y (verticale a sinistra) per rendere l'origine (0,0) visivamente esplicita,
	# non solo implicita nella posizione della base.
	draw_line(
		Vector2(plot_rect.position.x, baseline_y),
		Vector2(plot_rect.position.x + plot_rect.size.x, baseline_y),
		AXIS_COLOR, 1.0
	)
	draw_line(
		Vector2(plot_rect.position.x, plot_rect.position.y),
		Vector2(plot_rect.position.x, baseline_y),
		AXIS_COLOR, 1.0
	)

	var points := PackedVector2Array()
	for key in keys:
		var value := float(_data[key])
		var x_fraction := 0.5 if single_key else (float(key) - min_key) / (max_key - min_key)
		var y_fraction := 0.0 if all_zero else value / max_value
		points.append(Vector2(
			plot_rect.position.x + x_fraction * plot_rect.size.x,
			baseline_y - y_fraction * plot_rect.size.y
		))

	if points.size() >= 2:
		draw_polyline(points, LINE_COLOR, LINE_WIDTH, true)
	for point in points:
		draw_circle(point, POINT_RADIUS, POINT_COLOR)

	_draw_axis_labels(font, keys, max_value, plot_rect, baseline_y, single_key, all_zero)
	_draw_hover(font, keys, points, plot_rect, baseline_y)


# Griglia di riferimento leggera (richiesta utente, 2026-09-06) — SEPARATA dalle etichette
# min/max/0 già disegnate da _draw_axis_labels (che restano, sono i due estremi sempre garantiti);
# questa aggiunge tacche INTERMEDIE. Verticali: ogni GRID_YEAR_STEP anni esatti (0, 5, 10, ...),
# saltando quelle troppo vicine al bordo sinistro/destro del riquadro per non sovrapporsi alle
# etichette min/max. Orizzontali: passo calcolato da _compute_nice_step, stesso criterio.
func _draw_grid(
	font: Font, min_key: float, max_key: float, max_value: float, plot_rect: Rect2,
	baseline_y: float, all_zero: bool
) -> void:
	var key_range := max_key - min_key
	if key_range > 0.0:
		var first_tick := int(ceil(min_key / float(GRID_YEAR_STEP))) * GRID_YEAR_STEP
		var tick := first_tick
		while tick < max_key:
			if tick > min_key:
				var x_fraction := (float(tick) - min_key) / key_range
				var x := plot_rect.position.x + x_fraction * plot_rect.size.x
				draw_line(Vector2(x, plot_rect.position.y), Vector2(x, baseline_y), GRID_COLOR, 1.0)
				var label_text := str(tick)
				var label_width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_FONT_SIZE).x
				draw_string(
					font, Vector2(x - label_width / 2.0, size.y - 4.0 - AXIS_TITLE_ROW_HEIGHT),
					label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_FONT_SIZE, GRID_LABEL_COLOR
				)
			tick += GRID_YEAR_STEP

	if all_zero:
		return
	var step := _compute_nice_step(max_value)
	if step <= 0.0:
		return
	var value := step
	while value < max_value:
		var y_fraction := value / max_value
		var y := baseline_y - y_fraction * plot_rect.size.y
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.position.x + plot_rect.size.x, y), GRID_COLOR, 1.0)
		draw_string(
			font, Vector2(Y_VALUE_LABEL_X, y + GRID_LABEL_FONT_SIZE * 0.35),
			_format_value(value), HORIZONTAL_ALIGNMENT_LEFT, -1, GRID_LABEL_FONT_SIZE, GRID_LABEL_COLOR
		)
		value += step


# "Numero carino" per il passo della griglia orizzontale (richiesta utente, 2026-09-06: "ogni tot
# people") — mai un valore arbitrario tipo max_value/4: arrotonda al più vicino tra 1/2/5 (per la
# relativa potenza di 10) sopra o sotto max_value/GRID_LABEL_TARGET_COUNT, stesso algoritmo
# standard usato per gli assi di praticamente ogni libreria di grafici.
func _compute_nice_step(max_value: float) -> float:
	if max_value <= 0.0:
		return 0.0
	var raw_step := max_value / float(GRID_LABEL_TARGET_COUNT)
	var magnitude := pow(10.0, floor(log(raw_step) / log(10.0)))
	var residual := raw_step / magnitude
	var nice_residual: float
	if residual <= 1.0:
		nice_residual = 1.0
	elif residual <= 2.0:
		nice_residual = 2.0
	elif residual <= 5.0:
		nice_residual = 5.0
	else:
		nice_residual = 10.0
	return nice_residual * magnitude


# Overlay hover (richiesta utente, 2026-09-06) — disegnato per ULTIMO, sopra a tutto il resto:
# linea verticale tratteggiata-morbida (HOVER_LINE_COLOR, alpha basso) dalla base fino al punto
# della chiave sotto il mouse, punto evidenziato più grande, e un piccolo riquadro con
# "{x_axis_label}: {chiave}   {y_axis_label}: {valore}" — posizionato sopra il punto, ma con la X
# vincolata (clamp) a restare dentro il Control: altrimenti su un anno vicino al bordo destro il
# riquadro uscirebbe parzialmente dall'area visibile.
func _draw_hover(font: Font, keys: Array, points: PackedVector2Array, plot_rect: Rect2, baseline_y: float) -> void:
	if _hover_key == null:
		return
	var index := keys.find(_hover_key)
	if index < 0:
		return
	var point: Vector2 = points[index]
	var value := float(_data[_hover_key])

	draw_line(Vector2(point.x, plot_rect.position.y), Vector2(point.x, baseline_y), HOVER_LINE_COLOR, 1.0)
	draw_circle(point, HOVER_POINT_RADIUS, HOVER_POINT_COLOR)

	var label_text := "%s: %s   %s: %s" % [_x_axis_label, str(_hover_key), _y_axis_label, _format_value(value)]
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var box_padding := Vector2(5.0, 3.0)
	var box_size := text_size + box_padding * 2.0
	var box_position := Vector2(point.x - box_size.x / 2.0, point.y - box_size.y - 8.0)
	box_position.x = clampf(box_position.x, 0.0, maxf(size.x - box_size.x, 0.0))
	box_position.y = maxf(box_position.y, 0.0)

	draw_rect(Rect2(box_position, box_size), HOVER_BOX_BG_COLOR)
	draw_string(
		font, box_position + box_padding + Vector2(0.0, text_size.y * 0.8),
		label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, HOVER_BOX_TEXT_COLOR
	)


# Etichette agli estremi SOLO (richiesta esplicita: "non serve una griglia elaborata, solo che sia
# leggibile") — chiave minima/massima sull'asse X in basso, valore 0/massimo sull'asse Y a
# sinistra (il valore minimo dell'asse Y è ora SEMPRE 0, mai il minimo osservato — vedi _draw()).
# Con una sola chiave osservata, min e max chiave coincidono: l'etichetta va mostrata una sola
# volta, mai duplicata (es. "2026 2026") — stesso principio per 0/massimo quando TUTTI i valori
# sono 0 (altrimenti "0 0" duplicato in alto e in basso).
func _draw_axis_labels(
	font: Font, keys: Array, max_value: float, plot_rect: Rect2, baseline_y: float,
	single_key: bool, all_zero: bool
) -> void:
	# Etichette numeriche anno min/max — SOPRA la riga riservata al titolo asse X (vedi
	# AXIS_TITLE_ROW_HEIGHT), non più nell'ultima riga in assoluto.
	var key_label_y := size.y - 4.0 - AXIS_TITLE_ROW_HEIGHT
	var key_min_text := str(keys[0])
	draw_string(font, Vector2(plot_rect.position.x, key_label_y), key_min_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
	if not single_key:
		var key_max_text := str(keys[keys.size() - 1])
		var key_max_width := font.get_string_size(key_max_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		draw_string(
			font, Vector2(plot_rect.position.x + plot_rect.size.x - key_max_width, key_label_y),
			key_max_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR
		)

	# Etichette numeriche valore 0/massimo — spostate a destra di Y_VALUE_LABEL_X (prima x=2.0) per
	# fare spazio al titolo asse Y verticale a sinistra di loro.
	draw_string(font, Vector2(Y_VALUE_LABEL_X, plot_rect.position.y + LABEL_FONT_SIZE * 0.5), _format_value(max_value), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
	if not all_zero:
		draw_string(font, Vector2(Y_VALUE_LABEL_X, baseline_y), _format_value(0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)

	_draw_x_axis_title(font, plot_rect)
	_draw_y_axis_title(font, plot_rect)


# Titolo asse X (richiesta utente, 2026-09-06, es. "Year") — centrato in orizzontale sotto il
# riquadro di disegno, nell'ultima riga in assoluto (sotto le etichette numeriche anno min/max).
func _draw_x_axis_title(font: Font, plot_rect: Rect2) -> void:
	if _x_axis_label.is_empty():
		return
	var text_size := font.get_string_size(_x_axis_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var x := plot_rect.position.x + (plot_rect.size.x - text_size.x) / 2.0
	draw_string(font, Vector2(x, size.y - 4.0), _x_axis_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)


# Titolo asse Y (richiesta utente, 2026-09-06, es. "People") — VERTICALE (richiesta esplicita),
# centrato sull'altezza del riquadro di disegno, a sinistra delle etichette numeriche valore.
# draw_set_transform ruota il sistema di coordinate per questa sola stringa (ripristinato subito
# dopo): l'ancora è il punto in cui inizia il testo PRIMA della rotazione, quindi va calcolato in
# modo che, DOPO la rotazione di -90°, il testo risulti verticalmente centrato e legga dal basso
# verso l'alto (convenzione standard per un titolo asse Y).
func _draw_y_axis_title(font: Font, plot_rect: Rect2) -> void:
	if _y_axis_label.is_empty():
		return
	var text_size := font.get_string_size(_y_axis_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var center_y := plot_rect.position.y + plot_rect.size.y / 2.0
	draw_set_transform(Vector2(Y_AXIS_TITLE_X, center_y + text_size.x / 2.0), -PI / 2.0)
	draw_string(font, Vector2.ZERO, _y_axis_label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Interi mostrati senza decimali (il caso comune: conteggi/anni) — solo un valore non intero
# (in teoria non dovrebbe capitare con i tre usi previsti, tutti conteggi) mostrerebbe un decimale,
# difensivo più che atteso.
func _format_value(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _draw_placeholder_text(text: String) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	draw_string(font, (size - text_size) / 2.0, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, PLACEHOLDER_COLOR)
