class_name LedAnimalService
extends RefCounted

# Animali condotti con la cavezza (2026-11-18, richiesta utente — "Conduci al recinto"): dal momento in cui la persona mette
# la cavezza (PutHalterAction) a quando l'animale entra nel recinto (KeepAnimalAction), l'animale è un record in
# GameData.led_animals, salvato: {"id", "entry" (voce KeptAnimalService.make_entry con "led" e "led_id"), "catch_day",
# "holder_id" (chi lo tiene, -1 = legato), "macro_x", "macro_y", "x", "y" (dove sta: posizione di chi lo tiene, o dove è
# stato legato)}.
#
# Regola (richiesta utente): se chi lo conduce si ferma per qualunque motivo (bisogno, pericolo, crollo, morte, Blocca),
# l'animale resta LEGATO lì dov'è, con la cavezza addosso; il lavoro "Conduci" ricompare e parte da lì, senza un'altra
# cavezza. Legato non mangia: passati i giorni senza cibo della specie dalla cattura muore e resta una carcassa lì.
#
# Fuga (2026-11-18, richiesta utente): mentre è in mano a qualcuno, a ogni ora di cammino può scappare
# (DomesticAnimalRules.lead_escape_chance_per_hour, divisa per il fattore Allevamento di chi lo conduce; legato no). Se
# scappa: il record si toglie (il posto nel recinto si libera), la cavezza in cintura è persa, l'animale torna nella mandria
# della zona se c'è (sennò è perso), il lavoro si ferma, avviso e statistiche. Prossimo tiro nel record
# ("next_escape_check", giorno di gioco). Stateless, statico (salvo gli id appena scappati, solo per il disegno).
#
# Domestici dal recinto alla stalla (2026-11-19): voce con "animal_id" (il DomesticAnimal resta del recinto, carried_by =
# chi lo tiene, fino all'arrivo). Legato: i giorni senza cibo contano da quando è legato ("catch_day" spostato lì). Fuga
# con lead_escape_chance_per_hour_domestic: l'animale si toglie e si inselvatichisce (nella mandria se c'è).

const ESCAPE_CHECK_DAYS: float = 1.0 / 24.0
# Al massimo tante ore recuperate in un giro (gioco molto accelerato).
const ESCAPE_MAX_CHECKS: int = 24

# Appena scappati (led_id -> true): LedAnimalBodyService li fa correre via. Non salvato.
static var _escaped: Dictionary = {}


# Nuovo animale condotto da `individual` (cavezza appena messa): il record, e "led_id" nella voce.
static func start(game_data: GameData, entry: Dictionary, individual: HumanIndividual) -> Dictionary:
	var record := {
		"id": game_data.next_led_animal_id, "entry": entry, "catch_day": int(entry.get("catch_day", game_data.get_absolute_day())),
		"holder_id": individual.id, "macro_x": 0, "macro_y": 0, "x": 0.0, "y": 0.0,
	}
	game_data.next_led_animal_id += 1
	entry["led_id"] = record["id"]
	_follow(record, individual)
	game_data.led_animals.append(record)
	return record


static func find(game_data: GameData, led_id: int) -> Dictionary:
	if game_data == null:
		return {}
	for record in game_data.led_animals:
		if int(record["id"]) == led_id:
			return record
	return {}


# L'animale è uscito dalle mani: entrato nel recinto o macellato.
static func finish(game_data: GameData, led_id: int) -> void:
	for i in range(game_data.led_animals.size()):
		if int(game_data.led_animals[i]["id"]) == led_id:
			game_data.led_animals.remove_at(i)
			return


# true se l'animale `led_id` è davvero nelle mani di `individual` adesso.
static func is_held_by(game_data: GameData, led_id: int, individual: HumanIndividual) -> bool:
	var record := find(game_data, led_id)
	return not record.is_empty() and individual != null and int(record["holder_id"]) == individual.id


# Animali legati (nessuno li tiene).
static func tied(game_data: GameData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if game_data == null:
		return result
	for record in game_data.led_animals:
		if int(record["holder_id"]) < 0:
			result.append(record)
	return result


# Voci degli animali legati: posti prenotati per KeptAnimalService.reservations (quelli tenuti li conta già la loro tappa).
static func tied_entries(game_data: GameData) -> Array:
	var entries: Array = []
	for record in tied(game_data):
		entries.append(record["entry"])
	return entries


# Riprende un animale legato (PutHalterAction): ora lo tiene `individual`.
static func take(game_data: GameData, led_id: int, individual: HumanIndividual) -> Dictionary:
	var record := find(game_data, led_id)
	if record.is_empty() or int(record["holder_id"]) >= 0:
		return {}
	record["holder_id"] = individual.id
	_follow(record, individual)
	return record


# Punto dell'animale legato nelle coordinate di `individual`.
static func walk_point(individual: HumanIndividual, record: Dictionary) -> Vector2:
	var macro := Vector2i(int(record["macro_x"]), int(record["macro_y"]))
	return Vector2(float(record["x"]), float(record["y"])) + Vector2(macro - individual.home_macro_coords) * World.WIDTH


# Ogni secondo di gioco (GameSimulation.tick_second): chi tiene un animale e non sta più facendo la tappa che lo porta al
# recinto (compito fermato, sospeso, scartato, persona morta) lo lega lì dov'è. Gli altri: la posizione segue la persona.
static func settle(ctx: GameContext, effects: GameEffects, now: float) -> void:
	if ctx.game_data == null or ctx.game_data.led_animals.is_empty():
		return
	var by_id := {}
	for member in ctx.individuals:
		by_id[member.id] = member
	var escapes: Array = []
	for record in ctx.game_data.led_animals:
		var holder_id := int(record["holder_id"])
		if holder_id < 0:
			continue
		var holder: HumanIndividual = by_id.get(holder_id)
		if holder != null and _is_leading(holder, int(record["id"])):
			_follow(record, holder)
			if _rolls_escape(record, holder, now):
				escapes.append([record, holder])
			continue
		record.erase("next_escape_check")
		# Domestico (2026-11-19): la fame da legato conta da adesso.
		if Dictionary(record["entry"]).has("animal_id"):
			record["catch_day"] = ctx.game_data.get_absolute_day()
		if holder != null:
			_follow(record, holder)
			_drop_queued_lead_tasks(holder, int(record["id"]))
		record["holder_id"] = -1
		TrapService.log_line("%s condotto da #%d legato in %s (%.1f, %.1f): il lavoro si è fermato" % [
			record["entry"].get("wild_species", "?"), holder_id, Vector2i(int(record["macro_x"]), int(record["macro_y"])),
			float(record["x"]), float(record["y"])])
		effects.refresh_pending()
	for escape in escapes:
		_escape(ctx, effects, escape[0], escape[1])


# true se l'animale `led_id` è appena scappato (una volta sola): il disegno lo fa correre via.
static func take_escaped(led_id: int) -> bool:
	return _escaped.erase(led_id)


# Un tiro per ogni ora di cammino passata dall'ultimo (al primo giro: si comincia a contare ora).
static func _rolls_escape(record: Dictionary, holder: HumanIndividual, now: float) -> bool:
	var next := float(record.get("next_escape_check", -1.0))
	if next < 0.0:
		record["next_escape_check"] = now + ESCAPE_CHECK_DAYS
		return false
	if now < next:
		return false
	var checks := mini(int((now - next) / ESCAPE_CHECK_DAYS) + 1, ESCAPE_MAX_CHECKS)
	record["next_escape_check"] = next + ESCAPE_CHECK_DAYS * float(int((now - next) / ESCAPE_CHECK_DAYS) + 1)
	var entry: Dictionary = record["entry"]
	var rules := DomesticAnimalCalculator.get_rules(String(entry.get("species", "")))
	if rules == null:
		return false
	var base := rules.lead_escape_chance_per_hour_domestic if entry.has("animal_id") else rules.lead_escape_chance_per_hour
	if base <= 0.0:
		return false
	var chance := base / SkillEffectService.get_factor(DomesticTransferService.SKILL_EFFECT_KEY, holder)
	for i in range(checks):
		if randf() < chance:
			return true
	return false


# L'animale scappa dalle mani di `holder`: via il record, cavezza persa, nella mandria se c'è, lavoro fermo, avviso.
static func _escape(ctx: GameContext, effects: GameEffects, record: Dictionary, holder: HumanIndividual) -> void:
	var game_data := ctx.game_data
	finish(game_data, int(record["id"]))
	_escaped[int(record["id"])] = true
	var entry: Dictionary = record["entry"]
	var wild_species := String(entry.get("wild_species", ""))
	var macro := Vector2i(int(record["macro_x"]), int(record["macro_y"]))
	var to_herd := WildFaunaService.has_herd_in_region(game_data, wild_species, macro) and WildFaunaService.release_animals(
		ctx.world, game_data, wild_species, macro, 1, int(entry.get("age_band", GameTypes.AgeBand.ADULT))) > 0
	# Domestico (2026-11-19): esce dagli animali del villaggio, si inselvatichisce.
	var domestic := _domestic_of(game_data, entry)
	if domestic != null:
		game_data.domestic_animals.erase(domestic)
	var slot := ToolGateService.find_belt_slot_for(holder, TaskTypes.ToolCategory.LEADING)
	var halter_lost := slot >= 0 and holder.lose_equipped_tool(slot, game_data)
	if not entry.has("animal_id"):
		HuntTrapStatsService.add_trap_outcome(game_data, String(entry.get("trap_name", "")), wild_species,
			HuntTrapStatsService.TRAP_ESCAPED)
	TrapService.log_line("#%d %s: %s scappato in %s (%.1f, %.1f)%s, %s" % [holder.id, holder.name, wild_species, macro,
		float(record["x"]), float(record["y"]), " con la cavezza" if halter_lost else "",
		"tornato nella mandria" if to_herd else "perso (nessuna mandria)"])
	var notice_key := "notification_led_animal_escaped_stable" if entry.has("animal_id") else "notification_led_animal_escaped"
	effects.notify(NotificationTypes.NotificationPopupType.WILD_ANIMAL_GROUP_NEWS,
		GameContext.tr_text(notice_key).format({
			"species": KeptAnimalService.species_display_name(String(entry.get("species", "")), not entry.has("animal_id")),
		}))
	if LeadAnimalJobProvider.is_lead_task(holder.current_task):
		TaskCancelService.stop_current_task(ctx, holder, effects, "l'animale condotto è scappato")
	effects.refresh_pending()


# Ogni giorno: un animale legato oltre i giorni senza cibo della sua specie (dalla cattura) muore lì; la carcassa resta.
static func advance_daily(game_data: GameData) -> void:
	if game_data == null:
		return
	var day := game_data.get_absolute_day()
	for i in range(game_data.led_animals.size() - 1, -1, -1):
		var record: Dictionary = game_data.led_animals[i]
		if int(record["holder_id"]) >= 0:
			continue
		var entry: Dictionary = record["entry"]
		var wild_species := String(entry.get("wild_species", ""))
		if day - int(record["catch_day"]) < TrapService.survival_days_for(wild_species):
			continue
		var macro := Vector2i(int(record["macro_x"]), int(record["macro_y"]))
		var domestic := _domestic_of(game_data, entry)
		if domestic != null:
			# Domestico (2026-11-19): la carcassa è sua, lì dov'era legato.
			domestic.building_id = -1
			domestic.carried_by = -1
			domestic.macro_coords = macro
			domestic.position = Vector2(float(record["x"]), float(record["y"]))
			DomesticAnimalSlaughterService.kill(game_data, domestic)
		else:
			GroundPileService.drop_carcass(game_data, macro, Vector2(float(record["x"]), float(record["y"])), wild_species,
				int(entry.get("age_band", GameTypes.AgeBand.ADULT)))
		TrapService.log_line("%s legato in %s morto di fame: carcassa lì" % [wild_species, macro])
		game_data.led_animals.remove_at(i)


# Il DomesticAnimal di una voce dal recinto ("animal_id"), null per i selvatici dell'imbuto.
static func _domestic_of(game_data: GameData, entry: Dictionary) -> DomesticAnimal:
	if not entry.has("animal_id"):
		return null
	return DomesticAnimalService.find_animal(game_data, int(entry["animal_id"]))


# true se `holder` sta facendo ora il compito che porta l'animale `led_id` (una sua tappa KeepAnimalAction da fare).
static func _is_leading(holder: HumanIndividual, led_id: int) -> bool:
	var task := holder.current_task
	if task == null or task.is_finished():
		return false
	for i in range(task.current_step_index, task.steps.size()):
		var step := task.steps[i]
		if not step is KeepAnimalAction:
			continue
		for entry in (step as KeepAnimalAction).entries:
			if int(Dictionary(entry).get("led_id", -1)) == led_id:
				return true
	return false


# Compito "Conduci" sospeso in coda per un bisogno con l'animale `led_id`: l'animale ora è legato, il compito si toglie
# (il lavoro ricompare nella lista e parte dall'animale legato).
static func _drop_queued_lead_tasks(holder: HumanIndividual, led_id: int) -> void:
	for queued in holder.task_queue.duplicate():
		var task: Task = queued
		if not LeadAnimalJobProvider.is_lead_task(task):
			continue
		for i in range(task.current_step_index, task.steps.size()):
			var step: Action = task.steps[i]
			if step is KeepAnimalAction and (step as KeepAnimalAction).entries.any(
					func(entry: Variant) -> bool: return int(Dictionary(entry).get("led_id", -1)) == led_id):
				holder.task_queue.erase(task)
				break


# Frazione del passo di `individual` (HumanIndividualMovementService): quella della specie se tiene un animale, 1 altrimenti.
static func lead_speed_scale(individual: HumanIndividual) -> float:
	var game_data: GameData = GameSettings.active_game_data
	if game_data == null or game_data.led_animals.is_empty():
		return 1.0
	for record in game_data.led_animals:
		if int(record["holder_id"]) == individual.id:
			var rules := DomesticAnimalCalculator.get_rules(String(Dictionary(record["entry"]).get("species", "")))
			return rules.lead_speed_scale if rules != null else 1.0
	return 1.0


# Macrocella vera in cui sta `individual` (la sua posizione può uscire dalla macrocella di casa).
static func real_macro(individual: HumanIndividual) -> Vector2i:
	return individual.home_macro_coords + _cell_offset(individual)


# Posizione di `individual` nelle coordinate della sua macrocella vera.
static func real_local(individual: HumanIndividual) -> Vector2:
	return individual.position - Vector2(_cell_offset(individual)) * Vector2(World.WIDTH, World.HEIGHT)


static func _cell_offset(individual: HumanIndividual) -> Vector2i:
	return Vector2i(floori(individual.position.x / World.WIDTH), floori(individual.position.y / World.HEIGHT))


# Posizione del record = quella di `individual`, in coordinate della sua macrocella vera.
static func _follow(record: Dictionary, individual: HumanIndividual) -> void:
	var macro := real_macro(individual)
	var local := real_local(individual)
	record["macro_x"] = macro.x
	record["macro_y"] = macro.y
	record["x"] = local.x
	record["y"] = local.y
