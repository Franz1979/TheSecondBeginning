class_name GroundHeight3D
extends RefCounted

# Altezza del terreno nella vista 3D: lievi ondulazioni continue su tutto il mondo (in microcelle assolute, così due
# macrocelle vicine combaciano al bordo). Gli oggetti appoggiati a terra useranno la stessa funzione.

const AMPLITUDE := 0.35
# Profondità del fondale sotto fiumi, ruscelli e laghi/mare, e livello della superficie dell'acqua.
const WATER_BED := -0.9
const WATER_SURFACE := -0.2

static var _noise: FastNoiseLite


static func land_height(global_x: float, global_y: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1979
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.035
		_noise.fractal_octaves = 2
	return _noise.get_noise_2d(global_x, global_y) * AMPLITUDE
