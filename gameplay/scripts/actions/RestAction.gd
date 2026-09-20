class_name RestAction
extends Action

# Seconda sottoclasse concreta di Action (2026-09-07, richiesta utente) — a differenza di
# WalkAction (comandata esplicitamente dal player), Rest è lo stato IMPLICITO di un individuo
# quando non ha nessun'altra azione assegnata: nessun comando manuale, nessun target (vedi _init
# sotto, stesso pattern di WalkAction). `individual` resta tipizzato Variant in get_stamina_delta
# (deve combaciare esattamente col parametro della classe base Action, vedi Action.gd/WalkAction.gd
# per il perché) — nessuna perdita di correttezza, solo niente controllo statico a compile-time su
# questo singolo parametro.
#
# is_complete() ORA un vero criterio (2026-09-12, richiesta utente — Rest Task esplicita, terzo
# step "walk away": prima di questo passo restava il default ereditato da Action, sempre false, non
# serviva un criterio proprio perché Rest era lo stato IMPLICITO terminale di un individuo idle —
# vedi is_complete sotto per il criterio vero). "Tornare a un luogo specifico (casa)" — il vecchio
# TODO qui sopra — è nel frattempo diventato responsabilità della Rest Task/GameScene.
# _resolve_rest_target (Walk verso la casa PRIMA di questo step), non di questa classe: RestAction
# resta ignara di dove si trovi l'individuo, recupera stamina ovunque sia stato portato.
#
# Regen PERCENTUALE, non più assoluto (2026-09-16, richiesta utente — bugfix: con un valore
# assoluto, un individuo con max_stamina alto [es. 5000, il fallback] impiegava fino a 40 giorni di
# gioco per recuperare dalla soglia del 20% al 100%, "restano in rest anche mesi" nel gioco reale.
# Vedi STAMINA_REGEN_PERCENT_PER_DAY sotto per il nuovo tasso, ora proporzionale a max_stamina
# dell'individuo — tempo di recupero costante per chiunque, indipendente dalla taglia del tetto).
#
# max_duration_days/ignore_stamina_cap/_elapsed (2026-09-16, richiesta utente — stesso indagine:
# anche con regen percentuale il recupero dalla soglia resta comunque ~16 giorni fissi, troppo per
# restare bloccati senza un tetto di sicurezza; e serve un SECONDO uso di questa stessa Action per
# una "Rest perditempo" tra le Task idle-fallback, che NON deve mai fermarsi a stamina piena — vedi
# IdleTaskAssignmentService) — DUE nuovi campi opzionali, entrambi disattivati di default (nessun
# cambio di comportamento per chi non li imposta):
#   - max_duration_days (-1.0 = disattivato): un secondo criterio di fine, in GIORNI trascorsi in
#     QUESTO step (stesso principio/stesso schema di accumulo di ThinkAction._elapsed sotto).
#   - ignore_stamina_cap (false = disattivato): se vero, il criterio "stamina piena" viene IGNORATO
#     del tutto — SOLO max_duration_days decide la fine (per una Rest "per piacere", non per
#     bisogno: si ferma quando sono passati N giorni, non quando la stamina è già tornata al tetto).
# Vedi is_complete() sotto per la combinazione esatta dei due.
const STAMINA_REGEN_PERCENT_PER_DAY: float = 0.05

var max_duration_days: float = -1.0
var ignore_stamina_cap: bool = false

# Giorni trascorsi in QUESTO step — stesso principio/stesso nome di ThinkAction._elapsed: parte da
# 0.0 (nessun caso "primo frame" speciale, a differenza di WalkAction._last_position), incrementato
# in get_stamina_delta sotto (chiamato SEMPRE, ad ogni frame, prima di is_complete — stesso motivo
# per cui ThinkAction lo incrementa lì e non altrove).
var _elapsed: float = 0.0


# Moltiplicatore del recupero per-giorno (2026-09-12, richiesta utente — campo base per la Rest
# Task esplicita, poi COLLEGATO lo stesso giorno: GameScene._resolve_rest_target risolve 1.4 se
# individual.house_id punta a una Building con BuildingRules.rest_multiplier valorizzato, 1.0
# altrove — vedi rest.tres/step_rest.tres, l'unico consumatore che valorizza davvero questo
# parametro oggi). Default 1.0 = neutro, comportamento INVARIATO per ogni chiamata che non lo
# passa (es. TaskPersistenceService._build_step per un save precedente a questo campo).
var rest_multiplier: float = 1.0


func _init(p_rest_multiplier: float = 1.0, p_max_duration_days: float = -1.0, p_ignore_stamina_cap: bool = false) -> void:
	target = null
	rest_multiplier = p_rest_multiplier
	max_duration_days = p_max_duration_days
	ignore_stamina_cap = p_ignore_stamina_cap
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT]


# _elapsed incrementato QUI (2026-09-16), non in is_complete() — stesso motivo
# di ThinkAction: questo metodo è l'unico chiamato SEMPRE, ogni frame, con `delta` disponibile,
# prima che is_complete() venga valutato nello stesso passaggio (vedi HumanIndividualActionService.
# apply_action per l'ordine esatto). Incrementato PRIMA del calcolo/guardia sotto, così continua ad
# avanzare anche nei frame in cui il recupero è già a 0.0 (stamina piena) — altrimenti
# max_duration_days non avanzerebbe mai oltre il momento in cui la stamina si riempie, vanificando
# ignore_stamina_cap sotto.
#
# Nessun calcolo superfluo di regen una volta pieno: ritorna 0.0 immediatamente se la stamina è già
# al tetto massimo. Altrimenti il recupero è clampato in uscita (min(regen_calcolato, spazio
# rimanente)) così il chiamante può sempre sommarlo direttamente a current_stamina senza bisogno
# di un clamp separato lì. Regen ora PERCENTUALE di max_stamina (vedi STAMINA_REGEN_PERCENT_PER_DAY
# sopra), non più un valore assoluto.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	_elapsed += delta
	if individual.current_stamina >= individual.max_stamina:
		return 0.0
	var regen: float = individual.max_stamina * STAMINA_REGEN_PERCENT_PER_DAY * rest_multiplier * delta
	return min(regen, individual.max_stamina - individual.current_stamina)


# Completa quando la stamina ha raggiunto il tetto massimo (2026-09-12, richiesta utente — Rest
# Task esplicita, terzo step "walk away") — stesso campo/stessa soglia già usati sopra in
# get_stamina_delta per il clamp del recupero (individual.max_stamina, nome verificato: è quello
# reale su HumanIndividual, non un sinonimo), nessun margine di tolleranza (>=, coerente con
# get_stamina_delta che smette di applicare recupero esattamente in quel punto).
#
# RICALIBRATO 2026-09-16 (richiesta utente) — due criteri combinati, invariati per chi non imposta
# max_duration_days (resta -1.0, duration_reached sempre false, comportamento identico a prima):
#   - ignore_stamina_cap = true: SOLO duration_reached decide (la stamina piena non ferma più
#     questo step — "Rest per piacere", non per bisogno, vedi la nota di testa al file).
#   - ignore_stamina_cap = false (default): stamina piena OPPURE durata raggiunta, quale delle due
#     arriva prima — la Rest da bisogno recupera comunque per intero se ci riesce in tempo, ma non
#     resta bloccata oltre max_duration_days se il recupero fosse più lento del previsto.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	var duration_reached: bool = max_duration_days >= 0.0 and _elapsed >= max_duration_days
	if ignore_stamina_cap:
		return duration_reached
	return individual.current_stamina >= individual.max_stamina or duration_reached


# rest_multiplier/max_duration_days/ignore_stamina_cap (2026-09-12/16, richiesta utente, Rest Task
# esplicita — Task Persistence) — stesso principio di BuildAction.get_save_data per skill_
# multiplier/tool_multiplier: valori scalari JSON-safe, letti da TaskPersistenceService._build_step
# al reload e ripassati al costruttore (nessun load_save_data() per questi tre — il valore serve a
# COSTRUIRE l'istanza, non è progresso runtime). `elapsed` invece è vero progresso runtime (stesso
# principio di ThinkAction.get_save_data) — persistito qui ma ripristinato SOLO da load_save_data
# sotto, non da _build_step (che non lo leggerebbe comunque: un nuovo step ricostruito da zero deve
# ripartire da _elapsed=0.0, solo lo step CORRENTE di una Task in corso lo ripristina davvero, vedi
# TaskPersistenceService.deserialize_task per il perché).
func get_save_data() -> Dictionary:
	return {
		"rest_multiplier": rest_multiplier,
		"max_duration_days": max_duration_days,
		"ignore_stamina_cap": ignore_stamina_cap,
		"elapsed": _elapsed,
	}


func load_save_data(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
