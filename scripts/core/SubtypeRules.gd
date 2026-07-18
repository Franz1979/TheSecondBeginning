class_name SubtypeRules
extends Resource

@export var subtype_name: String = ""

@export_group("Initial Composition")
# Rapporto iniziale per bioma, usato solo alla generazione iniziale del mondo (chiavi:
# GameTypes.Biome). Un bioma assente dal dizionario vale 0 — nessuna presenza iniziale lì.
@export var initial_ratio_by_biome: Dictionary = {}

@export_group("Suitability")
# Vuoto = nessuna restrizione. Usati solo al momento dell'applicazione di un trasferimento
# di migrazione verso una cella di destinazione (vedi ResourceMigrationService).
@export var suitable_biomes: Array[GameTypes.Biome] = []
@export var suitable_terrains: Array[GameTypes.TerrainBase] = []

@export_group("Growth Bias")
# Peso (non un gate binario, quello è suitable_biomes sopra) usato da growth/encroachment
# (guadagno, diretto) e mortality (perdita, invertito) per far convergere lentamente la
# composizione locale verso ciò che il bioma favorisce, senza mai escludere del tutto un
# sottotipo ammesso. Un bioma assente dal dizionario vale 1.0 (nessun bias). Valori tipici:
# ~1.1-1.3 favorevole, 1.0 neutro, ~0.7-0.9 sfavorevole ma ammesso — mai vicino a 0, quello è
# compito dell'esclusione totale di suitable_biomes/suitable_terrains.
@export var growth_multiplier_by_biome: Dictionary = {}


func is_suitable_for(biome: GameTypes.Biome, terrain: GameTypes.TerrainBase) -> bool:
	if not suitable_biomes.is_empty() and not suitable_biomes.has(biome):
		return false
	if not suitable_terrains.is_empty() and not suitable_terrains.has(terrain):
		return false
	return true
