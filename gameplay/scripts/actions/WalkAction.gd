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
const STAMINA_DRAIN_PER_MICROCELL: float = 5.0


func _init(p_target: Vector2) -> void:
	target = p_target


# Punto in cui questo step prepara l'individuo a camminare (2026-09-07) — vedi Action.activate per
# il contratto generale. Imposta target_position/is_moving direttamente (stesso comportamento che
# prima viveva inline in HumanIndividual.set_target, ora spostato qui perché serve anche
# all'avanzamento automatico tra step di una Task, non solo al primo comando del player).
#
# super() PRIMA (bugfix 2026-09-07, vedi Action.activate) poi is_moving = true SUBITO DOPO: unica
# sottoclasse che ribalta il default a false della classe base — è l'unica azione che comporta
# movimento reale.
func activate(individual: Variant) -> void:
	super(individual)
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
func get_stamina_delta(individual: Variant, delta: float) -> float:
	if _last_position == null:
		_last_position = individual.position
		return 0.0
	# Tipo esplicito (float), non := (inferenza) — con individual Variant, individual.position è
	# anch'esso Variant, quindi .distance_to() ritorna un Variant per l'analizzatore statico:
	# l'inferenza di tipo non può dedurne il tipo a compile-time, mentre un'annotazione esplicita
	# accetta comunque la conversione a runtime (il valore reale è sempre un float).
	var distance: float = individual.position.distance_to(_last_position)
	_last_position = individual.position
	return -distance * STAMINA_DRAIN_PER_MICROCELL


# Completa quando la posizione ha raggiunto la destinazione DI QUESTO STEP — confronto contro
# `target` (il proprio campo, vedi sopra), non più contro individual.target_position (2026-09-07):
# più robusto/autocontenuto ora che target è la fonte di verità di QUESTO step (individual.
# target_position è solo lo specchio scritto da activate(), utile a HumanIndividualMovementService
# ma non più l'unica fonte da cui questa classe deve dipendere). Stesso criterio di sempre —
# uguaglianza esatta, coerente con l'assegnazione diretta `position = target_position` che
# HumanIndividualMovementService fa all'arrivo, mai un margine di tolleranza.
func is_complete(individual: Variant) -> bool:
	return individual.position == target
