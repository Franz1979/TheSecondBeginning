class_name ToolInstance
extends RefCounted

# Istanza individuale di un attrezzo USATO (2026-09-26, richiesta utente — attrezzi come istanze,
# step 1: il magazzino). Modello: gli attrezzi NUOVI restano una semplice quantità; solo un pezzo
# parzialmente consumato diventa un'istanza, perché non è più intercambiabile con uno nuovo. Vale
# SOLO per le risorse di categoria SecondaryResourceTypes.Category.TOOL (vedi is_tool_resource).
#
# L'istanza è un Dictionary estensibile, serializzabile in JSON così com'è (stesso principio di
# Building.stored_resources, salvato senza conversioni da GameSaveService): oggi solo
# {"remaining_uses": int}, domani eventuali altri campi per pezzo. Le chiavi vivono SOLO qui — chi
# crea o legge un'istanza passa sempre da queste funzioni, mai dal nome della chiave scritto a mano.
#
# Usata da BuildingStorageService (Building.stored_resources[nome]["used_instances"]), dallo zaino
# (HumanIndividual.carried_resources, stessa forma di voce) e dalla cintura (HumanIndividual.
# equipped_tool_uses, dove l'istanza si riduce ai soli usi residui dello slot). Stateless, funzioni statiche.

const KEY_REMAINING_USES := "remaining_uses"


static func create(remaining_uses: int) -> Dictionary:
	return {KEY_REMAINING_USES: remaining_uses}


static func get_remaining_uses(instance: Dictionary) -> int:
	return int(instance.get(KEY_REMAINING_USES, 0))


# Utilizzabile = almeno un uso residuo. Un attrezzo a 0 usi è rotto: sparisce, non si stocca.
static func is_usable(instance: Dictionary) -> bool:
	return get_remaining_uses(instance) > 0


# Usi pieni = indistinguibile da un pezzo nuovo (rientra nella quantità dei nuovi). max_uses <= 0
# (attrezzo che non si usura, vedi SecondaryResourceRules.max_uses) = sempre "pieno".
static func is_full(instance: Dictionary, max_uses: int) -> bool:
	return max_uses <= 0 or get_remaining_uses(instance) >= max_uses


# Copia indipendente dell'istanza, con i soli campi noti normalizzati al tipo atteso (i campi futuri
# eventualmente presenti vengono conservati). Usata al caricamento e quando un'istanza entra in un
# contenitore, così nessuno condivide lo stesso Dictionary.
static func normalized(instance: Dictionary) -> Dictionary:
	var copy: Dictionary = instance.duplicate(true)
	copy[KEY_REMAINING_USES] = get_remaining_uses(instance)
	return copy


# --- Voci a istanze (2026-09-26, step 2: cintura e zaino) ---
#
# Stessa forma di voce per magazzino (Building.stored_resources) e zaino (HumanIndividual.
# carried_resources): {"quantity": totale pezzi, "decay_fraction": float, "used_instances": [istanze]}
# — nuovi = quantity - used_instances.size(), chiave "used_instances" presente solo se non vuota.
# Le funzioni sotto lavorano sulla sola voce; scrivere/rimuovere la voce nel contenitore resta al
# chiamante (BuildingStorageService._write_entry, HumanIndividual._write_carried_entry).

const KEY_USED_INSTANCES := "used_instances"


# Istanze usate della voce (Array vuoto se la chiave manca). Da non modificare in place.
static func get_used_instances(entry: Dictionary) -> Array:
	var used_instances = entry.get(KEY_USED_INSTANCES, [])
	return used_instances if used_instances is Array else []


# Scrive la lista di istanze nella voce, togliendo la chiave se la lista è vuota.
static func set_used_instances(entry: Dictionary, used_instances: Array) -> void:
	if used_instances.is_empty():
		entry.erase(KEY_USED_INSTANCES)
	else:
		entry[KEY_USED_INSTANCES] = used_instances


# Toglie dalla voce fino a `quantity_requested` unità e le restituisce come istanze: prima le istanze
# utilizzabili in ordine di usi residui CRESCENTI (la più consumata esce per prima), poi i pezzi nuovi
# (usciti come istanze a `max_uses`). MUTA `entry` (quantity e used_instances); decay_fraction invariata.
# Un'istanza non utilizzabile non dovrebbe mai esistere (rifiutata in ingresso, scartata al caricamento):
# se capitasse resta nella voce, mai consegnata né scambiata per un pezzo nuovo.
static func take_units_from_entry(entry: Dictionary, quantity_requested: int, max_uses: int) -> Array:
	var units: Array = []
	var current_quantity: int = int(entry.get("quantity", 0))
	if current_quantity <= 0 or quantity_requested <= 0:
		return units

	var used_instances: Array = get_used_instances(entry).duplicate()
	var new_available: int = maxi(current_quantity - used_instances.size(), 0)
	var usable_indices: Array[int] = []
	for i in range(used_instances.size()):
		if is_usable(used_instances[i]):
			usable_indices.append(i)
	usable_indices.sort_custom(func(a: int, b: int) -> bool:
		return get_remaining_uses(used_instances[a]) < get_remaining_uses(used_instances[b])
	)
	var taken_indices: Array[int] = []
	for index in usable_indices:
		if units.size() >= quantity_requested:
			break
		units.append(used_instances[index])
		taken_indices.append(index)
	# Rimozione dall'indice più alto, così gli indici ancora da togliere restano validi.
	taken_indices.sort()
	taken_indices.reverse()
	for index in taken_indices:
		used_instances.remove_at(index)

	var new_taken: int = mini(quantity_requested - units.size(), new_available)
	for i in range(new_taken):
		units.append(create(max_uses))

	entry["quantity"] = current_quantity - units.size()
	set_used_instances(entry, used_instances)
	return units


# Aggiunge UN pezzo usato alla voce: quantity + 1 e copia dell'istanza in used_instances. Nessun
# controllo qui (pieno/rotto/spazio): li fa il chiamante prima (store_tool_instance/add_carried_tool_instance).
static func add_instance_to_entry(entry: Dictionary, instance: Dictionary) -> void:
	entry["quantity"] = int(entry.get("quantity", 0)) + 1
	var used_instances: Array = get_used_instances(entry).duplicate()
	used_instances.append(normalized(instance))
	set_used_instances(entry, used_instances)


# Unico criterio "questa risorsa segue il modello a istanze": categoria TOOL. Ogni altra risorsa
# resta quantità + decay_fraction media per lotto, invariata.
static func is_tool_resource(resource_name: String) -> bool:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules != null and resource_rules.category == SecondaryResourceTypes.Category.TOOL


# SecondaryResourceRules.max_uses della risorsa, 0 se non risolvibile.
static func get_max_uses(resource_name: String) -> int:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules.max_uses if resource_rules != null else 0
