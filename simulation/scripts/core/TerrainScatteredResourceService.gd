class_name TerrainScatteredResourceService
extends RefCounted

# Interfaccia uniforme per i pool di risorse GenerationSource.TERRAIN_SCATTERED (vedi
# SecondaryResourceTypes — sparse sul terreno stesso, non derivate da una risorsa primaria via
# CaloricCalculator.SECONDARY_SOURCES) — 2026-09-09, richiesta utente. Nata per togliere a
# PickUpAction l'accesso diretto a MacroCellState.pebble_quantities/stick_quantities: il chiamante
# passa solo resource_name, questo service smista internamente sul Dictionary/formato giusto.
# Aggiungere una terza risorsa scattered (es. un futuro "clay") richiede solo un nuovo case in
# get_available/consume qui, nessuna modifica a PickUpAction.
#
# game_data per il confronto di freschezza lotto stick (sotto) è risolto da GameSettings.
# active_game_data — non un parametro esplicito, per lasciare invariata la firma richiesta
# (get_available/consume prendono solo macro_state/resource_name/position, stessa firma con cui
# PickUpAction già li chiama oggi) e per non allungare la catena di parametri di PickUpAction
# (che oggi non riceve/non tiene game_data — vedi PickUpAction._init) solo per questo. Stessa
# fonte già letta da WorldScene/GameScene/MacroCellScene per lo stato "attivo" di sessione — qui è
# il solo consumatore che la legge da dentro un service invece che da uno script di scena.


static func get_available(macro_state: MacroCellState, resource_name: String, position: Vector2i) -> int:
	match resource_name:
		"pebble":
			return int(macro_state.pebble_quantities.get(position, 0))
		"stick":
			return _get_available_stick(macro_state, position)
		_:
			return 0


static func consume(macro_state: MacroCellState, resource_name: String, position: Vector2i, quantity: int) -> void:
	if quantity <= 0:
		return
	match resource_name:
		"pebble":
			_consume_pebble(macro_state, position, quantity)
		"stick":
			_consume_stick(macro_state, position, quantity)


# Lookup diretto, clamp a 0 — entry lasciata a 0 senza rimuoverla (stesso comportamento già in uso
# in PickUpAction.on_complete prima di questo refactor).
static func _consume_pebble(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var remaining: int = int(macro_state.pebble_quantities.get(position, 0)) - quantity
	macro_state.pebble_quantities[position] = max(remaining, 0)


# Lotto stale (mai ridisegnato dall'ultimo checkpoint growth passato — vedi
# StickPoolService.most_recent_growth_checkpoint_absolute_day) → 0: senza un refresh recente la
# capacità persistita non è affidabile, stesso confronto già usato da
# StickPoolService.refresh_macrocell per decidere se un lotto va rigenerato.
static func _get_available_stick(macro_state: MacroCellState, position: Vector2i) -> int:
	var entry: Dictionary = macro_state.stick_quantities.get(position, {})
	if entry.is_empty():
		return 0
	if GameSettings.active_game_data == null:
		return 0 # GameScene può girare con un game_data locale di riserva senza mai valorizzare
		# GameSettings.active_game_data (vedi GameScene._ready) — fail-closed invece di un crash null.
	var checkpoint_absolute_day := StickPoolService.most_recent_growth_checkpoint_absolute_day(GameSettings.active_game_data)
	if int(entry.get("checkpoint_day", -1)) != checkpoint_absolute_day:
		return 0
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	return max(capacity - harvested, 0)


# Incrementa harvested, clampato a non superare capacity — nessun controllo di freschezza qui
# (a differenza di get_available sopra): se il lotto è nel frattempo diventato stale, capacity/
# harvested persistiti sono comunque quelli dell'ultima generazione nota, e limitare consume a
# quell'ultima capacity nota resta corretto (mai un harvested > capacity, qualunque sia l'epoch).
static func _consume_stick(macro_state: MacroCellState, position: Vector2i, quantity: int) -> void:
	var entry: Dictionary = macro_state.stick_quantities.get(position, {})
	if entry.is_empty():
		return
	var capacity := int(entry.get("capacity", 0))
	var harvested := int(entry.get("harvested", 0))
	entry["harvested"] = min(harvested + quantity, capacity)
	macro_state.stick_quantities[position] = entry
