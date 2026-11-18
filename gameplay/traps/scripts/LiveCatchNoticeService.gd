class_name LiveCatchNoticeService
extends RefCounted

# Avviso delle prede vive macellate per mancanza di posto (2026-11-18, richiesta utente — il cesto a caduta si piazza anche
# senza tettoia delle gabbie). Chi svuota una trappola a cattura viva (TrapService.take_live_catches) o arriva alla tettoia
# senza più posto (KeepAnimalAction) registra qui l'animale macellato; una volta al giorno (GameSimulation, tick del
# giorno) esce UNA notifica con i numeri sommati di tutte le trappole. Solo per le specie non ancora addomesticate: dopo,
# la tettoia su "Nessuna" è una scelta e il macello è voluto. Vale per qualunque motivo (nessuna tettoia, piena, su
# un'altra specie, su "Nessuna"). Stato in GameData.live_catch_slaughtered_today (non salvato). Stateless, statico.


# Un animale vivo di `wild_species` (specie domestica d'arrivo `species`) macellato perché nessun `building_type` aveva posto.
static func record(game_data: GameData, wild_species: String, species: String,
		building_type: String = TrapService.LIVE_CATCH_BUILDING_TYPE) -> void:
	if game_data == null or wild_species == "" or DomesticAnimalService.is_domesticated(game_data, species):
		return
	var by_species: Dictionary = game_data.live_catch_slaughtered_today.get(building_type, {})
	by_species[wild_species] = int(by_species.get(wild_species, 0)) + 1
	game_data.live_catch_slaughtered_today[building_type] = by_species


# Una volta al giorno: una notifica per tipo di edificio mancante, poi si riparte da zero.
static func flush_daily(ctx: GameContext, effects: GameEffects) -> void:
	var game_data := ctx.game_data
	if game_data == null or game_data.live_catch_slaughtered_today.is_empty():
		return
	for building_type in game_data.live_catch_slaughtered_today:
		var by_species: Dictionary = game_data.live_catch_slaughtered_today[building_type]
		var parts: Array[String] = []
		for wild_species in by_species:
			parts.append("%s ×%d" % [GameContext.tr_text("animal_species_" + String(wild_species)), int(by_species[wild_species])])
		if parts.is_empty() or effects == null:
			continue
		var building_name := GameContext.tr_text("building_" + String(building_type))
		effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
			GameContext.tr_text("notification_live_catch_slaughtered").format({
				"list": ", ".join(parts), "building": building_name,
			}))
	game_data.live_catch_slaughtered_today.clear()
