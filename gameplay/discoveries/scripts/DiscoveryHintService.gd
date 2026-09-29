class_name DiscoveryHintService
extends RefCounted

# Scoperte (2026-09-28, richiesta utente) — stateless (static func), stesso pattern di RandomEventService: carica i
# DiscoveryHintRules di DATA_DIR per scansione e risponde a "(trigger, dati) -> scoperte corrispondenti non ancora
# viste". Non mostra nulla e non segna nulla da sé: popup e mark_seen li decide GameScene.

const DATA_DIR := "res://gameplay/discoveries/data/"

# Scoperta equivalente al vecchio GameData.thought_building_tech_tree_shown (vedi GameLoadService): un save con quel
# bool a true la riceve già come vista.
const LEGACY_THOUGHT_BUILDING_HINT_ID := "first_thought_building"

# Cache statica: i .tres sono immutabili per tutta la sessione.
static var _rules_cache: Array[DiscoveryHintRules] = []
static var _rules_loaded: bool = false


static func list_rules() -> Array[DiscoveryHintRules]:
	if _rules_loaded:
		return _rules_cache
	_rules_loaded = true
	_rules_cache.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("DiscoveryHintService: cartella %s non trovata." % DATA_DIR)
		return _rules_cache
	for file_name in dir.get_files():
		# Nei progetti esportati le risorse testuali possono comparire come "*.tres.remap".
		var resource_file := String(file_name).trim_suffix(".remap")
		if resource_file.get_extension() != "tres":
			continue
		var rules := load(DATA_DIR + resource_file) as DiscoveryHintRules
		if rules == null or rules.id == "":
			push_error("DiscoveryHintService: %s non è un DiscoveryHintRules valido." % resource_file)
			continue
		_rules_cache.append(rules)
	# Ordine stabile per id: le sezioni di un popup multiplo escono sempre nello stesso ordine.
	_rules_cache.sort_custom(func(a: DiscoveryHintRules, b: DiscoveryHintRules) -> bool: return a.id < b.id)
	return _rules_cache


# Scoperte che corrispondono al trigger e non sono ancora in game_data.seen_discovery_hints.
static func find_unseen(game_data: GameData, trigger: DiscoveryTypes.TriggerType, data: Dictionary) -> Array[DiscoveryHintRules]:
	var result: Array[DiscoveryHintRules] = []
	for rules in list_rules():
		if game_data != null and game_data.seen_discovery_hints.has(rules.id):
			continue
		if rules.matches(trigger, data):
			result.append(rules)
	return result


static func mark_seen(game_data: GameData, hint_id: String) -> void:
	if game_data != null and not game_data.seen_discovery_hints.has(hint_id):
		game_data.seen_discovery_hints.append(hint_id)
