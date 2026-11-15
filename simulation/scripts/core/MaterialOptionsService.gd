class_name MaterialOptionsService
extends RefCounted

# Materiali con opzioni (2026-11-15, richiesta utente — passo 1: i cantieri). Ogni materiale chiesto (un "posto", es.
# required_materials["fiber_rope"] = 10) si può riempire con lui stesso o con i suoi sostituti, anche mescolati, scegliendo
# sempre la sorgente più vicina (nessuna priorità tra le opzioni). Il posto è pieno quando la somma delle parti consegnate,
# ognuna pesata col suo valore, arriva alla quantità chiesta: i rapporti diversi da 1 a 1 sono già previsti.
# I sostituti li dichiara il materiale nuovo, non quello chiesto: SecondaryResourceRules.substitutes = {"fiber_rope": 1.0}
# sulla corda di lino = "una corda di lino vale 1,0 corde di fibre", in un senso solo. Da quelle dichiarazioni si costruisce
# UNA volta (alla prima domanda) l'indice al contrario chiesto -> {sostituto: valore}; dopo ogni domanda è una lettura.
# Gli alternativi propri di un edificio o di una ricetta (es. tetto di paglia o di frasche) arriveranno con lo stesso
# modello, dichiarati sull'edificio/ricetta.

static var _index_ready := false
# Materiale chiesto -> {sostituto: valore (unità del chiesto per unità del sostituto)}.
static var _substitutes_by_required: Dictionary = {}


static func _prepare_index() -> void:
	if _index_ready:
		return
	_index_ready = true
	for resource_name in CaloricCalculator.list_secondary_resource_names():
		var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
		if rules == null or rules.substitutes.is_empty():
			continue
		for required_name in rules.substitutes.keys():
			var value := float(rules.substitutes[required_name])
			if value <= 0.0 or String(required_name) == resource_name:
				continue
			if not _substitutes_by_required.has(String(required_name)):
				_substitutes_by_required[String(required_name)] = {}
			(_substitutes_by_required[String(required_name)] as Dictionary)[resource_name] = value


# {materiale: valore} che riempiono il posto `required_name`: lui stesso (1,0) e i suoi sostituti.
static func options_for(required_name: String) -> Dictionary:
	_prepare_index()
	var result: Dictionary = {required_name: 1.0}
	var substitutes: Dictionary = _substitutes_by_required.get(required_name, {})
	for substitute_name in substitutes.keys():
		result[substitute_name] = substitutes[substitute_name]
	return result


static func option_names(required_name: String) -> Array[String]:
	var names: Array[String] = []
	for option_name in options_for(required_name).keys():
		names.append(String(option_name))
	return names


static func has_substitutes(required_name: String) -> bool:
	_prepare_index()
	return _substitutes_by_required.has(required_name)


# Quanto del posto `required_name` coprono le scorte `stored`: stored_resources ({nome: {"quantity"}}) oppure un elenco
# semplice {nome: quantità}. In unità del materiale chiesto.
static func covered(stored: Dictionary, required_name: String) -> float:
	var total := 0.0
	var options := options_for(required_name)
	for option_name in options.keys():
		var entry: Variant = stored.get(option_name, 0)
		var quantity: float = float((entry as Dictionary).get("quantity", 0)) if entry is Dictionary else float(entry)
		total += quantity * float(options[option_name])
	return total


# Quanto manca al posto `required_name` di `required_quantity`, in unità del materiale chiesto (per eccesso).
static func missing(stored: Dictionary, required_name: String, required_quantity: int) -> int:
	return maxi(ceili(float(required_quantity) - covered(stored, required_name) - 0.0001), 0)


# Il posto di `requirements` ({chiesto: quantità}) che `resource_name` riempie: lui stesso se è chiesto, altrimenti il primo
# chiesto di cui è sostituto; "" se nessuno.
static func slot_for(requirements: Dictionary, resource_name: String) -> String:
	if requirements.has(resource_name):
		return resource_name
	_prepare_index()
	for required_name in requirements.keys():
		if (_substitutes_by_required.get(String(required_name), {}) as Dictionary).has(resource_name):
			return String(required_name)
	return ""


# Sostituti di `required_name` già disponibili al popolo (2026-11-15, passo 3 — richiesta utente: l'alternativa si
# mostra solo una volta disponibile): idea della risorsa completata e, se è una ricetta, conosciuta
# (ProductionService.is_recipe_known). In ordine di nome. Serve solo ai testi: il rifornimento usa tutte le opzioni.
static func known_substitute_names(required_name: String) -> Array[String]:
	var names: Array[String] = []
	_prepare_index()
	var substitutes: Dictionary = _substitutes_by_required.get(required_name, {})
	if substitutes.is_empty():
		return names
	var folk: Folk = GameSettings.active_human_folk
	for substitute_name in substitutes.keys():
		var rules := CaloricCalculator.get_caloric_source_rules(String(substitute_name))
		if rules == null:
			continue
		if rules.required_idea_id != "" and (folk == null or not folk.completed_ideas.has(rules.required_idea_id)):
			continue
		if not ProductionService.is_recipe_known(String(substitute_name), folk):
			continue
		names.append(String(substitute_name))
	names.sort()
	return names


# Nome da mostrare per il posto `required_name`: "Corda di fibre", oppure "Corda di fibre / Corda di lino" quando un
# sostituto è già disponibile (known_substitute_names).
static func display_name(required_name: String) -> String:
	var parts: Array[String] = [IconRegistry.get_resource_display_name(required_name)]
	for substitute_name in known_substitute_names(required_name):
		parts.append(IconRegistry.get_resource_display_name(substitute_name))
	return " / ".join(parts)


# Unità di `resource_name` che coprono `missing_required` unità del posto `required_name` (per eccesso); 0 se non vale lì.
static func units_needed(required_name: String, resource_name: String, missing_required: float) -> int:
	var value := float(options_for(required_name).get(resource_name, 0.0))
	if value <= 0.0 or missing_required <= 0.0:
		return 0
	return maxi(ceili(missing_required / value - 0.0001), 0)
