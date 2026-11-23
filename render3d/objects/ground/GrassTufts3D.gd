class_name GrassTufts3D
extends RefCounted

# SPENTO (2026-11-21, utente): troppo grandi per l'erba, che ora è la texture d'erba alta nello shader del terreno.
# Tenuto per una prossima risorsa a terra (erbe medicinali, verdure...), da rimpicciolire; da riagganciare in View3D
# (Cell3D.refresh_grass, GameStateReader.grass_snapshot/grass_signature sono pronti).
#
# Oggetto 3D: i ciuffi dell'erba-risorsa di UNA macrocella (2026-11-21). Il prato a texture resta il fondo ovunque; dove
# il 2D ha l'erba (vegetation_positions GRASS) un ciuffo per microcella, spostato a caso dentro la microcella (così non si
# vede la griglia), ruotato e di taglia variabile, scelto fra tre forme. Posto, rotazione, taglia e forma dipendono solo
# dalla microcella (hash): restano fermi quando l'erba attorno cambia.
# Forme: SOURCES_PER_GIOCO/blender/scripts/grass_tufts.py (misure in metri del Blender: qui x 0,1), colori a vertici
# dell'estate; le altre stagioni tingono ogni copia col rapporto fra i colori del 2D (GRASS_PALETTE_BY_SEASON).
# Materiale a due facce (i fili si vedono anche dal retro), senza ombre (migliaia di copie, ombre basse poco visibili).

const MODEL_DIR := "res://render3d/assets/models/props/"
const MODELS := ["grass_tuft_radi", "grass_tuft_fitto", "grass_tuft_piegato"]
const MODEL_SCALE := 0.1
const SIZE_RANGE := Vector2(0.6, 1.4)
# Spostamento massimo dal centro della microcella (frazione di microcella, totale).
const JITTER := 0.9
const SINK := 0.02

static var _meshes: Array = []
static var _material: StandardMaterial3D


static func build(snapshot: GrassSnapshot3D, base_global: Vector2) -> Node3D:
	if snapshot.positions.is_empty():
		return null
	if _meshes.is_empty():
		for model_name in MODELS:
			_meshes.append(ModelMesh3D.load_mesh(MODEL_DIR + model_name + ".glb"))
		_material = FlatMeshBuilder.vertex_color_material()
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tint := season_tint(snapshot.season)
	var buckets: Array = [[], [], []]
	var colors: Array = [[], [], []]
	for pos in snapshot.positions:
		var cell := Vector2i(pos.x, pos.y)
		var h := hash(cell * 7 + Vector2i(13, 29))
		var jitter := Vector2(float(h % 1000) / 1000.0 - 0.5, float((h / 1000) % 1000) / 1000.0 - 0.5) * JITTER
		var rotation := float((h / 7) % 628) / 100.0
		var size := MODEL_SCALE * lerpf(SIZE_RANGE.x, SIZE_RANGE.y, float((h / 13) % 1000) / 1000.0)
		var p := Vector2(cell.x + 0.5, cell.y + 0.5) + jitter
		var y := GroundHeight3D.land_height(base_global.x + p.x, base_global.y + p.y) - SINK
		var shape := posmod(h, MODELS.size())
		buckets[shape].append(Transform3D(Basis(Vector3.UP, rotation).scaled(Vector3.ONE * size), Vector3(p.x, y, p.y)))
		colors[shape].append(tint)
	var color_arg: Array = [] if tint == Color.WHITE else colors
	return MultiMeshGroup3D.build("GrassTufts", _meshes, buckets, _material, color_arg, false)


# Rapporto fra il colore medio dell'erba del 2D nella stagione e quello dell'estate (colori dei vertici), canale per canale.
static func season_tint(season: GameTypes.Season) -> Color:
	var summer: Dictionary = MicroCellRenderer.GRASS_PALETTE_BY_SEASON[GameTypes.Season.SUMMER]
	var palette: Dictionary = MicroCellRenderer.GRASS_PALETTE_BY_SEASON.get(season, summer)
	if palette == summer:
		return Color.WHITE
	var now: Color = (palette["base"] as Color).lerp(palette["tip"], 0.5)
	var ref: Color = (summer["base"] as Color).lerp(summer["tip"], 0.5)
	return Color(now.r / ref.r, now.g / ref.g, now.b / ref.b)
