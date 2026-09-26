class_name CombatTarget
extends RefCounted

# Bersaglio di un attacco (2026-09-26, richiesta utente — caccia: mira e tiro separati). AimAction e
# ThrowAction lavorano su un CombatTarget, non su una "preda": serviranno anche per il combattimento
# contro bersagli umani. Oggi l'unico tipo possibile è un animale (Kind.ANIMAL, individuo di
# AnimalGroupRenderer ritrovato per id nel registro dei vivi). Un tipo nuovo aggiunge un valore a Kind e
# un ramo in ciascuna funzione sotto; le azioni restano invariate.
#
# Contiene solo l'identità del bersaglio (tipo, id, etichetta, macrocella), mai un riferimento vivo:
# sopravvive al salvataggio (to_save_data/from_save_data) e si risolve a ogni uso.

enum Kind { ANIMAL }
# Stato del bersaglio: attaccabile solo se esiste ED è in vista (stesso test del disegno). Quando smette
# di esserlo, l'attacco (e la caccia) si chiude con il motivo nel log.
enum Status { OK, GONE, OUT_OF_SIGHT }

var kind: int = Kind.ANIMAL
var target_id: int = 0
# Etichetta leggibile per i log e i pannelli: per un animale la specie ("rabbit").
var label: String = ""
# Macrocella del bersaglio all'ultima risoluzione (aggiornata da get_status): serve a riattivarne la
# cella dopo un caricamento (GameScene._collect_hunt_prey_cells).
var macro_coords: Vector2i = Vector2i.ZERO


static func for_animal(animal_id: int, species: String, animal_macro_coords: Vector2i) -> CombatTarget:
	var combat_target := CombatTarget.new()
	combat_target.kind = Kind.ANIMAL
	combat_target.target_id = animal_id
	combat_target.label = species
	combat_target.macro_coords = animal_macro_coords
	return combat_target


# Individuo animale vivo del bersaglio, null se non esiste più o se il bersaglio non è un animale.
func get_animal() -> AnimalVisualGroup:
	if kind != Kind.ANIMAL:
		return null
	return AnimalGroupRenderer.find_live_individual(target_id)


func get_status() -> int:
	match kind:
		Kind.ANIMAL:
			var animal := get_animal()
			if animal == null:
				return Status.GONE
			macro_coords = animal.macro_coords
			if not AnimalGroupRenderer.is_live_individual_in_sight(target_id):
				return Status.OUT_OF_SIGHT
			return Status.OK
	return Status.GONE


func is_valid() -> bool:
	return get_status() == Status.OK


# Posizione del bersaglio nel sistema di coordinate dell'individuo `attacker` (stesso scarto di macrocella
# usato per gli edifici). Vector2.INF se il bersaglio non esiste.
func get_position_for(attacker: Variant) -> Vector2:
	var animal := get_animal()
	if animal == null:
		return Vector2.INF
	return animal.position + Vector2(animal.macro_coords - attacker.home_macro_coords) * World.WIDTH


# Distanza tra l'attaccante e il bersaglio (INF se il bersaglio non esiste).
func distance_from(attacker: Variant) -> float:
	var target_position := get_position_for(attacker)
	if target_position == Vector2.INF:
		return INF
	return attacker.position.distance_to(target_position)


func describe() -> String:
	return "%s #%d" % [label, target_id]


static func describe_status(status: int) -> String:
	match status:
		Status.OUT_OF_SIGHT:
			return "bersaglio perso di vista (fuori dalla zona visibile)"
		Status.GONE:
			return "bersaglio sparito (morto, rimosso dalla popolazione o cella disattivata)"
	return "bersaglio ancora valido"


# Persistenza: solo identità, stessa forma per ogni tipo.
func to_save_data() -> Dictionary:
	return {
		"target_kind": kind,
		"target_id": target_id,
		"target_label": label,
		"target_macro_x": macro_coords.x,
		"target_macro_y": macro_coords.y,
	}


# Legge i dati salvati; accetta anche le chiavi dei salvataggi precedenti (prey_id/prey_species/
# prey_macro_x/y della vecchia HuntAction), che erano sempre bersagli animali.
static func from_save_data(data: Dictionary) -> CombatTarget:
	var combat_target := CombatTarget.new()
	combat_target.kind = int(data.get("target_kind", Kind.ANIMAL))
	combat_target.target_id = int(data.get("target_id", data.get("prey_id", 0)))
	combat_target.label = String(data.get("target_label", data.get("prey_species", "")))
	combat_target.macro_coords = Vector2i(
		int(data.get("target_macro_x", data.get("prey_macro_x", 0))),
		int(data.get("target_macro_y", data.get("prey_macro_y", 0)))
	)
	return combat_target
