class_name ClearAction
extends Action

# Terzo step della Build Task (2026-09-11, richiesta utente — dopo Walk→SetupSiteAction, "chiude
# il cerchio" del cantiere): rimuove DAVVERO la vegetazione sulla microcella del cantiere
# (BuildingSiteClearingService.clear_microcell, STESSA chiamata già in uso da GameScene.
# _place_building_at per il piazzamento istantaneo) e riserva lo spazio dell'edificio
# (dedicated_space[BUILDING] += rules.required_space, STESSA formula di _place_building_at) — mai
# fatto finora su questo percorso, coerente con la nota "dedicated_space[BUILDING] non
# incrementato... differito a quando ClearAction esisterà davvero" lasciata deliberatamente in
# sospeso da _start_building_task_at quando la Build Task fu introdotta (2026-09-10).
#
# Nessun consumo/richiesta di materiale qui (fuori scope, per costruzione esplicita di questo
# passo — vedi discussione con l'utente): la vegetazione rimossa non produce risorse raccolte,
# sparisce semplicemente — stesso comportamento "distruttivo" già seguito da _place_building_at,
# mai stato diverso per quel percorso.
#
# `_macro_state`/`_is_currently_grass` iniettati dal costruttore, mai risolti da questa classe
# (stesso principio "chi crea la Task inietta i riferimenti già risolti" già seguito da
# PickUpAction.macro_state/UnloadAction.target_building): `_macro_state` è la MacroCellState della
# macrocella OSPITANTE il cantiere (target_building.macro_x/macro_y), non necessariamente quella
# HOME dell'individuo che eseguirà lo step (oggi coincidono sempre, stesso limite architetturale
# noto di _start_building_task_at — nessuna conversione cross-macrocella qui). `_is_currently_grass`
# è iniettato perché GRASS non ha posizioni proprie in MacroCellState (nessun equivalente di
# tree_claimed_lots/shrub_claimed_lots, vedi BuildingSiteClearingService._clear_grass) — la
# presenza di grass in QUESTA microcella è risolvibile solo contro le posizioni calcolate dal
# renderer (LiveMacroCell.renderer.vegetation_positions), stesso identico dato che GameScene.
# _place_building_at già calcola per lo stesso identico scopo.
#
# DURATA (2026-09-11, richiesta utente) — calcolata al COSTRUTTORE (non in activate(), a
# differenza di PickUpAction/UnloadAction: qui non c'è nulla che possa legittimamente cambiare tra
# costruzione ed attivazione da riverificare — la composizione della microcella al momento in cui
# la Task viene creata è quella che conta), ispezionando la SOLA microcella del cantiere (coerente
# col limite monocella attuale degli edifici): 1gg fisso se la microcella ha grass, + 1gg per ogni
# TREE presente (individui, non lotti: un lotto può ospitarne più di uno per densità, vedi
# BuildingSiteClearingService._clear_type/MacroCellState.tree_individual_subtype) + 0.5gg per ogni
# SHRUB presente, sommati (es. grass + 2 tree = 1 + 2 = 3gg).
#
# STAMINA_DRAIN_PER_DAY — STESSO valore di SetupSiteAction.STAMINA_DRAIN_PER_DAY/ThinkAction.
# STAMINA_DRAIN_PER_DAY (10.0), nessun valore migliore noto per "ripulire un cantiere" oggi, stesso
# trattamento "da bilanciare in seguito" di ogni altra costante di questo sistema. Costante separata
# (non condivisa/importata), stesso motivo già seguito ovunque nel progetto: nessuna costante
# condivisa tra Action diverse.
const STAMINA_DRAIN_PER_DAY: float = 200.0


var target_building: Building = null
var _macro_state: MacroCellState = null
var _is_currently_grass: bool = false

var _position: Vector2i = Vector2i.ZERO
var _duration: float = 0.0

# PROGRESSO SU Building.construction_progress["clear_days_done"], NON su un campo interno
# dell'istanza (2026-09-11, richiesta utente — stesso principio già applicato a BuildAction.
# labor_accumulated, ora esteso qui: "vogliamo che il progresso sopravviva a un'interruzione") —
# BUG CONFERMATO nella versione precedente di questo file: un `_elapsed` interno viveva SOLO
# sull'istanza, mai scritto su Building — un'interruzione (nuova Task assegnata allo stesso
# individuo a metà ClearAction, la vecchia Task/Action scartata) perdeva silenziosamente ogni
# progresso. _get_clear_days_done() sotto legge SEMPRE dal vivo, mai da una cache: una nuova
# istanza dopo un'interruzione trova il valore già lì e riparte da quello per costruzione, nessun
# intervento esplicito di "ripristino" oltre a NON cachare mai in un campo proprio (vedi il log in
# activate() sotto per la verifica a schermo). `_duration` invece resta un campo interno — non è
# "progresso" ma la SOGLIA target, ricalcolata deterministicamente da _compute_duration() ad ogni
# costruzione (dipende solo da is_currently_grass/composizione della microcella, che non cambiano
# finché il cantiere resta da ripulire) — nessun bisogno di spostarla su Building.

# Emesso UNA VOLTA quando il cantiere è stato ripulito DAVVERO (2026-09-11) — stesso principio di
# disaccoppiamento già seguito da SetupSiteAction.site_setup_completed: questa classe non conosce
# GameScene/MicroCellRenderer/live_cells, si limita a segnalare "la microcella di QUESTO edificio è
# stata ripulita e lo spazio è riservato", chi ha creato la Task (oggi GameScene.
# _start_building_task_at) decide come reagire visivamente (refresh vegetazione, vedi GameScene.
# _on_site_cleared). La mutazione di stato VERA (clear_microcell + dedicated_space) avviene invece
# DENTRO on_complete() sotto, non delegata al listener — questa classe ha già `_macro_state` dal
# costruttore, stesso principio di UnloadAction.on_complete (ramo fisico), che muta
# BuildingStorageService direttamente invece di limitarsi a segnalare.
signal site_cleared(building: Building)


func _init(
	p_target_building: Building = null,
	p_macro_state: MacroCellState = null,
	p_is_currently_grass: bool = false
) -> void:
	target = null
	target_building = p_target_building
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]
	_macro_state = p_macro_state
	_is_currently_grass = p_is_currently_grass
	_position = Vector2i(p_target_building.micro_x, p_target_building.micro_y) if p_target_building != null else Vector2i.ZERO
	_duration = _compute_duration()
	# Persistita su Building.construction_progress["clear_duration_days"] (2026-09-14, richiesta
	# utente — barra di avanzamento nel pannello edificio) — a differenza di clear_days_done
	# (progresso, sempre scritto dal vivo su Building), _duration è la SOGLIA target: PRIMA viveva
	# SOLO su questa istanza, mai leggibile da chi non ha un'istanza ClearAction viva (es.
	# BuildingInfoPanel, che riceve solo il Building). Scritta UNA SOLA VOLTA (mai sovrascritta da
	# una ricostruzione successiva per lo stesso edificio): _compute_duration() è deterministica
	# sulla composizione della microcella al momento in cui il cantiere è stato piazzato/la
	# vegetazione non cambia finché ClearAction non completa (on_complete la rimuove), quindi ogni
	# ricostruzione produrrebbe comunque lo stesso valore — il guard "solo se assente" evita solo una
	# scrittura ridondante, non un valore diverso.
	if target_building != null and not target_building.construction_progress.has("clear_duration_days"):
		target_building.construction_progress["clear_duration_days"] = _duration


# Lettura pura di Building.construction_progress["clear_days_done"] — 0.0 se target_building è
# null o se la chiave non esiste ancora (primissimo giorno di lavoro su questo cantiere). STESSA
# funzione/STESSO principio di BuildAction._get_labor_accumulated/SetupSiteAction.
# _get_site_setup_days_done.
func _get_clear_days_done() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get("clear_days_done", 0.0))


# Lettura pura di Building.construction_progress["space_reserved"] (2026-09-12, richiesta utente —
# bugfix idempotenza, in preparazione a un futuro meccanismo di riassegnazione Build Task) — false
# se target_building è null o se la chiave non esiste ancora (riserva mai avvenuta). DISTINTO da
# _get_clear_days_done() >= _duration: quel confronto dice solo che il TEMPO di lavoro è maturato,
# non che dedicated_space[BUILDING] sia già stato incrementato per questo edificio — un'istanza
# ClearAction ricostruita da zero per un Building con clear_days_done già oltre soglia (auto-skip,
# vedi is_complete()/get_stamina_delta() sopra) avrebbe altrimenti richiamato on_complete() una
# seconda volta, raddoppiando silenziosamente la riserva di spazio. Vedi on_complete() sotto per il
# guard che usa questo valore.
func _get_space_reserved() -> bool:
	if target_building == null:
		return false
	return bool(target_building.construction_progress.get("space_reserved", false))


func _compute_duration() -> float:
	var duration: float = 0.0
	if _is_currently_grass:
		duration += 1.0
	if _macro_state != null:
		duration += float(_count_individuals_at(GameTypes.WorldObjectType.TREE)) * 1.0
		duration += float(_count_individuals_at(GameTypes.WorldObjectType.SHRUB)) * 0.5
	return duration


# Conta gli individui di `object_type` presenti ESATTAMENTE in _position — stessa scansione lineare
# di BuildingSiteClearingService._clear_type (subtype_store.keys() filtrate per x/y), duplicata
# apposta invece di riusare quel service qui: quella funzione RIMUOVE mentre conta (side-effect su
# birth_year_store/subtype_store/dedicated_space), questa deve solo CONTARE senza toccare nulla (la
# rimozione vera avviene più tardi, in on_complete) — nessuna astrazione condivisa introdotta per
# due usi con contratti diversi (uno muta stato, l'altro no), stesso principio "non un'astrazione
# anticipata" già seguito nel progetto.
func _count_individuals_at(object_type: GameTypes.WorldObjectType) -> int:
	var subtype_store: Dictionary = _macro_state.tree_individual_subtype if object_type == GameTypes.WorldObjectType.TREE else _macro_state.shrub_individual_subtype
	var count := 0
	for key in subtype_store.keys():
		if key.x == _position.x and key.y == _position.y:
			count += 1
	return count


# _duration<=0.0 (microcella già completamente sgombra: nessuna grass/tree/shrub) ritorna 0.0 SENZA
# scrivere alcun progresso — stesso "azione immediatamente completa, nessun costo" già in
# PickUpAction/UnloadAction: is_complete() sotto (0.0 >= 0.0) risulta vera dal primo frame in cui
# questo step diventa attivo. Altrimenti scrive l'avanzamento INCREMENTALE direttamente su Building.
# construction_progress ad ogni drain (2026-09-11) — STESSO pattern di BuildAction.get_stamina_delta/
# SetupSiteAction.get_stamina_delta: nessun accumulatore interno, lettura+scrittura sempre dal vivo.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if _duration <= 0.0 or target_building == null:
		return 0.0
	if _get_clear_days_done() >= _duration:
		return 0.0
	target_building.construction_progress["clear_days_done"] = _get_clear_days_done() + delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _get_clear_days_done() >= _duration


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position e RetrieveAction.get_required_position per la stessa identica
# formula/stesso commento esteso) — DELIBERATAMENTE non riusa `_position` (il campo privato già
# presente sopra): quello è nel sistema di coordinate LOCALE della macrocella OSPITANTE il
# cantiere (_macro_state, non necessariamente quella HOME dell'individuo, vedi il commento in
# testa al file), qui invece serve la posizione GLOBALE comparabile a individual.position — stessa
# conversione cross-macrocella delle altre 4 Action basate su target_building, duplicata qui
# apposta (nessuna costante/funzione condivisa tra Action diverse).
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# LOG DEBUG VERIFICA SPAZIO OCCUPATO (2026-09-11, richiesta utente — validare che la microcella del
# cantiere non risulti MAI libera per la crescita vegetazione dal clear in poi, punto 2 della
# richiesta) — override SOLO per questo log, super() invariato (Action.activate: individual.
# is_moving = false). Logga get_empty_space(), il vero valore letto da ResourceGrowthService.
# grow_resources (vedi simulation/scripts/core/ResourceGrowthService.gd riga ~59: "var empty_space
# := state.get_empty_space()", il gate reale che decide quanto la vegetazione può ancora crescere
# in questa macrocella) — non un conteggio ricalcolato a parte qui, esattamente il dato che quel
# service consulterebbe davvero in questo istante. get_empty_space()/get_total_dedicated_space()
# sono una somma su dedicated_space.values() (Dictionary con al più una manciata di chiavi, una per
# WorldObjectType mai valorizzato in questa macrocella) — lettura ECONOMICA, nessuna iterazione
# sulla griglia: sicuro lasciarla sempre attiva dietro DebugLogging.ENABLED, nessun bisogno di
# disattivarla dopo il test.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and _macro_state != null:
		print("[OCCUPIED SPACE DEBUG] ClearAction.activate (PRIMA del clear) in (%d,%d): get_empty_space()=%d, dedicated_space[BUILDING]=%d" % [
			_position.x, _position.y,
			_macro_state.get_empty_space(), _macro_state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
		])
	# LOG DEBUG VERIFICA PROGRESSO (2026-09-11, richiesta utente — "verificare se un'Action riparte
	# da zero o da un progresso preesistente") — vedi il commento esteso su _get_clear_days_done.
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and target_building != null:
		print("[BUILD PROGRESS DEBUG] ClearAction attivata per building #%d: riparte da clear_days_done=%.2f (era 0.0 se prima volta, su una durata totale di %.2fgg)" % [
			target_building.id, _get_clear_days_done(), _duration
		])


func on_complete(individual: Variant, context: Dictionary) -> void:
	if target_building == null or _macro_state == null:
		return

	BuildingSiteClearingService.clear_microcell(_macro_state, _position, _is_currently_grass)

	# Spazio riservato (2026-09-11, richiesta utente, punto 2) — STESSA formula di GameScene.
	# _place_building_at, spostata QUI così la microcella non risulta mai libera per la crescita
	# vegetazione dal momento in cui viene ripulita, non solo da quando l'edificio sarà COMPLETO.
	# CONFERMATO (2026-09-11, stesso giorno — BuildAction, quarto e ultimo step, arrivata dopo questa
	# nota): BuildAction.on_complete NON tocca dedicated_space[BUILDING] — questo resta l'UNICO punto
	# che lo fa per il percorso Build Task, _place_building_at resta l'unico altro punto (percorso
	# istantaneo, Sx+B, indipendente da questo) — nessuna doppia riserva TRA i due percorsi.
	#
	# GUARD "space_reserved" (2026-09-12, richiesta utente — bugfix idempotenza confermato
	# nell'indagine precedente: questo blocco era un `+=` incondizionato, rieseguito ogni volta che
	# on_complete() scatta — comprese le volte in cui scatta SUBITO, senza alcun lavoro reale, per
	# un'istanza ClearAction ricostruita da zero quando clear_days_done è già oltre soglia, vedi
	# is_complete()/get_stamina_delta() sopra) — vedi _get_space_reserved() per il perché
	# clear_days_done>=_duration da solo non basta a distinguere "tempo maturato" da "riserva già
	# fatta". Marcato true SUBITO DOPO l'unica vera esecuzione, mai più toccato dopo.
	if target_building.rules != null and not _get_space_reserved():
		var current_building_space := _macro_state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
		_macro_state.set_dedicated_space(GameTypes.WorldObjectType.BUILDING, current_building_space + target_building.rules.required_space)
		target_building.construction_progress["space_reserved"] = true

	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS:
		print("[OCCUPIED SPACE DEBUG] ClearAction.on_complete (DOPO clear + riserva) in (%d,%d): get_empty_space()=%d, dedicated_space[BUILDING]=%d" % [
			_position.x, _position.y,
			_macro_state.get_empty_space(), _macro_state.get_dedicated_space(GameTypes.WorldObjectType.BUILDING)
		])

	site_cleared.emit(target_building)


# Persistenza (2026-09-11, richiesta utente, punto 4 del giro precedente; SEMPLIFICATA lo stesso
# giorno quando il progresso si è spostato su Building.construction_progress["clear_days_done"] —
# vedi il commento in testa al file) — SOLO target_building_id/is_currently_grass, dati "di
# identità" del costruttore: nessun progresso da salvare qui. `is_currently_grass` resta persistito
# ESPLICITAMENTE (non basterebbe lasciarlo al default false): serialize_task chiama get_save_data()
# per OGNI step, non solo quello corrente, quindi un ClearAction ancora FUTURO al momento del
# salvataggio (Task non ancora arrivata a questo step) viene ricostruito da _build_step con un
# _init() che RICALCOLA _duration da zero — senza questa chiave quel ricalcolo userebbe sempre
# is_currently_grass=false, producendo una durata sbagliata. Nessun load_save_data() sovrascritto
# (l'implementazione NEUTRA di Action.gd resta valida): _duration si ricalcola deterministicamente
# da sé ad ogni costruzione, clear_days_done vive su Building — nessuno stato interno di questa
# classe da ripristinare qui.
func get_save_data() -> Dictionary:
	var data := {
		"is_currently_grass": _is_currently_grass,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data
