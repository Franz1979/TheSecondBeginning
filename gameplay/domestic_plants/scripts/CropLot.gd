class_name CropLot
extends RefCounted

# Lotto di un terreno coltivato (2026-11-15, richiesta utente — campi, passo 2: "come se fossero 8 orti"): una microcella
# coltivata con la sua vita propria. L'orto ha un lotto, il campo uno per microcella di terra (CultivationService.lot_cells).
# Specie, "coltiva in automatico" e fertilità restano sull'edificio. Salvato dentro l'edificio (Building.crop_lots).

# Microcella del lotto, assoluta nella macrocella dell'edificio: è anche la sua identità (Task.context, salvataggi).
var microcell: Vector2i = Vector2i.ZERO
# Fase (CultivationService.Phase), once seminate, piantine nate e piante mature.
var phase: int = 0
var sown: int = 0
var sprouts: int = 0
var mature: int = 0
# Semina in corso: once portate e non ancora seminate. Lavoro fatto (semina o mietitura: le due fasi non si sovrappongono).
var seeds: int = 0
var labor: float = 0.0


func _init(p_microcell: Vector2i = Vector2i.ZERO) -> void:
	microcell = p_microcell


# Chiave della microcella per Task.context (un intero, sicuro nel salvataggio).
static func key_of(cell: Vector2i) -> int:
	return cell.y * World.WIDTH + cell.x


static func cell_of_key(key: int) -> Vector2i:
	return Vector2i(posmod(key, World.WIDTH), key / World.WIDTH)


func to_dict() -> Dictionary:
	return {"x": microcell.x, "y": microcell.y, "phase": phase, "sown": sown, "sprouts": sprouts, "mature": mature,
		"seeds": seeds, "labor": labor}


static func from_dict(data: Dictionary) -> CropLot:
	var lot := CropLot.new(Vector2i(int(data.get("x", 0)), int(data.get("y", 0))))
	lot.phase = int(data.get("phase", 0))
	lot.sown = int(data.get("sown", 0))
	lot.sprouts = int(data.get("sprouts", 0))
	lot.mature = int(data.get("mature", 0))
	lot.seeds = int(data.get("seeds", 0))
	lot.labor = float(data.get("labor", 0.0))
	return lot
