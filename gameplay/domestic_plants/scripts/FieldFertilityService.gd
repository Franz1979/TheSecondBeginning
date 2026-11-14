class_name FieldFertilityService
extends RefCounted

# Fertilità del campo (2026-11-15, richiesta utente): una per campo (Building.soil_fertility, 0,3-1,0), solo nei terreni
# a soli semi domestici (il campo); l'orto resta sempre a 1. Pesa sul tiro di maturazione (CultivationService.
# _advance_lot → TrialGardenService.roll_mature): con 0,7 matura circa il 70% delle piantine, il lotto si vede più rado.
# Si aggiorna una volta l'anno, il primo giorno della stagione dopo quella di raccolto della specie (estate se il campo
# non ha specie), con quanto è successo dall'ultima volta (Building.fertility_tracking):
# - mietitura: −10% × la parte dei lotti mietuta (4 lotti su 8 = −5%); se la specie mietuta è diversa da quella
#   dell'ultima mietitura, il primo anno +10% invece di −10% (cambio semenza, decisione utente);
# - nessuna semina dall'ultima volta (campo a "sempre no", senza specie o senza semi): maggese, +20%;
# - seminato ma niente mietuto (piante marcite o non nate): nessun cambio.
# Cura del campo (2026-11-15, richiesta utente — passo 1): regola generale del WM (GameData.stock_field_care_remedy e
# stock_field_care_threshold) o del singolo campo (Building.field_care_remedy/threshold, -1 = come la regola). Dopo il
# conto dell'anno, se la fertilità è sotto la soglia: Maggese = il campo salta la semina che viene (KEY_RESTING, fino al
# conto dopo, che darà +20%). Rizollatura (passo 2, rivista 2026-11-15 con l'utente): decisa all'inizio della stagione
# di raccolto con la fertilità di quel momento; ogni lotto si rizolla col piccone appena è vuoto (mietuto o mai nato)
# (KEY_RETILL, lavoro "retill" della lista, RetillAction, RETILL_LABOR_PER_LOT); +30% diviso per i lotti a ogni lotto
# finito (4 su 8 = +15%). All'inizio della stagione di semina le rizollature non finite si annullano e non contano: la
# Semina non aspetta mai.
# Stateless.

enum Remedy { NONE, FALLOW, RETILL }
const SELECTABLE_REMEDIES: Array[int] = [Remedy.NONE, Remedy.FALLOW, Remedy.RETILL]
const RETILL_GAIN := 0.30
# Lavoro di un lotto (decisione utente: tra la Semina, 300, e il dissodamento della costruzione, 500).
const RETILL_LABOR_PER_LOT := 400.0
const RETILL_TOOLS: Array[TaskTypes.ToolCategory] = [TaskTypes.ToolCategory.DIGGING]
const RETILL_TASK_DEFINITION_PATH := "res://gameplay/scripts/tasks/definitions/retill.tres"
const DEFAULT_REMEDY := Remedy.FALLOW
const DEFAULT_THRESHOLD := 60

const MIN_FERTILITY := 0.3
const HARVEST_LOSS := 0.10
const ROTATION_GAIN := 0.10
const FALLOW_GAIN := 0.20
const DEFAULT_CHECK_AFTER_SEASON := GameTypes.Season.SUMMER

const KEY_REAPED := "reaped"
const KEY_SOWN := "sown"
const KEY_SPECIES := "species"
const KEY_LAST_SPECIES := "last_species"
const KEY_YEAR := "year"
const KEY_RESTING := "resting"
const KEY_RETILL := "retill"
const KEY_RETILL_YEAR := "retill_year"


static func applies_to(building: Building) -> bool:
	return building != null and CultivationService.is_domestic_only(building)


# Moltiplicatore del tiro di maturazione.
static func fertility(building: Building) -> float:
	if not applies_to(building):
		return 1.0
	return clampf(building.soil_fertility, MIN_FERTILITY, 1.0)


# Un lotto seminato (CultivationService.finish_sowing, once seminate > 0).
static func on_sown(building: Building) -> void:
	if applies_to(building):
		building.fertility_tracking[KEY_SOWN] = true


# Un lotto chiuso alla Mietitura con `fraction` del lavoro fatto (0 = tutto marcito): conta per l'impoverimento.
static func on_reaped(building: Building, species: String, fraction: float) -> void:
	if not applies_to(building) or fraction <= 0.0:
		return
	var lot_count := maxi(CultivationService.lots(building).size(), 1)
	building.fertility_tracking[KEY_REAPED] = float(building.fertility_tracking.get(KEY_REAPED, 0.0)) \
		+ clampf(fraction, 0.0, 1.0) / float(lot_count)
	building.fertility_tracking[KEY_SPECIES] = species


# Giro giornaliero (CultivationService.advance_daily): il conto dell'anno, una volta sola, il primo giorno della stagione
# dopo quella di raccolto.
static func advance_daily(game_data: GameData, building: Building, season: int) -> void:
	if not applies_to(building) or building.is_demolished or not building.is_complete:
		return
	var rules := DomesticPlantCalculator.get_rules(building.crop_species)
	# Rizollatura: decisa all'inizio della stagione di raccolto (una volta l'anno), annullata all'inizio della semina.
	if rules != null and season == rules.harvest_season and int(building.fertility_tracking.get(KEY_RETILL_YEAR, -1)) != game_data.year:
		building.fertility_tracking[KEY_RETILL_YEAR] = game_data.year
		if remedy_for(game_data, building) == Remedy.RETILL and roundi(building.soil_fertility * 100.0) < threshold_for(game_data, building):
			var keys: Array = []
			for lot in CultivationService.lots(building):
				keys.append(CropLot.key_of(lot.microcell))
			building.fertility_tracking[KEY_RETILL] = keys
			CultivationService.mark_changed(building)
			CultivationService.log_line("%s #%d: fertilità %d%% sotto la soglia %d%%, rizollatura di %d lotti dopo la mietitura" % [
				building.building_type_name, building.id, roundi(building.soil_fertility * 100.0), threshold_for(game_data, building), keys.size()])
	if building.fertility_tracking.has(KEY_RETILL) and (rules == null or season == rules.sowing_season):
		_cancel_retill(building)
	var harvest_season: int = rules.harvest_season if rules != null and rules.harvest_season >= 0 else DEFAULT_CHECK_AFTER_SEASON
	if season != (harvest_season + 1) % 4 or int(building.fertility_tracking.get(KEY_YEAR, -1)) == game_data.year:
		return
	var tracking := building.fertility_tracking
	var before := building.soil_fertility
	var reaped := float(tracking.get(KEY_REAPED, 0.0))
	var why := ""
	if reaped > 0.0:
		var species := String(tracking.get(KEY_SPECIES, ""))
		var last_species := String(tracking.get(KEY_LAST_SPECIES, ""))
		var rotated := last_species != "" and species != "" and species != last_species
		building.soil_fertility += (ROTATION_GAIN if rotated else -HARVEST_LOSS) * minf(reaped, 1.0)
		if species != "":
			tracking[KEY_LAST_SPECIES] = species
		why = "cambio semenza" if rotated else "mietitura"
	elif not bool(tracking.get(KEY_SOWN, false)):
		building.soil_fertility += FALLOW_GAIN
		why = "maggese"
	building.soil_fertility = clampf(building.soil_fertility, MIN_FERTILITY, 1.0)
	tracking.erase(KEY_REAPED)
	tracking.erase(KEY_SOWN)
	tracking.erase(KEY_SPECIES)
	tracking.erase(KEY_RESTING)
	tracking[KEY_YEAR] = game_data.year
	if why != "":
		CultivationService.log_line("%s #%d: fertilità %d%% -> %d%% (%s)" % [building.building_type_name, building.id,
			roundi(before * 100.0), roundi(building.soil_fertility * 100.0), why])
	# Cura del campo: sotto la soglia, maggese per l'anno che viene.
	if remedy_for(game_data, building) == Remedy.FALLOW and roundi(building.soil_fertility * 100.0) < threshold_for(game_data, building):
		tracking[KEY_RESTING] = true
		CultivationService.log_line("%s #%d: fertilità %d%% sotto la soglia %d%%, maggese quest'anno" % [
			building.building_type_name, building.id, roundi(building.soil_fertility * 100.0), threshold_for(game_data, building)])



# Inizio della semina: le rizollature non finite si annullano, il lavoro fatto sui lotti si perde (non va alla Semina).
static func _cancel_retill(building: Building) -> void:
	var keys: Array = building.fertility_tracking.get(KEY_RETILL, [])
	for lot in CultivationService.lots(building):
		if keys.has(CropLot.key_of(lot.microcell)) and lot.phase == CultivationService.Phase.EMPTY and lot.seeds <= 0:
			lot.labor = 0.0
	CultivationService.log_line("%s #%d: inizia la semina, %d rizollature non finite annullate" % [building.building_type_name,
		building.id, keys.size()])
	building.fertility_tracking.erase(KEY_RETILL)
	CultivationService.mark_changed(building)


# true se il lotto è da rizollare adesso (vuoto, senza semi, campo finito e in piedi): la Semina lo aspetta.
static func needs_retill(_game_data: GameData, building: Building, lot: CropLot) -> bool:
	if lot == null or not applies_to(building) or not building.is_complete or building.is_demolished:
		return false
	if lot.phase != CultivationService.Phase.EMPTY or lot.seeds > 0:
		return false
	return (building.fertility_tracking.get(KEY_RETILL, []) as Array).has(CropLot.key_of(lot.microcell))


# Lotti ancora da rizollare quest'anno.
static func retill_pending(building: Building) -> int:
	if not applies_to(building):
		return 0
	return (building.fertility_tracking.get(KEY_RETILL, []) as Array).size()


# Lavoro della rizollatura di un lotto (× il moltiplicatore di lavoro del terreno, come Semina e Mietitura).
static func retill_labor(building: Building) -> float:
	if not applies_to(building):
		return 0.0
	return RETILL_LABOR_PER_LOT * building.rules.cultivation_labor_multiplier


# Lotto rizollato: +RETILL_GAIN diviso per i lotti, il lotto esce dalla lista e la Semina può partire.
static func finish_retill(building: Building, lot: CropLot) -> void:
	var keys: Array = building.fertility_tracking.get(KEY_RETILL, [])
	keys.erase(CropLot.key_of(lot.microcell))
	if keys.is_empty():
		building.fertility_tracking.erase(KEY_RETILL)
	lot.labor = 0.0
	var before := building.soil_fertility
	building.soil_fertility = clampf(building.soil_fertility + RETILL_GAIN / float(maxi(CultivationService.lots(building).size(), 1)),
		MIN_FERTILITY, 1.0)
	CultivationService.mark_changed(building)
	CultivationService.log_line("%s #%d lotto %s rizollato: fertilità %d%% -> %d%%, ne restano %d" % [building.building_type_name,
		building.id, lot.microcell, roundi(before * 100.0), roundi(building.soil_fertility * 100.0), keys.size()])


# true se il campo è a maggese quest'anno (niente Semina fino al prossimo conto).
static func is_resting(building: Building) -> bool:
	return applies_to(building) and bool(building.fertility_tracking.get(KEY_RESTING, false))


# Rimedio che vale per il campo: il suo, altrimenti la regola generale.
static func remedy_for(game_data: GameData, building: Building) -> int:
	if building != null and building.field_care_remedy >= 0:
		return building.field_care_remedy
	return game_data.stock_field_care_remedy if game_data != null else Remedy.NONE


# Soglia (percento) che vale per il campo: la sua, altrimenti la regola generale.
static func threshold_for(game_data: GameData, building: Building) -> int:
	if building != null and building.field_care_threshold >= 0:
		return building.field_care_threshold
	return game_data.stock_field_care_threshold if game_data != null else DEFAULT_THRESHOLD


static func remedy_key(remedy: int) -> String:
	match remedy:
		Remedy.FALLOW:
			return "field_care_fallow"
		Remedy.RETILL:
			return "field_care_retill"
	return "field_care_none"
