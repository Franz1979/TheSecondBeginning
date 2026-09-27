class_name WorkAreaService
extends RefCounted

# Logica delle zone di lavoro (2026-09-27, richiesta utente — work areas, passo 1a). Stateless, funzioni statiche,
# stesso pattern di GroundPileService: opera sempre su un GameData passato dal chiamante (GameData.work_areas). Le
# sovrapposizioni tra zone sono ammesse. Ogni creazione/eliminazione alza GameData.work_areas_revision, che le viste
# (overlay del layer, minimappa) usano per ridisegnarsi.


# Rettangolo accettabile per una zona: non vuoto, lati entro WorkAreaTypes.MAX_SIDE, tutto dentro la macrocella.
static func is_valid_rect(rect: Rect2i) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.size.x > WorkAreaTypes.MAX_SIDE or rect.size.y > WorkAreaTypes.MAX_SIDE:
		return false
	return rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= World.WIDTH and rect.end.y <= World.HEIGHT


# Rettangolo tra due microcelle di un trascinamento (estremi compresi), limitato alla macrocella e a MAX_SIDE a
# partire da `start`.
static func rect_from_drag(start: Vector2i, current: Vector2i) -> Rect2i:
	var clamped := Vector2i(clampi(current.x, 0, World.WIDTH - 1), clampi(current.y, 0, World.HEIGHT - 1))
	var limit := WorkAreaTypes.MAX_SIDE - 1
	clamped.x = clampi(clamped.x, start.x - limit, start.x + limit)
	clamped.y = clampi(clamped.y, start.y - limit, start.y + limit)
	var top_left := Vector2i(mini(start.x, clamped.x), mini(start.y, clamped.y))
	var bottom_right := Vector2i(maxi(start.x, clamped.x), maxi(start.y, clamped.y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


# Crea una zona con nome ("Zona N", N = id) e colore automatici (WorkAreaTypes.PALETTE a rotazione). null se il
# rettangolo non è valido o game_data manca.
static func create(game_data: GameData, macro_coords: Vector2i, rect: Rect2i) -> WorkArea:
	if game_data == null or not is_valid_rect(rect):
		return null
	var area := WorkArea.new()
	area.id = game_data.allocate_work_area_id()
	area.name = TranslationServer.translate("work_area_default_name").format({"n": area.id})
	area.color = WorkAreaTypes.PALETTE[(area.id - 1) % WorkAreaTypes.PALETTE.size()]
	area.macro_coords = macro_coords
	area.rect = rect
	game_data.work_areas.append(area)
	game_data.work_areas_revision += 1
	return area


# Una zona è stata modificata (nome, colore, lavori, filtri — 2026-09-27, pannello della zona): revisione della zona e
# dell'elenco alzate, così overlay e minimappa si ridisegnano.
static func notify_changed(game_data: GameData, area: WorkArea) -> void:
	if area != null:
		area.revision += 1
	if game_data != null:
		game_data.work_areas_revision += 1


# Sostituisce il rettangolo di una zona ("Ridisegna" — 2026-09-27), mantenendo tutto il resto. La macrocella può
# cambiare. false se il rettangolo non è valido.
static func set_rect(game_data: GameData, area: WorkArea, macro_coords: Vector2i, rect: Rect2i) -> bool:
	if area == null or not is_valid_rect(rect):
		return false
	area.macro_coords = macro_coords
	area.rect = rect
	notify_changed(game_data, area)
	return true


# Zona più piccola (per area) tra quelle che contengono la microcella, null se nessuna — vince sulla selezione quando
# più zone si sovrappongono (2026-09-27).
static func find_smallest_at(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i) -> WorkArea:
	var best: WorkArea = null
	for area in find_at(game_data, macro_coords, microcell):
		if best == null or area.rect.get_area() < best.rect.get_area():
			best = area
	return best


# Elimina la zona con questo id. Ritorna true se c'era.
static func delete(game_data: GameData, area_id: int) -> bool:
	var area := find_by_id(game_data, area_id)
	if area == null:
		return false
	game_data.work_areas.erase(area)
	game_data.work_areas_revision += 1
	return true


static func find_by_id(game_data: GameData, area_id: int) -> WorkArea:
	if game_data == null:
		return null
	for area in game_data.work_areas:
		if area.id == area_id:
			return area
	return null


# Zone di una macrocella, nell'ordine di creazione.
static func find_in_macro_cell(game_data: GameData, macro_coords: Vector2i) -> Array[WorkArea]:
	var result: Array[WorkArea] = []
	if game_data == null:
		return result
	for area in game_data.work_areas:
		if area.macro_coords == macro_coords:
			result.append(area)
	return result


# Zone che contengono una microcella (più d'una se si sovrappongono), nell'ordine di creazione.
static func find_at(game_data: GameData, macro_coords: Vector2i, microcell: Vector2i) -> Array[WorkArea]:
	var result: Array[WorkArea] = []
	if game_data == null:
		return result
	for area in game_data.work_areas:
		if area.contains(macro_coords, microcell):
			result.append(area)
	return result
