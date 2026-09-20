class_name RunAction
extends Action

# Variante "veloce" di WalkAction (2026-09-13, richiesta utente, in preparazione della futura Task
# Play — non ancora costruita in questo passo: solo l'Action e il suo collegamento a TaskFactory/
# persistenza). Stessa identica forma/stessa identica logica di completamento/stesso identico
# aggancio a is_moving/facing_direction di WalkAction (vedi WalkAction.gd per ogni commento non
# ripetuto qui) — l'UNICA differenza è il costo di stamina per microcella percorsa.
#
# `individual` resta Variant in ogni override, stesso motivo di WalkAction (il tipo deve combaciare
# esattamente con la firma di Action, deliberatamente agnostica su HumanIndividual).

# Fattore "intensità" della corsa rispetto a Walk — UNICO, condiviso da costo E velocità (bugfix
# 2026-09-13, richiesta utente: "correre" doveva anche accorciare il tempo di arrivo, non solo
# costare di più per la stessa andatura — verificato che HumanIndividualMovementService.
# advance_movement legge SOLO individual.move_speed/move_speed_multiplier, del tutto ignaro di quale
# Action sia attiva: PRIMA di questo fix RunAction impostava is_moving=true esattamente come
# WalkAction senza mai toccare la velocità, quindi si muoveva alla sua IDENTICA velocità pur
# costando il doppio). Applicato in DUE punti: qui sotto in get_stamina_delta (moltiplica
# WalkAction.STAMINA_DRAIN_PER_MICROCELL_BASE, mai una propria copia numerica — un domani in cui
# quella costante cambiasse in WalkAction.gd si propaga qui da solo) e in activate() sotto
# (moltiplica individual.move_speed tramite move_speed_multiplier). Stesso fattore per entrambi
# (2.0): "correre" è un unico concetto di intensità raddoppiata, non due tarature indipendenti da
# tenere sincronizzate a mano. Il costo per utensile/spazio carico invece resta IDENTICO a Walk
# (stessi WalkAction.STAMINA_DRAIN_PER_TOOL/used_carry_space, non moltiplicati): solo la parte
# "base" del costo (lo sforzo del movimento in sé) è raddoppiata dalla corsa, non il peso trasportato.
const RUN_INTENSITY_MULTIPLIER: float = 2.0


func _init(p_target: Vector2) -> void:
	target = p_target
	# INFANT non può correre da solo (stesso vincolo base di WalkAction — il vincolo CHILD-only
	# della futura Task Play vive lì, non qui, dato che Run potrebbe tornare utile anche per adulti
	# in futuro).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


# Identico a WalkAction.activate (super() PRIMA di is_moving = true, vedi lì per il perché) PIÙ
# move_speed_multiplier — bugfix 2026-09-13, vedi RUN_INTENSITY_MULTIPLIER sopra: senza questa riga
# RunAction si muoveva alla stessa velocità di WalkAction nonostante il costo doppio.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	individual.target_position = target
	individual.is_moving = true
	individual.move_speed_multiplier = RUN_INTENSITY_MULTIPLIER


# Stesso identico meccanismo di WalkAction._last_position — vedi lì per il perché (nessuna API di
# movimento espone "quanto ci si è mossi nell'ultimo frame", questa istanza se lo calcola da sola
# per differenza).
var _last_position: Variant = null


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _last_position == null:
		_last_position = individual.position
		return 0.0
	var distance: float = individual.position.distance_to(_last_position)
	_last_position = individual.position

	# Stesso identico lookup di WalkAction.get_stamina_delta per il carico trasportato.
	var used_carry_space := 0.0
	if individual.carried_resource_name != "":
		var carried_resource_rules := CaloricCalculator.get_caloric_source_rules(individual.carried_resource_name)
		if carried_resource_rules != null:
			used_carry_space = float(individual.carried_quantity) * carried_resource_rules.space_per_unit

	var cost_per_microcell: float = (
		# terrain_stamina_multiplier (2026-09-19, vedi MovementTerrainService): solo sulla quota base.
		RUN_INTENSITY_MULTIPLIER * WalkAction.STAMINA_DRAIN_PER_MICROCELL_BASE * individual.terrain_stamina_multiplier
		+ used_carry_space
		+ WalkAction.STAMINA_DRAIN_PER_TOOL * float(individual.equipped_tool_count)
	)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS:
		MovementStaminaDebugLog.record(
			individual, "Run", distance, individual.terrain_stamina_multiplier,
			RUN_INTENSITY_MULTIPLIER * WalkAction.STAMINA_DRAIN_PER_MICROCELL_BASE,
			used_carry_space + WalkAction.STAMINA_DRAIN_PER_TOOL * float(individual.equipped_tool_count)
		)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_LOGS:
		print("[RUN DEBUG] get_stamina_delta: distance=%.3f cost_per_microcell=%.2f (base Walk x%.1f + carico/utensili invariati) -> delta=%.2f" % [
			distance, cost_per_microcell, RUN_INTENSITY_MULTIPLIER, -distance * cost_per_microcell
		])
	return -distance * cost_per_microcell


# Identico a WalkAction.is_complete (2026-09-16, richiesta utente, fix bordo macrocella — vedi
# WalkAction.ARRIVAL_TOLERANCE per il perché non è più un'uguaglianza esatta), stessa costante
# condivisa (non una copia separata, mai un secondo numero da tenere sincronizzato a mano).
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return individual.position.distance_to(target) <= WalkAction.ARRIVAL_TOLERANCE


# Chiude la riga di log dell'ultima microcella attraversata (diagnostica TEMPORANEA, vedi
# MovementStaminaDebugLog) — nessun effetto se il flag è spento.
func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS:
		MovementStaminaDebugLog.flush(individual)
