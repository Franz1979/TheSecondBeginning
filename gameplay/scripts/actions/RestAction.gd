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

# Recupero di stamina al GIORNO (rinominata da STAMINA_REGEN_PER_SECOND, richiesta utente,
# 2026-09-07 — in coppia con l'aggancio al game clock: `delta` qui è ora una frazione di giorno di
# gioco, non più secondi reali, quindi il nome precedente descriveva un'unità che questa costante
# non moltiplica più). Valore numerico invariato (50.0, resta il punto di partenza ARBITRARIO già
# scelto, richiesta utente) — solo il significato cambia, da "al secondo" a "al giorno intero".
const STAMINA_REGEN_PER_DAY: float = 100.0

# Moltiplicatore del recupero per-giorno (2026-09-12, richiesta utente — campo base per la Rest
# Task esplicita, poi COLLEGATO lo stesso giorno: GameScene._resolve_rest_target risolve 1.4 se
# individual.house_id punta a una Building con BuildingRules.rest_multiplier valorizzato, 1.0
# altrove — vedi rest.tres/step_rest.tres, l'unico consumatore che valorizza davvero questo
# parametro oggi). Default 1.0 = neutro, comportamento INVARIATO per ogni chiamata che non lo
# passa (es. TaskPersistenceService._build_step per un save precedente a questo campo).
var rest_multiplier: float = 1.0


func _init(p_rest_multiplier: float = 1.0) -> void:
	target = null
	rest_multiplier = p_rest_multiplier


# Nessun calcolo superfluo una volta pieno: ritorna 0.0 immediatamente se la stamina è già al
# tetto massimo. Altrimenti il recupero è clampato in uscita (min(regen_calcolato, spazio
# rimanente)) così il chiamante può sempre sommarlo direttamente a current_stamina senza bisogno
# di un clamp separato lì.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if individual.current_stamina >= individual.max_stamina:
		return 0.0
	var regen: float = STAMINA_REGEN_PER_DAY * rest_multiplier * delta
	return min(regen, individual.max_stamina - individual.current_stamina)


# Completa quando la stamina ha raggiunto il tetto massimo (2026-09-12, richiesta utente — Rest
# Task esplicita, terzo step "walk away") — stesso campo/stessa soglia già usati sopra in
# get_stamina_delta per il clamp del recupero (individual.max_stamina, nome verificato: è quello
# reale su HumanIndividual, non un sinonimo), nessun margine di tolleranza (>=, coerente con
# get_stamina_delta che smette di applicare recupero esattamente in quel punto).
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return individual.current_stamina >= individual.max_stamina


# rest_multiplier (2026-09-12, richiesta utente, Rest Task esplicita — Task Persistence) — stesso
# principio di BuildAction.get_save_data per skill_multiplier/tool_multiplier: un solo valore
# scalare JSON-safe, letto da TaskPersistenceService._build_step al reload e ripassato al
# costruttore (nessun load_save_data() qui, stesso schema di BuildAction — il valore serve a
# COSTRUIRE l'istanza, non è progresso runtime da ripristinare dopo).
func get_save_data() -> Dictionary:
	return {"rest_multiplier": rest_multiplier}
