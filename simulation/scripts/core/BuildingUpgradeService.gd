class_name BuildingUpgradeService
extends RefCounted

# Miglioramento di un edificio nel tipo indicato da BuildingRules.upgrades_to (2026-10-03, richiesta utente — passo 1:
# dato, pulsante e costo; i lavori veri arriveranno al passo 2 e riuseranno get_upgrade_cost). Stateless (static),
# stesso pattern degli altri *Service. Una sola destinazione per tipo; un edificio più grande non nasce da un
# miglioramento (stesso required_space, controllato solo con un avviso all'avvio: warn_space_mismatches).
#
# COSTO (get_upgrade_cost):
#   - sconto = metà, arrotondata per difetto, di ogni materiale di costruzione dell'edificio di partenza;
#   - da portare = materiali di costruzione della destinazione meno lo sconto, mai sotto zero (voci a 0 omesse);
#   - recuperato = la parte di sconto che la destinazione non usa (materiale non richiesto o in eccesso);
#   - lavoro = quello pieno della destinazione (required_labor), senza lavoro di demolizione.


# MIGLIORAMENTO IN CORSO (2026-10-03, passo 2): l'edificio diventa un cantiere del tipo di destinazione (stesso id e
# posto, GameScene._start_building_upgrade). In Building.construction_progress (salvato con l'edificio) restano i valori
# per l'annullamento, cancellati al completamento o all'annullamento:
const UPGRADE_FROM_TYPE_KEY := "upgrade_from_type"
const UPGRADE_FROM_DURABILITY_KEY := "upgrade_from_durability"
const UPGRADE_FROM_BUILT_YEAR_KEY := "upgrade_from_built_year"
# Sconto usato dalla destinazione, segnato come materiale già consegnato: all'annullamento resta all'edificio di
# partenza, solo l'eccedenza va a terra.
const UPGRADE_CREDITED_KEY := "upgrade_credited"
# Orientamento dell'edificio di partenza (2026-10-04): rimesso all'annullamento — il miglioramento da un edificio senza
# porta a uno con porta può avere cambiato Building.rotation con la scelta dell'orientamento.
const UPGRADE_FROM_ROTATION_KEY := "upgrade_from_rotation"
const UPGRADE_KEYS: Array[String] = [
	UPGRADE_FROM_TYPE_KEY, UPGRADE_FROM_DURABILITY_KEY, UPGRADE_FROM_BUILT_YEAR_KEY, UPGRADE_CREDITED_KEY,
	UPGRADE_FROM_ROTATION_KEY,
]


# true se `building` è il cantiere di un miglioramento in corso.
static func is_upgrade_site(building: Building) -> bool:
	return building != null and not building.is_complete and building.construction_progress.has(UPGRADE_FROM_TYPE_KEY)


# Tipo da DISEGNARE sulla mappa (2026-10-03, richiesta utente — aspetto durante i lavori): per un cantiere di
# miglioramento il tipo di partenza salvato in construction_progress (l'edificio vecchio resta visibile, con sopra i
# rametti del cantiere), altrimenti il tipo dell'istanza.
static func get_drawn_type_name(building: Building) -> String:
	if is_upgrade_site(building):
		var from_type := String(building.construction_progress.get(UPGRADE_FROM_TYPE_KEY, ""))
		if from_type != "":
			return from_type
	return building.building_type_name


# Regole del tipo di partenza di un cantiere di miglioramento (null se non lo è o il tipo non è risolvibile).
static func get_upgrade_from_rules(building: Building) -> BuildingRules:
	if not is_upgrade_site(building):
		return null
	return BuildingCalculator.get_building_rules(String(building.construction_progress.get(UPGRADE_FROM_TYPE_KEY, "")))


# true se nel magazzino di `building` c'è almeno un'unità (protezione provvisoria del passo 2: con risorse in
# magazzino il miglioramento non parte; la regola definitiva è da decidere).
static func has_stored_resources(building: Building) -> bool:
	if building == null:
		return false
	for resource_name in building.stored_resources.keys():
		if int((building.stored_resources[resource_name] as Dictionary).get("quantity", 0)) > 0:
			return true
	return false


# true se `building` ha qualcosa da posare a terra all'avvio di un miglioramento (2026-10-04, richiesta utente): almeno
# un'unità nel magazzino (stored_resources) o nei prodotti finiti (production_output) — lo stesso contenuto che
# GroundPileService.drop_building_contents svuota. Decide la conferma e la riga del tooltip di "Migliora".
static func has_contents_to_drop(building: Building) -> bool:
	if building == null:
		return false
	if has_stored_resources(building):
		return true
	for output_name in building.production_output.keys():
		if int(building.production_output[output_name]) > 0:
			return true
	return false


# Regole del tipo di destinazione di `building` (null se non migliorabile o tipo non risolvibile).
static func get_upgrade_rules(building: Building) -> BuildingRules:
	if building == null or building.rules == null or building.rules.upgrades_to == "":
		return null
	return BuildingCalculator.get_building_rules(building.rules.upgrades_to)


# Costo del miglioramento da `from_rules` a `to_rules`:
#   {"to_bring": {materiale: unità}, "credited": {materiale: unità dello sconto usate dalla destinazione},
#    "recovered": {materiale: unità dello sconto avanzate}, "labor": int}.
# "credited" è quanto il passo 2 segnerà come già consegnato al cantiere.
static func get_upgrade_cost(from_rules: BuildingRules, to_rules: BuildingRules) -> Dictionary:
	var result := {"to_bring": {}, "credited": {}, "recovered": {}, "labor": 0}
	if from_rules == null or to_rules == null:
		return result
	var discount: Dictionary = {}
	for material_name in from_rules.required_materials.keys():
		var half: int = int(from_rules.required_materials[material_name]) / 2
		if half > 0:
			discount[String(material_name)] = half
	for material_name in to_rules.required_materials.keys():
		var needed: int = int(to_rules.required_materials[material_name])
		var available: int = int(discount.get(String(material_name), 0))
		var credited: int = mini(needed, available)
		if credited > 0:
			result["credited"][String(material_name)] = credited
		if needed - credited > 0:
			result["to_bring"][String(material_name)] = needed - credited
	for material_name in discount.keys():
		var unused: int = int(discount[material_name]) - int(result["credited"].get(material_name, 0))
		if unused > 0:
			result["recovered"][material_name] = unused
	result["labor"] = to_rules.required_labor
	return result


# Avviso all'avvio (push_warning): ogni tipo con upgrades_to verso una destinazione con required_space diverso.
# Nessun altro controllo (una destinazione inesistente non viene segnalata qui).
static func warn_space_mismatches() -> void:
	for type_name in BuildingCalculator.list_building_type_names():
		var rules := BuildingCalculator.get_building_rules(type_name)
		if rules == null or rules.upgrades_to == "":
			continue
		var target := BuildingCalculator.get_building_rules(rules.upgrades_to)
		if target != null and target.required_space != rules.required_space:
			push_warning("BuildingUpgradeService: '%s' migliora in '%s' ma required_space è diverso (%d -> %d)." % [
				type_name, rules.upgrades_to, rules.required_space, target.required_space
			])
