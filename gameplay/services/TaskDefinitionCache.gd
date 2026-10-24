class_name TaskDefinitionCache
extends RefCounted

# Definizioni delle task tenute in memoria (2026-10-24, richiesta utente — scatti dello svago e della lista attrezzi della
# caccia): Godot tiene una .tres caricata solo finché qualcuno la usa, quindi un load() di una definizione che nessuna task
# in corso tiene la rilegge dal disco (~1 ms l'una: 10 definizioni dello svago per ogni pipottino libero, ~60 ms a fine
# rito). Qui restano caricate per tutta la sessione; le definizioni non si modificano dopo il caricamento, quindi una copia
# condivisa vale come prima.

static var _definitions: Dictionary = {}  # path -> TaskDefinition


static func get_definition(path: String) -> TaskDefinition:
	var definition: TaskDefinition = _definitions.get(path)
	if definition == null:
		definition = load(path) as TaskDefinition
		_definitions[path] = definition
	return definition
