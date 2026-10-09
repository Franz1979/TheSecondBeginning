class_name RecipeInfoLines
extends RefCounted

# Righe informative di una risorsa (2026-10-07, richiesta utente — scheda "Risorse" della finestra Aiuto): ricevono
# solo i dati della risorsa (SecondaryResourceRules), mai un edificio, quindi mostrano i valori di base (senza i
# moltiplicatori di lavoro e combustibile della singola postazione, che applica ProductionService). Solo le righe con un
# valore: niente righe vuote o a zero. Stateless, statiche; testi tradotti con TranslationServer (stesso risultato di
# tr()). Tre gruppi: caratteristiche (characteristics), attrezzo (tool_lines), ricetta (build).


# Caratteristiche: spazio occupato, deperimento (giorni di conservazione dopo la raccolta; -1 = non deperisce, nessuna
# riga), calorie ed effetto su felicità e salute se è un cibo, valore come combustibile.
static func characteristics(rules: SecondaryResourceRules) -> Array[String]:
	var lines: Array[String] = []
	if rules == null:
		return lines
	if rules.space_per_unit > 0.0:
		lines.append(_tr("help_resource_space").format({"value": format_number(rules.space_per_unit)}))
	if rules.day_durability > 0:
		lines.append(_tr("help_resource_durability").format({"days": rules.day_durability}))
	if rules.category == SecondaryResourceTypes.Category.FOOD:
		if rules.calories_per_unit > 0.0:
			lines.append(_tr("help_resource_calories").format({"value": format_number(rules.calories_per_unit)}))
		if not is_zero_approx(rules.eat_happiness_per_100_calories):
			lines.append(_tr("help_resource_happiness").format({"value": format_signed(rules.eat_happiness_per_100_calories)}))
		if not is_zero_approx(rules.eat_health_per_100_calories):
			lines.append(_tr("help_resource_health").format({"value": format_signed(rules.eat_health_per_100_calories)}))
	if rules.fuel_value > 0.0:
		lines.append(_tr("help_resource_fuel").format({"value": format_number(rules.fuel_value)}))
	return lines


# Attrezzo: a cosa serve (categorie d'uso), usi, potenza e portata se è un'arma, munizione richiesta (con gli attrezzi
# che la forniscono, es. arco -> mazzo di frecce), efficienza di lavoro se diversa da 1, bonus di capacità.
static func tool_lines(rules: SecondaryResourceRules) -> Array[String]:
	var lines: Array[String] = []
	if rules == null:
		return lines
	if not rules.tool_categories.is_empty():
		lines.append(_tr("help_tool_categories").format({"categories": tool_categories_text(rules.tool_categories)}))
	if rules.max_uses > 0:
		lines.append(_tr("help_tool_uses").format({"uses": rules.max_uses}))
	if rules.attack_power > 0.0:
		lines.append(_tr("help_tool_attack").format({"value": format_number(rules.attack_power)}))
	if rules.max_range > 0.0:
		lines.append(_tr("help_tool_range").format({"value": format_number(rules.max_range)}))
	if rules.required_ammo_category >= 0:
		var ammo_names: Array[String] = []
		for resource_name in CaloricCalculator.list_secondary_resource_names():
			var ammo_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
			if ammo_rules != null and ammo_rules.tool_categories.has(rules.required_ammo_category):
				ammo_names.append(IconRegistry.get_resource_display_name(resource_name))
		ammo_names.sort()
		var ammo_text := ", ".join(ammo_names) if not ammo_names.is_empty() else tool_categories_text([rules.required_ammo_category])
		lines.append(_tr("help_tool_ammo").format({"ammo": ammo_text}))
	if not is_equal_approx(rules.work_efficiency, 1.0):
		lines.append(_tr("help_tool_efficiency").format({"value": format_number(rules.work_efficiency)}))
	if rules.carry_capacity_bonus > 0.0:
		lines.append(_tr("help_tool_carry_bonus").format({"value": format_number(rules.carry_capacity_bonus)}))
	return lines


# Ricetta: ingredienti, quantità prodotta per ciclo (solo se più di 1), lavoro, combustibile, giorni se avanza da sola,
# attrezzo richiesto. Vuoto se la risorsa non ha ricetta (recipe_workstation_types vuoto) o `rules` è null.
# `name_prefix` (facoltativo, 2026-10-08 — icone dell'Aiuto): Callable(nome risorsa) -> String messa davanti al nome di
# ogni ingrediente (HelpDialog ci mette l'icona); non valido = solo il nome, come prima.
static func build(rules: SecondaryResourceRules, name_prefix: Callable = Callable()) -> Array[String]:
	var lines: Array[String] = []
	if rules == null or rules.recipe_workstation_types.is_empty():
		return lines
	var inputs: Array[String] = []
	for input_name in rules.recipe_inputs.keys():
		var quantity := int(rules.recipe_inputs[input_name])
		if quantity > 0:
			var prefix := String(name_prefix.call(String(input_name))) if name_prefix.is_valid() else ""
			inputs.append("%d %s%s" % [quantity, prefix, IconRegistry.get_resource_display_name(String(input_name))])
	if not inputs.is_empty():
		lines.append(_tr("recipe_tooltip_ingredients").format({"items": ", ".join(inputs)}))
	if rules.recipe_output_quantity > 1:
		lines.append(_tr("help_recipe_output").format({"count": rules.recipe_output_quantity}))
	var labor := int(round(rules.recipe_labor))
	if labor > 0:
		lines.append(_tr("recipe_tooltip_labor").format({"labor": labor}))
	if rules.recipe_fuel_required > 0.0:
		lines.append(_tr("recipe_tooltip_fuel").format({"amount": format_number(rules.recipe_fuel_required)}))
	if rules.recipe_auto_progress_days > 0:
		lines.append(_tr("help_recipe_auto_days").format({"days": rules.recipe_auto_progress_days}))
	if not rules.recipe_required_tool_categories.is_empty():
		lines.append(_tr("recipe_tooltip_tools").format({"tools": tool_categories_text(rules.recipe_required_tool_categories)}))
	return lines


# Nomi del gioco delle categorie d'attrezzo ("taglio, scavo"), dalle chiavi tool_category_<categoria>.
static func tool_categories_text(categories: Array) -> String:
	var names: Array[String] = []
	for category in categories:
		names.append(_tr("tool_category_" + String(TaskTypes.ToolCategory.keys()[int(category)]).to_lower()))
	return ", ".join(names)


# Numero senza decimali inutili ("3", "1.5").
static func format_number(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


# Con il segno ("+5", "−3").
static func format_signed(value: float) -> String:
	return ("+" + format_number(value)) if value > 0.0 else ("−" + format_number(-value))


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
