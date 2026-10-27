class_name DomesticationEncounterService
extends RefCounted

# Specie selvatiche incontrate (addomesticazione passo 3a, 2026-10-26, richiesta utente): un'addomesticazione può
# iniziare solo per una specie che il villaggio ha già visto nel mondo. Unico punto che scrive
# GameData.encountered_wild_species; chi decide "vista" è GameScene (_check_encountered_wild_species, giornaliero:
# un animale della specie visibile, fuori dalla nebbia, in una cella viva).


static func mark_encountered(game_data: GameData, wild_species: String) -> bool:
	if game_data == null or game_data.encountered_wild_species.has(wild_species):
		return false
	game_data.encountered_wild_species.append(wild_species)
	print("[DOMESTICATION] incontrata: %s" % wild_species)
	return true


static func is_encountered(game_data: GameData, wild_species: String) -> bool:
	return game_data != null and game_data.encountered_wild_species.has(wild_species)
