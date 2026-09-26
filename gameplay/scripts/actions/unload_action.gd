class_name UnloadAction
extends Action

# Rinominata da DepositAction (2026-09-09, richiesta utente, BuildingStorageService Step 1) — il
# nome generico "Deposit" era ambiguo col deposito FISICO in un edificio, che oggi diventa reale:
# "Unload" resta l'azione GENERICA di scarico, con due rami distinti secondo `deposit_kind` (vedi
# enum DepositKind/_init/on_complete sotto), non più solo un TODO per il ramo fisico. Nessun altro
# cambio di comportamento per il ramo pensiero (Folk.thoughts_invested via IdeaProgressService)
# rispetto a prima del rename. Nessun target di posizione (stesso pattern di RestAction/ThinkAction
# — vedi _init sotto): il posizionamento (davanti al Folk per il pensiero, o davanti all'edificio
# per il ramo fisico) è già garantito dal WalkAction precedente nella stessa Task, questa classe non
# verifica/richiede nulla sulla posizione.
#
# DISCRIMINATORE ESPLICITO deposit_kind, non più la nullità di target_building (2026-09-10,
# richiesta utente — scollegare la scelta di ramo da target_building, in vista di una futura
# ricerca con predicate "accepts_thoughts" che potrebbe risolvere un Building anche per il ramo
# PENSIERO). PRIMA di questo passo il discriminatore era implicito: target_building != null →
# fisico, target_building == null → pensiero — questo impediva di passare un Building risolto
# dinamicamente al ramo pensiero, perché sarebbe caduto per errore nel ramo fisico. Ora
# target_building è un parametro indipendente (può essere valorizzato o meno indipendentemente dal
# tipo di deposito, vedi DepositKind sotto) — comportamento di haul_resource INVARIATO: ogni call
# site che oggi passa un building lo accoppia esplicitamente a DepositKind.RESOURCE, ogni call site
# che oggi non passa nulla usa DepositKind.THOUGHT (anche il default del parametro, per coerenza col
# comportamento implicito di prima per qualunque chiamante non ancora aggiornato).
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

# Emesso OGNI VOLTA che questo deposito esegue DAVVERO il ramo FISICO (2026-09-12, richiesta
# utente — bugfix "il mucchietto non si aggiorna in automatico quando viene fatto il deposito"):
# STESSO principio di thought_deposited sopra (un evento per deposito riuscito, non un fallimento
# distruttivo se nessuno ascolta), ma per il ramo opposto — deposited > 0, vedi on_complete sotto.
# UnloadAction non conosce GameScene/MicroCellRenderer, si limita a segnalare "ho depositato
# DAVVERO in `building`", chi ascolta decide se/come rinfrescare il disegno (vedi GameScene.
# _on_resource_deposited, che richiama _refresh_building_visuals — necessario perché la griglia di
# stoccaggio sulla mappa, vedi MicroCellRenderer._draw_deposit_site_storage_grid, legge da una COPIA
# di Building.stored_resources presa al momento dell'ultimo refresh, non dall'oggetto live).
signal resource_deposited(building: Building)

# Consegna effettiva della TRANSPORT alla propria destinazione (2026-09-20, ripetizione automatica): emesso da
# on_complete() SOLO per l'Unload la cui destinazione e' quella indicata da context["transport_destination_id"]
# (chiave non consumata dalla factory, quindi ancora in task.context; l'Unload della destinazione e' quello
# costruito da transport.tres, mai i Walk+Unload aggiunti a runtime per i residui, che puntano ad altri
# magazzini: la destinazione e' in excluded_building_ids). `delivered` = unita' della risorsa
# context["transport_delivery_resource"] DAVVERO entrate nella destinazione (0 se non e' entrato niente);
# `context` e' il task.context vivo, cosi' chi ascolta legge contatore e obiettivo senza un secondo canale.
signal transport_delivered(individual: Variant, context: Dictionary, delivered: int)

# Discriminatore ESPLICITO di ramo (2026-09-10, vedi nota in testa al file) — RESOURCE = ramo
# FISICO (deposita TUTTE le varietà di individual.carried_resources che l'edificio accetta in target_building via
# BuildingStorageService), THOUGHT = ramo PENSIERO (IdeaProgressService.add_thoughts). Sostituisce
# la deduzione implicita da `target_building != null` usata prima di questo passo — activate()/
# on_complete() sotto controllano SEMPRE questo campo, mai più la nullità di target_building.
enum DepositKind { RESOURCE, THOUGHT }

# THOUGHT di default (2026-09-10) — stesso comportamento implicito di prima di questo passo per
# qualunque chiamante che costruisca UnloadAction senza specificare nulla (equivalente al vecchio
# "target_building resta null di default = ramo pensiero"); ogni call site reale in questo progetto
# lo passa comunque esplicitamente (vedi call site aggiornati), il default è solo una rete di
# sicurezza coerente col comportamento pre-refactor.
var deposit_kind: DepositKind = DepositKind.THOUGHT

# Bersaglio opzionale, indipendente da deposit_kind (2026-09-10, DEVIAZIONE dal comportamento
# pre-refactor: PRIMA la nullità di questo campo era essa stessa il discriminatore di ramo, vedi
# deposit_kind sopra) — oggi usato attivamente SOLO dal ramo FISICO (deposita individual.
# carried_resources in questo Building via BuildingStorageService, vedi on_complete
# sotto); un ramo PENSIERO con target_building valorizzato è ora strutturalmente possibile (es. un
# futuro Building trovato con predicate "accepts_thoughts") ma questa classe non lo consuma ancora
# per quel ramo — arriverà con un handler successivo, fuori scope qui. Iniettato dal costruttore,
# mai risolto da questa classe (nessuna ricerca automatica di edificio, nessun fallback
# multi-edificio — chi costruisce la Task decide già QUALE edificio, oggi solo un debug hook o un
# click, stesso principio già seguito da PickUpAction.macro_state).
var target_building: Building = null

# Distanza dell'ultimo "cammina via" dopo un deposito fisico riuscito (2026-09-09, richiesta utente
# — haul_resource, "stesso schema di walk_away in Daydream") — STESSO valore di GameScene._DEBUG_
# DAYDREAM_LEAVE_DISTANCE (5.0), stesso motivo lì dichiarato: evita che più individui si accumulino
# "uno sopra l'altro" sulla stessa microcella dopo un deposito ripetuto. Qui però è una vera
# costante di classe (non un valore di debug "usa e getta"): haul_resource, a differenza del test
# Daydream, non è un hook temporaneo.
# Oggi usata SOLO dal ramo pensiero (Daydream); il ramo fisico usa PHYSICAL_WALK_AWAY_DISTANCE sotto.
const WALK_AWAY_DISTANCE: float = 5.0
# "Cammina via" dopo un deposito FISICO completo — transport, haul_resource e scarico manuale dello
# zaino (2026-09-25, richiesta utente: da 5 a circa 1 microcella, un piccolo passo per liberare la
# microcella dell'edificio invece di un allontanamento vero). Misurata dal centro della microcella
# dell'edificio: il tratto effettivamente percorso è quindi circa 0.5–1.5 microcelle.
const PHYSICAL_WALK_AWAY_DISTANCE: float = 1.0

# Costo/durata del deposito FISICO (2026-09-10, richiesta utente — "lo metterei come unload, sia
# come costo che come tempo", stesso schema esatto di PickUpAction.get_stamina_delta/is_complete:
# un accumulatore _elapsed confrontato con _duration, tasso = _total_stamina_cost/_duration).
# SOLO il ramo FISICO (deposit_kind == RESOURCE) li valorizza (vedi activate() sotto) — il ramo
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


# Modalità "cintura" (2026-09-25, richiesta utente — riponi un attrezzo in un magazzino dal pannello
# individuo): se >= 0, lo step deposita in target_building l'attrezzo di QUESTO slot della cintura,
# senza passare dallo zaino e senza la logica di re-routing/ricerca magazzino del deposito normale
# (il magazzino è già stato scelto da GameScene con WarehouseSelectionService.find_best). Richiede
# deposit_kind RESOURCE. -1 (default) = deposito normale dallo zaino. Persistito (get_save_data, letto
# da TaskPersistenceService._build_step).
var unequip_slot_index: int = -1


func _init(p_target_building: Building = null, p_deposit_kind: DepositKind = DepositKind.THOUGHT, p_unequip_slot_index: int = -1) -> void:
	target = null
	target_building = p_target_building
	deposit_kind = p_deposit_kind
	unequip_slot_index = p_unequip_slot_index
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Nessun override prima d'ora (ereditava Action.activate — solo individual.is_moving = false,
# invariato: super() chiamato PRIMA di ogni log, stesso ordine di WalkAction/PickUpAction.activate)
# — aggiunto SOLO per diagnostica (2026-09-09, richiesta utente: "perché il carico non diminuisce
# dopo l'arrivo al magazzino"). Logga esattamente lo stato con cui questo step PARTE: deposit_kind
# (2026-09-10 — il vero discriminatore di ramo, non più la nullità di target_building, vedi nota in
# testa al file), target_building risolto (id/posizione) se presente, categorie accettate, e zaino
# dell'individuo AL MOMENTO dell'attivazione (prima di qualunque decremento).
#
# DEPOSITO PARZIALE (2026-09-14, richiesta utente — bugfix "porto più/diverso materiale di quanto
# serve, oggi va tutto perso invece di depositare quel che entra"; RICALIBRATO rispetto alla vecchia
# logica "still_fits" — vedi cronologia sotto) — costo/durata risolti QUI su quanto verrà DAVVERO
# depositato in QUESTO passaggio (min(quantità della varietà in spalla, max_depositable), per ogni varietà accettata, MAI più l'intera
# quantità in spalla a prescindere): se il posto residuo è meno di quanto trasportato, l'individuo
# scarica solo quella parte (tempo/stamina proporzionali a quella sola quantità, coerente col
# principio "il costo riflette il lavoro davvero svolto") — il deposito VERO E PROPRIO (store(),
# decremento zaino, eventuale re-routing del residuo) resta in on_complete() sotto, che rilegge
# get_max_depositable DAL VIVO (può essere cambiato nel frattempo, vedi sotto) invece di fidarsi di
# questo valore ormai "vecchio" se la durata calcolata qui non è stata 0.0 (più giorni di gioco
# trascorsi in mezzo).
#
# CRONOLOGIA (perché non c'è più un ramo "still_fits") — PRIMA (2026-09-09/13) un controllo
# `max_depositable >= quantità in spalla` decideva TUTTO O NIENTE: se l'intero carico non entrava,
# zero deposito qui, l'INTERA quantità andava in re-routing (context["pending_warehouse_search"],
# vedi sotto) — comportamento CONFERMATO SBAGLIATO con l'utente: portare 4 stick a un cantiere che
# ne aspetta ancora 2 faceva perdere il viaggio per intero (0 depositati), invece dei 2 che
# sarebbero comunque entrati. Zero fits (max_depositable<=0, es. risorsa sbagliata o cantiere già
# rifornito) resta l'UNICO caso in cui NON si deposita nulla qui — un `min()` con 0 dà comunque 0,
# nessun ramo speciale necessario.
#
# Nessun effetto se deposit_kind != RESOURCE (ramo pensiero, non riguardato da questo meccanismo) o
# se lo zaino è già vuoto (nulla da ricollocare) — _duration/_total_stamina_cost restano a 0.0
# (resettati incondizionatamente qui sotto prima di ogni ramo), quindi is_complete()/get_stamina_
# delta() sotto restano "istantanei, costo zero" per quei casi, esattamente come per il pensiero.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if _restored_from_save:
		return
	_duration = 0.0
	_total_stamina_cost = 0.0
	_elapsed = 0.0
	if unequip_slot_index >= 0:
		_activate_unequip(individual)
		return
	if deposit_kind == DepositKind.RESOURCE and target_building != null and not individual.carried_resources.is_empty():
		# Zaino multi-risorsa (2026-09-20, richiesta utente): deposita TUTTO quello che l'edificio accetta.
		# Costo/durata = somma, per ogni varietà accettata, di min(get_max_depositable, quantità in spalla) —
		# STESSA formula di PickUpAction.activate applicata a ciò che entrerà davvero questo giro (2026-09-14:
		# solo quantity_to_deposit_now, non l'intero carico). Stima: le varietà si contendono gli stessi slot,
		# quindi on_complete (che le deposita in sequenza) può depositare meno di quanto stimato qui — mai più.
		var space_to_deposit: float = 0.0
		var planned_units: Dictionary = {}
		# Cantiere di una Transport già completato (vedi _is_completed_site_destination): nulla viene
		# pianificato qui, on_complete lo tratta come destinazione non valida (reinstradamento).
		var destination_rejected: bool = _is_completed_site_destination(context)
		for resource_name in individual.carried_resources.keys():
			var carried_units: int = individual.get_carried_quantity(String(resource_name))
			if carried_units <= 0 or destination_rejected or not BuildingStorageService.can_accept(target_building, String(resource_name)):
				continue
			var units_now: int = min(BuildingStorageService.get_max_depositable(target_building, String(resource_name)), carried_units)
			if units_now <= 0:
				continue
			var resource_rules := CaloricCalculator.get_caloric_source_rules(String(resource_name))
			var space_per_unit: float = resource_rules.space_per_unit if resource_rules != null else 0.0
			space_to_deposit += float(units_now) * space_per_unit
			planned_units[resource_name] = units_now
		if not planned_units.is_empty():
			if space_to_deposit > 0.0 and individual.max_carry_capacity > 0.0:
				_duration = space_to_deposit / individual.max_carry_capacity
				_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space_to_deposit
			if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[UNLOAD] activate: deposito previsto %s su zaino %s (residuo restante gestito da on_complete) — duration=%.3fgg, total_stamina_cost=%.1f" % [
					str(planned_units), str(individual.carried_resources), _duration, _total_stamina_cost
				])
		elif DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] activate: target_building id=%d non ha ALCUN posto (o non accetta nulla) per %s — deposito istantaneo nullo, on_complete gestirà il re-routing dell'intero carico." % [
				target_building.id, str(individual.carried_resources.keys())
			])
	# Guardia zaino GIÀ vuoto all'arrivo (2026-09-16, richiesta utente — "Scaricare risorsa" attivata
	# per errore, poi se lo zaino si svuota per un motivo indipendente [es. un'altra Task/comando che
	# nel frattempo consuma/scarta il carico] la Task andava in tilt") — RAMO ESPLICITO, PRIMA
	# implicito: se `carried_resources` vuoto già al momento di questa activate(), il ramo
	# sopra non entra affatto (guardia `not carried_resources.is_empty()`), quindi _duration/
	# _total_stamina_cost restano a 0.0 (già azzerati poco sopra) — is_complete() sotto risulta VERO
	# da subito (0.0 >= 0.0), esattamente come "task_activity_idle": questo step (e quindi l'intera
	# Task "Scaricare risorsa", che è [Walk, Unload]) si DICHIARA COMPLETO immediatamente, zero
	# costo, nessun deposito tentato — mai un errore/blocco. Log dedicato per diagnosticare il caso
	# (prima silenzioso, nessun ramo lo intercettava esplicitamente).
	elif deposit_kind == DepositKind.RESOURCE and target_building != null and individual.carried_resources.is_empty():
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] activate: zaino già vuoto all'arrivo (target_building id=%d) — nulla da scaricare, step dichiarato completo istantaneamente, nessun costo." % target_building.id)
	# Riverifica ramo PENSIERO (2026-09-12, richiesta utente — bugfix "deposito nel vuoto") — STESSO
	# principio/STESSO momento della riverifica ramo RESOURCE appena sopra (activate(), quando
	# l'individuo arriva davvero): un pensiero non ha un concetto di "capacità residua" da
	# riverificare (nessuna BuildingStorageService coinvolta per questo ramo), quindi il solo
	# controllo sensato è "questo edificio esiste ancora?" — Building.is_demolished (vedi lì per il
	# perché il riferimento resta valido anche a edificio demolito). pending_thought riportato a
	# false QUI, non in on_complete(): quel metodo ha già un guard `if not individual.pending_thought:
	# return` in testa, quindi azzerarlo qui basta a farlo restare un no-op silenzioso più avanti,
	# senza duplicare la condizione in due posti.
	elif deposit_kind == DepositKind.THOUGHT and target_building != null and target_building.is_demolished:
		individual.pending_thought = false
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] activate: target_building id=%d demolito nel frattempo — pending_thought azzerato, pensiero perso." % target_building.id)
	if not (DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS):
		return
	if deposit_kind != DepositKind.RESOURCE:
		print("[UNLOAD] activate: deposit_kind=THOUGHT (ramo PENSIERO) | target_building=%s | zaino=%s" % [
			(str(target_building.id) if target_building != null else "null"), str(individual.carried_resources)
		])
		return
	var accepted_categories: String = "QUALUNQUE (array vuoto)" if target_building.rules != null and target_building.rules.accepted_categories.is_empty() else str(target_building.rules.accepted_categories if target_building.rules != null else "rules=null")
	print("[UNLOAD] activate: target_building id=%d macro=(%d,%d) micro=(%d,%d) categorie_accettate=%s | individuo zaino=%s" % [
		target_building.id, target_building.macro_x, target_building.macro_y,
		target_building.micro_x, target_building.micro_y, accepted_categories,
		str(individual.carried_resources)
	])


# Destinazione di una Transport che alla creazione era un CANTIERE (context["transport_destination_is_site"],
# scritto da GameScene._build_transport_task) ed è stata completata nel frattempo (2026-09-21, richiesta
# utente): il materiale per costruirla non serve più e non va depositato nell'edificio finito — trattata
# come destinazione non valida, con il reinstradamento esistente verso un magazzino (come per una
# destinazione demolita). Una Transport verso un magazzino vero non ha il flag: nessun effetto.
func _is_completed_site_destination(context: Dictionary) -> bool:
	return deposit_kind == DepositKind.RESOURCE and target_building != null \
		and bool(context.get("transport_destination_is_site", false)) \
		and int(context.get("transport_destination_id", -1)) == target_building.id \
		and target_building.is_complete


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
# _duration a 0.0: ramo pensiero (Daydream, deposit_kind != RESOURCE), zaino vuoto, target_building
# null, o re-routing appena scattato — tutti e quattro invariati rispetto a prima di questo passo,
# nessuno di loro acquisisce una durata artificiale. Il ramo FISICO con un deposito davvero in corso
# è l'UNICO che ora impiega più di un frame/giorno per completarsi.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	# Gated dalla categoria SHOW_TRANSPORT_BUILD_LOGS (rinominato da SHOW_UNLOAD_COMPLETION_LOGS,
	# 2026-09-16, richiesta utente — riordino log di debug), non dal solo master switch ENABLED —
	# questo print gira ad ogni chiamata (~60/s, una per frame) per l'intera durata del ramo FISICO
	# in corso: col solo ENABLED produrrebbe decine di righe per un singolo Unload. Default false:
	# chi vuole vederlo accende la categoria TRANSPORT_BUILD, stesso principio degli altri filtri
	# dedicati in DebugLogging.gd.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and _elapsed < _duration:
		print("[UNLOAD] is_complete: false (in corso) — elapsed=%.3f/%.3fgg, target_building=%s" % [
			_elapsed, _duration, str(target_building.id) if target_building != null else "null"
		])
	return _elapsed >= _duration


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position) — SOLO ramo FISICO (deposit_kind == RESOURCE): il ramo PENSIERO
# non ha alcun vincolo di posizione reale (deposita su un Folk via source_group_ref, non su una
# cella — vedi on_complete sotto), quindi ritorna sempre null per quel ramo, indipendentemente da
# target_building (che per il pensiero può essere valorizzato ma non è consumato come posizione,
# vedi la nota in testa al file). Stessa formula/stesso commento esteso di RetrieveAction.
# get_required_position per il ramo fisico.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if deposit_kind != DepositKind.RESOURCE or target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# Due rami MUTUAMENTE ESCLUSIVI secondo deposit_kind (2026-09-10, DEVIAZIONE dal discriminatore
# `target_building != null` usato prima di questo passo, vedi nota in testa al file) — mai entrambi
# nella stessa istanza: chi costruisce l'azione decide già quale ramo vuole tramite il costruttore,
# non un caso ambiguo da risolvere qui dentro.
#
# Ramo FISICO (deposit_kind == RESOURCE, Step 1 BuildingStorageService) — legge lo zaino
# dell'individuo (carried_resources, multi-risorsa dal 2026-09-20), tenta di depositare OGNI varietà per
# intero in target_building via BuildingStorageService.store (che clampa da sé allo spazio libero/
# categoria accettata), poi decrementa lo zaino di SOLO quanto è stato effettivamente depositato: se lo
# spazio non basta (o la categoria non è accettata), il resto resta trasportato, MAI perso. Nessun
# effetto se lo zaino è già vuoto (carried_resources vuoto) — niente da
# scaricare, coerente col "no-op istantaneo senza effetti" già seguito da PickUpAction.on_complete
# quando _quantity_to_collect è 0. target_building == null qui è un caso limite difensivo (nessun
# call site reale lo produce oggi, vedi call site aggiornati) — return anticipato, mai un crash.
#
# Ramo PENSIERO (deposit_kind == THOUGHT, invariato nella logica dal rename DepositAction->
# UnloadAction) — risolve Folk dalla stessa catena già in uso altrove (individual.source_group_ref.
# folk_ref, vedi HumanStaminaIndividualService per il precedente), poi IdeaProgressService.
# add_thoughts(folk, 1). Guardie difensive su source_group_ref/folk_ref null (stesso trattamento già
# visto altrove per questa catena, es. HumanStaminaIndividualService.recalculate_max_stamina) — non
# dovrebbero mai essere null con dati coerenti, ma questa azione non deve fallire rumorosamente se
# lo sono. target_building può essere valorizzato anche qui (vedi nota sul campo, in testa al file)
# ma non è ancora consumato da questo ramo — nessun comportamento nuovo introdotto in questo passo.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if unequip_slot_index >= 0:
		_complete_unequip(individual, context)
		return
	if deposit_kind == DepositKind.RESOURCE:
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] on_complete: ramo FISICO (target_building id=%s)" % (str(target_building.id) if target_building != null else "null"))
		if target_building == null:
			return
		if individual.carried_resources.is_empty():
			if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[UNLOAD] on_complete: zaino vuoto — nessun deposito, return anticipato.")
			return
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			# can_accept/get_free_space richiamati QUI solo per il log — sola lettura, nessun
			# effetto collaterale, store() sotto li ricalcola comunque da sé indipendentemente da
			# queste righe (nessuna modifica alla logica esistente).
			var accepted_log: Dictionary = {}
			for resource_name in individual.carried_resources.keys():
				accepted_log[resource_name] = BuildingStorageService.can_accept(target_building, String(resource_name))
			print("[UNLOAD] on_complete: can_accept=%s, free_space=%.1f, zaino PRIMA=%s" % [
				str(accepted_log),
				BuildingStorageService.get_free_space(target_building),
				str(individual.carried_resources),
			])
		# Snapshot dello zaino PRIMA dei depositi: si itera su questa copia mentre lo zaino vero viene
		# decrementato varietà per varietà (mai mutare un Dictionary mentre lo si itera).
		var carried_before_deposit: Dictionary = individual.carried_resources.duplicate(true)
		# decay_fraction della varietà (2026-09-09, richiesta utente — Step 3 decadimento) — passata a
		# store() così la frazione dello zaino si fonde (media pesata) con quella già presente nel
		# magazzino per lo stesso resource_name, invece di andare persa/azzerata al deposito.
		# store() clampa DA SÉ a min(quantità, get_max_depositable(...)) — può quindi depositare MENO del
		# richiesto (deposito PARZIALE) o 0 (nessun posto/risorsa non accettata), MAI un errore: chi resta in
		# spalla confluisce nella STESSA gestione del residuo sotto (2026-09-14, richiesta utente — vedi
		# cronologia in testa ad activate()). Zaino multi-risorsa (2026-09-20): una store() per varietà, in
		# sequenza — ognuna vede gli slot già occupati dalle precedenti.
		var any_deposited: bool = false
		var deposited_by_resource: Dictionary = {}
		for resource_name in carried_before_deposit.keys():
			var carried_entry: Dictionary = carried_before_deposit[resource_name]
			# Destinazione non valida (cantiere già completato, vedi _is_completed_site_destination): nessun
			# deposito, tutto il carico confluisce nel residuo e nel reinstradamento verso un magazzino
			# qui sotto — stesso esito di una destinazione demolita (can_accept/store ritornano 0).
			var deposited: int = 0
			if not _is_completed_site_destination(context):
				deposited = BuildingStorageService.store(
					target_building, String(resource_name), int(carried_entry["quantity"]), float(carried_entry["decay_fraction"])
				)
			if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
				print("[UNLOAD] on_complete: store() ha depositato %d unità di '%s' (su %d richieste)" % [
					deposited, resource_name, int(carried_entry["quantity"])
				])
			deposited_by_resource[String(resource_name)] = deposited
			if deposited > 0:
				any_deposited = true
				individual.remove_carried_resource(String(resource_name), deposited)
		if any_deposited:
			# resource_deposited (2026-09-12) — emesso SOLO se qualcosa è stato depositato (una volta per
			# on_complete, non per varietà): chi ascolta (GameScene._on_resource_deposited) deve rinfrescare la
			# mappa anche se il deposito è stato solo PARZIALE (il resto gestito sotto) — la griglia di
			# stoccaggio del deposit site è comunque cambiata.
			resource_deposited.emit(target_building)
		# Consegna Transport (2026-09-20): valutata QUI, al deposito effettivo, non alla stima di activate().
		if context.has("transport_destination_id") and int(context["transport_destination_id"]) == target_building.id:
			var delivery_resource: String = String(context.get("transport_delivery_resource", ""))
			transport_delivered.emit(individual, context, int(deposited_by_resource.get(delivery_resource, 0)))
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] on_complete: zaino PRIMA=%s -> DOPO=%s" % [str(carried_before_deposit), str(individual.carried_resources)])
		if individual.carried_resources.is_empty():
			# Le decay_fraction vivono dentro le entry di carried_resources: con lo zaino vuoto non resta
			# nessun valore "orfano" (vedi HumanIndividual.carried_resources).
			# "Cammina via" (2026-09-09, richiesta utente — haul_resource, stesso schema di walk_away
			# in Daydream: target_building.position + Vector2.from_angle(randf() * TAU) * distanza,
			# qui PHYSICAL_WALK_AWAY_DISTANCE = 1.0, non i 5.0 del ramo pensiero) — SOLO
			# quando lo zaino si è svuotato DEL TUTTO qui (deposito completo, nessun residuo da
			# reinstradare sotto): mai per il ramo pensiero (richiesta esplicita utente: "quando
			# UnloadAction.on_complete() deposita fisicamente con successo"). Questa Action non ha
			# accesso alla Task (solo individual/context, vedi Action.gd) quindi non può accodare
			# direttamente un nuovo WalkAction: scrive la posizione target in context,
			# HumanIndividualActionService.apply_action la consuma SUBITO dopo on_complete() (stesso
			# canale/momento già usato per pending_warehouse_search sotto) e fa lei l'append_steps
			# vero.
			#
			# Conversione cross-macrocella verificata (richiesta utente, 2026-09-09) — NON omessa per
			# "sappiamo già che è sempre zero": individual.home_macro_coords può SOLO essere diverso
			# da (target_building.macro_x, target_building.macro_y) se l'individuo avesse
			# attraversato un bordo di macrocella camminando fin qui, ma GameScene.
			# _attempt_macro_cell_transition chiama individual.stop() (azzera current_task) ad OGNI
			# attraversamento — quindi una Task il cui WalkAction precedente avrebbe dovuto
			# attraversare un bordo per raggiungere target_building verrebbe interrotta PRIMA di
			# arrivare, e questo on_complete() fisico non verrebbe mai raggiunto per quel caso. In
			# pratica l'offset qui sotto risulta quindi sempre (0,0) con lo stato attuale del
			# movimento — ma la formula resta quella GENERALE (stessa già in uso in _try_assign_
			# unload_command_on_right_click/_debug_test_daydream_task), per coerenza e nel caso quella
			# limitazione sui bordi venga rimossa in futuro senza che nessuno si ricordi di
			# aggiornare anche questo punto.
			var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
			var building_position: Vector2 = Vector2(target_building.micro_x, target_building.micro_y) + macro_offset
			context["pending_walk_away_position"] = building_position + Vector2.from_angle(randf() * TAU) * PHYSICAL_WALK_AWAY_DISTANCE
			return
		# RESIDUO (2026-09-14, richiesta utente — deposito parziale, punto 1 del piano concordato:
		# "deposito ok seguito da rerouting SOLO del residuo") — copre ENTRAMBI i casi che lasciano
		# qualcosa nello zaino qui: deposited=0 per una varietà (nulla è entrato, es. risorsa non accettata o
		# cantiere già rifornito — l'INTERA varietà è "residuo") e 0<deposited<quantità (deposito parziale,
		# solo l'eccedenza è "residuo"). Zaino multi-risorsa (2026-09-20): UNA ricerca per varietà residua,
		# tutte nella stessa voce "searches" del canale. STESSA forma/STESSO canale generico già usato da
		# PickUpAction.on_complete per la ricerca iniziale (context["pending_warehouse_search"],
		# consumato da HumanIndividualActionService._handle_pending_warehouse_search DOPO
		# on_complete()) — SPOSTATA QUI da activate() (che PRIMA scriveva questa stessa richiesta
		# PRIMA ancora di tentare il deposito, tutto-o-niente): ora la richiesta riflette SEMPRE la
		# quantità VERAMENTE rimasta in spalla dopo il tentativo, mai l'intero carico originale a
		# prescindere da quanto sia effettivamente entrato.
		#
		# discard_on_failure: true (invariato) — se find_best non trova nemmeno un vero magazzino per
		# il residuo di una varietà, quella varietà viene scartata (discard_carried_resource_entry, vedi
		# _handle_pending_warehouse_search) — stesso comportamento di prima per il caso "nessun
		# candidato", solo applicato ora alla quantità corretta e alla sola varietà che non ha trovato posto.
		#
		# target_building.id escluso (2026-09-14) — STESSO principio di prima (un edificio appena
		# rifiutato/riempito non va riproposto identico): dopo un fix A (WarehouseSelectionService.
		# find_best ora richiede is_complete), un cantiere in costruzione non passerebbe comunque il
		# filtro, ma l'esclusione esplicita resta comunque corretta e innocua per un target_building
		# che fosse invece un vero magazzino già pieno.
		var excluded: Array[int] = []
		for raw_id in context.get("warehouse_search_excluded_building_ids", []):
			excluded.append(int(raw_id))
		if not excluded.has(target_building.id):
			excluded.append(target_building.id)
		context["warehouse_search_excluded_building_ids"] = excluded
		var residual_searches: Array = []
		for resource_name in individual.carried_resources.keys():
			residual_searches.append({
				"resource_name": String(resource_name),
				"quantity": individual.get_carried_quantity(String(resource_name)),
			})
		context["pending_warehouse_search"] = {
			"searches": residual_searches,
			"excluded_building_ids": excluded,
			"discard_on_failure": true,
		}
		if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
			print("[UNLOAD] on_complete: residuo %s dopo deposito parziale/nullo in target_building id=%d — pending_warehouse_search scritto (una ricerca per varietà), esclusi finora=%s" % [
				str(individual.carried_resources), target_building.id, str(excluded)
			])
		return

	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[UNLOAD] on_complete: ramo PENSIERO (deposit_kind=THOUGHT) — pending_thought=%s" % individual.pending_thought)
	if not individual.pending_thought:
		return
	if individual.source_group_ref == null or individual.source_group_ref.folk_ref == null:
		return
	var folk: Folk = individual.source_group_ref.folk_ref
	individual.pending_thought = false
	thought_deposited.emit()
	if IdeaProgressService.add_thoughts(folk, 1):
		idea_completed.emit(folk.completed_ideas[-1])

	# "Cammina via" (2026-09-10, richiesta utente — Step 1b del refactor Daydream via TaskFactory,
	# preparazione del meccanismo, non ancora collegato/testabile in-game: arriva col secondo
	# prompt) — STESSA identica formula/STESSO canale generico del ramo FISICO sopra (target_building.
	# position + Vector2.from_angle(randf() * TAU) * WALK_AWAY_DISTANCE, consumato da
	# HumanIndividualActionService._handle_pending_walk_away, già generico/riusabile senza modifiche),
	# ora possibile qui perché target_building non è più legato al solo ramo RESOURCE (2026-09-10,
	# refactor 2b — discriminatore esplicito deposit_kind, target_building indipendente): un ramo
	# PENSIERO risolto dinamicamente da _handle_pending_thought_target_search (2c) passa un Building
	# reale (lo Pebble Circle o equivalente) anche qui.
	#
	# Guardia target_building != null (a differenza del ramo FISICO sopra, dove un target_building
	# null è già un caso limite difensivo mai prodotto da un call site reale) — QUI invece è ancora
	# il caso NORMALE di oggi: _debug_test_daydream_task (non toccata in questo prompt, arriva col
	# secondo) costruisce ancora UnloadAction.new(null, DepositKind.THOUGHT), quindi questo ramo deve
	# restare un no-op silenzioso finché quel chiamante non passa a risolvere target_building
	# dinamicamente via 2c — nessun comportamento nuovo visibile in-game da questo prompt.
	if target_building != null:
		var thought_macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
		var thought_building_position: Vector2 = Vector2(target_building.micro_x, target_building.micro_y) + thought_macro_offset
		context["pending_walk_away_position"] = thought_building_position + Vector2.from_angle(randf() * TAU) * WALK_AWAY_DISTANCE


# Persistenza (2026-09-09, richiesta utente; ESTESA 2026-09-10 per costo/durata E per deposit_kind)
# — target_building via building.id (l'unico identificatore stabile/serializzabile, stesso
# principio di PopulationGroup.id: Building stesso non è mai serializzato per riferimento diretto,
# JSON non trasporta riferimenti a oggetti vivi) PIÙ duration/elapsed/total_stamina_cost (2026-09-10,
# stesso motivo di PickUpAction/ThinkAction: senza, un salvataggio a metà deposito fisico perderebbe
# silenziosamente il progresso già maturato, ripartendo da 0 al reload — vedi _restored_from_save).
# total_stamina_cost persistito ESPLICITAMENTE (a differenza di PickUpAction, che non lo fa — la
# sua get_stamina_delta si affiderebbe a un _total_stamina_cost rimasto a 0.0 dopo un reload,
# azzerando silenziosamente il drain residuo: un gap preesistente non toccato qui, ma non replicato
# in questa classe) — così get_stamina_delta() resta corretta anche dopo un reload a metà scarico.
#
# deposit_kind persistito ESPLICITAMENTE (2026-09-10, richiesta utente — scollegare il ramo dalla
# nullità di target_building) — NECESSARIO ora che non è più deducibile dalla presenza/assenza di
# "target_building_id": prima di questo passo un salvataggio a metà scarico FISICO si ricostruiva
# correttamente per pura coincidenza (target_building_id presente → target_building risolto non-null
# → ramo fisico dedotto), ma quella coincidenza non regge più con un discriminatore esplicito — senza
# questa chiave, un reload userebbe sempre il default DepositKind.THOUGHT, rompendo silenziosamente
# qualunque UnloadAction fisica ricaricata a metà. Stesso int-sotto-un-enum già salvato/ricaricato
# altrove nel progetto per altri campi enum (es. GameLoadService.terrain_base).
#
# `target` resta sempre null per questa Action (vedi _init sopra) quindi non è mai coperto dal
# trattamento GENERICO di TaskPersistenceService.serialize_task.
# Modalità "cintura": durata e stamina con la stessa formula del deposito normale, sullo spazio di
# UNA unità dell'attrezzo dello slot; nulla da fare (durata 0) se lo slot è vuoto o il magazzino non
# lo accetta più.
func _activate_unequip(individual: Variant) -> void:
	var tool_name: String = individual.get_equipped_tool(unequip_slot_index)
	if tool_name == "" or target_building == null or BuildingStorageService.get_max_depositable(target_building, tool_name) <= 0:
		return
	var resource_rules := CaloricCalculator.get_caloric_source_rules(tool_name)
	var space: float = resource_rules.space_per_unit if resource_rules != null else 0.0
	if space > 0.0 and individual.max_carry_capacity > 0.0:
		_duration = space / individual.max_carry_capacity
		_total_stamina_cost = STAMINA_COST_PER_SPACE_UNIT * space


# Modalità "cintura": deposita l'attrezzo dello slot (ricontrollando che il magazzino lo accetti) e
# libera lo slot; se il magazzino non lo accetta più l'attrezzo resta in cintura, mai perso. Poi lo
# stesso piccolo "cammina via" del deposito fisico (PHYSICAL_WALK_AWAY_DISTANCE). game_data null:
# capacità corretta del solo bonus dello slot (vedi HumanIndividual._recalculate_carry_capacity_after_
# tool_change).
func _complete_unequip(individual: Variant, context: Dictionary) -> void:
	var tool_name: String = individual.get_equipped_tool(unequip_slot_index)
	if tool_name == "" or target_building == null:
		return
	if BuildingStorageService.get_max_depositable(target_building, tool_name) <= 0:
		return
	if BuildingStorageService.store(target_building, tool_name, 1, 0.0) <= 0:
		return
	individual.take_equipped_tool(unequip_slot_index, null)
	resource_deposited.emit(target_building)
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	var building_position: Vector2 = Vector2(target_building.micro_x, target_building.micro_y) + macro_offset
	context["pending_walk_away_position"] = building_position + Vector2.from_angle(randf() * TAU) * PHYSICAL_WALK_AWAY_DISTANCE


func get_save_data() -> Dictionary:
	var data := {
		"duration": _duration,
		"elapsed": _elapsed,
		"total_stamina_cost": _total_stamina_cost,
		"deposit_kind": deposit_kind,
		# Modalità "cintura" (2026-09-25) — letta da TaskPersistenceService._build_step.
		"unequip_slot_index": unequip_slot_index,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data


# Il building vero E deposit_kind vengono risolti e iniettati da TaskPersistenceService._build_step
# PRIMA di chiamare questo metodo (building: ha accesso a World.buildings, questa classe non ce
# l'ha, stesso principio già seguito da PickUpAction/macro_state; deposit_kind: per coerenza con
# target_building, così entrambi i parametri "di identità" del ramo arrivano insieme dal costruttore
# — vedi nota in testa al file) — le chiavi "target_building_id"/"deposit_kind" sono lette
# direttamente da _build_step, non da qui. duration/elapsed/total_stamina_cost (2026-09-10) invece SÌ
# da qui — stesso schema esatto di PickUpAction.load_save_data: marca _restored_from_save così la
# ripetizione di activate() che GameLoadService invoca subito dopo (per ripristinare gli effetti
# collaterali non persistiti delle altre Action, es. WalkAction) non sovrascriva questo progresso
# appena ripristinato ricalcolandolo da zero.
func load_save_data(data: Dictionary) -> void:
	_duration = float(data.get("duration", 0.0))
	_elapsed = float(data.get("elapsed", 0.0))
	_total_stamina_cost = float(data.get("total_stamina_cost", 0.0))
	_restored_from_save = true
