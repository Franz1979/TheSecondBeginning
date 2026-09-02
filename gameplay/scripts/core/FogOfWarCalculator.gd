class_name FogOfWarCalculator
extends RefCounted

const FOG_OF_WAR_RULES_PATH := "res://gameplay/data/fog_of_war/fog_of_war_rules.tres"

# Cache statica come ResourceCalculator._density_rules_cache/_growth_rules_cache: qui non serve
# un Dictionary keyed per tipo (FogOfWarRules è una singola istanza globale, stesso schema di
# DifficultyRules/DifficultyCalculator), ma il caricamento va comunque cacheato — get_fog_of_war_
# rules() viene chiamato da FogOfWarRenderer.setup(), una volta per ogni cella viva attivata (vedi
# GameScene._activate_live_cell — con lo streaming multi-cella possono essercene diverse vive
# contemporaneamente), non solo una volta per sessione.
# _rules_loaded distingue "non ancora tentato" da "tentato, risorsa assente" (in quel caso
# _rules_cache resta null legittimamente, non va ritentato il load ad ogni chiamata).
static var _rules_cache: FogOfWarRules = null
static var _rules_loaded := false


static func get_fog_of_war_rules() -> FogOfWarRules:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	if ResourceLoader.exists(FOG_OF_WAR_RULES_PATH):
		_rules_cache = load(FOG_OF_WAR_RULES_PATH) as FogOfWarRules
	return _rules_cache


# "Quanto arriva a ricordare oggi, nel complesso, la percezione del player" — pensata per il
# pruning di FogOfWarMemory.last_seen_by_position (prossimo step): la soglia oltre cui un'entry è
# sicuramente troppo vecchia per QUALUNQUE dei tre tier attuali, non il tetto teorico massimo mai
# raggiungibile in futuro (deciso esplicitamente con l'utente: una scheda di memoria più grande
# non deve "resuscitare" foto già cancellate — vedi la discussione sul pruning). Oggi ha una sola
# fonte (le tre soglie di FogOfWarRules), quindi il massimo coincide sempre con terrain_memory_days
# (il più alto dei tre per design) — ma è una funzione DERIVATA apposta, non un alias diretto di
# terrain_memory_days: ogni chiamante che ha bisogno di "il massimo oggi conosciuto" deve passare
# da qui, mai leggere terrain_memory_days direttamente, proprio per il motivo sotto.
#
# TODO evoluzione stadio_di_memorizzazione: nessun secondo stadio di percezione/memorizzazione
# esiste ancora (nessuna tech/popolazione che allunga la memoria oltre FogOfWarRules) — quando ne
# verrà progettato uno (vedi conversazione 2026-08-29/30 su un futuro PopulationRules/enum di
# tier in GameTypes, mai implementato), il suo contributo va sommato/moltiplicato QUI dentro,
# in un solo punto, non propagato a mano in ogni chiamante.
static func get_max_known_memory_days() -> int:
	var rules := get_fog_of_war_rules()
	if rules == null:
		return 90 # stesso fallback di FogOfWarRenderer.terrain_memory_days se la risorsa manca
	return max(rules.detail_memory_days, max(rules.resource_memory_days, rules.terrain_memory_days))
