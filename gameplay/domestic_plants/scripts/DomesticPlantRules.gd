class_name DomesticPlantRules
extends Resource

# Specie vegetale da addomesticare (2026-11-13, richiesta utente — ramo delle piante, punto 2): come DomesticAnimalRules
# ma ridotta a ciò che serve ai punti. Un solo capostipite, l'orzo (barley.tres). I punti stanno nello stesso registro
# degli animali (GameData.domestication_points / domesticated_species / domestication_years, DomesticationPointsService);
# alla soglia la scoperta della specie (DiscoveryTypes.TriggerType.ANIMAL_DOMESTICATED con species = species_name)
# regala l'idea delle piante. Dati in res://gameplay/domestic_plants/data/{species_name}.tres (DomesticPlantCalculator).

@export var species_name: String = ""
# Chiavi tr(): la specie domestica (es. "Orzo") e quella selvatica da cui si parte (es. "Orzo selvatico").
@export var display_name: String = ""
@export var wild_display_name: String = ""
@export var domestication_points_required: int = 0
# Risorsa raccolta da terra che fa avanzare la specie (es. "wild_seeds") e quante unità raccolte fanno un punto
# (2026-11-13, richiesta utente: 1 punto ogni 10 once). Il resto si accumula in GameData.domestication_harvest_units.
@export var harvest_resource_name: String = ""
@export var harvested_units_per_point: int = 0
# Risorsa delle once della pianta domestica (2026-11-15, richiesta utente — es. "domestic_barley"): la dà la Mietitura
# dell'orto a specie addomesticata (CultivationService.harvest_resource), e la semineranno i campi. "" = non ancora fatta:
# l'orto continua a dare il selvatico.
@export var domestic_resource_name: String = ""
# Punti per ogni pasto cucinato che usa harvest_resource_name come ingrediente (zuppa di midollo e semi tostati).
@export var points_per_meal: int = 0
# Tetto dei punti da raccolta e zuppa (2026-11-15, ramo piante): oltre questo totale la specie avanza solo nell'orto delle
# prove. 0 = nessun tetto (l'orzo, spontaneo).
@export var wild_points_cap: int = 0
# Punti per ogni pezzo prodotto di product_resource_name (2026-11-15, corda di lino: come la zuppa per i cereali), dentro
# wild_points_cap. "" = nessun prodotto.
@export var product_resource_name: String = ""
@export var points_per_product: int = 0

# Orto delle prove e campo (2026-11-15, TrialGardenService). Default = la specie non si semina (l'orzo). Specie selvatica
# finché non è in GameData.domesticated_species: nell'orto ogni oncia nasce e ogni piantina matura con probabilità pari
# all'avanzamento (punti / soglia); dopo, sempre.
@export_group("Semina")
# GameTypes.Season (0 inverno, 1 primavera, 2 estate, 3 autunno); -1 = mai.
@export var sowing_season: int = -1
@export var harvest_season: int = -1
# Once seminate per microcella: l'orto è 1 microcella; varrà anche per il campo (da ritarare con l'agricoltura).
@export var sown_units_per_lot: int = 0
# Resa a regime: once raccolte per pianta matura con la specie domestica. Nell'orto: 1 + (resa - 1) × avanzamento.
@export var yield_per_unit: float = 0.0
@export var points_per_sown_unit: int = 0
@export var points_per_sprout: int = 0
# Dal 2026-11-15 (richiesta utente) i punti della pianta matura si danno solo alla Mietitura, per pianta mietuta: chi non
# raccoglie non impara.
@export var points_per_mature_plant: int = 0
# Punti TOLTI per ogni pianta matura lasciata marcire (fine della stagione di raccolto senza mietitura).
@export var points_per_rotten_plant: int = 0
# Colore della spiga (o del fiore) delle piante mature disegnate sul terreno (MicroCellRenderer, piantine): la forma è la
# stessa per tutte le specie, cambia solo questo.
@export var crop_color: Color = Color(0.86, 0.7, 0.32, 1.0)
