class_name DifficultyRules
extends Resource

# Moltiplicatori di difficolta' per ciascuna opzione di NewGameOptionsMenu — chiavi = le STESSE
# stringhe gia' usate da GameSettings/GameData ("YOUNG"/"ADULT"/"OLD", "FEW"/"MEDIUM"/"MANY",
# "SPARSE"/"NORMAL"/"DENSE"), nessuna conversione da fare in DifficultyCalculator. 1.0 = la scelta
# piu' difficile del gruppo, valori piu' bassi = piu' facile — combinati per prodotto (vedi
# DifficultyCalculator.compute_difficulty_ratio), MAI normalizzati: aggiungere un'opzione futura o
# ritarare un numero qui non deve spostare il significato di un valore gia' salvato in una
# partita precedente (confermato con l'utente: nessun rescaling, proprio per questo).
@export var world_age_multiplier: Dictionary = {}
@export var animal_density_multiplier: Dictionary = {}
@export var population_size_multiplier: Dictionary = {}
# "RICH"/"NORMAL"/"POOR" — stesso schema a Dictionary dei tre sopra (e' una scelta a 3 vie come
# quelle, non un booleano come la coppia hostile/predator sotto), POOR = 1.0 (piu' difficile,
# coerente col principio della classe).
@export var resource_richness_multiplier: Dictionary = {}
# "COUPLE"/"FAMILY"/"GROUP" — con quanti individui il player sceglie di partire (rinominato da
# FAMILY/SMALL_GROUP/BIG_GROUP, BIG_GROUP a 20 individui eliminato — richiesta utente, 2026-09-04;
# vedi HumanSeedingService.GROUP_SIZE_COMPOSITIONS per le composizioni esatte): COUPLE (2
# individui) = 1.0, piu' difficile, meno persone per lavorare/difendersi; FAMILY (5) = 0.9; GROUP
# (10) = 0.6, piu' facile.
@export var group_size_multiplier: Dictionary = {}

# Flag booleano fisso (non un gruppo di opzioni che puo' crescere come i tre Dictionary sopra),
# per questo due @export float invece di un Dictionary con chiavi "true"/"false".
@export var hostile_start_excluded_multiplier: float = 0.9
@export var hostile_start_included_multiplier: float = 1.0

# Stesso trattamento della coppia sopra, per "Escludi partenza vicino ai predatori".
@export var predator_territory_excluded_multiplier: float = 0.9
@export var predator_territory_included_multiplier: float = 1.0

# Stesso trattamento delle due coppie sopra, per "Presenza sicura animali" — a differenza delle
# altre due (dove ESCLUDERE qualcosa e' la scelta piu' facile, 0.9), qui e' l'opposto: GARANTIRE
# la presenza e' la scelta piu' facile (0.8, non 0.9 — un vantaggio piu' marcato, e' una garanzia
# assoluta non solo un'esclusione di rischio), lasciarla al caso resta la piu' difficile (1.0,
# coerente col principio della classe).
@export var animal_presence_guaranteed_multiplier: float = 0.8
@export var animal_presence_not_guaranteed_multiplier: float = 1.0
