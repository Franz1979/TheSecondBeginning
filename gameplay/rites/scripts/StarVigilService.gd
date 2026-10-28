class_name StarVigilService
extends RefCounted

# Veglia delle stelle (2026-10-29, richiesta utente — dati in StarVigilRiteRules, star_vigil.tres). Servizio senza stato,
# stato sull'edificio (Building.star_vigil_*, salvato). La veglia si celebra solo l'ultimo giorno di ogni stagione (il
# giorno prima del cambio). Passo 2a — calendario e annuncio:
#   - stagioni: la veglia si fa da sola nelle stagioni spuntate nel pannello (Building.star_vigil_seasons, tutte di
#     default), nessuna programmazione a mano (2026-10-29, richiesta utente);
#   - annuncio (on_day_advanced), convocation_days_before giorni prima: se la stagione è spuntata, il gioco sceglie chi
#     guida (pick_guide, la skill_ritual più alta tra chi può celebrare) e lo segna sull'edificio; nessuno smette di
#     lavorare. Stagione non spuntata o nessuna guida: la veglia salta (log; effetti della veglia saltata al passo 2c).
# Passo 2b — chiamata, inizio e fine (tick, dal giro al secondo GameSimulation.tick_second):
#   - chiamata, call_days_before_start giorni prima dell'inizio (3, insieme all'annuncio): il rito sociale parte con la
#     guida annunciata (o un'altra, se quella non può più) e tutto il villaggio lascia il lavoro e va al cerchio
#     (SocialRiteService.start; i neonati seguono la madre come sempre). Gli arrivi non fanno cominciare nulla;
#   - inizio, dall'alba del giorno della veglia per start_window_days (appena le condizioni ci sono): servono almeno min_village_adults abitanti nelle fasce counted_age_bands
#     (malati esclusi), almeno min_present_ratio di loro al cerchio e la guida al cerchio; se a fine finestra mancano ancora, la veglia salta;
#   - fine, feast_days dopo l'inizio vero (RECORD_START_KEY) (SocialRiteService.finish_scheduled -> on_finished).
# Tiro sul cielo ed effetti (sereno, coperto, saltata) arrivano al passo 2c. Mai nell'elenco dei riti ordinabili
# (RiteService.is_scheduled_only).

const RITE_ID := "star_vigil"
# Nel record del rito sociale: giorno assoluto della veglia.
const RECORD_VIGIL_DAY_KEY := "vigil_day"
# Nel record: momento (giorni, con la frazione) in cui la veglia è cominciata, per la fine dopo feast_days.
const RECORD_START_KEY := "vigil_start"

# Effetti verso la scena (2026-10-29, richiesta utente — suoni della veglia), impostati da GameScene:
# Callable(HumanIndividual): richiamo della guida alla chiamata (GameScene.star_vigil_called);
static var call_sound_emitter: Callable = Callable()
# Callable(Building): inizio della veglia, icona e coro (GameScene._spawn_social_rite_started_effect, start_sound_id).
static var start_effect_emitter: Callable = Callable()


static func log_event(text: String) -> void:
	SocialRiteService.log_event("veglia delle stelle: %s" % text)


static func get_rules() -> StarVigilRiteRules:
	return RiteService.get_rules(RITE_ID) as StarVigilRiteRules


# true se `building` può ospitare la veglia adesso (tipo nei building_types, completo e in servizio).
static func is_vigil_building(building: Building, rules: StarVigilRiteRules) -> bool:
	return rules != null and RiteService.is_building_usable(building) and rules.building_types.has(building.building_type_name)


# Giorno assoluto della prossima veglia: l'ultimo giorno della stagione in corso (oggi stesso, se è quel giorno).
static func get_next_vigil_day(game_data: GameData) -> int:
	var season := SeasonCalculator.get_season_for_day(game_data.current_day)
	return game_data.year * GameData.DAYS_PER_YEAR + SeasonCalculator.get_season_end_day(season)


static func get_days_until_vigil(game_data: GameData) -> int:
	return get_next_vigil_day(game_data) - game_data.get_absolute_day()


# Stagione in corso, la cui ultima giornata è la prossima veglia.
static func get_current_season(game_data: GameData) -> GameTypes.Season:
	return SeasonCalculator.get_season_for_day(game_data.current_day)


# true se la veglia di fine `season` si fa a `building` (spunta del pannello).
static func is_season_enabled(building: Building, season: int) -> bool:
	return building.star_vigil_seasons.has(season)


# Spunta o toglie `season` (pannello). Una veglia già annunciata per questa stagione resta.
static func set_season_enabled(building: Building, season: int, enabled: bool) -> void:
	if enabled and not building.star_vigil_seasons.has(season):
		building.star_vigil_seasons.append(season)
		building.star_vigil_seasons.sort()
	elif not enabled:
		building.star_vigil_seasons.erase(season)


# Chi guida: tra gli abitanti del villaggio dell'edificio che possono celebrare (RiteService.can_celebrate: età del rito,
# non malati, skill_ritual minima), quello con la skill_ritual più alta. null se nessuno.
static func pick_guide(building: Building, rules: StarVigilRiteRules, individuals: Array, game_data: GameData) -> HumanIndividual:
	var folk := GameSettings.active_human_folk
	var village: Village = folk.find_village(building.village_id) if folk != null else null
	var best: HumanIndividual = null
	for member in individuals:
		var individual := member as HumanIndividual
		if individual == null or (village != null and individual.village_ref != village):
			continue
		if not RiteService.can_celebrate(rules, individual, _age_band(individual, game_data)):
			continue
		if best == null or individual.skill_ritual > best.skill_ritual:
			best = individual
	return best


# Una volta al giorno (GameTimeService._on_day_advanced): pulizia dei giorni passati e annuncio.
static func on_day_advanced(world: World, game_data: GameData, individuals: Array) -> void:
	var rules := get_rules()
	if rules == null or world == null or game_data == null:
		return
	var today := game_data.get_absolute_day()
	var next_day := get_next_vigil_day(game_data)
	var season := get_current_season(game_data)
	for building in world.buildings:
		# Annuncio di un giorno passato senza che la veglia sia mai partita (cerchio occupato da un altro rito fino alla
		# fine): si chiude. Con la veglia ancora in corso resta, la chiude la sua fine (tick).
		if building.star_vigil_announced_day >= 0 and building.star_vigil_announced_day < today \
				and SocialRiteService.find_rite(game_data, building.id).is_empty():
			log_event("all'edificio #%d la veglia del giorno %d non è mai partita." % [building.id, building.star_vigil_announced_day])
			clear_announcement(building)
		if not is_vigil_building(building, rules):
			continue
		if next_day - today != rules.convocation_days_before or building.star_vigil_announced_day == next_day:
			continue
		if not is_season_enabled(building, season):
			log_event("all'edificio #%d salta la veglia del giorno %d: stagione non spuntata." % [building.id, next_day])
			continue
		var guide := pick_guide(building, rules, individuals, game_data)
		if guide == null:
			log_event("all'edificio #%d salta la veglia del giorno %d: nessuno può guidarla." % [building.id, next_day])
			continue
		building.star_vigil_announced_day = next_day
		building.star_vigil_guide_id = guide.id
		log_event("annunciata all'edificio #%d per il giorno %d, guida #%d %s (rito %d)." % [
			building.id, next_day, guide.id, guide.name, int(guide.skill_ritual)
		])


# Chiude l'annuncio di `building` (veglia finita, saltata o annullata).
static func clear_announcement(building: Building) -> void:
	building.star_vigil_announced_day = -1
	building.star_vigil_guide_id = -1


# Fase della veglia in corso a `building` (SocialRiteService.PHASE_*), "" se la chiamata non c'è stata.
static func get_active_phase(building: Building, game_data: GameData) -> String:
	var record := SocialRiteService.find_rite(game_data, building.id)
	if record.is_empty() or String(record.get("rite_id", "")) != RITE_ID:
		return ""
	return String(record.get("phase", ""))


# Giro al secondo (GameSimulation.tick_second): `now` è il momento di gioco in giorni, con la frazione del giorno.
static func tick(world: World, game_data: GameData, individuals: Array, now: float) -> void:
	var rules := get_rules()
	if rules == null or world == null or game_data == null:
		return
	var today := game_data.get_absolute_day()
	for building in world.buildings:
		var record := SocialRiteService.find_rite(game_data, building.id)
		if not record.is_empty():
			# Un altro rito al cerchio: la chiamata aspetta che finisca, purché prima del giorno della veglia.
			if String(record.get("rite_id", "")) == RITE_ID:
				_advance(record, building, rules, individuals, game_data, today, now)
			continue
		var vigil_day := building.star_vigil_announced_day
		if vigil_day < 0 or today >= vigil_day or now < float(vigil_day) - rules.call_days_before_start:
			continue
		if not is_vigil_building(building, rules):
			continue
		_call(building, rules, individuals, game_data, world, vigil_day)


# Chiamata: rito sociale con la guida e convocazione di tutto il villaggio.
static func _call(
	building: Building, rules: StarVigilRiteRules, individuals: Array, game_data: GameData, world: World, vigil_day: int
) -> void:
	var guide := _find(individuals, building.star_vigil_guide_id)
	if guide == null or not RiteService.can_celebrate(rules, guide, _age_band(guide, game_data)):
		var replacement := pick_guide(building, rules, individuals, game_data)
		if replacement == null:
			_skip_without_call(building, vigil_day, "nessuno può guidarla")
			return
		log_event("all'edificio #%d la guida #%d non può più, guida #%d %s (rito %d)." % [
			building.id, building.star_vigil_guide_id, replacement.id, replacement.name, int(replacement.skill_ritual)
		])
		guide = replacement
		building.star_vigil_guide_id = guide.id
	var rejection := SocialRiteService.start(guide, building, rules, individuals, game_data, world)
	if rejection != "":
		_skip_without_call(building, vigil_day, "chiamata non partita (%s)" % rejection)
		return
	SocialRiteService.find_rite(game_data, building.id)[RECORD_VIGIL_DAY_KEY] = vigil_day
	log_event("chiamata all'edificio #%d: il villaggio va al cerchio per la veglia del giorno %d, guida #%d %s." % [
		building.id, vigil_day, guide.id, guide.name
	])
	if call_sound_emitter.is_valid():
		call_sound_emitter.call(guide)


# Inizio all'alba del giorno della veglia (controllo dei presenti) e fine dopo feast_days.
static func _advance(
	record: Dictionary, building: Building, rules: StarVigilRiteRules, individuals: Array, game_data: GameData, today: int,
	now: float
) -> void:
	var vigil_day := int(record.get(RECORD_VIGIL_DAY_KEY, building.star_vigil_announced_day))
	var phase := String(record.get("phase", ""))
	if phase == SocialRiteService.PHASE_WAITING and today >= vigil_day:
		_try_begin(record, building, rules, individuals, game_data, vigil_day, now)
	elif phase == SocialRiteService.PHASE_FEASTING 			and now >= float(record.get(RECORD_START_KEY, float(vigil_day))) + rules.feast_days:
		SocialRiteService.finish_scheduled(building, individuals, game_data)


static func _try_begin(
	record: Dictionary, building: Building, rules: StarVigilRiteRules, individuals: Array, game_data: GameData, vigil_day: int,
	now: float
) -> void:
	var adults := 0
	var present := 0
	for member in SocialRiteService._village_members(building, individuals):
		if member.is_sick() or not rules.counted_age_bands.has(_age_band(member, game_data)):
			continue
		adults += 1
		if SocialRiteService.is_attending(member, building.id):
			present += 1
	var needed := ceili(rules.min_present_ratio * float(adults))
	var guide := _find(individuals, int(record.get("organizer_id", -1)))
	var reason := ""
	if adults < rules.min_village_adults:
		reason = "nel villaggio solo %d adulti, ne servono %d" % [adults, rules.min_village_adults]
	elif present < needed:
		reason = "al cerchio %d adulti su %d, ne servono %d" % [present, adults, needed]
	elif guide == null or not SocialRiteService.is_attending(guide, building.id):
		reason = "la guida #%d non è al cerchio (%s)" % [int(record.get("organizer_id", -1)), _activity_text(guide)]
	if reason != "":
		# Finestra d'inizio: finché è aperta si aspetta, senza log (il controllo gira ogni secondo).
		if now < float(vigil_day) + rules.start_window_days:
			return
		log_event("all'edificio #%d salta la veglia del giorno %d: %s." % [building.id, vigil_day, reason])
		# Le task del rito finiscono da sole (SocialRiteAttendAction vede il rito sparito).
		SocialRiteService.cancel(building, individuals, game_data, false)
		return
	SocialRiteService.begin_scheduled(building)
	record[RECORD_START_KEY] = now
	if start_effect_emitter.is_valid():
		start_effect_emitter.call(building)
	log_event("comincia all'edificio #%d: al cerchio %d adulti su %d, guida #%d %s." % [
		building.id, present, adults, guide.id, guide.name
	])


# Fine della veglia (SocialRiteService._finish, presenti già contati). Passo 2b: solo il log; tiro sul cielo ed effetti
# al passo 2c.
static func on_finished(
	record: Dictionary, building: Building, rules: StarVigilRiteRules, present: Array[HumanIndividual], individuals: Array,
	game_data: GameData
) -> void:
	log_event("finisce all'edificio #%d: %d presenti, guida #%d (esito del cielo non ancora in gioco)." % [
		building.id, present.size(), int(record.get("organizer_id", -1))
	])
	clear_announcement(building)


static func _skip_without_call(building: Building, vigil_day: int, reason: String) -> void:
	log_event("all'edificio #%d salta la veglia del giorno %d: %s." % [building.id, vigil_day, reason])
	clear_announcement(building)


# Cosa sta facendo `individual` (per il log della guida assente): la task in corso, "morta o sparita" se non c'è più.
static func _activity_text(individual: HumanIndividual) -> String:
	if individual == null:
		return "morta o sparita"
	var task := individual.current_task
	if task == null or task.is_finished():
		return "senza task"
	return "fa '%s'" % task.task_name


static func _age_band(individual: HumanIndividual, game_data: GameData) -> int:
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		individual.sex, float(game_data.year - individual.birth_year_virtual)
	)


static func _find(individuals: Array, individual_id: int) -> HumanIndividual:
	if individual_id < 0:
		return null
	for member in individuals:
		var individual := member as HumanIndividual
		if individual != null and individual.id == individual_id:
			return individual
	return null
