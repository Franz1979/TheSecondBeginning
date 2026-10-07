class_name JobBoardService
extends RefCounted

# Lista dei lavori (2026-10-07, richiesta utente — assegnazione compiti, passo A): i lavori senza nessuno assegnato
# (nessuna task in corso o in coda) compaiono nella sezione "In lista" del cassetto dell'assegnazione, "attivi"
# (disponibili per chiunque) o "bloccati" (fermi finché il giocatore non li sblocca). Vale solo con l'idea
# TaskAssignmentPanel.REQUIRED_IDEA_ID completata. La scheda "In sospeso" dell'info panel non dipende da questo stato.
#
# Stato in un punto unico, GameData.job_board_states (salvato), con le chiavi della scheda "In sospeso" ("build:<id>",
# in futuro "upgrade:", "demolish:", "produce:", "body:"). Oggi il solo tipo gestito è il cantiere di un edificio nuovo
# ("build"), dal 2026-10-07 il cantiere di un miglioramento ("upgrade", stesse regole: è un cantiere normale) e
# l'edificio "da demolire" senza demolitore ("demolish", fuori lista finché è aperto il suo mirino): un tipo
# nuovo si aggiunge a DEFAULT_STATE_BY_KIND (e a SKILL_KEY_BY_KIND per il punteggio).
#
# Passo B (2026-10-07): un pipottino libero prende da solo il lavoro attivo più adatto (try_take_job), chiamato SOLO da
# HumanIndividualActionService.resolve_idle_individual tra una task e l'altra — dopo bisogni, coda personale e
# rilascio del carico, prima delle attività di ripiego — mai durante una task o un'attività di ripiego. La scelta e
# l'assegnazione (stessa funzione dell'assegnazione a mano) le fa GameScene, che registra qui `job_taker`; il punteggio
# è score_job. Stateless, funzioni statiche (job_taker è l'unico dato, un aggancio, mai salvato).

# Attesa per l'assegnazione a mano (2026-10-07, richiesta utente): secondi reali (uguali a ogni velocità, fermi in pausa)
# dopo l'ingresso di un lavoro in lista (nato senza lavoratore o tornato in lista) durante i quali nessuno può prenderlo
# dalla lista; l'assegnazione a mano resta sempre possibile. 0 = nessuna attesa. Il conto lo tiene GameScene, mai salvato.
# Valore iniziale: dal 2026-10-07 il giocatore lo sceglie nelle impostazioni del cassetto (UserOptions.
# job_board_manual_assign_seconds, tra MIN e MAX); leggere sempre get_manual_assign_window_seconds().
const MANUAL_ASSIGN_WINDOW_SECONDS := 5.0
const MANUAL_ASSIGN_WINDOW_MIN_SECONDS := 0.0
const MANUAL_ASSIGN_WINDOW_MAX_SECONDS := 30.0

const STATE_LISTED := "listed"
const STATE_LOCKED := "locked"
# Tipi di lavoro gestiti dalla lista -> stato iniziale (chiave assente in GameData.job_board_states).
# "body" (2026-10-07): corpi da seppellire; "pile" (2026-10-07): mucchi a terra abbandonati.
const DEFAULT_STATE_BY_KIND := {"build": STATE_LISTED, "upgrade": STATE_LISTED, "demolish": STATE_LISTED, "body": STATE_LISTED, "pile": STATE_LISTED}
# Tipo di lavoro -> chiave di SkillEffectService (skill_action_effects.tres) del suo fattore di skill nel punteggio.
const SKILL_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "build", "body": RiteAction.SKILL_EFFECT_KEY, "pile": "pickup"}
# Tipo di lavoro -> icona di comando (IconRegistry) che lampeggia sull'edificio durante l'attesa per l'assegnazione a mano.
const ICON_KEY_BY_KIND := {"build": "build", "upgrade": "build", "demolish": "demolish", "body": "bury", "pile": "pickup"}
# Stesso scarto della distanza della scelta delle zone di lavoro (HaulZoneService).
const SCORE_DISTANCE_OFFSET: float = HaulZoneService.ZONE_DISTANCE_OFFSET

# Callable(individual: HumanIndividual) -> bool, registrato da GameScene: guarda la lista e prova a far prendere a
# `individual` il lavoro più adatto; true = preso (ha una task nuova). Non valido fuori dalla scena di gioco.
static var job_taker: Callable = Callable()


# Attesa per l'assegnazione a mano in uso: l'impostazione del giocatore (UserOptions), nei limiti; mai scelta = il valore
# iniziale MANUAL_ASSIGN_WINDOW_SECONDS.
static func get_manual_assign_window_seconds() -> float:
	if UserOptions.job_board_manual_assign_seconds < 0:
		return MANUAL_ASSIGN_WINDOW_SECONDS
	return clampf(float(UserOptions.job_board_manual_assign_seconds), MANUAL_ASSIGN_WINDOW_MIN_SECONDS, MANUAL_ASSIGN_WINDOW_MAX_SECONDS)


# true con l'idea dell'assegnazione completata dal popolo del giocatore.
static func is_enabled(folk: Folk) -> bool:
	return folk != null and folk.completed_ideas.has(TaskAssignmentPanel.REQUIRED_IDEA_ID)


# Tipo del lavoro dalla chiave ("build:12" -> "build").
static func get_kind(job_key: String) -> String:
	return job_key.get_slice(":", 0)


# true se il tipo del lavoro passa dalla lista.
static func is_managed(job_key: String) -> bool:
	return DEFAULT_STATE_BY_KIND.has(get_kind(job_key))


static func get_state(game_data: GameData, job_key: String) -> String:
	var default_state := String(DEFAULT_STATE_BY_KIND.get(get_kind(job_key), STATE_LOCKED))
	if game_data == null:
		return default_state
	var state := String(game_data.job_board_states.get(job_key, default_state))
	# "suspended" e "paused" = nomi di prima di "bloccato" (stesso giorno), letti come bloccato.
	return STATE_LOCKED if state == "suspended" or state == "paused" else state


static func set_state(game_data: GameData, job_key: String, state: String) -> void:
	if game_data == null or not is_managed(job_key):
		return
	game_data.job_board_states[job_key] = state


# Punteggio di un lavoro per `individual` (più alto = più adatto): fattore della skill del tipo di lavoro
# (SkillEffectService.get_factor, 1.0 se il tipo non ne ha) diviso (distanza + SCORE_DISTANCE_OFFSET). `job_macro_coords`
# e `job_microcell` = dove si fa il lavoro; la distanza è quella delle zone di lavoro (posizione dell'individuo, locale
# alla sua macrocella di casa, e scostamento HaulZoneService.macro_offset_for della macrocella del lavoro).
static func score_job(individual: HumanIndividual, job_kind: String, job_macro_coords: Vector2i, job_microcell: Vector2i) -> float:
	var skill_key := String(SKILL_KEY_BY_KIND.get(job_kind, ""))
	var skill_factor := SkillEffectService.get_factor(skill_key, individual) if skill_key != "" else 1.0
	var job_position := Vector2(job_microcell) + Vector2(0.5, 0.5) + HaulZoneService.macro_offset_for(individual, job_macro_coords)
	return skill_factor / (individual.position.distance_to(job_position) + SCORE_DISTANCE_OFFSET)


# Punto d'ingresso di resolve_idle_individual: true se `individual` ha preso un lavoro dalla lista.
static func try_take_job(individual: HumanIndividual) -> bool:
	if individual == null or not job_taker.is_valid():
		return false
	return bool(job_taker.call(individual))


# Toglie le voci dei lavori che non esistono più (`existing_keys`: chiave -> true dei lavori ancora da fare, assegnati
# o no). Un lavoro che qualcuno sta facendo resta, così se viene abbandonato torna dov'era.
static func forget_missing(game_data: GameData, existing_keys: Dictionary) -> void:
	if game_data == null:
		return
	for job_key in game_data.job_board_states.keys():
		if not existing_keys.has(job_key):
			game_data.job_board_states.erase(job_key)
