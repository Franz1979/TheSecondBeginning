class_name SoundDef
extends Resource

# Definizione di UN suono (2026-09-26, richiesta utente — banchi sonori): un id e le sue varianti, più i
# parametri di riproduzione usati da AudioManager.play. Vive dentro un SoundBank (audio/banks/*.tres),
# generato e aggiornato da audio/scripts/tools/BuildSoundBanks.gd: lo strumento riscrive solo `streams`,
# tutti gli altri campi si possono tarare a mano nell'Inspector e vengono conservati.

# Identificatore univoco in TUTTI i banchi (AudioManager segnala i duplicati). Per convenzione è il nome
# del file senza estensione e senza il suffisso _N delle varianti ("step_grass_2.wav" -> step_grass).
@export var id: StringName = &""
# Varianti: a ogni riproduzione ne viene scelta una (shuffle bag, mai due volte di fila la stessa).
@export var streams: Array[AudioStream] = []
# Volume relativo del suono (il volume utente è sul bus, vedi UserOptions).
@export var volume_db: float = 0.0
# Pitch casuale in [pitch_min, pitch_max] a ogni riproduzione (1.0/1.0 = nessuna variazione).
@export var pitch_min: float = 0.95
@export var pitch_max: float = 1.05
# Bus di uscita (audio/buses/default_bus_layout.tres: Music, Ambience, SFX, UI).
@export var bus: StringName = &"SFX"
# true = posizionale (AudioStreamPlayer2D) quando play() riceve una posizione; senza posizione, o con false,
# il suono è non posizionale.
@export var spatial: bool = false
# Quante istanze di questo id possono suonare insieme: oltre, la più vecchia viene riavviata col nuovo suono.
@export var max_voices: int = 3
# Intervallo minimo tra due riproduzioni dello stesso id: una richiesta più ravvicinata viene ignorata.
@export var cooldown_ms: int = 100
# Priorità a pool pieno: un suono ruba la voce di priorità più bassa (fino a uguale alla propria), altrimenti
# viene scartato. Più alto = più importante.
@export var priority: int = 0
