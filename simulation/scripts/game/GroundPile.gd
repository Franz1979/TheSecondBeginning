class_name GroundPile
extends RefCounted

# Mucchio di risorse a terra (2026-09-26, richiesta utente — ground drop). Un contenitore in un punto del
# mondo, non legato a un edificio: oggi ci finisce il carico scartato da un individuo (HumanIndividual.
# discard_carried_resource/_entry), domani la carcassa di un animale ucciso e la carne che non entra nello
# zaino. Stato puro: la logica vive in GroundPileService, il disegno in GroundPileView (GameScene).
#
# Un solo mucchio per microcella (macro_coords + microcell): scarti successivi nello stesso punto si sommano,
# nessun limite di capacità. `resources` ha lo STESSO formato di Building.stored_resources e di
# HumanIndividual.carried_resources — resource_name -> {"quantity": int, "decay_fraction": float,
# "used_instances": [istanze ToolInstance] (solo attrezzi usati, chiave assente se vuota)} — così istanze
# degli attrezzi e medie di deperimento passano da un contenitore all'altro senza conversioni.
#
# Vive in GameData.ground_piles, salvato da GameSaveService/GameLoadService. Scadenza come gli oggetti
# scaduti: ExpiredObjectCalculator.is_expired su get_expiry_record(), con le regole di
# ExpiredObjectTypes.ExpiredObjectType.GROUND_PILE (ground_pile_rules.tres).

var id: int = 0
var macro_coords: Vector2i = Vector2i.ZERO
# Microcella del mucchio, locale alla sua macrocella (0..World.WIDTH-1).
var microcell: Vector2i = Vector2i.ZERO
var resources: Dictionary = {}
# Carcasse (2026-09-26, richiesta utente — carcassa a terra): contenuto SPECIALE del mucchio, non una risorsa.
# Una voce per animale ucciso: {"id": int, "species": String, "age_band": int (GameTypes.AgeBand), "killed_year": int,
# "killed_day": int}. `id` (2026-09-26, macellazione) è stabile e unico — la macellazione punta a una carcassa
# per id, non per indice, perché una carcassa che marcisce prima sposterebbe gli indici delle altre. Marciscono dopo i giorni di ExpiredObjectTypes.ExpiredObjectType.CARCASS
# (carcass_rules.tres), vedi GroundPileService.advance_daily. Nessuna macellazione ancora.
var carcasses: Array = []
# Giorno di comparsa (stessa forma dei record di GameData.expired_objects): la durata massima parte da qui e
# non viene rinnovata dagli scarti successivi.
var appeared_at_year: int = 0
var appeared_at_day: int = 0
# Contatore delle modifiche (runtime, non salvato): la vista si ridisegna quando cambia.
var revision: int = 0


# Punto del mondo del mucchio (centro della microcella), in microcelle locali alla macrocella.
func get_position() -> Vector2:
	return Vector2(microcell) + Vector2(0.5, 0.5)


# Vuoto = nessuna risorsa E nessuna carcassa: un mucchio con una carcassa resta finché la carcassa c'è.
func is_empty() -> bool:
	return resources.is_empty() and carcasses.is_empty()


func get_quantity(resource_name: String) -> int:
	return int((resources.get(resource_name, {}) as Dictionary).get("quantity", 0))


# Record nella forma letta da ExpiredObjectCalculator (appeared_at_year/appeared_at_day).
func get_expiry_record() -> Dictionary:
	return {"appeared_at_year": appeared_at_year, "appeared_at_day": appeared_at_day}


# Nomi delle risorse ordinati (disegno e pannello stabili).
func get_resource_names() -> Array[String]:
	var names: Array[String] = []
	for resource_name in resources.keys():
		names.append(String(resource_name))
	names.sort()
	return names


func to_save_data() -> Dictionary:
	return {
		"id": id,
		"macro_x": macro_coords.x,
		"macro_y": macro_coords.y,
		"micro_x": microcell.x,
		"micro_y": microcell.y,
		"appeared_at_year": appeared_at_year,
		"appeared_at_day": appeared_at_day,
		# Già JSON-nativo (stesso trattamento di Building.stored_resources in GameSaveService).
		"resources": resources,
		"carcasses": carcasses,
	}


# Record di una carcassa nella forma letta da ExpiredObjectCalculator (appeared_at_year/appeared_at_day).
static func get_carcass_expiry_record(carcass: Dictionary) -> Dictionary:
	return {"appeared_at_year": int(carcass.get("killed_year", 0)), "appeared_at_day": int(carcass.get("killed_day", 0))}
