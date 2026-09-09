class_name UnloadAction
extends Action

# Rinominata da DepositAction (2026-09-09, richiesta utente, BuildingStorageService Step 1) — il
# nome generico "Deposit" era ambiguo col deposito FISICO in un edificio, che oggi diventa reale:
# "Unload" resta l'azione GENERICA di scarico, con due rami distinti secondo `target_building`
# (vedi _init/on_complete sotto), non più solo un TODO per il ramo fisico. Nessun altro cambio di
# comportamento per il ramo pensiero (Folk.thoughts_invested via IdeaProgressService) rispetto a
# prima del rename. Nessun target di posizione (stesso pattern di RestAction/ThinkAction — vedi
# _init sotto): il posizionamento (davanti al Folk per il pensiero, o davanti all'edificio per il
# ramo fisico) è già garantito dal WalkAction precedente nella stessa Task, questa classe non
# verifica/richiede nulla sulla posizione.
#
# NON PIÙ sempre istantanea (2026-09-10, richiesta utente — "lo metterei come unload, sia come
# costo che come tempo") — il ramo FISICO ora ha un vero costo/durata, STESSO schema a
# accumulatore di ThinkAction/PickUpAction (_elapsed confrontato con _duration, vedi quei campi più
# sotto). Il ramo PENSIERO (Daydream) resta invece istantaneo e a costo zero, come da richiesta
# esplicita utente ("un pensiero non occupa spazio") — non per un ramo speciale dedicato, ma perché
# _duration resta naturalmente a 0.0 per quel ramo (nessun `quantity`/`space_per_unit` da cui
# derivarla, vedi activate()/get_stamina_delta sotto), che equivale a "istantanea, costo zero" nella
# stessa formula generica usata anche dal ramo fisico.

# idea_id dell'Idea completata DA QUESTO deposito, se ne ha completata una (2026-09-07) — segnale
# d'ISTANZA, non un evento globale: chi costruisce la Task con questo step (quando esisterà una
# vera TaskDefinition "Daydream", non ancora in questo passo) lo collega UNA VOLTA alla creazione,
# esattamente come GameScene collega TechTreePanel.idea_completed una volta in _ready() — stesso
# identico principio di disaccoppiamento: UnloadAction non conosce GameScene/BuildBar, si limita a
# segnalare "un'Idea è stata completata da questo deposito", chi ascolta decide se/come reagire
# (es. _refresh_building_slots_buildable). Un segnale per-istanza invece di un bus/autoload globale
# perché non esiste già un bus di eventi nel progetto (GameSettings è per stato di sessione, non
# eventi) e introdurne uno solo per questo sarebbe sproporzionato rispetto al bisogno reale.
# Emesso SOLO dal ramo pensiero (il ramo fisico non produce mai Idee) — vedi on_complete sotto.
signal idea_completed(idea_id: String)

# Emesso OGNI VOLTA che questo deposito esegue davvero il ramo pensiero (2026-09-07, richiesta
# utente — effetto visivo "una lampadina sale e sfuma") — a differenza di idea_completed sopra, che
# scatta SOLO quando quel pensiero fa scattare il completamento dell'Idea attiva, questo scatta ad
# OGNI deposito riuscito (pending_thought era true, Folk risolvibile), completi o meno l'Idea.
# Nessun payload: chi ascolta ha già l'individuo (lo cattura al momento del collegamento, vedi
# GameScene._debug_test_daydream_task), questa classe non lo conosce come tipo concreto (Variant).
# Emesso SOLO dal ramo pensiero, stesso motivo di idea_completed sopra.
signal thought_deposited()

# Bersaglio del ramo FISICO (2026-09-09) — null (default) = ramo pensiero, comportamento invariato
# rispetto a prima del rename; valorizzato = ramo fisico (deposita individual.carried_resource_
# name/carried_quantity in questo Building via BuildingStorageService, vedi on_complete sotto).
# Iniettato dal costruttore, mai risolto da questa classe (nessuna ricerca automatica di edificio,
# nessun fallback multi-edificio — chi costruisce la Task decide già QUALE edificio, oggi solo un
# debug hook o un futuro click, stesso principio già seguito da PickUpAction.macro_state).
var target_building: Building = null

# Esito della riverifica spazio fatta in activate() sotto (2026-09-09, richiesta utente —
# re-routing su magazzino pieno, poi GENERALIZZATO nello stesso canale usato per la ricerca
# magazzino iniziale post-PickUp, vedi context["pending_warehouse_search"] sotto): true se, al
# momento di attivare questo step, target_building NON ha più posto per l'INTERA carried_quantity —
# scoperto tipicamente perché qualcun altro ha riempito il magazzino nel frattempo (il WalkAction
# precedente in questa stessa Task può aver richiesto diversi giorni di gioco). Quando true,
# on_complete() sotto salta ESPLICITAMENTE il deposito fisico (nessuna chiamata a store()): la
# richiesta di ricerca è già stata scritta in context da activate(), e HumanIndividualActionService.
# apply_action la consuma DOPO on_complete() (vedi lì, _handle_pending_warehouse_search) — questo
# flag esiste solo per far sì che on_complete() sappia di dover stare fermo, non duplica la logica
# di ricerca vera e propria. Rinominato da _needs_reroute (2026-09-09) per lo stesso motivo di
# generalizzazione — nessun cambio di comportamento, solo nome.
var _needs_warehouse_search: bool = false

# Distanza dell'ultimo "cammina via" dopo un deposito fisico riuscito (2026-09-09, richiesta utente
# — haul_resource, "stesso schema di walk_away in Daydream") — STESSO valore di GameScene._DEBUG_
# DAYDREAM_LEAVE_DISTANCE (5.0), stesso motivo lì dichiarato: evita che più individui si accumulino
# "uno sopra l'altro" sulla stessa microcella dopo un deposito ripetuto. Qui però è una vera
# costante di classe (non un valore di debug "usa e getta"): haul_resource, a differenza del test
# Daydream, non è un hook temporaneo.
const WALK_AWAY_DISTANCE: float = 5.0

# Costo/durata del deposito FISICO (2026-09-10, richiesta utente — "lo metterei come unload, sia
# come costo che come tempo", stesso schema esatto di PickUpAction.get_stamina_delta/is_complete:
# un accumulatore _elapsed confrontato con _duration, tasso = _total_stamina_cost/_duration).
# SOLO il ramo FISICO (target_building != null) li valorizza (vedi activate() sotto) — il ramo
# PENSIERO (Daydream, un'idea non occupa spazio) li lascia SEMPRE a 0.0, quindi resta a costo zero
# per costruzione (get_stamina_delta ritorna 0.0 quando _duration<=0, vedi sotto): nessun ramo
# separato necessario, la stessa formula generica dà "zero" al pensiero semplicemente perché non ha
# mai un `quantity_to_deposit`/space_per_unit da cui derivare una durata. Richiesta esplicita utente
# ("se impiega tempo va bene lo stesso" per il pensiero) soddisfatta lasciandolo a durata 0 — nessuna
# durata artificiale inventata per un'azione che non ha un analogo naturale di "quantità" da timerare.
#
# STAMINA_COST_PER_SPACE_UNIT — STESSO valore di PickUpAction.STAMINA_COST_PER_SPACE_UNIT (2.0),
# per simmetria "costa uguale scaricare quanto raccogliere la stessa quantità" — valore di partenza
# ARBITRARIO, stesso trattamento "da bilanciare" di ogni altra costante di questo sistema. Costante
# separata (non condivisa/importata da PickUpAction) perché le due classi restano indipendenti,
# stesso principio già seguito ovunque in questo progetto (nessuna costante condivisa tra Action).
const STAMINA_COST_PER_SPACE_UNIT: float = 2.0

var _duration: float = 0.0
var _total_stamina_cost: float = 0.0
var _elapsed: float = 0.0

# Guardia persistenza (2026-09-10) — STESSO principio/STESSO motivo di PickUpAction._restored_from_
# save: activate() sotto ora RICALCOLA _duration/_total_stamina_cost/_elapsed=0.0 da zero ogni volta
# che diventa lo step attivo (prima di questo passo era innocuo, l'azione era istantanea e non aveva
# progresso da perdere) — senza questa guardia, un salvataggio a metà scarico perderebbe silenziosamente
# _elapsed ripartendo da 0 al reload (GameLoadService richiama SEMPRE activate() dopo la
# deserializzazione, stesso motivo già documentato in PickUpAction.gd).
var _restored_from_save: bool = false


func _init(p_target_building: Building = null) -> void:
	target = null
	target_building = p_target_building


# Nessun override prima d'ora (ereditava Action.activate — solo individual.is_moving = false,
# invariato: super() chiamato PRIMA di ogni log, stesso ordine di WalkAction/PickUpAction.activate)
# — aggiunto SOLO per diagnostica (2026-09-09, richiesta utente: "perché il carico non diminuisce
# dopo l'arrivo al magazzino"). Logga esattamente lo stato con cui questo step PARTE: target_
# building risolto (id/posizione) — null qui significherebbe che il ramo fisico non scatterà mai in
# on_complete() (route silenziosa verso il ramo pensiero) — categorie accettate, e zaino
# dell'individuo AL MOMENTO dell'attivazione (prima di qualunque decremento).
#
# RIVERIFICA SPAZIO (2026-09-09, richiesta utente — re-routing, poi GENERALIZZATO nello stesso
# canale di ricerca magazzino usato da PickUpAction.on_complete per la ricerca iniziale, vedi
# HumanIndividualActionService._handle_pending_warehouse_search) — aggiunta qui, PRIMA di ogni log:
# il momento in cui questo step diventa attivo è l'ultima occasione per scoprire che target_building
# si è riempito nel frattempo (tra quando la Task è stata creata — magari con WalkAction ancora da
# percorrere — e ora). Se non c'è più posto per l'INTERA carried_quantity, questa Action non deposita
# affatto in questo passaggio: scrive invece context["pending_warehouse_search"] = {"resource_name",
# "quantity", "excluded_building_ids", "discard_on_failure": true} — STESSA forma generica che
# PickUpAction.on_complete scrive per la ricerca iniziale (vedi lì), così un solo handler in
# HumanIndividualActionService serve entrambi i casi, invece di due flag paralleli (reroute_pending/
# reroute_excluded_building_ids, come prima di questa generalizzazione).
#
# "discard_on_failure": true SOLO qui (non nella scrittura di PickUpAction) — DEVIAZIONE aggiuntiva
# rispetto alla forma letterale del Dictionary richiesta (che elencava solo resource_name/quantity/
# excluded_building_ids): necessaria perché i DUE casi hanno un esito diverso quando la ricerca non
# trova nulla (richiesta esplicita utente per entrambi, punti distinti dello stesso prompt) — qui
# (re-routing, un edificio già raggiunto è risultato pieno) nessun sistema di scarico a terra esiste
# ancora, quindi "nessun candidato" comporta la perdita TEMPORANEA della merce; per PickUpAction
# invece "nessun candidato" lascia semplicemente l'individuo con la merce in spalla, nessuna perdita
# (vedi _handle_pending_warehouse_search per come il campo pilota questa scelta). Un solo campo
# booleano in più nello stesso Dictionary, non un secondo segnale.
#
# warehouse_search_excluded_building_ids (2026-09-09) — persistente in context per l'intera durata
# della Task (mai azzerato qui, cresce ad ogni tentativo fallito), generalizzazione dell'ex
# reroute_excluded_building_ids: PickUpAction.on_complete NON lo tocca (la sua ricerca iniziale parte
# sempre con excluded_building_ids=[] indipendentemente da questo), solo UnloadAction.activate lo
# legge/accresce quando scopre un magazzino pieno — così un secondo/terzo tentativo fallito continua
# a escludere anche i precedenti, evitando un loop sullo stesso magazzino pieno.
#
# Nessun effetto se target_building è null (ramo pensiero, non riguardato da questo meccanismo) o se
# lo zaino è già vuoto (nulla da ricollocare).
#
# COSTO/DURATA (2026-09-10, richiesta utente) — risolti QUI, stesso momento/stesso principio di
# PickUpAction.activate: SOLO quando il deposito avverrà davvero (still_fits true sotto, quantità
# intera già garantita depositabile) — se invece scatta il re-routing (still_fits false) o lo zaino è
# vuoto o target_building è null (ramo pensiero), _duration/_total_stamina_cost restano a 0.0 (resettati
# incondizionatamente qui sotto prima di ogni ramo), quindi is_complete()/get_stamina_delta() sotto
# restano "istantanei, costo zero" per tutti quei casi — esattamente come oggi per il pensiero,
# invariato.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _restored_from_save:
		return
	_needs_warehouse_search = false
	_duration = 0.0
	_total_stamina_cost = 0.0
	_elapsed = 0.0
	if target_building != null and individual.carried_quantity > 0:
		var max_depositable := BuildingStorageService.get_max_depositable(target_building, individual.carried_resource_name)
		var still_fits: bool = max_depositable >= individual.carried_quantity
		if not still_fits:
			_needs_warehouse_search = true
			# Costruita manualmente (int(id) per elemento), non Array[int](context.get(...)) —
			# quel costrutto tipizzato non è comunque necessario qui e questo loop gestisce anche
			# il caso in cui la lista arrivi da un context deserializzato da JSON (numeri sempre
			# float, mai int — stesso principio già richiesto altrove nel progetto per i save).
			var excluded: Array[int] = []
			for raw_id in context.get("warehouse_search_excluded_building_ids", []):
				excluded.append(int(raw_id))
			if not excluded.has(target_building.id):
				excluded.append(target_building.id)
			context["warehouse_search_excluded_building_ids"] = excluded
			context["pending_warehouse_search"] = {
				"resource_name": individual.carried_resource_name,
				"quantity": individual.carried_quantity,
				"excluded_building_ids": excluded,
				"discard_on_failure": true,
			}
			if DebugLogging.ENABLED:
				print("[UNLOAD] activate: target_building id=%d non ha più posto per carried_quantity=%d — pending_warehouse_search scritto, esclusi finora=%s" % [
					target_building.id, individual.carried_quantity, str(excluded)
				])
		else:
			# Il deposito avverrà davvero questo passaggio (nessun re-routing) — costo/durata
			# risolti sull'INTERA carried_quantity (still_fits sopra garantisce che ci entri tutta),
			# stessa formula di PickUpAction.activate: durata proporzionale allo spazio occupato
			# rispetto alla capacità di carico TOTALE dell'individuo (stesso "metro" usato per la
			# raccolta, coerente da entrambi i lati del trasporto), costo proporzionale allo spazio.
			var resource_rules := CaloricCalculator.get_caloric_source_rules(individual.carried_resource_name)
			var space_per_unit: float = resource_rules.space_per_unit if resource_rules != null else 0.0
			var space_to_deposit: float = float(individual.carried_quantity) * space_per_unit
			if space_to_deposit > 0.0 and individual.max_carry_capacity > 0.0:
				_duration = space_to_deposit / individual.max_carry_capacity
				_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_to_deposit
			if DebugLogging.ENABLED:
				print("[UNLOAD] activate: deposito previsto di carried_quantity=%d — duration=%.3fgg, total_stamina_cost=%.1f" % [
					individual.carried_quantity, _duration, _total_stamina_cost
				])
	if not DebugLogging.ENABLED:
		return
	if target_building == null:
		print("[UNLOAD] activate: target_building=null (ramo PENSIERO) | carried_resource_name='%s' carried_quantity=%d" % [
			individual.carried_resource_name, individual.carried_quantity
		])
		return
	var accepted_categories: String = "QUALUNQUE (array vuoto)" if target_building.rules != null and target_building.rules.accepted_categories.is_empty() else str(target_building.rules.accepted_categories if target_building.rules != null else "rules=null")
	print("[UNLOAD] activate: target_building id=%d macro=(%d,%d) micro=(%d,%d) categorie_accettate=%s | individuo carried_resource_name='%s' carried_quantity=%d" % [
		target_building.id, target_building.macro_x, target_building.macro_y,
		target_building.micro_x, target_building.micro_y, accepted_categories,
		individual.carried_resource_name, individual.carried_quantity
	])


# Nessun override prima d'ora (ereditava Action.get_stamina_delta — sempre 0.0, invariato per il
# ramo pensiero e per ogni caso "istantaneo" di sopra) — STESSO schema esatto di PickUpAction: tasso
# = _total_stamina_cost/_duration, accumula _elapsed. _duration<=0.0 ritorna 0.0 SENZA incrementare
# _elapsed (stesso "azione immediatamente completa, nessun costo" già in PickUpAction) — questo è
# esattamente il meccanismo che garantisce zero costo per il ramo pensiero (richiesta esplicita
# utente): non serve un `if target_building == null: return 0.0` dedicato, il pensiero non ha mai
# una _duration diversa da zero per costruzione (vedi activate() sopra).
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _duration <= 0.0:
		return 0.0
	_elapsed += delta
	return -(_total_stamina_cost / _duration) * delta


# NON PIÙ sempre true (2026-09-10, richiesta utente — costo/durata reali per il deposito fisico) —
# ora confronta _elapsed con _duration, STESSO schema esatto di PickUpAction/ThinkAction.is_complete.
# Resta "istantanea" (0.0 >= 0.0, vero da subito) per QUALUNQUE caso in cui activate() ha lasciato
# _duration a 0.0: ramo pensiero (Daydream), zaino vuoto, target_building null, o re-routing appena
# scattato — tutti e quattro invariati rispetto a prima di questo passo, nessuno di loro acquisisce
# una durata artificiale. Il ramo FISICO con un deposito davvero in corso è l'UNICO che ora impiega
# più di un frame/giorno per completarsi.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	if DebugLogging.ENABLED and _elapsed < _duration:
		print("[UNLOAD] is_complete: false (in corso) — elapsed=%.3f/%.3fgg, target_building=%s" % [
			_elapsed, _duration, str(target_building.id) if target_building != null else "null"
		])
	return _elapsed >= _duration


# Due rami MUTUAMENTE ESCLUSIVI secondo target_building (2026-09-09, richiesta utente) — mai
# entrambi nella stessa istanza: chi costruisce l'azione decide già quale ramo vuole tramite il
# costruttore, non un caso ambiguo da risolvere qui dentro.
#
# Ramo FISICO (target_building != null, Step 1 BuildingStorageService) — legge lo zaino
# dell'individuo (carried_resource_name/carried_quantity), tenta di depositarlo per intero in
# target_building via BuildingStorageService.store (che clampa da sé allo spazio libero/categoria
# accettata), poi decrementa lo zaino di SOLO quanto è stato effettivamente depositato: se lo
# spazio non basta (o la categoria non è accettata), il resto resta trasportato, MAI perso. Nessun
# effetto se lo zaino è già vuoto (carried_resource_name == "" o carried_quantity <= 0) — niente da
# scaricare, coerente col "no-op istantaneo senza effetti" già seguito da PickUpAction.on_complete
# quando _quantity_to_collect è 0.
#
# Ramo PENSIERO (target_building == null, invariato dal rename) — risolve Folk dalla stessa catena
# già in uso altrove (individual.source_group_ref.folk_ref, vedi HumanStaminaIndividualService per
# il precedente), poi IdeaProgressService.add_thoughts(folk, 1). Guardie difensive su
# source_group_ref/folk_ref null (stesso trattamento già visto altrove per questa catena, es.
# HumanStaminaIndividualService.recalculate_max_stamina) — non dovrebbero mai essere null con dati
# coerenti, ma questa azione non deve fallire rumorosamente se lo sono.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if target_building != null:
		if DebugLogging.ENABLED:
			print("[UNLOAD] on_complete: ramo FISICO (target_building id=%d)" % target_building.id)
		# _needs_warehouse_search (2026-09-09, richiesta utente — re-routing, generalizzato) — deciso
		# da activate() sopra: nessun deposito qui, HumanIndividualActionService.apply_action gestisce
		# la ricerca leggendo context DOPO questa chiamata (vedi commento in testa al file).
		if _needs_warehouse_search:
			if DebugLogging.ENABLED:
				print("[UNLOAD] on_complete: _needs_warehouse_search=true — nessun deposito, delego la ricerca magazzino ad apply_action.")
			return
		if individual.carried_resource_name == "" or individual.carried_quantity <= 0:
			if DebugLogging.ENABLED:
				print("[UNLOAD] on_complete: zaino vuoto (carried_resource_name='%s' carried_quantity=%d) — nessun deposito, return anticipato." % [
					individual.carried_resource_name, individual.carried_quantity
				])
			return
		if DebugLogging.ENABLED:
			# can_accept/get_free_space richiamati QUI solo per il log — sola lettura, nessun
			# effetto collaterale, store() sotto li ricalcola comunque da sé indipendentemente da
			# queste due righe (nessuna modifica alla logica esistente).
			print("[UNLOAD] on_complete: can_accept('%s')=%s, free_space=%d, carried_quantity PRIMA=%d" % [
				individual.carried_resource_name,
				BuildingStorageService.can_accept(target_building, individual.carried_resource_name),
				BuildingStorageService.get_free_space(target_building),
				individual.carried_quantity,
			])
		var carried_before_deposit: int = individual.carried_quantity
		# carried_decay_fraction (2026-09-09, richiesta utente — Step 3 decadimento) — passato a
		# store() così la frazione dello zaino si fonde (media pesata) con quella già presente nel
		# magazzino per lo stesso resource_name, invece di andare persa/azzerata al deposito.
		var deposited: int = BuildingStorageService.store(
			target_building, individual.carried_resource_name, individual.carried_quantity, individual.carried_decay_fraction
		)
		if DebugLogging.ENABLED:
			print("[UNLOAD] on_complete: store() ha depositato %d unità (su %d richieste)" % [deposited, carried_before_deposit])
		if deposited <= 0:
			if DebugLogging.ENABLED:
				print("[UNLOAD] on_complete: deposited<=0 — nessun decremento zaino, return anticipato. carried_quantity resta %d" % individual.carried_quantity)
			return
		individual.carried_quantity -= deposited
		if individual.carried_quantity <= 0:
			individual.carried_quantity = 0
			individual.carried_resource_name = ""
			# carried_decay_fraction azzerata insieme a resource_name/quantity (2026-09-09) — stesso
			# principio già dichiarato su HumanIndividual.carried_decay_fraction: mai un valore
			# "orfano" associato a uno zaino vuoto. Il resto NON scaricato (deposited < carried_
			# before_deposit, quantity ancora > 0 sotto) mantiene invece la propria decay_fraction
			# INVARIATA — è ancora fisicamente nello zaino, nessuna ragione di toccarla.
			individual.carried_decay_fraction = 0.0
		if DebugLogging.ENABLED:
			print("[UNLOAD] on_complete: carried_quantity PRIMA=%d -> DOPO=%d (carried_resource_name DOPO='%s')" % [
				carried_before_deposit, individual.carried_quantity, individual.carried_resource_name
			])
		# "Cammina via" (2026-09-09, richiesta utente — haul_resource, stesso schema di walk_away in
		# Daydream: target_building.position + Vector2.from_angle(randf() * TAU) * 5.0) — SOLO qui,
		# deposito FISICO riuscito (deposited > 0, già garantito da questo punto in poi: il ramo
		# pensiero sotto non passa mai di qui), mai per il ramo pensiero (richiesta esplicita utente:
		# "quando UnloadAction.on_complete() deposita fisicamente con successo (non il ramo
		# pensiero)"). Questa Action non ha accesso alla Task (solo individual/context, vedi Action.
		# gd) quindi non può accodare direttamente un nuovo WalkAction: scrive la posizione target in
		# context, HumanIndividualActionService.apply_action la consuma SUBITO dopo on_complete()
		# (stesso identico canale/stesso momento già usato per pending_warehouse_search sopra) e fa
		# lei l'append_steps vero.
		#
		# Conversione cross-macrocella verificata (richiesta utente, 2026-09-09) — NON omessa per
		# "sappiamo già che è sempre zero": individual.home_macro_coords può SOLO essere diverso da
		# (target_building.macro_x, target_building.macro_y) se l'individuo avesse attraversato un
		# bordo di macrocella camminando fin qui, ma GameScene._attempt_macro_cell_transition chiama
		# individual.stop() (azzera current_task) ad OGNI attraversamento — quindi una Task il cui
		# WalkAction precedente avrebbe dovuto attraversare un bordo per raggiungere target_building
		# verrebbe interrotta PRIMA di arrivare, e questo on_complete() fisico non verrebbe mai
		# raggiunto per quel caso. In pratica l'offset qui sotto risulta quindi sempre (0,0) con lo
		# stato attuale del movimento — ma la formula resta quella GENERALE (stessa già in uso in
		# _try_assign_unload_command_on_right_click/_debug_test_daydream_task), per coerenza e nel
		# caso quella limitazione sui bordi venga rimossa in futuro senza che nessuno si ricordi di
		# aggiornare anche questo punto.
		var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
		var building_position: Vector2 = Vector2(target_building.micro_x, target_building.micro_y) + macro_offset
		context["pending_walk_away_position"] = building_position + Vector2.from_angle(randf() * TAU) * WALK_AWAY_DISTANCE
		return

	if DebugLogging.ENABLED:
		print("[UNLOAD] on_complete: ramo PENSIERO (target_building=null) — pending_thought=%s" % individual.pending_thought)
	if not individual.pending_thought:
		return
	if individual.source_group_ref == null or individual.source_group_ref.folk_ref == null:
		return
	var folk: Folk = individual.source_group_ref.folk_ref
	individual.pending_thought = false
	thought_deposited.emit()
	if IdeaProgressService.add_thoughts(folk, 1):
		idea_completed.emit(folk.completed_ideas[-1])


# Persistenza (2026-09-09, richiesta utente; ESTESA 2026-09-10 per costo/durata) — target_building
# via building.id (l'unico identificatore stabile/serializzabile, stesso principio di
# PopulationGroup.id: Building stesso non è mai serializzato per riferimento diretto, JSON non
# trasporta riferimenti a oggetti vivi) PIÙ duration/elapsed/total_stamina_cost (2026-09-10, stesso
# motivo di PickUpAction/ThinkAction: senza, un salvataggio a metà deposito fisico perderebbe
# silenziosamente il progresso già maturato, ripartendo da 0 al reload — vedi _restored_from_save).
# total_stamina_cost persistito ESPLICITAMENTE (a differenza di PickUpAction, che non lo fa — la
# sua get_stamina_delta si affiderebbe a un _total_stamina_cost rimasto a 0.0 dopo un reload,
# azzerando silenziosamente il drain residuo: un gap preesistente non toccato qui, ma non replicato
# in questa classe) — così get_stamina_delta() resta corretta anche dopo un reload a metà scarico.
# `target` resta sempre null per questa Action (vedi _init sopra) quindi non è mai coperto dal
# trattamento GENERICO di TaskPersistenceService.serialize_task.
func get_save_data() -> Dictionary:
	var data := {"duration": _duration, "elapsed": _elapsed, "total_stamina_cost": _total_stamina_cost}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


# Il building vero viene risolto e iniettato da TaskPersistenceService._build_step (che ha
# accesso a World.buildings, questa classe non ce l'ha — stesso principio già seguito da
# PickUpAction/macro_state) PRIMA di chiamare questo metodo: la chiave "target_building_id" è letta
# direttamente da _build_step, non da qui. duration/elapsed/total_stamina_cost (2026-09-10) invece
# SÌ da qui — stesso schema esatto di PickUpAction.load_save_data: marca _restored_from_save così
# la ripetizione di activate() che GameLoadService invoca subito dopo (per ripristinare gli effetti
# collaterali non persistiti delle altre Action, es. WalkAction) non sovrascriva questo progresso
# appena ripristinato ricalcolandolo da zero.
func load_save_data(data: Dictionary) -> void:
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_total_stamina_cost = float(data.get("total_stamina_cost", 0.0))
	_restored_from_save = true
