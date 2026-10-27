class_name AnimalVisitorGroup
extends RefCounted

# Gruppo di animali che frequenta il villaggio (2026-10-26, richiesta utente): un'istanza simulata, sempre la stessa,
# indipendente dalla fauna selvatica della mappa — un elemento di gioco garantito, non realismo. Primo uso: il branco
# di lupi (species "wolf", regole in gameplay/visitors/animals/data/wolf.tres). Per ora solo dati: il comportamento
# (visite, punti, attacchi) arriverà nei passi successivi, in servizi propri per specie.

var id: int = 0
# Nome del file di AnimalVisitorRules (es. "wolf").
var species: String = ""
var animals: Array[AnimalVisitor] = []
var next_animal_id: int = 1


func to_save_data() -> Dictionary:
	var saved_animals: Array = []
	for animal in animals:
		saved_animals.append(animal.to_save_data())
	return {"id": id, "species": species, "animals": saved_animals, "next_animal_id": next_animal_id}


static func from_save_data(data: Dictionary) -> AnimalVisitorGroup:
	var group := AnimalVisitorGroup.new()
	group.id = int(data.get("id", 0))
	group.species = String(data.get("species", ""))
	group.next_animal_id = int(data.get("next_animal_id", 1))
	for saved_animal in data.get("animals", []):
		group.animals.append(AnimalVisitor.from_save_data(saved_animal))
	return group
