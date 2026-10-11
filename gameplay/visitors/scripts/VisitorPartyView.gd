class_name VisitorPartyView
extends Node2D

# Disegno di un gruppo di visitatori (2026-09-27, richiesta utente — infrastruttura dei visitatori): una
# figura per membro, sullo schema di HumanIndividualView (stesse proporzioni e colori, riusati dalle sue
# costanti) ma semplificata e senza HumanIndividual dietro: solo le posizioni calcolate da
# VisitorService.get_member_position. Non selezionabile. Figlia del container della LiveMacroCell del
# gruppo, all'origine della cella: ogni figura è disegnata con la propria trasformazione.

const CELL_SIZE: int = HumanIndividualView.CELL_SIZE

var party: VisitorParty = null
var game_data: GameData = null
var human_rules: HumanRules = null
var clock: GameClockController = null
var walk_phase: float = 0.0
# Scala di disegno per membro (età fissa e sesso: non cambia finché il gruppo esiste), calcolata in setup.
var _member_scales: Array[float] = []
# Colori del vestiario per membro (2026-10-11), calcolati in setup: il vestiario di partenza che riceveranno
# all'accoglienza (HumanIndividual.STARTING_APPAREL) dall'adolescenza in su, i vestiti di recupero per i bambini
# (HumanIndividualView.RECYCLED_CLOTHES_COLOR); calotta trasparente = nessun copricapo.
var _member_body_colors: Array[Color] = []
var _member_cap_colors: Array[Color] = []


func setup(p_party: VisitorParty, p_game_data: GameData, p_human_rules: HumanRules) -> void:
	party = p_party
	game_data = p_game_data
	human_rules = p_human_rules
	_member_scales.clear()
	_member_body_colors.clear()
	_member_cap_colors.clear()
	for member in party.members:
		_member_scales.append(_resolve_member_scale(member))
		_resolve_member_apparel_colors(member)
	queue_redraw()


func _resolve_member_scale(member: Dictionary) -> float:
	var draw_scale := HumanIndividualView.BASE_DRAW_SCALE
	if human_rules == null or game_data == null:
		return draw_scale
	var sex: HumanTypes.Sex = member.get("sex", HumanTypes.Sex.MALE)
	var age_band := HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		sex, float(member.get("age", 0))
	)
	return draw_scale * human_rules.size_multiplier_by_age[age_band] * human_rules.size_multiplier_by_sex[sex]


func _resolve_member_apparel_colors(member: Dictionary) -> void:
	var adult := true
	if game_data != null:
		adult = HumanIndividual.is_apparel_age_band(HumanCalculator.get_age_band(
			game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
			member.get("sex", HumanTypes.Sex.MALE), float(member.get("age", 0))
		))
	var trait_color := int(member.get("clothing_color", HumanTypes.ClothingColor.TAN))
	if not adult:
		_member_body_colors.append(HumanIndividualView.RECYCLED_CLOTHES_COLOR)
		_member_cap_colors.append(Color(0, 0, 0, 0))
		return
	var body_name := String(HumanIndividual.STARTING_APPAREL.get(HumanIndividual.ApparelSlot.BODY, ""))
	var head_name := String(HumanIndividual.STARTING_APPAREL.get(HumanIndividual.ApparelSlot.HEAD, ""))
	_member_body_colors.append(HumanIndividualView.SKIN_COLOR if body_name == "" else HumanIndividualView.apparel_draw_color(body_name, trait_color))
	_member_cap_colors.append(Color(0, 0, 0, 0) if head_name == "" else HumanIndividualView.apparel_draw_color(head_name, trait_color))


func _process(delta: float) -> void:
	if party == null:
		return
	if VisitorService.is_moving(party):
		if clock == null or clock.is_playing:
			walk_phase += delta * HumanIndividualView.WALK_PHASE_SPEED
	else:
		walk_phase = 0.0
	queue_redraw()


func _draw() -> void:
	if party == null:
		return
	var angle := party.facing_direction.angle()
	var phase := sin(walk_phase)
	for i in range(party.members.size()):
		var member: Dictionary = party.members[i]
		var member_scale: float = _member_scales[i] if i < _member_scales.size() else HumanIndividualView.BASE_DRAW_SCALE
		draw_set_transform(VisitorService.get_member_position(party, i) * CELL_SIZE, angle, Vector2.ONE * member_scale)
		_draw_member(member, phase, i)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Stesse forme di HumanIndividualView._draw (gambe, busto, capelli lunghi per le donne, spalle, testa, viso,
# naso), senza gravidanza né selezione.
func _draw_member(member: Dictionary, phase: float, index: int) -> void:
	var skin := HumanIndividualView.SKIN_COLOR
	var hair_color: Color = HumanIndividualView.HAIR_COLOR_BY_TRAIT.get(
		member.get("hair_color", HumanTypes.HairColor.BROWN), HumanIndividualView.HAIR_COLOR_BY_TRAIT[HumanTypes.HairColor.BROWN]
	)
	var clothing_color: Color = _member_body_colors[index] if index < _member_body_colors.size() else HumanIndividualView.SKIN_COLOR
	var is_female: bool = member.get("sex", HumanTypes.Sex.MALE) == HumanTypes.Sex.FEMALE
	var leg_offset := _swing(phase, HumanIndividualView.LEG_SWING_FORWARD_AMPLITUDE, HumanIndividualView.LEG_SWING_BACKWARD_AMPLITUDE)
	var leg_offset_other := _swing(-phase, HumanIndividualView.LEG_SWING_FORWARD_AMPLITUDE, HumanIndividualView.LEG_SWING_BACKWARD_AMPLITUDE)
	_draw_ellipse(Vector2(HumanIndividualView.LEG_BASE_FORWARD + leg_offset, -HumanIndividualView.LEG_SIDE_OFFSET),
		HumanIndividualView.LEG_RADIUS_FORWARD, HumanIndividualView.LEG_RADIUS_SIDE, skin)
	_draw_ellipse(Vector2(HumanIndividualView.LEG_BASE_FORWARD + leg_offset_other, HumanIndividualView.LEG_SIDE_OFFSET),
		HumanIndividualView.LEG_RADIUS_FORWARD, HumanIndividualView.LEG_RADIUS_SIDE, skin)
	var torso_scale := HumanIndividualView.FEMALE_TORSO_SCALE if is_female else 1.0
	_draw_ellipse(Vector2.ZERO, HumanIndividualView.TORSO_RADIUS_FORWARD * torso_scale,
		HumanIndividualView.TORSO_RADIUS_SIDE * torso_scale, clothing_color)
	if is_female:
		_draw_ellipse(Vector2(HumanIndividualView.HAIR_LONG_OFFSET_FORWARD, 0.0), HumanIndividualView.HAIR_LONG_RADIUS_FORWARD,
			HumanIndividualView.HAIR_LONG_RADIUS_SIDE, hair_color)
	var arm_amp_f := HumanIndividualView.ARM_SWING_FORWARD_AMPLITUDE
	var arm_amp_b := HumanIndividualView.ARM_SWING_BACKWARD_AMPLITUDE
	draw_circle(Vector2(_swing(-phase, arm_amp_f, arm_amp_b), -HumanIndividualView.SHOULDER_SIDE_OFFSET), HumanIndividualView.SHOULDER_RADIUS, clothing_color)
	draw_circle(Vector2(_swing(phase, arm_amp_f, arm_amp_b), HumanIndividualView.SHOULDER_SIDE_OFFSET), HumanIndividualView.SHOULDER_RADIUS, clothing_color)
	draw_circle(Vector2.ZERO, HumanIndividualView.HEAD_RADIUS, hair_color)
	# Copricapo (2026-10-11): stessa calotta di HumanIndividualView._draw_head_cap.
	if index < _member_cap_colors.size() and _member_cap_colors[index].a > 0.0:
		draw_circle(
			Vector2(-HumanIndividualView.HEAD_RADIUS * HumanIndividualView.HEAD_CAP_OFFSET_BACK, 0.0),
			HumanIndividualView.HEAD_RADIUS * HumanIndividualView.HEAD_CAP_RADIUS_SCALE, _member_cap_colors[index]
		)
	# Viso: un ovale di pelle sul davanti della testa (approssima la lente testa/viso di HumanIndividualView).
	_draw_ellipse(Vector2(HumanIndividualView.HEAD_RADIUS * 0.55, 0.0), HumanIndividualView.HEAD_RADIUS * 0.4,
		HumanIndividualView.HEAD_RADIUS * 0.55, skin)
	draw_circle(Vector2(HumanIndividualView.NOSE_OFFSET_FORWARD, 0.0), HumanIndividualView.NOSE_RADIUS, skin)


static func _swing(signed_phase: float, forward_amplitude: float, backward_amplitude: float) -> float:
	return signed_phase * (forward_amplitude if signed_phase >= 0.0 else backward_amplitude)


func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(HumanIndividualView.ELLIPSE_SEGMENTS):
		var angle := (float(i) / float(HumanIndividualView.ELLIPSE_SEGMENTS)) * TAU
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, color)
