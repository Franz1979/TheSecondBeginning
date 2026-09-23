class_name ThinkAction
extends Action

# Terza sottoclasse concreta di Action, seconda con una vera DURATA (dopo Rest, che invece non
# completa mai da sola) — primo passo del futuro Daydream (2026-09-07, richiesta utente). A
# differenza di WalkAction (un bersaglio SPAZIALE, individual.position vs target) e di RestAction
# (nessun completamento, stato implicito), ThinkAction ha un bersaglio TEMPORALE: un accumulatore
# di tempo trascorso (_elapsed sotto, stesso principio di _last_position in WalkAction — stato
# privato dell'istanza, mai su HumanIndividual) confrontato con `duration`.
#
# `duration` arriva GIÀ RISOLTA dal chiamante (base × EraRules.think_duration_multiplier) — questa
# classe non conosce EraRules né Folk, stesso principio "nessuna Action conosce il dominio che la
# orchestra" già seguito da WalkAction/RestAction (che non conoscono HumanIndividualMovementService/
# HumanStaminaIndividualService). Unità = FRAZIONE DI GIORNO DI GIOCO, stessa di `delta` in
# get_stamina_delta (vedi la ricognizione game-clock: delta non è più tempo reale) — quindi
# duration=1.0 significa "un giorno pieno di riflessione continua", coerente con STAMINA_REGEN_PER_
# DAY/STAMINA_DRAIN_PER_MICROCELL già calibrate sulla stessa unità.
#
# Nessun target spaziale (stesso pattern di RestAction — vedi _init sotto): ThinkAction agisce solo
# sull'individuo stesso, in loco.

# Drain di stamina al GIORNO — valore di partenza ARBITRARIO (10.0, richiesta utente) da ricalibrare
# in seguito, come tutti gli altri drain/regen di questo sistema. Scelto in proporzione a Walk/Rest
# già calibrati: camminare drena 50.0 stamina/giorno a pieno ritmo (WalkAction.STAMINA_DRAIN_PER_
# MICROCELL=5.0 × HumanIndividual.move_speed=10.0 microcelle/giorno) e riposare recupera altrettanto
# (RestAction.STAMINA_REGEN_PER_DAY=50.0) — pensare è uno sforzo mentale, non fisico: un quinto del
# drain di una camminata piena (10.0 = 50.0/5) rende il costo reale ma nettamente più leggero di uno
# sforzo fisico, senza azzerare comunque il recupero passivo di un'eventuale Task successiva di Rest.
const STAMINA_DRAIN_PER_DAY: float = 10.0


var duration: float = 0.0

# Tempo trascorso in QUESTO step, in frazioni di giorno di gioco — parte da 0.0 (a differenza di
# WalkAction._last_position, che parte a null perché la primissima chiamata non ha ancora un punto
# di confronto: qui non serve, "quanto tempo è passato" è correttamente 0.0 prima di qualunque
# chiamata, nessun caso speciale per il primo frame).
var _elapsed: float = 0.0


func _init(p_duration: float) -> void:
	duration = p_duration
	target = null
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD/TEENAGER aggiunti 2026-09-13 (richiesta
	# utente): pensare è riservato agli adulti. FERTILE_ADULT RIAMMESSA 2026-09-21 (richiesta utente): i
	# fondatori nascono tutti in quella fascia, senza di loro nessuna idea avanzerebbe.
	disallowed_age_bands = [
		HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD,
		HumanTypes.AgeBand.TEENAGER,
	]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= duration


# Lascia un pensiero "in sospeso" sull'individuo quando il ciclo di riflessione si conclude
# (2026-09-07) — vedi Action.on_complete per il contratto generale/perché non è dentro is_complete()
# stessa, e HumanIndividual.pending_thought per cosa succede dopo.
#
# pending_thought_target_search (2026-09-10, richiesta utente — Step 1 del refactor Daydream via
# TaskFactory, preparazione del meccanismo, non ancora collegato/testabile in-game: arriva col
# secondo prompt) — STESSO canale generico già in uso per pending_warehouse_search (scritto da
# PickUpAction.on_complete/UnloadAction.activate, consumato da HumanIndividualActionService.
# _handle_pending_warehouse_search) ma per il ramo PENSIERO: scritto qui, consumato da
# _handle_pending_thought_target_search (già costruito, 2c) DOPO questa chiamata, nello stesso
# passaggio di apply_action (vedi HumanIndividualActionService.apply_action per l'ordine esatto).
# Struttura MINIMA già decisa (vedi 2c) — solo "excluded_building_ids": [] (nessun resource_name/
# quantity, non pertinenti a un pensiero, stesso motivo già documentato su
# _handle_pending_thought_target_search). Scritto INCONDIZIONATAMENTE ad ogni Think completato —
# stesso principio di individual.pending_thought sotto: questa Action non sa (e non deve sapere) se
# esiste già un edificio idoneo nel mondo, quella verifica vive altrove (vedi
# ThoughtTargetSelectionService.has_thought_accepting_building, usata a monte per decidere se
# assegnare l'intera Task Daydream, non qui).
func on_complete(individual: Variant, context: Dictionary) -> void:
	individual.pending_thought = true
	context["pending_thought_target_search"] = {"excluded_building_ids": []}


# duration/_elapsed persistiti (2026-09-08, richiesta utente) — duration non è coperto dal
# `target` generico di TaskPersistenceService (resta null per questa Action, vedi _init sopra),
# quindi va nel proprio get_save_data(); _elapsed è il vero motivo di questo override: senza,
# un save a metà riflessione perderebbe il progresso e ricomincerebbe da 0 al reload.
func get_save_data() -> Dictionary:
	return {"duration": duration, "elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
