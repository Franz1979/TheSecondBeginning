class_name HumanFoodPouchService
extends RefCounted

# Contenuto della "saccoccia" del cibo di HumanIndividual (2026-09-19, richiesta utente): tre campi
# sull'individuo — food_space_capacity (spazio massimo, ricalcolato da HumanCarryCapacityIndividual
# Service, MAI persistito), food_space_used (spazio occupato) e food_calories_held (calorie
# contenute), gli ultimi due persistiti. Stateless (RefCounted, static), stesso pattern degli altri
# *IndividualService.
#
# Oggi l'unico cibo che ci entra e' la frutta (STARTING_FOOD_NAME): la saccoccia parte piena di
# unita' INTERE di frutta — quante ne stanno in food_space_capacity secondo space_per_unit della
# risorsa; un'unita' che non ci sta per intero non entra. Nessun consumo in questo passo.

const STARTING_FOOD_NAME: String = "fruit"


# Riempie la saccoccia di frutta: unita' = floor(capacita' / space_per_unit),
# food_space_used = unita' x space_per_unit, food_calories_held = unita' x calories_per_unit.
# Regole della risorsa non risolvibili o space_per_unit <= 0 -> saccoccia vuota (mai una divisione
# per zero).
static func fill_with_fruit(individual: HumanIndividual) -> void:
	individual.food_space_used = 0.0
	individual.food_calories_held = 0.0
	var rules := CaloricCalculator.get_caloric_source_rules(STARTING_FOOD_NAME)
	if rules == null or rules.space_per_unit <= 0.0:
		return
	var units: int = int(floor(individual.food_space_capacity / rules.space_per_unit))
	if units <= 0:
		return
	individual.food_space_used = float(units) * rules.space_per_unit
	individual.food_calories_held = float(units) * rules.calories_per_unit


# Se il contenuto supera la capacita' lo riduce IN PROPORZIONE (le calorie scalano con lo spazio
# occupato: non inventa contenuto, non assume quale cibo ci sia dentro). Solo verso il basso: se la
# capacita' cresce il contenuto non cambia.
static func clamp_to_capacity(individual: HumanIndividual) -> void:
	if individual.food_space_used <= individual.food_space_capacity:
		return
	if individual.food_space_used > 0.0:
		individual.food_calories_held *= individual.food_space_capacity / individual.food_space_used
	individual.food_space_used = individual.food_space_capacity


# Chiamata da HumanCarryCapacityIndividualService dopo aver ricalcolato food_space_capacity.
# `from_rules`: true se la capacita' viene da HumanRules reali, false se dal fallback (catena
# source_group_ref -> folk_ref -> human_rules_ref non risolvibile). La PRIMA volta che la capacita'
# vera e' nota (food_pouch_resolved ancora false: individuo appena creato — l'_init non conosce le
# regole, un neonato riceve il gruppo solo dopo — o caricato senza le chiavi del contenuto) la
# saccoccia viene riempita di nuovo con la capacita' vera, cosi' le unita' intere sono quelle
# giuste; da allora in poi solo clamp.
static func on_capacity_recalculated(individual: HumanIndividual, from_rules: bool) -> void:
	if from_rules and not individual.food_pouch_resolved:
		fill_with_fruit(individual)
		individual.food_pouch_resolved = true
		return
	clamp_to_capacity(individual)
