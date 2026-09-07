class_name HumanIndividualActionService
extends RefCounted

# Servizio single-responsibility (stesso pattern di HumanIndividualMovementService, stesso
# livello/cartella): applica lo step ATTIVO della Task corrente di un HumanIndividual
# (individual.current_task), se presente — costo/recupero di stamina per questo istante, poi
# verifica se quello step è concluso e fa avanzare la Task di conseguenza. Girato ogni frame da
# GameScene._process, DOPO individual_movement_service.advance_movement (vedi lì per il perché
# dell'ordine: WalkAction.get_stamina_delta calcola la distanza percorsa confrontando
# individual.position con l'ultima nota, quindi deve leggere la position già aggiornata di questo
# frame — e advance_movement NON chiama più individual.stop() all'arrivo, vedi lì: è QUESTO
# servizio, non quello, a decidere quando una Task è davvero conclusa).
#
# Nessun clamp su current_stamina in questo passo (richiesta esplicita utente, 2026-09-06): può
# scendere sotto zero senza conseguenze — l'auto-interrupt quando la stamina si esaurisce arriverà
# in uno step successivo.

# Rest è lo stato IMPLICITO di un individuo senza current_task attiva (2026-09-07, richiesta
# utente — "senza current_action" nel commento originale, aggiornato per Task) — istanza condivisa
# unica, creata una sola volta qui come costante statica del servizio, non una nuova istanza per
# frame per ogni individuo idle: RestAction non ha bisogno di stato proprio (nessun target, nessun
# _last_position come in WalkAction), quindi una sola istanza può servire tutti gli individui idle
# contemporaneamente senza rischio di stato incrociato.
static var _idle_rest_action := RestAction.new()


func apply_action(individual: HumanIndividual, delta: float) -> void:
	if individual.current_task == null or individual.current_task.is_finished():
		# Rest implicito: non scrive individual.current_task (resta null/conclusa) — non "occupa"
		# lo slot della task corrente, che resta libero per essere sovrascritto immediatamente da
		# un comando esplicito come Walk.
		individual.current_stamina += _idle_rest_action.get_stamina_delta(individual, delta)
		return
	# Avanzamento automatico Task (2026-09-07, richiesta utente, introdotto insieme a Task) —
	# applica lo step ATTIVO (mai la Task intera: Task non sa nulla di stamina, vedi Task.gd), poi
	# se quello step è concluso fa avanzare l'indice: se la Task risulta conclusa DOPO l'avanzamento
	# ferma per davvero l'individuo (stop(), che azzera is_moving/current_task — vedi HumanIndividual.
	# gd), altrimenti attiva subito il nuovo step attivo (activate(), vedi Action.gd/WalkAction.gd)
	# così il movimento prosegue senza soluzione di continuità verso la destinazione successiva,
	# nello stesso frame in cui il precedente è arrivato — nessun frame "fermo" in mezzo.
	# `task` tenuto in una variabile locale (2026-09-07, necessario per il log di costo sotto):
	# individual.stop() azzera individual.current_task, quindi senza questo riferimento la Task non
	# sarebbe più raggiungibile nel momento in cui va stampato il suo riepilogo costi.
	var task := individual.current_task
	var action := task.get_current_action()
	var stamina_delta := action.get_stamina_delta(individual, delta)
	individual.current_stamina += stamina_delta
	# Accumulo costo per-step (2026-09-07, richiesta utente) — stesso stamina_delta/delta appena
	# applicati sopra, nessun ricalcolo: vedi Task.record_step_cost/print_cost_summary.
	task.record_step_cost(stamina_delta, delta)
	if action.is_complete(individual):
		# on_complete() (2026-09-07, richiesta utente, introdotta con ThinkAction) — SEMPRE PRIMA di
		# advance_to_next_step()/stop(): quello che uno step lascia sull'individuo al proprio termine
		# (es. ThinkAction -> individual.pending_thought = true) deve essere scritto mentre quello
		# step è ancora "il current" per costruzione, non dopo che la Task è già passata oltre.
		action.on_complete(individual)
		task.advance_to_next_step()
		if task.is_finished():
			if DebugLogging.ENABLED and DebugLogging.SHOW_TASK_TOTAL_COST_LOGS:
				task.print_cost_summary(individual)
			individual.stop()
		else:
			task.get_current_action().activate(individual)
