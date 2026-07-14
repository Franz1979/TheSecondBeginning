class_name NaturalEventCalculator
extends RefCounted

const EVENT_RULES_DIR := "res://data/natural_events/"


static func get_event_rules(event_type: GameTypes.NaturalEventType) -> NaturalEventRules:
	var type_name: String = GameTypes.NaturalEventType.keys()[event_type].to_lower()
	var path := EVENT_RULES_DIR + type_name + "_event.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as NaturalEventRules
