class_name WalkAction
extends Action

# Prima sottoclasse concreta di Action (2026-09-06, richiesta utente) — costo di stamina per
# camminare. `individual` resta tipizzato Variant in TUTTI i metodi sotto (get_stamina_delta/
# is_complete/activate) — un override in GDScript deve combaciare esattamente col tipo del
# parametro della classe base (Action), che è deliberatamente Variant per non introdurre lì una
# dipendenza da HumanIndividual (vedi Action.gd). L'accesso ai campi di HumanIndividual dentro
# questa classe resta comunque corretto a runtime (dispatch dinamico), solo senza controllo
# statico su quel singolo parametro.
#
# `target` (2026-09-07, richiesta utente, introdotto insieme a Task) — ORA un Vector2 reale
# (destinazione di QUESTO step), passato al costruttore: REVISIONE del design precedente
# (2026-09-06), che lasciava deliberatamente `target = null` perché un singolo WalkAction era
# sempre l'UNICA azione attiva, con individual.target_position già valorizzato dall'esterno
# (HumanIndividual.set_target) prima ancora che l'azione esistesse. Con Task (sequenze di più
# WalkAction verso destinazioni diverse), quell'assunzione non regge più: ogni step deve portare
# con sé la PROPRIA destinazione, così activate() sotto può valorizzare individual.target_position
# ogni volta che DIVENTA lo step attivo (sia il primo che uno step successivo raggiunto per
# avanzamento automatico — vedi HumanIndividualActionService.apply_action).

# Costo di stamina per microcella percorsa — costante di classe (facilmente ritarabile senza
# toccare la formula sotto), valore di partenza ARBITRARIO (1.0 stamina/microcella, richiesta
# utente) da bilanciare quando un consumatore reale esisterà. Unità = microcella (coordinate
# continue di individual.position, vedi ricognizione 2026-09-06), MAI "metro": il progetto non ha
# nessuna conversione metrica per position — il nome precedente (STAMINA_DRAIN_PER_METER)
# assumeva implicitamente 1 unità di position = 1 metro, un'equivalenza mai stabilita altrove nel
# codebase.
# Ritarato da 2.0 a 5.0 (richiesta utente, 2026-09-07, in coppia con la ritaratura di
# HumanIndividual.move_speed e SECONDS_PER_DAY_BY_SPEED per l'aggancio al game clock).
# Base FISSA del costo/microcella (richiesta utente, 2026-09-08) — non più l'intero costo: ora solo
# il termine indipendente dal carico, sommato a used_carry_space/tool sotto in get_stamina_delta.
# Con lo zaino vuoto (carried_resources) ed equipped_tool_count 0 il costo totale resta esattamente questo
# valore (nessun carico), invariato rispetto a prima di questa modifica.
const STAMINA_DRAIN_PER_MICROCELL_BASE: float = 5.0
# Costo aggiuntivo/microcella per ogni utensile in equipaggiamento (richiesta utente, 2026-09-08) —
# valore ARBITRARIO di partenza, stesso principio "da bilanciare" già dichiarato sopra per la base.
# Attivo dal 2026-09-25: HumanIndividual.equipped_tool_count conta gli attrezzi nella cintura.
const STAMINA_DRAIN_PER_TOOL: float = 3.0
# Moltiplicatore del carico trasportato nel costo/microcella (2026-09-21, richiesta utente — con 1.0 un
# carico di 40 di spazio costava 45 stamina/microcella contro le 5 a vuoto, "troppo"): il costo del
# carico è used_carry_space × questo valore. Usato anche da RunAction.
const CARRY_STAMINA_MULTIPLIER: float = 0.5

# Nessun effetto sull'happiness (2026-09-19, richiesta utente): le Action non toccano i parametri
# vitali di happiness, solo le Task lo fanno al completamento (vedi TaskCompletionEffects,
# task_completion_effects.tres). Il vecchio drain per microcella (-5.0) e' stato rimosso.


func _init(p_target: Vector2) -> void:
	target = p_target
	# INFANT non può camminare da solo (2026-09-12, richiesta utente — collegamento AgeBand.INFANT
	# al gameplay, vedi Action.disallowed_age_bands).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


# Punto in cui questo step prepara l'individuo a camminare (2026-09-07) — vedi Action.activate per
# il contratto generale. Imposta target_position/is_moving direttamente (stesso comportamento che
# prima viveva inline in HumanIndividual.set_target, ora spostato qui perché serve anche
# all'avanzamento automatico tra step di una Task, non solo al primo comando del player).
#
# super() PRIMA (bugfix 2026-09-07, vedi Action.activate) poi is_moving = true SUBITO DOPO: unica
# sottoclasse che ribalta il default a false della classe base — è l'unica azione che comporta
# movimento reale.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	individual.target_position = target
	individual.is_moving = true


# Distanza percorsa nel FRAME CORRENTE — HumanIndividualMovementService.advance_movement non
# espone (e non va modificato in questo passo, richiesta esplicita) "quanto si è mosso l'ultimo
# frame": nessun campo/segnale del genere esiste oggi su HumanIndividual o sul service di
# movimento. Soluzione auto-contenuta proposta (nessuna modifica a codice esterno): questa istanza
# ricorda la propria ultima `individual.position` nota (_last_position) e calcola la distanza per
# differenza ad ogni chiamata. Funziona perché un'istanza di WalkAction è pensata per vivere per
# tutta la durata di UNA singola camminata (uno step di Task = una camminata verso UNA
# destinazione, mai riusata tra due step diversi — vedi Task.gd): confrontare "dove sono ora" con
# "dove ero all'ultima chiamata" equivale esattamente a "quanto mi sono mosso in questo istante",
# senza che HumanIndividualMovementService debba sapere nulla di stamina/azioni. _last_position
# parte a null (sentinella, non Vector2.ZERO — un individuo raramente sta esattamente all'origine,
# Vector2.ZERO produrrebbe una distanza-fantasma alla prima chiamata): la primissima chiamata su
# una nuova istanza non ha ancora un punto di confronto valido, quindi si limita a registrare la
# posizione di partenza e non applica alcun drain quel frame.
var _last_position: Variant = null


# individual tipizzato Variant (non HumanIndividual) — DEVE combaciare esattamente col tipo del
# parametro nella firma della classe base Action.get_stamina_delta, altrimenti Godot rifiuta
# l'override ("The function signature doesn't match the parent"). L'accesso a .position sotto
# resta comunque tipizzato correttamente a runtime (dispatch dinamico su Variant, stesso principio
# già usato altrove nel progetto per valori letti da Dictionary/Array generici) — nessuna perdita
# di correttezza, solo niente controllo statico a compile-time su questo singolo parametro.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _last_position == null:
		_last_position = individual.position
		return 0.0
	# Tipo esplicito (float), non := (inferenza) — con individual Variant, individual.position è
	# anch'esso Variant, quindi .distance_to() ritorna un Variant per l'analizzatore statico:
	# l'inferenza di tipo non può dedurne il tipo a compile-time, mentre un'annotazione esplicita
	# accetta comunque la conversione a runtime (il valore reale è sempre un float).
	var distance: float = individual.position.distance_to(_last_position)
	_last_position = individual.position
	return compute_walk_stamina_delta(individual, distance, "Walk")


# Costo di stamina per `distance` microcelle camminate — ESTRATTO (2026-09-26, caccia step 2) dal corpo
# di get_stamina_delta sopra, formula invariata, per condividerlo con ApproachPreyAction (che cammina
# allo stesso modo ma verso un bersaglio mobile). Ritorna il delta (negativo). `debug_label` = nome
# dell'azione nella riga di MovementStaminaDebugLog.
static func compute_walk_stamina_delta(individual: Variant, distance: float, debug_label: String) -> float:
	# Costo/microcella = base + spazio REALMENTE occupato dal carico + costo per utensile
	# (richiesta utente, 2026-09-08) — stesso identico lookup/stessa identica formula di
	# used_carry_space già usata da GameScene._update_individual_panel_content per il pannello
	# individuo (mai cachato: il carico può cambiare tra una chiamata e l'altra).
	var used_carry_space: float = individual.get_carried_space()

	# individual.terrain_stamina_multiplier (2026-09-19, richiesta utente — vedi MovementTerrainService): scala
	# la sola quota BASE del costo, mai il sovraccarico di carico e utensili.
	var cost_per_microcell: float = STAMINA_DRAIN_PER_MICROCELL_BASE * individual.terrain_stamina_multiplier + used_carry_space * CARRY_STAMINA_MULTIPLIER + STAMINA_DRAIN_PER_TOOL * float(individual.equipped_tool_count)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS:
		MovementStaminaDebugLog.record(
			individual, debug_label, distance, individual.terrain_stamina_multiplier, STAMINA_DRAIN_PER_MICROCELL_BASE,
			used_carry_space * CARRY_STAMINA_MULTIPLIER + STAMINA_DRAIN_PER_TOOL * float(individual.equipped_tool_count)
		)
	return -distance * cost_per_microcell


# Tolleranza di arrivo (2026-09-16, richiesta utente, fix bordo macrocella — robustezza generica,
# non specifica al bordo) — RIMPIAZZA l'uguaglianza esatta di prima: HumanIndividualMovementService
# continua ad assegnare `position = target_position` esattamente all'arrivo normale (nessun
# cambio di comportamento per quel caso, distance_to()==0.0 resta sempre <= tolleranza), ma un
# target ribasato da GameScene._attempt_macro_cell_transition (Task.rebase_positional_targets)
# combina due sottrazioni in virgola mobile (entry_position - position, poi position += offset in
# frame successivi) invece della singola assegnazione diretta di un arrivo normale — un'uguaglianza
# ESATTA su quella somma non è più garantita bit-per-bit. Valore minimo (0.01 microcelle,
# ben sotto qualunque soglia visiva) che assorbe questo solo rischio senza introdurre un arrivo
# "anticipato" percepibile.
const ARRIVAL_TOLERANCE: float = 0.01


# Completa quando la posizione ha raggiunto la destinazione DI QUESTO STEP (entro ARRIVAL_
# TOLERANCE sopra) — confronto contro `target` (il proprio campo, vedi sopra), non più contro
# individual.target_position (2026-09-07): più robusto/autocontenuto ora che target è la fonte di
# verità di QUESTO step (individual.target_position è solo lo specchio scritto da activate(),
# utile a HumanIndividualMovementService ma non più l'unica fonte da cui questa classe deve
# dipendere).
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return individual.position.distance_to(target) <= ARRIVAL_TOLERANCE


# Chiude la riga di log dell'ultima microcella attraversata (diagnostica TEMPORANEA, vedi
# MovementStaminaDebugLog) — nessun effetto se il flag è spento.
func on_complete(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and DebugLogging.SHOW_MOVEMENT_STAMINA_LOGS:
		MovementStaminaDebugLog.flush(individual)
