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


# Giorni di memoria di ogni tier per questo popolo (2026-11-03, richiesta utente — con Insegnamento
# orale si scorda più tardi): i giorni di FogOfWarRules per i moltiplicatori delle idee completate.
# Unico punto da cui leggerli. Se la risorsa manca, stessi fallback di FogOfWarRenderer; folk null =
# nessuna idea.
static func get_detail_memory_days(folk: Folk) -> int:
	var rules := get_fog_of_war_rules()
	if rules == null:
		return 10
	return _apply_idea_multipliers(rules.detail_memory_days, rules.detail_memory_multiplier_by_idea, folk)


static func get_resource_memory_days(folk: Folk) -> int:
	var rules := get_fog_of_war_rules()
	if rules == null:
		return 30
	return _apply_idea_multipliers(rules.resource_memory_days, rules.resource_memory_multiplier_by_idea, folk)


static func get_terrain_memory_days(folk: Folk) -> int:
	var rules := get_fog_of_war_rules()
	if rules == null:
		return 90
	return _apply_idea_multipliers(rules.terrain_memory_days, rules.terrain_memory_multiplier_by_idea, folk)


static func _apply_idea_multipliers(base_days: int, multiplier_by_idea: Dictionary, folk: Folk) -> int:
	if folk == null:
		return base_days
	var multiplier := 1.0
	for idea_id in multiplier_by_idea:
		if folk.completed_ideas.has(idea_id):
			multiplier *= float(multiplier_by_idea[idea_id])
	return roundi(base_days * multiplier)


# "Quanto arriva a ricordare oggi, nel complesso, la percezione del player" — pensata per il
# pruning di FogOfWarMemory.last_seen_by_position (prossimo step): la soglia oltre cui un'entry è
# sicuramente troppo vecchia per QUALUNQUE dei tre tier attuali, non il tetto teorico massimo mai
# raggiungibile in futuro (deciso esplicitamente con l'utente: una scheda di memoria più grande
# non deve "resuscitare" foto già cancellate — vedi la discussione sul pruning). Il massimo di solito
# coincide con il tier del terreno (il più alto dei tre per design) — ma è una funzione DERIVATA
# apposta, non un alias diretto: ogni chiamante che ha bisogno di "il massimo oggi conosciuto" deve
# passare da qui.
static func get_max_known_memory_days(folk: Folk) -> int:
	return max(get_detail_memory_days(folk), max(get_resource_memory_days(folk), get_terrain_memory_days(folk)))
