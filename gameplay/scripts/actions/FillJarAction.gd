class_name FillJarAction
extends Action

# Riempimento della giara alla riva (2026-11-06, richiesta utente — Vasellame, giare: passo 1, comando diretto; vedi
# fill_jar.tres e WaterJarService). Una breve sosta sul posto (la riva è il Walk prima), poi la giara vuota dello zaino
# diventa una giara piena con un uso in meno. Bersaglio temporale come DrinkAction (accumulatore _elapsed).
# Niente giara o giara rotta: la Task si chiude qui. Niente posto per la giara piena: la giara torna vuota nella tettoia
# e la serie finisce (WaterJarService.CONTEXT_STOP_AFTER_TRIP).

# Durata della sosta, in giorni di gioco: il doppio del bere.
const DURATION_DAYS: float = 0.02

var _elapsed: float = 0.0


func _init() -> void:
	target = null
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	return 0.0


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _elapsed >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	var failure := WaterJarService.fill_carried_jar(individual)
	if failure == "":
		return
	# Testo già tradotto, il giocatore lo vede come i rifiuti dei comandi. Correzione 2026-11-07 (richiesta utente): con la
	# giara ancora nello zaino (niente posto da piena) il viaggio prosegue e la riporta vuota nella tettoia, poi la serie
	# finisce; senza giara (rotta o sparita) il compito si chiude qui.
	context[HumanIndividualActionService.CONTEXT_PENDING_PLAYER_MESSAGE] = failure
	if individual.get_carried_quantity(WaterJarService.JAR) > 0:
		context[WaterJarService.CONTEXT_STOP_AFTER_TRIP] = true
	else:
		context[HumanIndividualActionService.CONTEXT_PENDING_TASK_ABORT] = failure


func get_save_data() -> Dictionary:
	return {"elapsed": _elapsed}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
