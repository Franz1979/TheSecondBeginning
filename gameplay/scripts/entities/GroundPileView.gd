class_name GroundPileView
extends Node2D

# Disegno di un mucchio a terra (2026-09-26, richiesta utente — ground drop, vedi GroundPile). Solo vista:
# creata, aggiornata e rimossa da GameScene._sync_ground_pile_views, figlia del container della cella viva,
# origine al centro della microcella del mucchio.
#
# Nessuna sagoma di sfondo: solo le icone delle risorse contenute, al massimo MAX_ICONS, piccole, ruotate a
# caso e leggermente sovrapposte, come oggetti caduti a terra, ciascuna con un'ombra tenue sotto. Le icone
# sono le STESSE disegnate nella griglia del magazzino (DepositStorageIcons.draw_icon, condivisa con
# MicroCellRenderer); una risorsa senza icona dedicata diventa un pallino nel suo colore, come nel magazzino.
# Disposizione stabile per lo stesso mucchio: posizioni e rotazioni degli slot sono tirate una volta sola con
# seed = id del mucchio, e la risorsa i-esima (ordine per nome) occupa sempre lo slot i. Selezionato = contorno
# chiaro attorno all'insieme.

const MAX_ICONS: int = 4
# Lato delle icone rispetto alla griglia del magazzino (MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE).
const ICON_SCALE: float = 0.8
# Distanza massima di uno slot dal centro del mucchio, in pixel (una microcella = 10): abbastanza stretta da
# far sovrapporre un po' le icone.
const SCATTER_RADIUS: float = 1.1
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const SHADOW_OFFSET := Vector2(0.25, 0.45)
const SELECTED_COLOR := Color(1.0, 0.95, 0.6, 1.0)
# Carcasse (2026-09-26, disegno provvisorio distinto dalle risorse): un animale disteso di fianco — corpo
# ellittico, testa, quattro zampe rigide — color pelame, su una macchia scura. Lunghezza del corpo in pixel per un
# adulto di taglia di riferimento, scalata per sqrt(max_health / CARCASS_REFERENCE_HEALTH) e per fascia d'età.
const CARCASS_BODY_LENGTH: float = 5.0
const CARCASS_REFERENCE_HEALTH: float = 25.0
const CARCASS_SCALE_MIN: float = 0.5
const CARCASS_SCALE_MAX: float = 1.5
const CARCASS_FUR_COLOR := Color(0.52, 0.38, 0.24, 1.0)
const CARCASS_FUR_DARK_COLOR := Color(0.34, 0.23, 0.13, 1.0)
const CARCASS_STAIN_COLOR := Color(0.35, 0.05, 0.05, 0.45)

var pile_id: int = -1
var is_selected: bool = false
# Ultima revisione disegnata del mucchio (GroundPile.revision): GameScene ridisegna solo quando cambia.
var shown_revision: int = -1

# Slot stabili (posizione del centro e rotazione), generati alla prima show_pile.
var _slot_offsets: Array[Vector2] = []
var _slot_rotations: Array[float] = []
# Risorse disegnate in questo momento, una per slot.
var _resource_names: Array[String] = []
# Carcasse disegnate: {"scale": float, "rotation": float, "offset": Vector2}, una per carcassa del mucchio.
var _carcass_shapes: Array[Dictionary] = []


func show_pile(pile: GroundPile) -> void:
	pile_id = pile.id
	shown_revision = pile.revision
	z_index = 1
	if _slot_offsets.is_empty():
		_build_slots(pile.id)
	_resource_names = pile.get_resource_names().slice(0, MAX_ICONS)
	_carcass_shapes.clear()
	for i in range(pile.carcasses.size()):
		var carcass: Dictionary = pile.carcasses[i]
		# Orientamento e piccolo spostamento stabili per mucchio e posizione nella lista.
		var rng := RandomNumberGenerator.new()
		rng.seed = pile.id * 31 + i
		_carcass_shapes.append({
			"scale": _carcass_scale(String(carcass.get("species", "")), int(carcass.get("age_band", GameTypes.AgeBand.ADULT))),
			"rotation": rng.randf_range(-0.6, 0.6),
			"offset": Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6)),
		})
	queue_redraw()


# Scala della carcassa: taglia della specie (radice di max_health rispetto al riferimento) × fascia d'età.
func _carcass_scale(species: String, age_band: int) -> float:
	var rules := AnimalCalculator.get_animal_rules(species)
	if rules == null:
		return 1.0
	var size_factor: float = sqrt(maxf(rules.max_health, 1.0) / CARCASS_REFERENCE_HEALTH)
	if age_band >= 0 and age_band < rules.size_multiplier_by_age.size():
		size_factor *= rules.size_multiplier_by_age[age_band]
	return clampf(size_factor, CARCASS_SCALE_MIN, CARCASS_SCALE_MAX)


func _draw_carcass(shape: Dictionary) -> void:
	var scale_factor: float = shape["scale"]
	var length: float = CARCASS_BODY_LENGTH * scale_factor
	draw_set_transform(shape["offset"], shape["rotation"], Vector2.ONE)
	# Macchia sotto il corpo.
	draw_set_transform(shape["offset"] + Vector2(0.0, length * 0.12), shape["rotation"], Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, length * 0.6, CARCASS_STAIN_COLOR)
	draw_set_transform(shape["offset"], shape["rotation"], Vector2.ONE)
	# Zampe rigide (disteso di fianco: escono tutte dallo stesso lato del corpo).
	var leg_width: float = length * 0.07
	for leg_x in [-0.28, -0.14, 0.16, 0.30]:
		var hip := Vector2(leg_x * length, length * 0.08)
		draw_line(hip, hip + Vector2(leg_x * length * 0.25, length * 0.32), CARCASS_FUR_DARK_COLOR, leg_width, true)
	# Corpo ellittico.
	draw_set_transform(shape["offset"], shape["rotation"], Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, length * 0.5, CARCASS_FUR_COLOR)
	draw_set_transform(shape["offset"], shape["rotation"], Vector2.ONE)
	# Testa a un'estremità, con l'occhio chiuso (una linea scura).
	var head_center := Vector2(length * 0.55, -length * 0.06)
	draw_circle(head_center, length * 0.16, CARCASS_FUR_COLOR)
	draw_line(head_center + Vector2(-length * 0.04, -length * 0.03), head_center + Vector2(length * 0.04, -length * 0.03),
		CARCASS_FUR_DARK_COLOR, leg_width * 0.6, true)


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	queue_redraw()


func _icon_side() -> float:
	return MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE * ICON_SCALE


# Posizioni sparse attorno al centro (angolo e distanza casuali, il primo slot vicino al centro) e rotazioni
# libere, stabili per mucchio.
func _build_slots(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start_angle := rng.randf_range(0.0, TAU)
	for i in range(MAX_ICONS):
		var distance := 0.0 if i == 0 else rng.randf_range(SCATTER_RADIUS * 0.6, SCATTER_RADIUS)
		var angle := start_angle + TAU * float(i) / float(MAX_ICONS) + rng.randf_range(-0.5, 0.5)
		_slot_offsets.append(Vector2.from_angle(angle) * distance)
		_slot_rotations.append(rng.randf_range(-PI, PI))


func _draw() -> void:
	var side := _icon_side()
	var count := _resource_names.size()
	# Carcasse per prime: le icone delle risorse ci stanno sopra.
	for shape in _carcass_shapes:
		_draw_carcass(shape)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Prima tutte le ombre, poi le icone, così un'ombra non copre mai un'icona vicina.
	for i in range(count):
		draw_set_transform(_slot_offsets[i] + SHADOW_OFFSET, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, side * 0.5, SHADOW_COLOR)
	for i in range(count):
		draw_set_transform(_slot_offsets[i], _slot_rotations[i], Vector2.ONE)
		var top_left := Vector2(-side, -side) * 0.5
		if not DepositStorageIcons.draw_icon(self, _resource_names[i], top_left, side):
			draw_circle(Vector2.ZERO, side * 0.3, IconRegistry.get_resource_color(_resource_names[i]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if is_selected and (count > 0 or not _carcass_shapes.is_empty()):
		var radius := 0.0
		for i in range(count):
			radius = maxf(radius, _slot_offsets[i].length() + side * 0.8)
		for shape in _carcass_shapes:
			radius = maxf(radius, (shape["offset"] as Vector2).length() + CARCASS_BODY_LENGTH * float(shape["scale"]) * 0.75)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, SELECTED_COLOR, 0.35, true)
