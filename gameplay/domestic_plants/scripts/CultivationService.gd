class_name CultivationService
extends RefCounted

# Terreno coltivato (2026-11-15, richiesta utente — passo 1 dell'orto): vale per l'orto delle prove e per i campi futuri
# (BuildingRules.cultivation_lots > 0). Una specie per edificio, cambiabile solo a terreno vuoto; la sceglie il giocatore
# fra le specie già incontrate (almeno un'oncia raccolta, come la carta del pannello Addomesticazioni), anche se oggi non
# ne ha nei vasi: la semina (passo 2) aspetterà i semi. Fasi: vuoto -> seminato -> germogliato -> maturo -> (mietitura)
# vuoto. Lavoro di semina e mietitura per microcella × BuildingRules.cultivation_labor_multiplier.

enum Phase { EMPTY, SOWN, SPROUTED, READY }
# "Coltiva in automatico" del terreno (Building.crop_auto_mode): la scelta del terreno vince sulla regola del WM.
enum AutoMode { FOLLOW_RULE, ALWAYS, NEVER }

# Terreni il cui disegno è cambiato (id -> Building), letti e svuotati da GameScene ogni fotogramma (take_changed): così
# il livello degli edifici si ridisegna solo quando nasce, matura o si miete qualcosa.
static var _changed: Dictionary = {}

# Semina (passo 2, 2026-11-15): lavoro "Semina" della lista (CultivationJobProvider, tipo "cultivate"). Chi lo prende porta
# i semi (fino a sown_units_per_lot, quanti ne entrano nello zaino) sul suo lotto (CropLot.seeds) e lavora col
# bastone da scavo; il lavoro fatto sta sul lotto (CropLot.labor), così un altro può riprenderlo. Finito il lavoro tutte
# le once sono seminate; finita la stagione prima, solo la parte fatta e il resto dei semi è perso (advance_daily).
# Piantine (advance_daily): il giorno SPROUT_DAY_IN_SEASON della stagione dopo la semina, un tiro per oncia.
const SPROUT_DAY_IN_SEASON := 4
# Maturazione (passo 3, 2026-11-15): il giorno MATURE_DAY_IN_SEASON (30°) della stagione di raccolto, un tiro per piantina
# (avanzamento × fertilità del terreno): fa i semi o marcisce. Nessun punto qui: i punti alla Mietitura, per pianta
# mietuta. Piante mature non mietute entro la fine della stagione di raccolto: marciscono, -points_per_rotten_plant
# ciascuna, terreno vuoto.
const MATURE_DAY_IN_SEASON := 29
const TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/sow.tres"
const RESUME_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/sow_resume.tres"
const SKILL_EFFECT_KEY := "sow"
const SOWING_TOOLS: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.SOWING]
# Mietitura (passo 4, 2026-11-15): lavoro "Mietitura" della lista sul terreno maturo, nella stagione di raccolto, col
# falcetto (categoria Mietitura). Lavoro sul lotto (CropLot.labor, lo stesso della semina: le due fasi non si
# sovrappongono). Finito: once raccolte in un mucchio accanto all'orto (poi il lavoro dei mucchi le porta in magazzino o
# granaio), points_per_mature_plant per pianta mietuta, terreno vuoto. Finita la stagione prima: mietuta la parte fatta,
# il resto marcisce (-points_per_rotten_plant ciascuna).
const REAP_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/reap.tres"
const REAP_SKILL_EFFECT_KEY := "reap"
const REAPING_TOOLS: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.REAPING]
const CONTEXT_BUILDING_ID := "sow_building_id"
# Lotto del lavoro (2026-11-15, passo 2 dei campi): CropLot.key_of della sua microcella.
const CONTEXT_LOT_CELL := "sow_lot_cell"
# Attrezzi del capanno (2026-11-15, passo 2c dei campi — come la produzione nelle officine): true = chi lavora usa il
# bastone o il falcetto dell'Attrezzeria del terreno, non i propri. Deciso all'assegnazione
# (CultivationJobProvider.shed_covers): un pezzo per lavoratore, quindi col capanno a 4 bastoni seminano col bastone del
# capanno al più 4 persone, le altre coi propri.
const CONTEXT_SHED_TOOLS := "sow_shed_tools"
# Semi dal capanno (2026-11-15, passo 3c): once che chi semina conta di trovare nel capanno del campo
# (CultivationJobProvider.shed_seeds_free all'assegnazione); il resto lo porta dal magazzino.
const CONTEXT_SHED_SEEDS := "sow_shed_seeds"

# Lavoro per microcella, cioè per lotto (2026-11-15, richiesta utente: tutto a mano su 10×10 m): semina col bastone
# ~2 giorni, mietitura col falcetto ~1,5 giorni a 150 al giorno; nell'orto ×2.
const SOWING_LABOR_PER_LOT := 300.0
const REAPING_LABOR_PER_LOT := 225.0


static func is_cultivated(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.cultivation_lots > 0


static func sowing_labor(building: Building) -> float:
	if not is_cultivated(building):
		return 0.0
	return SOWING_LABOR_PER_LOT * building.rules.cultivation_labor_multiplier


static func reaping_labor(building: Building) -> float:
	if not is_cultivated(building):
		return 0.0
	return REAPING_LABOR_PER_LOT * building.rules.cultivation_labor_multiplier


# Specie sceglibili: con un .tres seminabile e già incontrate; per il campo (solo domestico) solo quelle addomesticate con
# la loro risorsa domestica.
static func selectable_species(game_data: GameData, building: Building = null) -> Array[String]:
	var result: Array[String] = []
	if game_data == null:
		return result
	var domestic_only := is_domestic_only(building)
	for species in DomesticPlantCalculator.list_species():
		var rules := DomesticPlantCalculator.get_rules(species)
		if not TrialGardenService.can_sow(rules):
			continue
		if domestic_only:
			if game_data.domesticated_species.has(species) and rules.domestic_resource_name != "":
				result.append(species)
			continue
		if DomesticationPointsService.get_points(game_data, species) > 0 \
				or int(game_data.domestication_harvest_units.get(species, 0)) > 0 \
				or game_data.domesticated_species.has(species):
			result.append(species)
	return result


static func can_change_species(building: Building) -> bool:
	if not is_cultivated(building):
		return false
	for lot in lots(building):
		if lot.phase != Phase.EMPTY or lot.seeds > 0:
			return false
	return true


# Microcelle dei lotti (2026-11-15, passo 2 dei campi): il campo la sua terra senza il capanno (FieldShape.world_cells),
# gli altri l'ingombro dell'edificio (l'orto: la sua microcella).
static func lot_cells(building: Building) -> Array[Vector2i]:
	if building.building_type_name == FieldShape.TYPE:
		return FieldShape.world_cells(building)
	return BuildingFootprint.cells_of(building)


# Once seminate in un lotto: quelle dell'edificio (il campo 100), altrimenti quelle della specie (l'orto).
static func units_per_lot(building: Building) -> int:
	var rules := DomesticPlantCalculator.get_rules(building.crop_species) if building != null else null
	if rules == null or not TrialGardenService.can_sow(rules):
		return 0
	if building.rules != null and building.rules.cultivation_units_per_lot > 0:
		return building.rules.cultivation_units_per_lot
	return rules.sown_units_per_lot


# true se il terreno semina solo il domestico (il campo, BuildingRules.cultivation_domestic_only).
static func is_domestic_only(building: Building) -> bool:
	return building != null and building.rules != null and building.rules.cultivation_domestic_only


# Punti di addomesticazione del terreno: nessuno dove si semina solo il domestico (il campo).
static func _points_of(building: Building, points: Dictionary) -> Dictionary:
	return {} if is_domestic_only(building) else points


# Lotti del terreno, uno per microcella di lot_cells, nello stesso ordine; creati vuoti la prima volta (e per una
# microcella nuova), quelli che ci sono restano con la loro vita.
static func lots(building: Building) -> Array[CropLot]:
	if not is_cultivated(building):
		return building.crop_lots if building != null else ([] as Array[CropLot])
	var cells := lot_cells(building)
	var matches := building.crop_lots.size() == cells.size()
	if matches:
		for i in range(cells.size()):
			if building.crop_lots[i].microcell != cells[i]:
				matches = false
				break
	if not matches:
		var by_cell: Dictionary = {}
		for lot in building.crop_lots:
			by_cell[lot.microcell] = lot
		var result: Array[CropLot] = []
		for cell in cells:
			result.append(by_cell[cell] if by_cell.has(cell) else CropLot.new(cell))
		building.crop_lots = result
	return building.crop_lots


# Lotto del terreno sulla microcella `cell`, o null.
static func find_lot(building: Building, cell: Vector2i) -> CropLot:
	if building == null:
		return null
	for lot in lots(building):
		if lot.microcell == cell:
			return lot
	return null


# Lotto di un lavoro dal suo Task.context (CONTEXT_LOT_CELL); senza la chiave (compiti salvati prima dei lotti) il primo.
static func lot_from_context(building: Building, context: Dictionary) -> CropLot:
	if building == null:
		return null
	if context.has(CONTEXT_LOT_CELL):
		return find_lot(building, CropLot.cell_of_key(int(context[CONTEXT_LOT_CELL])))
	var all := lots(building)
	return all[0] if not all.is_empty() else null


static func set_species(building: Building, species: String) -> bool:
	if not can_change_species(building) or building.crop_species == species:
		return false
	building.crop_species = species
	return true


# Nome della specie: domestico se addomesticata, altrimenti selvatico.
# Nome della specie nell'orto (scelta della coltura, lavori della lista): sempre quello selvatico, anche a specie
# addomesticata (2026-11-15, richiesta utente), perché l'orto semina solo il selvatico. Il campo (`building` solo
# domestico): il nome domestico.
static func species_display_name(_game_data: GameData, species: String, building: Building = null) -> String:
	var rules := DomesticPlantCalculator.get_rules(species)
	if rules == null:
		return species
	return TranslationServer.translate(rules.display_name if is_domestic_only(building) else rules.wild_display_name)


# Risorsa che si semina sul terreno: il campo il domestico, l'orto quella che si raccoglie in natura.
static func seed_resource(building: Building) -> String:
	var rules := DomesticPlantCalculator.get_rules(building.crop_species) if building != null else null
	if rules == null:
		return ""
	if is_domestic_only(building):
		return rules.domestic_resource_name
	return rules.harvest_resource_name


# Once che dà la Mietitura (2026-11-15, richiesta utente): l'orto si semina sempre col selvatico; a specie addomesticata
# (conta lo stato al momento della Mietitura) rende la risorsa domestica, se la specie ce l'ha già, altrimenti il selvatico.
static func harvest_resource(game_data: GameData, species: String) -> String:
	var rules := DomesticPlantCalculator.get_rules(species)
	if rules == null:
		return ""
	if game_data != null and game_data.domesticated_species.has(species) and rules.domestic_resource_name != "":
		return rules.domestic_resource_name
	return rules.harvest_resource_name


static func current_season(game_data: GameData) -> int:
	return int(SeasonCalculator.get_season_for_day(game_data.current_day))


static func is_sowing_season(game_data: GameData, species: String) -> bool:
	var rules := DomesticPlantCalculator.get_rules(species)
	return game_data != null and rules != null and TrialGardenService.can_sow(rules) and current_season(game_data) == rules.sowing_season


# true se sul lotto c'è da seminare adesso: edificio finito, specie scelta, lotto vuoto, stagione di semina.
static func needs_sowing(game_data: GameData, building: Building, lot: CropLot) -> bool:
	return lot != null and is_cultivated(building) and building.is_complete and not building.is_demolished \
		and building.crop_species != "" and lot.phase == Phase.EMPTY and is_sowing_season(game_data, building.crop_species) \
		and not FieldFertilityService.is_resting(building)


# true se il lotto maturo è da mietere adesso (stagione di raccolto della specie).
static func needs_reaping(game_data: GameData, building: Building, lot: CropLot) -> bool:
	if game_data == null or lot == null or not is_cultivated(building) or not building.is_complete or building.is_demolished \
			or lot.phase != Phase.READY:
		return false
	var rules := DomesticPlantCalculator.get_rules(building.crop_species)
	return rules != null and current_season(game_data) == rules.harvest_season


# Chiude la mietitura del lotto con `fraction` del lavoro fatto: once delle piante mietute in un mucchio sul lotto, punti
# (mietute +, marcite -) e lotto vuoto. Ritorna {specie: punti} (vuoto se zero).
static func finish_reaping(game_data: GameData, world: World, building: Building, lot: CropLot, fraction: float) -> Dictionary:
	var species := building.crop_species
	var rules := DomesticPlantCalculator.get_rules(species)
	var reaped := clampi(int(floor(float(lot.mature) * clampf(fraction, 0.0, 1.0))), 0, lot.mature)
	var rotten := lot.mature - reaped
	FieldFertilityService.on_reaped(building, species, clampf(fraction, 0.0, 1.0))
	# Resa prima dei punti: l'avanzamento è quello del raccolto.
	var units := TrialGardenService.harvest_units(game_data, species, reaped, disease_yield_multiplier(building),
		building.rules.cultivation_yield_cap)
	var seed_name := rules.domestic_resource_name if is_domestic_only(building) else harvest_resource(game_data, species)
	# Sul lotto stesso (2026-11-15, richiesta utente): finché non si porta via, il lotto non si risemina (harvest_pile).
	if units > 0 and seed_name != "":
		GroundPileService.drop_at(game_data, Vector2i(building.macro_x, building.macro_y), lot.microcell,
			{seed_name: {"quantity": units, "decay_fraction": 0.0}})
	log_line("%s #%d lotto %s: mietute %d piante di %s (%d once a terra), marcite %d" % [
		building.building_type_name, building.id, lot.microcell, reaped, species, units, rotten])
	_clear(building, lot)
	lot.labor = 0.0
	var points := TrialGardenService.mature_points(rules, reaped) + TrialGardenService.rotten_points(rules, rotten)
	return _points_of(building, {species: points} if points != 0 else {})


# Mucchio del raccolto ancora sul lotto (con qualcosa dentro), o null: finché c'è, la Semina del lotto è bloccata.
static func harvest_pile(game_data: GameData, building: Building, lot: CropLot) -> GroundPile:
	if game_data == null or building == null or lot == null:
		return null
	var pile := GroundPileService.find_at(game_data, Vector2i(building.macro_x, building.macro_y), lot.microcell)
	return pile if pile != null and not pile.is_empty() else null


# Once che il lotto vuole ancora (oltre a quelle già portate).
static func seeds_wanted(building: Building, lot: CropLot) -> int:
	var rules := DomesticPlantCalculator.get_rules(building.crop_species) if building != null else null
	if rules == null or lot == null or not is_cultivated(building):
		return 0
	return maxi(units_per_lot(building) - lot.seeds, 0)


# Chiude la semina del lotto con `fraction` del lavoro fatto: once seminate, fase, punti ({specie: punti}, vuoto se nessuno).
static func finish_sowing(building: Building, lot: CropLot, fraction: float) -> Dictionary:
	var species := building.crop_species
	var rules := DomesticPlantCalculator.get_rules(species)
	var sown := clampi(int(floor(float(lot.seeds) * clampf(fraction, 0.0, 1.0))), 0, lot.seeds)
	var lost := lot.seeds - sown
	lot.seeds = 0
	lot.labor = 0.0
	lot.sown = sown
	lot.sprouts = 0
	lot.mature = 0
	lot.phase = Phase.SOWN if sown > 0 else Phase.EMPTY
	if sown > 0:
		FieldFertilityService.on_sown(building)
	mark_changed(building)
	log_line("%s #%d lotto %s: seminate %d once di %s (perse %d)" % [
		building.building_type_name, building.id, lot.microcell, sown, species, lost])
	var points := TrialGardenService.sowing_points(rules, sown) if rules != null else 0
	return _points_of(building, {species: points} if points > 0 else {})


# Giro giornaliero (GameScene._on_day_advanced), lotto per lotto: semine interrotte dalla fine della stagione, piantine
# che spuntano, piante che maturano, mietiture interrotte. Ritorna i punti {specie: punti} da assegnare.
static func advance_daily(world: World, game_data: GameData) -> Dictionary:
	var earned: Dictionary = {}
	if world == null or game_data == null:
		return earned
	var season := current_season(game_data)
	var day_in_season := game_data.current_day - SeasonCalculator.get_season_day_range(season as GameTypes.Season).x
	for building in world.buildings:
		if not is_cultivated(building) or building.is_demolished:
			continue
		var rules := DomesticPlantCalculator.get_rules(building.crop_species) if building.crop_species != "" else null
		if rules != null:
			for lot in lots(building):
				_merge(earned, _advance_lot(world, game_data, building, lot, rules, season, day_in_season))
		# Conto annuale della fertilità del campo, dopo i lotti (anche senza specie: maggese).
		FieldFertilityService.advance_daily(game_data, building, season)
	return earned


static func _advance_lot(world: World, game_data: GameData, building: Building, lot: CropLot, rules: DomesticPlantRules,
		season: int, day_in_season: int) -> Dictionary:
	if lot.phase == Phase.EMPTY and lot.seeds > 0 and season != rules.sowing_season:
		var required := sowing_labor(building)
		return finish_sowing(building, lot, lot.labor / required if required > 0.0 else 1.0)
	if lot.phase == Phase.SOWN and season == (rules.sowing_season + 1) % 4 and day_in_season >= SPROUT_DAY_IN_SEASON:
		var sprouts := TrialGardenService.roll_sprouts(game_data, building.crop_species, lot.sown)
		log_line("%s #%d lotto %s: spuntate %d piantine di %s su %d once" % [
			building.building_type_name, building.id, lot.microcell, sprouts, building.crop_species, lot.sown])
		lot.sprouts = sprouts
		lot.phase = Phase.SPROUTED if sprouts > 0 else Phase.EMPTY
		mark_changed(building)
		if sprouts <= 0:
			lot.sown = 0
		var points := TrialGardenService.sprout_points(rules, sprouts)
		return _points_of(building, {building.crop_species: points} if points > 0 else {})
	if lot.phase == Phase.SPROUTED and season == rules.harvest_season and day_in_season >= MATURE_DAY_IN_SEASON:
		var mature := TrialGardenService.roll_mature(game_data, building.crop_species, lot.sprouts, soil_fertility(building))
		log_line("%s #%d lotto %s: %d piante di %s fanno i semi su %d piantine" % [
			building.building_type_name, building.id, lot.microcell, mature, building.crop_species, lot.sprouts])
		if mature > 0:
			lot.mature = mature
			lot.phase = Phase.READY
			mark_changed(building)
		else:
			_clear(building, lot)
		return {}
	if lot.phase == Phase.READY and season != rules.harvest_season:
		# Fine della stagione di raccolto: mietuta solo la parte fatta (anche niente), il resto marcisce.
		var required := reaping_labor(building)
		return finish_reaping(game_data, world, building, lot, lot.labor / required if required > 0.0 else 0.0)
	return {}


# Usura di un lotto chiuso (Semina e Mietitura, un uso per lotto dal 2026-11-15): con gli attrezzi del capanno (`uses_shed`) un uso
# sul pezzo dell'Attrezzeria che copre ogni categoria, come ProduceAction._consume_tools_for_cycle; le categorie che il
# capanno non copre (o senza capanno) sulla cintura. Ritorna gli attrezzi rotti.
static func wear_tools(individual: HumanIndividual, building: Building, categories: Array[TaskTypes.ToolCategory],
		uses_shed: bool, game_data: GameData) -> Array[String]:
	var broken: Array[String] = []
	var shed_tools: Array[String] = []
	var belt_categories: Array[TaskTypes.ToolCategory] = []
	for category in categories:
		var shed_tool := BuildingToolkitService.find_tool_for(building, category) if uses_shed else ""
		if shed_tool == "":
			belt_categories.append(category)
		elif not shed_tools.has(shed_tool):
			shed_tools.append(shed_tool)
	for shed_tool in shed_tools:
		if BuildingToolkitService.consume_use(building, shed_tool):
			broken.append(shed_tool)
	broken.append_array(ToolGateService.consume_tool_uses(individual, belt_categories, game_data))
	return broken


# Categorie che deve coprire chi lavora: con gli attrezzi del capanno solo quelle che il capanno non copre (per esempio
# se il pezzo si è rotto nel frattempo).
static func worker_tool_categories(building: Building, categories: Array[TaskTypes.ToolCategory], uses_shed: bool) -> Array[TaskTypes.ToolCategory]:
	return BuildingToolkitService.filter_uncovered(building, categories) if uses_shed else categories


# Lotto di nuovo vuoto (la specie scelta resta sull'edificio).
static func _clear(building: Building, lot: CropLot) -> void:
	mark_changed(building)
	lot.phase = Phase.EMPTY
	lot.sown = 0
	lot.sprouts = 0
	lot.mature = 0


# Fertilità del terreno, moltiplicatore del tiro di maturazione (0,3-1; orto sempre 1): FieldFertilityService.
static func soil_fertility(building: Building) -> float:
	return FieldFertilityService.fertility(building)


# Malattie delle piante, moltiplicatore della resa alla Mietitura (es. 0,5 = resa dimezzata). Per ora sempre 1.
# DA FARE (2026-11-15, richiesta utente): malattie che colpiscono un terreno coltivato e ne dimezzano la resa.
static func disease_yield_multiplier(_building: Building) -> float:
	return 1.0


static func _merge(into: Dictionary, extra: Dictionary) -> void:
	for species in extra:
		into[species] = int(into.get(species, 0)) + int(extra[species])


static func log_line(message: String) -> void:
	print("[COLTIVAZIONE] %s" % message)


# Semina e Mietitura di questo terreno vanno da sole nella lista dei lavori? Sempre sì / sempre no del terreno, altrimenti
# la regola del WM (GameData.stock_cultivation_auto).
static func is_auto(game_data: GameData, building: Building) -> bool:
	if building == null:
		return false
	match building.crop_auto_mode:
		AutoMode.ALWAYS:
			return true
		AutoMode.NEVER:
			return false
	return game_data == null or game_data.stock_cultivation_auto


static func mark_changed(building: Building) -> void:
	if building != null:
		_changed[building.id] = building


static func take_changed() -> Array:
	var result := _changed.values()
	_changed.clear()
	return result


# Dati del disegno delle piantine (MicroCellRenderer), un elemento per lotto con qualcosa da disegnare:
# {"cell" (microcella), "phase", "ratio" (piante / once seminabili del lotto), "color"}; vuoto se nessun lotto ne ha.
static func crop_visual(building: Building) -> Array:
	var result: Array = []
	if not is_cultivated(building) or not building.is_complete:
		return result
	var rules := DomesticPlantCalculator.get_rules(building.crop_species)
	if rules == null:
		return result
	var capacity := maxi(units_per_lot(building), 1)
	for lot in lots(building):
		if lot.phase != Phase.SPROUTED and lot.phase != Phase.READY:
			continue
		var plants := lot.sprouts if lot.phase == Phase.SPROUTED else lot.mature
		result.append({"cell": lot.microcell, "phase": lot.phase,
			"ratio": clampf(float(plants) / float(capacity), 0.0, 1.0), "color": rules.crop_color})
	return result


static func phase_key(phase: int) -> String:
	match phase:
		Phase.SOWN:
			return "crop_phase_sown"
		Phase.SPROUTED:
			return "crop_phase_sprouted"
		Phase.READY:
			return "crop_phase_ready"
	return "crop_phase_empty"
