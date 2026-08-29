class_name FogOfWarRules
extends Resource

# Soglie di decadimento della memoria del fog of war (vedi FogOfWarMemory/FogOfWarRenderer),
# estratte qui da FogOfWarRenderer perché sono dati di bilanciamento gameplay/percezione, non
# hardcoded nel nodo di rendering — stessa convenzione .tres delle altre *Rules del progetto,
# stesso schema di DifficultyRules (singola istanza, nessuna chiave per-tipo, a differenza di
# ResourceGrowthRules/NaturalEventRules che sono invece keyed per WorldObjectType/NaturalEventType).
# Ordine crescente per design (detail < resource < terrain — il tipo di terreno si dimentica più
# lentamente delle risorse, che a loro volta durano più delle posizioni esatte/entità in
# movimento): non imposto qui via codice, responsabilità di chi tara questo file .tres.
@export var detail_memory_days: int = 10
@export var resource_memory_days: int = 30
@export var terrain_memory_days: int = 90

# Ogni quanti giorni GameScene esegue la pulizia periodica di FogOfWarMemory.last_seen_by_
# position (vedi GameScene._maybe_prune_fog_of_war_memories/FogOfWarMemory.prune_stale) —
# scollegato di proposito dal checkpoint stagionale di WorldTimeService (dominio diverso: quello
# itera l'intero mondo, questo solo le macrocelle mai visitate dal player in questa partita,
# quindi non ha bisogno della stessa cadenza né dello stesso "posto" nel codice). Valore di
# partenza non ancora misurato con un vero profiling — vedi la discussione con l'utente sul
# perché 21 e non un numero legato alle stagioni.
@export var prune_interval_days: int = 21
