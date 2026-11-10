class_name PlacedTrap
extends RefCounted

# Trappola montata sulla mappa (2026-11-07, capanna del trappoliere — rete per uccelli, passo del piazzamento). Generica per
# ogni trappola (SecondaryResourceRules gruppo Trap): tipo, posto, il pezzo con i suoi usi rimasti (ToolInstance), giorno
# del montaggio e indice del posto calcolato una volta al montaggio (TrapService.site_index, senza stagione). Creata da
# SetTrapAction, salvata in GameData.placed_traps (GameSaveService "placed_traps").

var id: int = 0
var trap_name: String = ""
var macro_coords: Vector2i = Vector2i.ZERO
var lot: Vector2i = Vector2i.ZERO
# Pezzo montato (ToolInstance: usi rimasti), JSON-nativo.
var instance: Dictionary = {}
var placed_day: int = 0
var site_index: float = 0.0
# Zona di lavoro per cui è stata montata (0 = nessuna).
var work_area_id: int = 0
# Prede prese e ancora nella trappola, in attesa dello svuotamento: il giorno assoluto della cattura di ognuna (al
# massimo SecondaryResourceRules.trap_capacity; dopo trap_catch_spoil_days marciscono, TrapService.advance_daily).
var catch_days: Array[int] = []
# Lacci (2026-11-09): specie di ogni preda, stesso ordine di catch_days (vuoto per le trappole che non la segnano).
var catch_species: Array[String] = []
# Fascia d'età di ogni preda (GameTypes.AgeBand), stesso ordine: la resa della macellazione la segue come nella caccia.
var catch_ages: Array[int] = []
# Giorno assoluto dell'ultimo uso consumato (montaggio, svuotamento o usura a riposo): da qui contano i
# trap_idle_wear_days dell'usura a riposo (TrapService.advance_daily), 2026-11-07.
var last_wear_day: int = 0


func get_caught() -> int:
	return catch_days.size()


func get_remaining_uses() -> int:
	return ToolInstance.get_remaining_uses(instance)


func to_save_data() -> Dictionary:
	return {
		"id": id,
		"trap_name": trap_name,
		"macro_x": macro_coords.x,
		"macro_y": macro_coords.y,
		"lot_x": lot.x,
		"lot_y": lot.y,
		"instance": instance,
		"placed_day": placed_day,
		"site_index": site_index,
		"work_area_id": work_area_id,
		"catch_days": Array(catch_days),
		"catch_species": Array(catch_species),
		"catch_ages": Array(catch_ages),
		"last_wear_day": last_wear_day,
	}


static func from_save_data(data: Dictionary) -> PlacedTrap:
	var trap := PlacedTrap.new()
	trap.id = int(data.get("id", 0))
	trap.trap_name = String(data.get("trap_name", ""))
	trap.macro_coords = Vector2i(int(data.get("macro_x", 0)), int(data.get("macro_y", 0)))
	trap.lot = Vector2i(int(data.get("lot_x", 0)), int(data.get("lot_y", 0)))
	var raw_instance = data.get("instance", {})
	trap.instance = ToolInstance.normalized(raw_instance) if raw_instance is Dictionary else {}
	trap.placed_day = int(data.get("placed_day", 0))
	trap.site_index = float(data.get("site_index", 0.0))
	trap.work_area_id = int(data.get("work_area_id", 0))
	trap.last_wear_day = int(data.get("last_wear_day", trap.placed_day))
	for day in data.get("catch_days", []):
		trap.catch_days.append(int(day))
	for species in data.get("catch_species", []):
		trap.catch_species.append(String(species))
	for age_band in data.get("catch_ages", []):
		trap.catch_ages.append(int(age_band))
	return trap
