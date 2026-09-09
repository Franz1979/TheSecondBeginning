class_name Building
extends RefCounted

# Istanza runtime di un edificio piazzato — stato di PARTITA (salvato/caricato da GameSaveService/
# GameLoadService, sezione "world.buildings", mai come .tres: i parametri di TIPO restano su
# BuildingRules, stesso schema di PopulationGroup/AnimalRules). Nessun controllo di
# sovrapposizione/spazio libero ancora scritto qui — solo il dato.

# ID progressivo assegnato UNA volta alla creazione (vedi World.allocate_building_id), mai
# ricalcolato — stesso principio di PopulationGroup.id: resta stabile per tutta la vita
# dell'edificio, indipendente da quanti altri ne esistono o vengono distrutti nel frattempo.
var id: int = 0

# Nome file/tipo (es. "hut", per BuildingCalculator.get_building_rules) — NON la chiave tr() di
# BuildingRules.building_name (es. "building_hut"), sono stringhe diverse. Serve a ricaricare
# `rules` da GameLoadService: `rules` stesso non viene mai serializzato (è dato statico di tipo,
# stesso principio di PopulationGroup che salva species_name e non l'AnimalRules).
var building_type_name: String = ""
var rules: BuildingRules = null

# Coordinate MACRO della cella che ospita l'edificio.
var macro_x: int = 0
var macro_y: int = 0

# Coordinate MICRO (0..World.WIDTH*CELL_SIZE-1 in unità di microcella, non pixel) all'interno
# della macrocella ospitante — dove esattamente disegnare l'edificio (vedi GameScene.
# _place_building_at/MicroCellRenderer._draw_buildings). Non usate per alcuna logica di
# simulazione (spazio/dedicated_space resta a livello di macrocella intera, vedi
# MacroCellState.dedicated_space), solo per il rendering.
var micro_x: int = 0
var micro_y: int = 0

# -1 = costruzione non ancora iniziata. Absolute_day (GameData.get_absolute_day()) del giorno in
# cui è iniziata, non un countdown — stesso principio già usato altrove nel progetto (es.
# FogOfWarMemory.last_seen_by_position) per non dover ritoccare questo campo ogni giorno.
var construction_started_day: int = -1
var is_complete: bool = false

# Valorizzata al completamento (= rules.max_durability), mai prima — scende per attacchi (futuro,
# non ancora implementato) e/o degrado da rules.lifespan_years (anch'esso non ancora applicato).
var current_durability: int = 0

# -1 = non ancora completato. Anno di GIOCO (GameData.year) in cui la costruzione è terminata,
# usato insieme a rules.lifespan_years per calcolare quando l'edificio scadrà.
var built_year: int = -1

# Nome risorsa -> {"quantity": int, "decay_fraction": float} (2026-09-09, richiesta utente — Step 3
# decadimento a lotto unico: PRIMA era resource_name -> int diretto, vedi GameLoadService per la
# retrocompatibilità con save salvati nel vecchio formato). decay_fraction è una MEDIA PESATA sulla
# quantità di tutto ciò che è stato depositato nel tempo per quella risorsa in questo edificio — un
# "lotto unico" per tipo di risorsa per edificio (vedi BuildingStorageService.store per la formula
# di fusione), non un lotto per singolo deposito separato. Avanzata di 1/day_durability al giorno da
# ResourceDecayService.advance_building_decay; la entry viene rimossa dal Dictionary quando
# raggiunge 1.0 (risorsa deperita). Vuoto finché non esiste un vero inventario da cui prelevare/
# depositare.
var stored_resources: Dictionary = {}

# Restrizione PER-ISTANZA delle categorie accettate (2026-09-09, richiesta utente) — DIVERSO da
# BuildingRules.accepted_categories: quello è per TIPO (condiviso — vedi BuildingCalculator.
# get_building_rules, che cacha il .tres per path: ogni edificio dello stesso tipo punta allo
# STESSO oggetto BuildingRules, mai una copia per istanza — modificarlo lì cambierebbe TUTTI i
# depositi/capanne del mondo). enabled_categories invece vive QUI, su questa singola istanza:
# vuoto (default) = nessuna restrizione propria, accetta tutto ciò che il TIPO già accetta —
# un ulteriore filtro che il player può restringere (mai ampliare: BuildingStorageService.
# can_accept controlla ENTRAMBI i livelli, il tipo resta comunque il tetto massimo) solo tra le
# categorie che il tipo ammette, edificio per edificio (es. "il magazzino #3 accetta solo cibo,
# il #7 solo materiali grezzi", pur essendo entrambi lo stesso tipo di edificio generico).
#
# Controllo SOLO IN ENTRATA (richiesta esplicita utente) — togliere una categoria da qui non
# rimuove/butta fuori ciò che è già in stored_resources con quella categoria, impedisce solo
# nuovi depositi futuri di quella categoria: BuildingStorageService.can_accept è consultato SOLO
# da store() (il momento del deposito), mai da get_used_space/get_slots_used/get_slot_breakdown
# (che restano una lettura pura di ciò che è già stoccato, a prescindere da questo filtro).
var enabled_categories: Array[SecondaryResourceTypes.Category] = []

# Orientamento (dove guarda la porta) — scelto dal player durante il piazzamento (vedi
# BuildingGhost.rotation/GameScene, tasto R per ruotare), fissato al momento del piazzamento
# stesso (nessun modo per ruotare un edificio già costruito, per ora). Default SOUTH = porta
# verso il basso/il player.
var rotation: GameTypes.Direction = GameTypes.Direction.SOUTH


func _init(_rules: BuildingRules = null, _macro_x: int = 0, _macro_y: int = 0, _building_type_name: String = "") -> void:
	rules = _rules
	macro_x = _macro_x
	macro_y = _macro_y
	building_type_name = _building_type_name
