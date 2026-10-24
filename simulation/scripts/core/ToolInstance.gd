class_name ToolInstance
extends RefCounted

# Istanza individuale di un attrezzo USATO (2026-09-26, richiesta utente — attrezzi come istanze,
# step 1: il magazzino). Dal 2026-10-11 anche di un capo di vestiario (uses_instances), i cui "usi" sono giorni
# indossato. Modello: gli attrezzi NUOVI restano una semplice quantità; solo un pezzo
# parzialmente consumato diventa un'istanza, perché non è più intercambiabile con uno nuovo. Vale
# SOLO per le risorse di categoria TOOL o APPAREL (vedi uses_instances).
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
# Deperimento da stock DEL SINGOLO PEZZO (2026-10-11, richiesta utente — vestiario): un capo ha due stati
# indipendenti, il consumo (remaining_uses, giorni indossato) e il deperimento da riposto (questa frazione 0..1).
# Il deperimento avanza solo mentre il pezzo è riposto (advance_entry_decay) e resta congelato mentre è indossato:
# tolto di dosso riparte dal valore che aveva. Chiave scritta solo se > 0, quindi gli attrezzi (che non deperiscono)
# restano nel formato di sempre.
const KEY_DECAY_FRACTION := "decay_fraction"


static func create(remaining_uses: int, decay_fraction: float = 0.0) -> Dictionary:
	var instance := {KEY_REMAINING_USES: remaining_uses}
	if decay_fraction > 0.0:
		instance[KEY_DECAY_FRACTION] = decay_fraction
	return instance


static func get_remaining_uses(instance: Dictionary) -> int:
	return int(instance.get(KEY_REMAINING_USES, 0))


static func get_decay_fraction(instance: Dictionary) -> float:
	return float(instance.get(KEY_DECAY_FRACTION, 0.0))


static func set_decay_fraction(instance: Dictionary, decay_fraction: float) -> void:
	if decay_fraction > 0.0:
		instance[KEY_DECAY_FRACTION] = decay_fraction
	else:
		instance.erase(KEY_DECAY_FRACTION)


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
	set_decay_fraction(copy, clampf(get_decay_fraction(instance), 0.0, 1.0))
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
# `fullest_first` (2026-10-24, munizioni per la caccia — il mazzo con più colpi): ordine opposto, prima i pezzi nuovi,
# poi le istanze in ordine di usi residui DECRESCENTI.
static func take_units_from_entry(entry: Dictionary, quantity_requested: int, max_uses: int, fullest_first: bool = false) -> Array:
	var units: Array = []
	var current_quantity: int = int(entry.get("quantity", 0))
	if current_quantity <= 0 or quantity_requested <= 0:
		return units

	var used_instances: Array = get_used_instances(entry).duplicate()
	var new_available: int = maxi(current_quantity - used_instances.size(), 0)
	# I pezzi nuovi escono con il deperimento del loro lotto (la decay_fraction della voce), che da qui in poi
	# viaggia con il pezzo (vestiario, 2026-10-11).
	var lot_decay: float = float(entry.get("decay_fraction", 0.0))
	if fullest_first:
		for i in range(mini(quantity_requested, new_available)):
			units.append(create(max_uses, lot_decay))
		new_available -= units.size()
	var usable_indices: Array[int] = []
	for i in range(used_instances.size()):
		if is_usable(used_instances[i]):
			usable_indices.append(i)
	usable_indices.sort_custom(func(a: int, b: int) -> bool:
		if fullest_first:
			return get_remaining_uses(used_instances[a]) > get_remaining_uses(used_instances[b])
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
		units.append(create(max_uses, lot_decay))

	entry["quantity"] = current_quantity - units.size()
	set_used_instances(entry, used_instances)
	return units


# Aggiunge UN pezzo usato alla voce: quantity + 1 e copia dell'istanza in used_instances (con il suo
# deperimento: non entra nella media del lotto). Nessun controllo qui (pieno/rotto/spazio): li fa il
# chiamante prima (store_tool_instance/add_carried_tool_instance).
static func add_instance_to_entry(entry: Dictionary, instance: Dictionary) -> void:
	entry["quantity"] = int(entry.get("quantity", 0)) + 1
	var used_instances: Array = get_used_instances(entry).duplicate()
	used_instances.append(normalized(instance))
	set_used_instances(entry, used_instances)


# Pezzi NUOVI della voce (quantity - istanze usate): sono loro, e solo loro, ad avere la decay_fraction della voce.
static func get_new_quantity(entry: Dictionary) -> int:
	return maxi(int(entry.get("quantity", 0)) - get_used_instances(entry).size(), 0)


# decay_fraction della voce dopo l'arrivo di `incoming_quantity` pezzi nuovi a `incoming_decay`: media pesata sui
# soli pezzi NUOVI già presenti (2026-10-11 — le istanze usate hanno ciascuna il proprio deperimento). Per una voce
# senza istanze coincide con la media sulla quantità di sempre.
static func merged_lot_decay(entry: Dictionary, incoming_quantity: int, incoming_decay: float) -> float:
	var current_new: int = get_new_quantity(entry)
	var total: int = current_new + incoming_quantity
	if total <= 0:
		return 0.0
	return (float(current_new) * float(entry.get("decay_fraction", 0.0)) + float(incoming_quantity) * incoming_decay) / float(total)


# Deperimento giornaliero di una voce (2026-10-11, unico punto per zaino, magazzini e mucchi): il lotto dei pezzi
# nuovi avanza di `daily_step` sulla decay_fraction della voce, ogni istanza usata sulla propria. A 1.0 il lotto dei
# nuovi sparisce per intero, un'istanza sparisce da sola. MUTA `entry` (quantity, decay_fraction, used_instances);
# ritorna quanti pezzi sono andati persi. La voce a quantità 0 va rimossa dal chiamante.
static func advance_entry_decay(entry: Dictionary, daily_step: float) -> int:
	var lost: int = 0
	var new_quantity: int = get_new_quantity(entry)
	if new_quantity > 0:
		var lot_decay: float = float(entry.get("decay_fraction", 0.0)) + daily_step
		if lot_decay >= 1.0:
			lost += new_quantity
			new_quantity = 0
			entry["decay_fraction"] = 0.0
		else:
			entry["decay_fraction"] = lot_decay
	var kept: Array = []
	for instance in get_used_instances(entry):
		var instance_decay: float = get_decay_fraction(instance) + daily_step
		if instance_decay >= 1.0:
			lost += 1
			continue
		var updated: Dictionary = (instance as Dictionary).duplicate(true)
		set_decay_fraction(updated, instance_decay)
		kept.append(updated)
	entry["quantity"] = new_quantity + kept.size()
	set_used_instances(entry, kept)
	return lost


# Categoria TOOL: un attrezzo vero (oggi lo chiede solo l'Attrezzeria, BuildingToolkitService). Per decidere se una
# risorsa segue il modello a istanze usare uses_instances, che copre anche il vestiario.
static func is_tool_resource(resource_name: String) -> bool:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules != null and resource_rules.category == SecondaryResourceTypes.Category.TOOL


# Unico criterio "questa risorsa segue il modello a istanze" (magazzino, zaino, mucchi a terra, salvataggi): categoria
# TOOL o APPAREL (2026-10-11, vestiario — un capo indossato si consuma come un attrezzo, vedi SecondaryResourceRules.
# apparel_kind). Ogni altra risorsa resta quantità + decay_fraction media per lotto, invariata.
static func uses_instances(resource_name: String) -> bool:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules != null and (
		resource_rules.category == SecondaryResourceTypes.Category.TOOL
		or resource_rules.category == SecondaryResourceTypes.Category.APPAREL
	)


# SecondaryResourceRules.max_uses della risorsa, 0 se non risolvibile.
static func get_max_uses(resource_name: String) -> int:
	var resource_rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	return resource_rules.max_uses if resource_rules != null else 0
