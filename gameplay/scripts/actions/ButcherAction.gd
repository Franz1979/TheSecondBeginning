class_name ButcherAction
extends Action

# Macellazione di una carcassa a terra (2026-09-26, richiesta utente — step "Butcher" della Task butcher.tres:
# Walk → Butcher → PickUp dal mucchio). Il bersaglio è UNA carcassa di un GroundPile, identificata da
# macrocella, microcella del mucchio e id della carcassa (GroundPile.carcasses[i]["id"], stabile: gli indici
# cambierebbero quando una carcassa vicina marcisce).
#
#   - Attrezzi: richiede la categoria BUTCHERING con il gate di sempre (Action.ensure_required_tools a ogni tick:
#     senza coltello resta fermo e riparte quando arriva, come ProduceAction). Consuma UN uso per carcassa, al
#     termine (ToolGateService.consume_tool_uses).
#   - Età: vietata a neonati e bambini, permessa dagli adolescenti in su.
#   - Durata: carne ricavata / MEAT_UNITS_PER_DAY giorni di gioco (minimo MIN_DURATION_DAYS), con il consumo
#     di stamina delle azioni stazionarie (STAMINA_DRAIN_PER_DAY, stesso ordine di ProduceAction).
#   - Al termine: carne, pelli, tendini e ossa (AnimalRules gruppo Butchering, scalati per
#     size_multiplier_by_age della fascia della carcassa) vanno nello STESSO mucchio, poi la carcassa viene tolta.
#     Lo step successivo (PickUp dal mucchio) raccoglie quel che entra nello zaino.
#   - Carcassa marcita o sparita prima della fine: la Task si chiude (pending_task_abort).
# La skill (skill_crafting) cresce al completamento della Task, via TaskCompletionEffects (task_butcher_name).

# Ritmo della macellazione: unità di carne ricavate per giorno di gioco.
const MEAT_UNITS_PER_DAY: float = 10.0
# Durata minima (una carcassa con poca o nessuna carne richiede comunque un po' di lavoro).
const MIN_DURATION_DAYS: float = 0.1
# Stamina per giorno di gioco durante il lavoro (stesso ordine di ProduceAction/BuildAction).
const STAMINA_DRAIN_PER_DAY: float = 150.0

var pile_macro_coords: Vector2i = Vector2i.ZERO
var pile_microcell: Vector2i = Vector2i.ZERO
var carcass_id: int = -1

var _duration: float = 0.0
var _elapsed: float = 0.0
var _done: bool = false
# Progresso ripristinato da un salvataggio: activate() non deve ricalcolarlo (stesso schema di PickUpAction).
var _restored_from_save: bool = false


func _init(p_pile_macro_coords: Vector2i = Vector2i.ZERO, p_pile_microcell: Vector2i = Vector2i.ZERO, p_carcass_id: int = -1) -> void:
	target = null
	pile_macro_coords = p_pile_macro_coords
	pile_microcell = p_pile_microcell
	carcass_id = p_carcass_id
	required_tool_categories = [TaskTypes.ToolCategory.BUTCHERING]
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Rese di una carcassa: {"meat", "hide", "sinew", "bone"} in unità intere, dalle rese dell'adulto della specie
# (AnimalRules.butcher_*_units) scalate per size_multiplier_by_age della fascia. Statica e pura.
static func compute_yields(species: String, age_band: int) -> Dictionary:
	var yields := {"meat": 0, "hide": 0, "sinew": 0, "bone": 0}
	var rules := AnimalCalculator.get_animal_rules(species)
	if rules == null:
		return yields
	var scale: float = 1.0
	if age_band >= 0 and age_band < rules.size_multiplier_by_age.size():
		scale = rules.size_multiplier_by_age[age_band]
	yields["meat"] = roundi(rules.butcher_meat_units * scale)
	yields["hide"] = roundi(rules.butcher_hide_units * scale)
	yields["sinew"] = roundi(rules.butcher_sinew_units * scale)
	yields["bone"] = roundi(rules.butcher_bone_units * scale)
	return yields


func _get_carcass() -> Dictionary:
	return GroundPileService.find_carcass(GameSettings.active_game_data, pile_macro_coords, pile_microcell, carcass_id)


func is_target_valid() -> bool:
	return not _get_carcass().is_empty()


func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	_done = false
	if _restored_from_save:
		return
	_elapsed = 0.0
	var carcass := _get_carcass()
	var meat_units: int = 0
	if not carcass.is_empty():
		meat_units = int(compute_yields(String(carcass["species"]), int(carcass["age_band"]))["meat"])
	_duration = maxf(float(meat_units) / MEAT_UNITS_PER_DAY, MIN_DURATION_DAYS)


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _done:
		return 0.0
	if _get_carcass().is_empty():
		_done = true
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = "carcassa marcita o sparita durante la macellazione"
		return 0.0
	if not ensure_required_tools(individual):
		return 0.0
	_elapsed += delta
	if _elapsed >= _duration:
		_done = true
		_finish_butchering(individual)
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _done


# Prodotti nello stesso mucchio, poi via la carcassa (in quest'ordine: togliere prima la carcassa potrebbe
# svuotare e rimuovere il mucchio), infine un uso del coltello.
func _finish_butchering(individual: Variant) -> void:
	var game_data: GameData = GameSettings.active_game_data
	var carcass := _get_carcass()
	if carcass.is_empty():
		return
	var yields := compute_yields(String(carcass["species"]), int(carcass["age_band"]))
	var entries: Dictionary = {}
	for resource_name in yields:
		if int(yields[resource_name]) > 0:
			entries[resource_name] = {"quantity": int(yields[resource_name]), "decay_fraction": 0.0}
	if not entries.is_empty():
		GroundPileService.drop_entries(game_data, pile_macro_coords, Vector2(pile_microcell) + Vector2(0.5, 0.5), entries)
	GroundPileService.remove_carcass(game_data, pile_macro_coords, pile_microcell, carcass_id)
	var broken := ToolGateService.consume_tool_uses(individual, required_tool_categories, null)
	if not broken.is_empty():
		report_broken_tools(individual, broken)
	# Anche con i log della caccia (2026-09-27, diagnosi macellazione doppia): mostra quante volte la stessa carcassa
	# viene davvero macellata.
	if HuntService.is_logging() or (DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS):
		print("[BUTCHER] #%d %s: macellata carcassa #%d di %s (fascia %d) -> %s%s." % [
			individual.id, individual.name, carcass_id, String(carcass["species"]), int(carcass["age_band"]), str(yields),
			"" if broken.is_empty() else ", attrezzi rotti: %s" % str(broken)
		])


# Posizione della carcassa (centro della microcella del mucchio) nel sistema di coordinate dell'individuo.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	var macro_offset: Vector2 = Vector2(pile_macro_coords - individual.home_macro_coords) * World.WIDTH
	return Vector2(pile_microcell) + Vector2(0.5, 0.5) + macro_offset


func get_save_data() -> Dictionary:
	return {
		"pile_macro_x": pile_macro_coords.x,
		"pile_macro_y": pile_macro_coords.y,
		"pile_micro_x": pile_microcell.x,
		"pile_micro_y": pile_microcell.y,
		"carcass_id": carcass_id,
		"duration": _duration,
		"elapsed": _elapsed,
	}


# Solo lo step corrente riceve questa chiamata (TaskPersistenceService): riprende la macellazione in corso.
func load_save_data(data: Dictionary) -> void:
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_restored_from_save = _duration > 0.0
