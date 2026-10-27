class_name DomesticAnimalRules
extends Resource

# Specie domestica (addomesticazione passo 1, 2026-10-26, richiesta utente): descrive la specie, non il singolo
# animale. Un file per specie in gameplay/domestic_animals/data/{species_name}.tres, caricato per nome da
# DomesticAnimalCalculator. Ogni specie domestica deriva da una selvatica (cane ← lupo): i parametri biologici si
# leggeranno dal suo AnimalRules (DomesticAnimalCalculator.get_wild_rules), qui solo quello che è proprio del
# domestico. Campi di vita domestica (cucciolate, cibo, ruoli) arriveranno con i passi che li usano.

# Uguale al nome del file .tres (es. "dog").
@export var species_name: String = ""
# Chiave tr() del nome mostrato (es. "domestic_animal_dog").
@export var display_name: String = ""
# Specie selvatica d'origine: nome di un .tres in simulation/data/animals/ (es. "wolf").
@export var wild_species_name: String = ""

@export_group("Domestication")
# Punti addomesticazione per il primo animale (vedi DomesticationPointsService). Specie diverse accumulano in
# parallelo, ognuna verso la propria soglia.
@export var domestication_points_required: int = 1000
# Idea da conoscere perché i punti si accumulino. Vuoto = sempre (il cane: è proprio addomesticando il lupo che si
# scopre l'idea dell'addomesticazione).
@export var required_idea_id: String = ""
