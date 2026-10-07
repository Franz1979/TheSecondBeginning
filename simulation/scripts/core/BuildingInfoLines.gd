class_name BuildingInfoLines
extends RefCounted

# Righe "Info" di un TIPO di edificio (2026-10-07, richiesta utente — spostate da BuildingInfoPanel._build_info_lines per
# poterle mostrare anche dove l'edificio non esiste in mappa, es. la finestra Aiuto): ricevono solo le regole del tipo
# (BuildingRules), mai l'edificio costruito. Stateless, statiche; testi tradotti con TranslationServer (stesso risultato
# di tr()). Il pannello edificio (BuildingInfoPanel._refresh_info) le passa a InfoCardBlock come prima.


# Righe del blocco Info: {"text": String, "indent": bool} (rientrate le categorie della conservazione e la regola d'uso
# dell'attrezzeria). Vuoto se `rules` è null.
static func build(rules: BuildingRules) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if rules == null:
		return rows
	var add_row := func(text: String, indent: bool) -> void:
		rows.append({"text": text, "indent": indent})
	if rules.storage_slot_count > 0:
		add_row.call(_tr("building_info_storage").format({
			"slots": rules.storage_slot_count, "space": rules.storage_space_per_slot,
			"total": rules.storage_slot_count * rules.storage_space_per_slot,
		}), false)
		add_row.call(_tr("building_info_conservation"), false)
		for category_index in SecondaryResourceTypes.Category.size():
			add_row.call(_tr("building_info_conservation_row").format({
				"category": category_display_name(category_index),
				"value": format_percent_bonus(durability_multiplier(rules, category_index)),
			}), true)
	if rules.max_residents > 0:
		add_row.call(_tr("building_info_residents").format({"count": rules.max_residents}), false)
		add_row.call(_tr("building_info_rest").format({"value": format_percent_bonus(rules.rest_multiplier)}), false)
	# Capienza del cumulo sepolcrale (2026-10-04): "Capienza: 10 sepolti". L'elenco dei sepolti sta nel corpo del pannello
	# (BuildingInfoPanel._refresh_buried_list).
	if rules.max_buried > 0:
		add_row.call(_tr("building_info_burial_capacity").format({"max": rules.max_buried}), false)
	# Attrezzeria (2026-10-04): letta dai dati, su ogni edificio che ce l'ha; con la regola d'uso.
	if rules.toolkit_tool_types > 0 and rules.toolkit_units_per_type > 0:
		add_row.call(_tr("building_info_toolkit").format({"types": rules.toolkit_tool_types, "units": rules.toolkit_units_per_type}), false)
		add_row.call(_tr("building_info_toolkit_usage"), true)
	if rules.is_workstation:
		add_row.call(_tr("building_info_concurrent_orders").format({"count": rules.production_concurrent_orders}), false)
		# Solo se diversi da 1,0 (2026-10-04, richiesta utente): un moltiplicatore neutro non si mostra.
		if not is_equal_approx(rules.production_labor_multiplier, 1.0):
			add_row.call(_tr("building_info_labor_multiplier").format({"value": format_percent_bonus(rules.production_labor_multiplier)}), false)
		if not is_equal_approx(rules.production_fuel_multiplier, 1.0):
			add_row.call(_tr("building_info_fuel_multiplier").format({"value": format_percent_bonus(rules.production_fuel_multiplier)}), false)
	# Dove finiscono i prodotti (2026-10-05, richiesta utente), stessa regola di ProductionService.flush_output_to_storage:
	# nel magazzino se l'edificio ne ha uno e ci travasa i prodotti, altrimenti restano nei posti dei prodotti finiti.
	if rules.production_output_slots > 0:
		if rules.production_output_to_storage and rules.storage_slot_count > 0:
			add_row.call(_tr("building_info_output_to_storage"), false)
		else:
			add_row.call(_tr("building_info_output_to_collect").format({"max": rules.production_output_slots}), false)
	add_row.call(_tr("building_info_max_durability").format({"value": rules.max_durability}), false)
	# Difesa (2026-10-04): ancora senza effetti in gioco, vedi BuildingRules.defense. A 0 non si mostra (2026-10-07).
	if rules.defense != 0:
		add_row.call(_tr("building_info_defense").format({"value": rules.defense}), false)
	for entry in [
		["building_info_political_radius", rules.political_radius],
		["building_info_cultural_radius", rules.cultural_radius],
	]:
		if int(entry[1]) > 0:
			add_row.call(_tr(String(entry[0])).format({"radius": int(entry[1])}), false)
	# Raggio religioso (2026-10-04): dato del tipo, base e massimo raggiungibile con tutte le soglie di sacralità
	# (max_religious_radius, dalla tabella delle soglie). Il raggio attuale della singola istanza sta nel corpo del pannello.
	if rules.religious_radius > 0:
		add_row.call(_tr("building_info_religious_radius_range").format({
			"base": rules.religious_radius, "max": max_religious_radius(rules),
		}), false)
	return rows


# Raggio religioso massimo di un tipo di edificio: base + una unità per ogni soglia di
# BuildingRules.influence_level_thresholds, entro il tetto base × influence_max_multiplier — la stessa regola di
# InfluenceService.get_effective_radius con tutte le soglie raggiunte.
static func max_religious_radius(rules: BuildingRules) -> int:
	var base := maxi(rules.religious_radius, 0)
	var cap := maxi(base, floori(maxf(float(base), float(base) * rules.influence_max_multiplier)))
	return clampi(base + rules.influence_level_thresholds.size(), base, cap)


# Moltiplicatore di conservazione di una categoria (BuildingRules.durability_multiplier_by_category, indice = categoria);
# 1.0 se l'elenco è più corto. Stessa regola di BuildingInfoPanel._durability_multiplier.
static func durability_multiplier(rules: BuildingRules, category_index: int) -> float:
	if rules == null or category_index >= rules.durability_multiplier_by_category.size():
		return 1.0
	return rules.durability_multiplier_by_category[category_index]


# Moltiplicatore come scarto percentuale: ×1.1 -> "+10%", ×1.0 -> "—", ×0.7 -> "−30%". Stessa regola di
# BuildingInfoPanel._format_percent_bonus.
static func format_percent_bonus(multiplier: float) -> String:
	var percent := roundi((multiplier - 1.0) * 100.0)
	if percent == 0:
		return "—"
	return ("+%d%%" % percent) if percent > 0 else ("−%d%%" % -percent)


# Nome tradotto di una categoria di risorse secondarie ("category_name_<categoria>"), come
# BuildingInfoPanel._category_display_name.
static func category_display_name(category: int) -> String:
	return _tr("category_name_%s" % SecondaryResourceTypes.Category.keys()[category].to_lower())


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
