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

@export_group("Foliage")
# Puramente descrittivo oggi: nessun servizio legge questo campo. Riservato a un futuro step
# di stagionalità/rendering (chioma persistente vs caduca).
@export var is_evergreen: bool = false

@export_group("Age Bands")
# Master switch: false (default) = comportamento invariato, nessuna delle logiche sotto viene
# mai letta per questo sottotipo (stesso idioma "vuoto/false = non tracciato" di is_evergreen/
# suitable_biomes sopra). true solo per i due sottotipi SHRUB oggi (wood_only, fruit_bearing).
@export var track_age_bands: bool = false
# Anni interi (nessuna frazione): quanti cicli di maturazione (fine primavera, vedi
# ResourceAgeBandService) un individuo attraversa in YOUNG prima di passare ad ADULT, e in
# ADULT prima di passare a OLD. La transizione è una frazione 1/N per anno (residenza media
# statistica, non un tracking di coorte per anno di nascita).
@export var maturation_years: int = 2
@export var elder_years: int = 6
# Quota (young, adult, old) del TOTALE morto quest'anno per fill_ratio (ResourceMortalityService)
# attribuita a ciascuna fascia — convenzionalmente somma a 1.0, ma non validato a runtime (stesso
# trattamento di initial_ratio_by_biome sopra: _split_by_weight normalizza comunque per la somma
# dei pesi). Se una fascia non ha abbastanza unità per la propria quota, l'eccedenza si
# ridistribuisce sulle altre (vedi MacroCellState.apply_age_band_loss/_split_by_weight_capped).
@export var mortality_share_by_age: Array[float] = [0.34, 0.33, 0.33]
# Coefficiente di produttività per fascia, usato SOLO dal calcolo delle risorse secondarie a
# sottotipo (vedi CaloricCalculator._get_base_quantity): YOUNG non produce nulla, ADULT piena
# produttività, OLD ridotta ma non nulla.
@export var production_coefficient_young: float = 0.0
@export var production_coefficient_adult: float = 1.0
@export var production_coefficient_old: float = 0.65
# Ripartizione (young, adult, old) usata SOLO al seeding iniziale del mondo
# (InitialResourceSetupService), MAI durante la simulazione a regime (dove ogni guadagno va
# sempre e solo in YOUNG, vedi MacroCellState.add_age_band_gain) — permette a un mondo nuovo di
# partire come un ecosistema già stabilito invece che "appena piantato". Chiavi = GameTypes.
# AgeBand assenti/tutte a 0 => ripiega su pesi uguali (stesso fallback di initial_ratio_by_biome).
@export var initial_age_ratio: Dictionary = {}


func is_suitable_for(biome: GameTypes.Biome, terrain: GameTypes.TerrainBase) -> bool:
	if not suitable_biomes.is_empty() and not suitable_biomes.has(biome):
		return false
	if not suitable_terrains.is_empty() and not suitable_terrains.has(terrain):
		return false
	return true
