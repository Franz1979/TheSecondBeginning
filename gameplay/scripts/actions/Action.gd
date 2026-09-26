class_name Action
extends RefCounted

# Classe base per il futuro sistema di azioni (Walk/Rest/Cut/Build/...) del refactor Stamina
# (2026-09-06, richiesta utente) — RefCounted come ogni altra classe di stato/servizio del
# progetto (mai Node, vedi CLAUDE.md), pura interfaccia/scheletro. Sottoclassi concrete oggi:
# WalkAction/RestAction (vedi file omonimi, stessa cartella) — Cut/Build restano ancora da
# scrivere. HumanIndividual.current_task (Task, 2026-09-07 — SOSTITUISCE il precedente
# current_action: Action, un solo campo) referenzia una sequenza ordinata di istanze di questa
# classe (vedi Task.gd) — HumanIndividualActionService.apply_action legge/avanza quella sequenza,
# questa classe resta ignara di Task/HumanIndividual, la conosce solo per dispatch dinamico sui
# parametri Variant sotto.
#
# Deliberatamente NESSUN collegamento a HumanIndividual/HumanIndividualMovementService/GameScene:
# `individual` sotto è tipizzato Variant, non HumanIndividual, per non introdurre una dipendenza da
# quella classe qui — il futuro service esterno che orchestrerà le azioni deciderà lui il tipo
# concreto da passare.


# Bersaglio opzionale dell'azione (una cella, una risorsa, un altro individuo, ...) — tipo
# generico (Variant, non ancora un tipo concreto) perché nessuna sottoclasse esiste ancora per
# decidere cosa un target debba essere; Cut/Build lo popoleranno quando arriveranno. null = azione
# senza bersaglio (es. un futuro Rest, che agisce solo sull'individuo stesso).
var target: Variant = null

# Categorie di tool richiesti da questa Action (2026-09-08, richiesta utente) — SOLO struttura
# dati, NESSUNA logica di verifica/possesso qui: nessun controllo che l'individuo abbia il tool,
# nessun auto-accodamento di un futuro PickUp, nessuna conseguenza se l'array non è vuoto. Vuoto
# di default = nessun tool richiesto, comportamento invariato per ogni Action esistente (WalkAction/
# RestAction/ThinkAction/UnloadAction, nessuna delle quali lo sovrascrive). Vedi TaskTypes.
# ToolCategory per l'enum — quando arriverà il vero sistema tool (equip/verifica), leggerà questo
# campo da qui, non da un nuovo posto.
var required_tool_categories: Array[TaskTypes.ToolCategory] = []

# Attesa degli attrezzi (spostata qui da ProduceAction il 2026-09-26, caccia step 2 — prima era solo
# della produzione): stato dell'ULTIMO controllo di ToolGateService fatto da ensure_required_tools,
# ricalcolato a ogni tick dallo step che lo chiama, mai salvato. tool_wait_result == OK = nessuna
# attesa; MISSING_TOOLS = mancano gli attrezzi per tool_wait_missing_categories; BELT_FULL/
# CANNOT_EQUIP = l'attrezzo tool_wait_tool_name c'è nello zaino ma non entra in cintura. Letti da
# GameScene._describe_tool_wait per i pannelli, per qualunque step.
var tool_wait_result: int = ToolGateService.Result.OK
var tool_wait_missing_categories: Array = []
var tool_wait_tool_name: String = ""

# Fasce d'età a cui è VIETATO eseguire questa Action (2026-09-12, richiesta utente — collegamento
# di HumanTypes.AgeBand.INFANT al gameplay) — STESSO schema di required_tool_categories sopra: solo
# struttura dati qui, la verifica vera vive nel chiamante (HumanIndividual.assign_task, vedi lì).
# Vuoto di default = nessun vincolo. A differenza di required_tool_categories (ancora non
# consultato da nessuno), questo campo viene letto da assign_task fin da subito: ogni Action
# concreta esistente lo imposta a [HumanTypes.AgeBand.INFANT] nel proprio _init (vedi le
# sottoclassi) — un INFANT non può eseguire nessuna Action oggi esistente.
var disallowed_age_bands: Array[HumanTypes.AgeBand] = []


# Variazione di stamina per questo istante/frame — negativa per un drain (es. Walk/Cut consumano),
# positiva per un recharge (es. Rest recupera). `individual`/`delta` generici (Variant/float) così
# un futuro service esterno può chiamarlo senza che questa classe dipenda da HumanIndividual.
# Implementazione di base neutra (nessun effetto): ogni sottoclasse concreta la sovrascriverà con
# la propria formula di costo/recupero.
#
# `context` (2026-09-09, richiesta utente — prerequisito per il futuro SearchAction) — il
# Task.context CONDIVISO della Task che possiede questo step (Dictionary libero, vedi Task.gd),
# passato così un'Action può in futuro leggere un risultato scritto da uno step precedente della
# stessa Task (es. SearchAction scrive qui cosa ha trovato, PickUpAction/AimAction lo leggono).
# SOLO IL CANALE per ora: questa classe base non lo usa (nessun comportamento di default), e
# nessuna sottoclasse esistente lo legge/scrive ancora — vedi le sottoclassi concrete per la stessa
# nota. Posizionato subito dopo `individual` in ogni firma di questo file (stesso ordine in
# is_complete/activate/on_complete sotto): individual+context sono la coppia di riferimenti sempre
# passati dal chiamante, gli altri parametri (delta, ...) variano per metodo.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	return 0.0


# Variazione di happiness per questo istante/frame (2026-09-13, richiesta utente) — STESSO
# identico schema di get_stamina_delta sopra: firma identica, implementazione di base neutra
# (0.0), ogni sottoclasse concreta la sovrascrive con il proprio tasso. Meccanismo PARALLELO e
# INDIPENDENTE da get_stamina_delta, non un secondo valore di ritorno dello stesso metodo
# (indagine dedicata, giro precedente: get_stamina_delta ritorna un solo float, nessuna firma
# multi-valore già pronta) — HumanIndividualActionService.apply_action chiama ENTRAMBI i metodi
# nello stesso frame, in sequenza (stamina prima, poi happiness).
#
# ATTENZIONE per chi implementa una sottoclassa (nota valida per ogni override esistente, vedi le
# sottoclassi concrete): questo metodo NON deve mai duplicare la scrittura di stato di progresso
# già fatta da get_stamina_delta nello stesso frame (es. _elapsed, Building.construction_progress)
# — chiamato SEMPRE insieme a get_stamina_delta sullo stesso `delta`, un secondo incremento
# raddoppierebbe silenziosamente la velocità di avanzamento dello step. Le sottoclassi con un
# criterio di completamento temporale/di progresso LEGGONO quello stato (per sapere se l'azione è
# già conclusa e quindi non deve più maturare happiness) ma non lo scrivono mai da qui.
func get_happiness_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	return 0.0


# Vero se l'azione è da considerarsi conclusa — `individual` generico (Variant), stesso principio
# di get_stamina_delta sopra: nessuna dipendenza da HumanIndividual in questa classe base (corretta
# 2026-09-06, richiesta utente — l'asimmetria precedente, nessun parametro qui contro uno su
# get_stamina_delta, impediva a una sottoclassa di verificare il completamento in base allo stato
# dell'individuo). Implementazione di base neutra: l'azione base non termina mai da sola (nessuno
# stato interno di progresso esiste qui) — ogni sottoclassa concreta la sovrascrive con il proprio
# criterio. `context` — vedi get_stamina_delta sopra, stesso canale, ancora inutilizzato qui.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	return false


# Invocata UNA VOLTA quando questo step diventa quello ATTIVO di una Task (2026-09-07, richiesta
# utente, introdotta insieme a Task) — sia all'assegnazione del primissimo step (chi crea la Task
# la chiama subito dopo, vedi HumanIndividual.set_target) sia all'avanzamento automatico a uno step
# successivo (vedi HumanIndividualActionService.apply_action). Punto in cui una sottoclasse
# concreta può inizializzare lo stato dell'individuo necessario per ESEGUIRE questo step — es.
# WalkAction imposta qui individual.target_position/is_moving dal proprio `target` (vedi
# WalkAction.gd). `individual` generico (Variant), stesso principio di get_stamina_delta/
# is_complete sopra.
#
# is_moving = false DI DEFAULT (bugfix, richiesta utente 2026-09-07 — "il pipottino quando pensa
# continua a muovere gambe e braccia come stesse camminando"): is_moving restava true per l'intera
# durata di una Task multi-step, azzerato solo da stop() — un WalkAction lo mette a true nel proprio
# activate(), ma nessuno step successivo (Think/Deposit/Rest) lo rimetteva a false quando diventava
# lo step attivo, quindi HumanIndividualView continuava ad animare le gambe (gated su is_moving,
# vedi lì) anche durante uno step immobile. Messo qui nella classe BASE, non ripetuto in ogni
# sottoclasse stazionaria, cosi' ogni futura azione immobile (Cut/Build/...) lo ottiene gratis
# semplicemente non sovrascrivendo activate(); WalkAction resta l'UNICA sottoclasse che lo
# riporta a true, subito dopo aver chiamato questa implementazione base (vedi WalkAction.activate).
# `context` — vedi get_stamina_delta sopra, stesso canale, ancora inutilizzato qui.
func activate(individual: Variant, context: Dictionary) -> void:
	individual.is_moving = false
	# move_speed_multiplier (2026-09-13, bugfix RunAction) — STESSO principio/STESSO motivo di
	# is_moving sopra: default 1.0 nella classe base così ogni futura azione (di movimento o
	# stazionaria) lo ottiene corretto senza doverlo ripetere, WalkAction non ha bisogno di
	# sovrascriverlo (1.0 è già la velocità normale), solo RunAction.activate() lo alza dopo aver
	# chiamato questa implementazione base. Vedi HumanIndividual.move_speed_multiplier/
	# HumanIndividualMovementService.advance_movement per i due consumatori.
	individual.move_speed_multiplier = 1.0


# Invocata UNA VOLTA quando is_complete(individual) diventa vero, PRIMA che la Task avanzi allo step
# successivo (2026-09-07, richiesta utente, introdotta con ThinkAction) — simmetrica ad activate()
# sopra: se activate() è "come preparo l'individuo a ESEGUIRE questo step", questa è "cosa lascio
# sull'individuo quando questo step FINISCE" (es. ThinkAction imposta qui individual.pending_thought
# = true, vedi ThinkAction.gd). Deliberatamente un metodo a parte, non un effetto collaterale dentro
# is_complete() stessa: is_complete() resta una query pura in ogni sottoclasse esistente (WalkAction
# confronta solo position/target, senza scrivere nulla) — un chiamante potrebbe in teoria valutarla
# più volte per lo stesso stato senza aspettarsi effetti collaterali, mentre on_complete() ha una
# semantica esplicita di "chiamami esattamente una volta, ora". Richiamata da
# HumanIndividualActionService.apply_action subito dopo aver verificato is_complete(), prima di
# avanzare l'indice della Task. `individual` generico (Variant), stesso principio di get_stamina_
# delta/is_complete/activate sopra. Implementazione di base neutra: un'azione senza nulla da
# lasciare sull'individuo al termine (es. WalkAction/RestAction) non la sovrascrive. `context` —
# vedi get_stamina_delta sopra, stesso canale, ancora inutilizzato qui.
func on_complete(individual: Variant, context: Dictionary) -> void:
	pass


# Stato interno di progresso di QUESTO step da persistere, oltre a quanto TaskPersistenceService
# già copre genericamente da solo (action_type via dispatch sul tipo concreto, `target` se è un
# Vector2 — vedi Action.target sopra) — 2026-09-08, richiesta utente (persistenza Task/Action).
# Dictionary vuoto di default: nessuno stato interno da salvare (WalkAction oltre a `target` ha
# solo _last_position, un aiuto per calcolare il delta di UN frame — ripartire da null dopo un
# load è innocuo, un solo frame senza drain, MAI persistito qui; RestAction/UnloadAction non hanno
# proprio stato interno). Sottoclassi con un vero accumulatore di progresso (es. ThinkAction.
# _elapsed) sovrascrivono. Simmetrico a load_save_data sotto.
func get_save_data() -> Dictionary:
	return {}


# Applica i dati extra da get_save_data() sopra DOPO che TaskPersistenceService.deserialize_task ha
# già costruito l'istanza (con `target`/altri argomenti di _init risolti dal proprio step_data) —
# no-op di default, coerente con get_save_data() sopra.
func load_save_data(data: Dictionary) -> void:
	pass


# Posizione FISICA richiesta da questo step per essere eseguito correttamente, o null se questo
# step non ne ha una (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa": una Task
# sospesa in task_queue può riprendere con l'individuo fisicamente altrove rispetto a dove lo
# step in corso si aspetta di trovarlo, es. PickUpAction/UnloadAction/RetrieveAction/
# SetupSiteAction/ClearAction/BuildAction — tutte "stazionarie", nessuna verifica la posizione da
# sole, vedi l'indagine precedente). Implementazione di base neutra (null): WalkAction/RestAction/
# ThinkAction/LookAroundAction/RunAction/JumpAction NON la sovrascrivono — un Walk non ha bisogno
# di un secondo Walk per "arrivare a se stesso" (ricalcola la distanza residua da solo al
# prossimo activate()), le altre non hanno alcun vincolo di posizione. Le 6 Action stazionarie
# elencate sopra la sovrascrivono, ciascuna risolvendo la propria posizione dal proprio formato
# interno (target_position per PickUp, target_building per le altre 5 — vedi ciascuna).
# `individual` (Variant, non HumanIndividual — stesso principio di ogni altro metodo qui) SERVE
# per le 5 basate su target_building: la posizione di un Building è locale alla SUA macrocella
# (target_building.micro_x/y), va convertita nel sistema di coordinate GLOBALE di
# individual.position tramite lo stesso offset cross-macrocella già usato in
# UnloadAction.on_complete (individual.home_macro_coords). `context` — stesso canale di ogni
# altro metodo qui, nessuna delle 6 Action stazionarie tiene la propria posizione IN context (è
# sempre un campo dell'istanza), passato solo per uniformità di firma con is_complete/activate.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	return null


# Validità del bersaglio (2026-09-21, richiesta utente — fix task su edifici completati/demoliti):
# false = questo step non ha più senso perché il suo bersaglio persistente non esiste più o non è
# più nello stato atteso (es. edificio demolito, cantiere già completato). Controllato alla RIPRESA
# di una Task dalla coda (HumanIndividualActionService.resolve_idle_individual/activate_resumed_task)
# e all'ATTIVAZIONE di uno step (finish_current_step): una Task con uno step non valido viene chiusa
# invece di restare bloccata. Default true — nessun vincolo per le Action senza bersaglio persistente;
# ogni sottoclasse con un target_building lo sovrascrive se serve.
func is_target_valid() -> bool:
	return true


# Categorie richieste da questo step (sue + ricetta per ProduceAction, vedi ToolGateService.
# get_action_required_categories) coperte dalla cintura, spostando dallo zaino ciò che serve; aggiorna
# lo stato tool_wait_*. Ritorna true se lo step può lavorare. Chiamata a ogni tick dagli step che
# richiedono attrezzi (ProduceAction, ApproachPreyAction): senza attrezzi restano fermi
# e ripartono da soli quando arrivano nello zaino. game_data null: lo step non lo possiede — la
# capacità di trasporto viene corretta del solo bonus dello slot occupato (HumanIndividual.
# _recalculate_carry_capacity_after_tool_change).
func ensure_required_tools(individual: Variant) -> bool:
	var required := ToolGateService.get_action_required_categories(self)
	if required.is_empty() or individual == null:
		tool_wait_result = ToolGateService.Result.OK
		tool_wait_missing_categories = []
		tool_wait_tool_name = ""
		return true
	var outcome := ToolGateService.try_satisfy(individual, required, null)
	tool_wait_result = int(outcome["result"])
	tool_wait_missing_categories = outcome["missing_categories"]
	tool_wait_tool_name = String(outcome["tool_name"])
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and not outcome["equipped"].is_empty():
		print("[TOOLS] #%d: attrezzi spostati in cintura per %s: %s." % [individual.id, get_script().get_global_name(), str(outcome["equipped"])])
	return tool_wait_result == ToolGateService.Result.OK


func is_waiting_for_tools() -> bool:
	return tool_wait_result != ToolGateService.Result.OK


# Avviso di rottura degli attrezzi (spostato qui da ProduceAction il 2026-09-26, condiviso con la caccia):
# `broken` = nomi restituiti da ToolGateService.consume_tool_uses. Testo tradotto sul pannello
# dell'individuo (stesso canale di tool_gate_warning). No-op se nulla si è rotto.
func report_broken_tools(individual: Variant, broken: Array[String]) -> void:
	if broken.is_empty() or individual == null:
		return
	var tool_names: PackedStringArray = []
	for tool_name in broken:
		tool_names.append(IconRegistry.get_resource_display_name(tool_name))
	individual.tool_gate_warning = tr("tool_broken_warning").format({
		"name": individual.name, "tool": ", ".join(tool_names),
	})
