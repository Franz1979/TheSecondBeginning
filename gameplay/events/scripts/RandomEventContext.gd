class_name RandomEventContext
extends RefCounted

# Tutto quello che un evento casuale può leggere o modificare quando viene applicato (2026-09-26, richiesta
# utente — sistema di eventi casuali). Costruito da GameTimeService (_build_random_event_context), che possiede
# lo stato della simulazione; passato a RandomEvent.apply/get_popup_text.

var rules: RandomEventRules = null
var game_data: GameData = null
var world: World = null
var human_individuals: Array[HumanIndividual] = []
var human_folk: Folk = null
# Parametri decisi al sorteggio e salvati con l'evento programmato (vuoti per un evento scatenato a mano).
var params: Dictionary = {}


# Contesto dei servizi di gioco con gli stessi riferimenti (2026-10-25, SicknessService.on_bedridden). Senza celle vive.
func game_context() -> GameContext:
	var ctx := GameContext.new()
	ctx.game_data = game_data
	ctx.world = world
	ctx.individuals = human_individuals
	ctx.folk = human_folk
	return ctx
