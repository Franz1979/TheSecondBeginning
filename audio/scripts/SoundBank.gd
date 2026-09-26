class_name SoundBank
extends Resource

# Banco sonoro (2026-09-26, richiesta utente): l'elenco dei SoundDef di una categoria (audio/banks/
# sfx_<categoria>.tres, generato da audio/scripts/tools/BuildSoundBanks.gd). AudioManager carica tutti i
# banchi all'avvio e li fonde in un unico indice id -> SoundDef.

@export var defs: Array[SoundDef] = []

# Indice id -> SoundDef, costruito in cache al primo accesso (get_def/get_index). Non salvato.
var _index: Dictionary = {}
var _index_built: bool = false


# Il SoundDef con questo id, null se il banco non lo contiene.
func get_def(sound_id: StringName) -> SoundDef:
	return get_index().get(sound_id, null)


# Indice id -> SoundDef del banco. Voci senza id o con id già visto vengono segnalate con push_error e
# scartate (vale la prima).
func get_index() -> Dictionary:
	if _index_built:
		return _index
	_index.clear()
	for def in defs:
		if def == null:
			continue
		if def.id == &"":
			push_error("SoundBank %s: una voce non ha id — ignorata." % resource_path)
			continue
		if _index.has(def.id):
			push_error("SoundBank %s: id duplicato '%s' — vale la prima voce, le altre sono ignorate." % [resource_path, def.id])
			continue
		_index[def.id] = def
	_index_built = true
	return _index


# Da chiamare dopo aver modificato `defs` da codice (BuildSoundBanks), così il prossimo accesso ricostruisce l'indice.
func invalidate_index() -> void:
	_index_built = false
	_index.clear()
