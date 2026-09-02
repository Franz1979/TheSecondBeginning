class_name GameData
extends RefCounted

const DAYS_PER_YEAR := 365

var year: int = 0
var current_day: int = 0 # 0..DAYS_PER_YEAR-1

# Opzioni scelte in NewGameOptionsMenu e difficolta' risultante, valorizzate UNA SOLA VOLTA in
# WorldScene._populate_new_world al momento della creazione di QUESTA partita — mai piu'
# modificate dopo. Non alimentano nessuna logica di simulazione: solo statistica (poter vedere a
# posteriori, su un campione di salvataggi, che opzioni/difficolta' scelgono davvero i
# giocatori). starting_difficulty_ratio e' il prodotto GREZZO dei tre moltiplicatori (vedi
# DifficultyCalculator.compute_difficulty_ratio) — MAI arrotondato, mai in percentuale qui:
# l'arrotondamento all'unita' percentuale e' solo per la barra in NewGameOptionsMenu, i dati
# salvati restano sempre il valore esatto. -1.0 = non applicabile (world_age_mode "CLASSIC").
var starting_world_age_mode: String = ""
var starting_animal_density: String = ""
var starting_population_size: String = ""
var starting_exclude_hostile_start: bool = false
var starting_exclude_predator_territories: bool = false
var starting_resource_richness_preference: String = ""
# A differenza dei campi sopra (puramente statistici), questo e' predisposto per un consumo
# FUTURO reale: quando esistera' un punto che deve sapere con quanti individui il player inizia
# la partita (modulo player, non ancora implementato), leggera' questo valore invece di
# ricalcolarlo. Oggi alimenta solo DifficultyCalculator, nessuna differenza pratica.
var starting_group_size_preference: String = ""
# A differenza dei campi puramente statistici sopra, questo alimenta DAVVERO
# FirstStartMacroCellSelectionService (vedi GameScene._ready()), esattamente come
# starting_exclude_hostile_start/starting_exclude_predator_territories/
# starting_resource_richness_preference — non e' solo una statistica.
var starting_guarantee_animal_presence: bool = false
var starting_difficulty_ratio: float = -1.0

# Coordinate della macrocella "sede" del player nella futura vista GameScene (vista principale
# player su una singola macrocella, non ancora implementata). -1 = mai inizializzata: GameScene
# la interpreta come segnale per invocare FirstStartMacroCellSelectionService la primissima
# volta. Vivono qui e non in GameSettings (che è tutto stato di sola sessione, mai scritto nel
# salvataggio — vedi i suoi commenti) perché "il player ha già scelto la sua macrocella" è un
# fatto che appartiene a QUESTA partita salvata e deve sopravvivere a save/load, non solo alla
# sessione corrente. Nessun bool separato: l'esistenza di una coordinata valida è già il segnale.
var player_macro_cell_x: int = -1
var player_macro_cell_y: int = -1

# Id dell'HumanIndividual che era il bersaglio di movimento/streaming corrente (GameScene.
# individual) al momento del salvataggio/cambio-scena — richiesta utente, 2026-09-02 (persistenza
# Folk/HumanPopulationGroup/HumanIndividual). Sostituisce player_micro_x/y (RIMOSSI, ridondanti
# ora: la posizione di OGNI individuo, bersaglio incluso, viaggia già dentro l'array persistito di
# HumanIndividual — vedi GameSaveService/GameLoadService, sezione "human"). -1 = nessun individuo
# umano persistito in questa partita (mai il caso oggi che il player esista, ma sentinella comunque
# coerente con la convenzione già in uso nel file). GameScene lo usa per ripristinare `individual`
# sul MEDESIMO membro del gruppo invece che sempre sul primo dell'array.
var player_individual_id: int = -1

# Zoom della Camera2D di GameScene (Camera2D.zoom.x == .y sempre in questo progetto — vedi
# CameraController, lo scroll/le scorciatoie +/- applicano sempre lo stesso delta a entrambi gli
# assi — quindi un solo float basta, a differenza di camera_x/y sotto che sono davvero 2D). -1.0
# = mai valorizzato: GameScene lascia lo zoom di default della .tscn (partita nuova, o save
# precedente l'introduzione di questo campo).
var camera_zoom: float = -1.0

# Posizione della Camera2D di GameScene, in pixel — lo "sgancio camera-player" anticipato nel
# commento sopra (Step 3 del piano movimento indipendente, 2026-09-02: la camera non segue più
# nessun individuo, quindi la sua posizione non è più derivabile da quella di chi la seguiva e va
# persistita per conto proprio). camera_position_saved (booleano esplicito, non il sentinel -1.0
# usato altrove in questo file) segnala "mai valorizzato" — a differenza di player_macro_cell_x/y,
# che vivono in un intervallo stretto e sempre non negativo, CameraController non ha alcun limite
# di pan (vedi la nota "Camera bounds deferred" — memoria di progetto): camera_x/y possono quindi
# legittimamente essere negativi o qualunque valore, rendendo -1.0 un sentinel ambiguo qui.
var camera_x: float = 0.0
var camera_y: float = 0.0
var camera_position_saved: bool = false

# Ultimo absolute_day (vedi get_absolute_day sotto) in cui GameScene ha eseguito la pulizia
# periodica di FogOfWarMemory.last_seen_by_position (vedi FogOfWarMemory.prune_stale/
# GameScene._maybe_prune_fog_of_war_memories) — deve sopravvivere a save/load, altrimenti ogni
# ricaricamento farebbe ripartire il conteggio da zero, sfasando la cadenza reale rispetto a
# quanto tempo di gioco è davvero trascorso. Default 0 (non -1 come i sentinel sopra): "mai
# potato" equivale correttamente a "come se fosse stato potato al giorno 0 di questa partita",
# nessun caso speciale da gestire nel confronto (current_absolute_day - questo campo >= intervallo).
var fog_of_war_last_prune_absolute_day: int = 0

# Monotonic day count since year 0, day 0 — the single source of truth for "how long ago"
# comparisons (e.g. natural-event growth-bonus expiry) that must not reset/round at a year
# boundary the way a per-year counter would.
func get_absolute_day() -> int:
	return year * DAYS_PER_YEAR + current_day

# Advances the calendar by one day. Returns true if this tick rolled the
# year over (current_day wrapped back to 0, year incremented) — callers use
# this to decide whether to run the yearly simulation pipeline.
func advance_day() -> bool:
	current_day += 1
	if current_day >= DAYS_PER_YEAR:
		current_day = 0
		year += 1
		return true
	return false
