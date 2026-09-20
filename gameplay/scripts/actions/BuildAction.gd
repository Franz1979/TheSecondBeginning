class_name BuildAction
extends Action

# Quarto e ultimo step della Build Task (2026-09-11, richiesta utente — dopo Walk→SetupSite→Clear,
# "la costruzione vera"): accumula lavoro giorno per giorno su target_building.construction_progress
# finché non raggiunge target_building.rules.required_labor, poi marca l'edificio completo.
#
# FABBISOGNO MATERIALE (2026-09-14, richiesta utente — "step 2 della build": bypass rimosso) —
# legge rules.required_materials (il Dictionary riservato APPOSTA a questa fase, distinto da
# BuildingRules.setup_site_material_name/setup_site_material_per_cell che SetupSiteAction usa per
# la fase precedente — vedi quel file per la separazione originale) e blocca il progresso finché
# ANCHE UNA SOLA risorsa richiesta manca — vedi get_missing_materials sotto/get_stamina_delta per
# il guard esatto. A differenza di SetupSiteAction (una sola risorsa), required_materials può avere
# PIÙ voci insieme (es. stick_tent oggi: stick E pebble) — il blocco è "manca qualcosa", non
# "manca tutto": basta UNA voce sotto soglia per fermare l'intero step.
#
# A DIFFERENZA di SetupSiteAction/ClearAction (durata nota subito, un accumulatore _elapsed
# confrontato con una _duration fissa calcolata al costruttore o dalla composizione della
# microcella) — questa classe NON precalcola alcuna durata: lavora a CICLI GIORNALIERI, drenando
# stamina ad un tasso costante (STAMINA_DRAIN_PER_DAY, stesso principio "costante di classe, da
# bilanciare in seguito" di ogni altra Action di questo sistema) e convertendo quella stamina spesa
# in lavoro EFFETTIVO tramite skill_multiplier/tool_multiplier — entrambi PLACEHOLDER oggi (nessun
# sistema skill/tool esiste ancora, vedi TaskTypes.ToolCategory/Action.required_tool_categories),
# ma già parametri ESPLICITI del costruttore (non costanti hardcoded qui dentro) così quando quei
# sistemi esisteranno davvero non servirà toccare questa classe — solo chi la costruisce passerà
# valori diversi da 1.0.
#
# L'ACCUMULATORE VIVE SU Building.construction_progress["labor_accumulated"] (float), NON su un
# campo interno di questa istanza (DEVIAZIONE deliberata dal pattern _elapsed/_duration usato
# altrove) — per due motivi: 1) il lavoro accumulato è una proprietà del CANTIERE, non di QUESTO
# specifico step in esecuzione — se in futuro più individui potessero lavorare in parallelo sullo
# stesso edificio (vedi BuildingRules.max_builders, già esistente ma non ancora sfruttato da
# nessuna logica di condivisione), ognuno avrebbe la PROPRIA istanza di BuildAction ma tutte
# dovrebbero contribuire allo STESSO totale — un accumulatore per-istanza non lo permetterebbe;
# 2) persistenza GRATUITA: Building.construction_progress è già un campo serializzato per intero da
# GameSaveService/GameLoadService (vedi Building.gd), quindi labor_accumulated sopravvive a un
# salvataggio/ricaricamento senza che questa classe debba implementare get_save_data/load_save_data
# per il proprio progresso (a differenza di ThinkAction/PickUpAction/UnloadAction/ClearAction, che
# DEVONO persistere _elapsed/_duration da sé) — solo target_building_id/skill_multiplier/
# tool_multiplier restano da salvare qui, dati "di identità" del costruttore, mai progresso.
#
# STAMINA_DRAIN_PER_DAY — valore di partenza ARBITRARIO, stesso trattamento "da bilanciare in
# seguito" di ogni altra costante di questo sistema, scelto nello stesso ordine di grandezza di
# SetupSiteAction/ClearAction (100.0/200.0 al momento di scrivere questo file, entrambe alzate
# rispetto al valore originale 10.0 per rendere i test più rapidi) così un required_labor di test
# (1000-1500, vedi hut/pebble_circle/deposit_site.tres) resta completabile in pochi giorni di gioco.
const STAMINA_DRAIN_PER_DAY: float = 200.0


var target_building: Building = null
var skill_multiplier: float = 1.0
var tool_multiplier: float = 1.0

# Emesso UNA VOLTA quando la costruzione è DAVVERO completa (2026-09-11) — stesso principio di
# disaccoppiamento già seguito da SetupSiteAction.site_setup_completed/ClearAction.site_cleared:
# questa classe non conosce GameScene/MicroCellRenderer/live_cells, si limita a segnalare "QUESTO
# edificio è ora completo", chi ha creato la Task (oggi GameScene._start_building_task_at) decide
# come reagire visivamente (rimozione placeholder, refresh sprite — vedi GameScene.
# _on_building_construction_completed). built_year NON è valorizzato da questa classe (vedi
# on_complete sotto per il perché) — il listener lo scrive lui, avendo accesso a game_data.
signal building_construction_completed(building: Building)


func _init(
	p_target_building: Building = null,
	p_skill_multiplier: float = 1.0,
	p_tool_multiplier: float = 1.0
) -> void:
	target = null
	target_building = p_target_building
	skill_multiplier = p_skill_multiplier
	tool_multiplier = p_tool_multiplier
	# INFANT non può eseguire questa Action (2026-09-12, richiesta utente — collegamento AgeBand.
	# INFANT al gameplay, vedi Action.disallowed_age_bands). CHILD aggiunto 2026-09-13 (richiesta
	# utente).
	disallowed_age_bands = [HumanTypes.AgeBand.INFANT, HumanTypes.AgeBand.CHILD]


# Lettura pura di Building.construction_progress["labor_accumulated"] — 0.0 se target_building è
# null o se la chiave non esiste ancora (primissimo giorno di lavoro su questo cantiere, o un
# edificio piazzato istantaneamente da _place_building_at che non passa mai da qui).
func _get_labor_accumulated() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get("labor_accumulated", 0.0))


# Fabbisogno materiale (2026-09-14, richiesta utente) — {resource_name: missing_quantity} per ogni
# voce di rules.required_materials la cui quantità stoccata sul cantiere è ancora sotto soglia;
# voci già soddisfatte (o con required<=0, "non richiesto per questo tipo") non compaiono affatto —
# Dictionary VUOTO = nulla manca, stesso significato "via libera" già usato da SetupSiteAction.
# get_missing_material_quantity() (lì un int, qui un Dictionary perché required_materials può avere
# PIÙ voci insieme, a differenza del singolo setup_site_material_name).
func get_missing_materials() -> Dictionary:
	if target_building == null or target_building.rules == null:
		return {}
	var missing: Dictionary = {}
	for resource_name in target_building.rules.required_materials.keys():
		var required: int = int(target_building.rules.required_materials[resource_name])
		if required <= 0:
			continue
		var stored_entry: Dictionary = target_building.stored_resources.get(resource_name, {})
		var stored: int = int(stored_entry.get("quantity", 0))
		var missing_quantity: int = max(required - stored, 0)
		if missing_quantity > 0:
			missing[resource_name] = missing_quantity
	return missing


# Fabbisogno materiale (2026-09-14, richiesta utente) — controllato ad OGNI attivazione di questo
# step, STESSO principio/STESSO canale di SetupSiteAction.activate() (vedi quel file per il
# commento esteso): se manca ANCHE UNA SOLA risorsa, questo step non accumula NULLA questo giro,
# scrive invece la richiesta in context["pending_material_shortage"] (consumata da
# HumanIndividualActionService._handle_pending_material_shortage). Il blocco vero (zero
# costo/accumulo, mai completa) resta comunque garantito ANCHE da get_stamina_delta/
# is_complete sotto, indipendentemente da questo flag.
#
# LOG DEBUG VERIFICA PROGRESSO (2026-09-11, richiesta utente — "verificare se un'Action riparte da
# zero o da un progresso preesistente") — CONFERMATO (punto 4 della richiesta): questa classe legge
# SEMPRE labor_accumulated dal vivo via _get_labor_accumulated() — mai un campo interno cachato —
# quindi una NUOVA istanza di BuildAction creata dopo un'interruzione (Task riassegnata allo stesso
# individuo a metà lavoro) riprende già correttamente da dove Building era rimasto.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	var missing := get_missing_materials()
	if not missing.is_empty():
		context["pending_material_shortage"] = {
			"missing": missing,
			"target_building_id": target_building.id,
		}
		return
	if DebugLogging.ENABLED and DebugLogging.SHOW_TRANSPORT_BUILD_LOGS and target_building != null:
		print("[BUILD PROGRESS DEBUG] BuildAction attivata per building #%d: riparte da labor_accumulated=%.2f (era 0.0 se prima volta)" % [
			target_building.id, _get_labor_accumulated()
		])


# Nessuna guardia _restored_from_save (a differenza di PickUpAction/UnloadAction) — questa classe
# non ha nulla da RICALCOLARE in activate()/get_stamina_delta che dipenda dallo stato al momento
# dell'attivazione: ogni chiamata legge/scrive semplicemente l'accumulatore ESTERNO (Building.
# construction_progress), già corretto qualunque sia il momento (appena creato, ripristinato da un
# save, o già in corso da giorni) — nessun valore "interno" da perdere/duplicare a un reload.
#
# Guardia materiale (2026-09-14) AGGIUNTA in testa, PRIMA di quella su labor_accumulated: mentre
# manca anche una sola risorsa questo step non deve MAI accumulare progresso, indipendentemente da
# chi/quando consumi il pending_material_shortage scritto da activate() sopra.
#
# Già completo (labor_accumulated >= required_labor) → 0.0 senza ulteriore accumulo: difensivo,
# is_complete() sotto dovrebbe già aver fermato la Task prima che questo venga richiamato di nuovo,
# ma evita comunque un piccolo overshoot se mai chiamato un'ultima volta nello stesso frame.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if target_building == null or target_building.rules == null:
		return 0.0
	if not get_missing_materials().is_empty():
		return 0.0
	if _get_labor_accumulated() >= float(target_building.rules.required_labor):
		return 0.0
	var stamina_spent_this_day: float = STAMINA_DRAIN_PER_DAY * delta
	var effective_work_this_day: float = stamina_spent_this_day * skill_multiplier * tool_multiplier
	target_building.construction_progress["labor_accumulated"] = _get_labor_accumulated() + effective_work_this_day
	return -stamina_spent_this_day


# false (mai "vero da subito") se target_building/rules non risolvibili — difensivo: nessun dato
# valido da cui decidere, meglio non completare mai un'Action mal costruita che fingere un
# completamento istantaneo che salterebbe on_complete con dati a metà. Guardia materiale (2026-09-14)
# AGGIUNTA — mai completa mentre manca anche una sola risorsa, indipendentemente da labor_accumulated
# (che può anche essere già a target da un tentativo precedente, se mai possibile): il completamento
# resta subordinato a ENTRAMBE le condizioni.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	if target_building == null or target_building.rules == null:
		return false
	if not get_missing_materials().is_empty():
		return false
	return _get_labor_accumulated() >= float(target_building.rules.required_labor)


# get_required_position (2026-09-13, richiesta utente — fix "Walk di ritorno alla ripresa", vedi
# Action.get_required_position e RetrieveAction.get_required_position per la stessa identica
# formula/stesso commento esteso, duplicata qui apposta — nessuna costante/funzione condivisa tra
# Action diverse, stesso principio già seguito ovunque in questo sistema). Rilevante ora che
# build.tres è sospendibile (is_suspendable = true, 2026-09-13): un individuo che lascia il
# cantiere a metà BuildAction per un bisogno di stamina deve tornare esattamente lì alla ripresa.
func get_required_position(individual: Variant, context: Dictionary) -> Variant:
	if target_building == null:
		return null
	var macro_offset: Vector2 = Vector2(Vector2i(target_building.macro_x, target_building.macro_y) - individual.home_macro_coords) * World.WIDTH
	return Vector2(target_building.micro_x, target_building.micro_y) + macro_offset


# is_complete/current_durability risolti QUI (nessun dato esterno necessario, solo target_building.
# rules già disponibile) — built_year DELIBERATAMENTE NON valorizzato qui (DEVIAZIONE rispetto a
# ClearAction.on_complete, che muta macro_state direttamente avendolo già dal costruttore): questa
# classe non riceve un riferimento a GameData (Action.gd, per design, non conosce nulla di
# "GameScene"/stato di partita globale — solo `target_building`/i moltiplicatori, dati di dominio
# "edificio", non "partita") e game_data.year è per costruzione un valore che può cambiare tra la
# creazione della Task e il completamento di QUESTO step (una costruzione può durare più anni di
# gioco, a differenza del piazzamento istantaneo di _place_building_at, dove è sempre lo stesso
# frame) — un valore "iniettato al costruttore" sarebbe quindi STANTIO al momento in cui serve
# davvero. Il listener che ascolta building_construction_completed (oggi GameScene.
# _on_building_construction_completed, che HA accesso a game_data) lo scrive lui, stesso identico
# valore/stessa fonte di _place_building_at (game_data.year), ma letto nel momento giusto.
func on_complete(individual: Variant, context: Dictionary) -> void:
	if target_building == null:
		return
	target_building.is_complete = true
	# built_year scritto QUI, nello stesso punto di is_complete (2026-09-19, richiesta utente —
	# prima lo scriveva solo il listener GameScene._on_building_construction_completed: se il
	# segnale partiva senza listener collegato, l'edificio risultava completo con built_year=-1).
	# Letto ADESSO da GameSettings.active_game_data (stessa istanza di GameScene.game_data, vedi
	# GameScene, dove viene assegnata) invece che iniettato al costruttore: l'anno può cambiare tra
	# la creazione della Task e questo step (vedi il commento sopra), un valore iniettato sarebbe
	# stantio. Nessuna partita attiva (null) -> resta -1, il pannello lo mostra come "anno non noto".
	if GameSettings.active_game_data != null:
		target_building.built_year = GameSettings.active_game_data.year
	if target_building.rules != null:
		target_building.current_durability = target_building.rules.max_durability
		# Consumo dei materiali di costruzione (2026-09-14, richiesta utente) — STESSO bugfix già
		# applicato a SetupSiteAction.on_complete (vedi quel file per il commento esteso, "BUG
		# CONFERMATO": il materiale restava per sempre in stored_resources anche a costruzione
		# completa, occupando slot di storage veri su un edificio con storage_slot_count>0):
		# erase() di ciascuna voce di required_materials, non un decremento — consumato per intero,
		# non "ancora in giacenza parziale".
		for resource_name in target_building.rules.required_materials.keys():
			target_building.stored_resources.erase(resource_name)
	# is_awaiting_material -> false (2026-09-14, richiesta utente — STESSO bugfix di
	# SetupSiteAction.on_complete: senza questo, un cantiere bloccato per il fabbisogno di Build
	# restava "in attesa" per sempre nel pannello anche a costruzione DAVVERO completa, dato che
	# nessun punto lo azzerava più una volta risolto il blocco senza passare da una riattivazione).
	target_building.is_awaiting_material = false
	building_construction_completed.emit(target_building)


# Persistenza (2026-09-11, richiesta utente, punto 4) — SOLO dati "di identità" del costruttore
# (target_building via id, skill_multiplier/tool_multiplier): nessun progresso da salvare qui, vedi
# il commento in testa al file — labor_accumulated vive su Building.construction_progress, già
# serializzato per intero da GameSaveService/GameLoadService, persiste "gratis" senza che questa
# classe debba fare nulla. skill_multiplier/tool_multiplier persistiti per COMPLETEZZA (oggi sempre
# 1.0, nessun chiamante reale li valorizza diversamente ancora) — così un futuro chiamante che li
# valorizzasse davvero non perderebbe silenziosamente quel valore ad un reload.
func get_save_data() -> Dictionary:
	var data := {
		"skill_multiplier": skill_multiplier,
		"tool_multiplier": tool_multiplier,
	}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data

# Nessun load_save_data() sovrascritto — vedi get_save_data sopra: skill_multiplier/tool_multiplier/
# target_building sono già risolti e passati al costruttore da TaskPersistenceService._build_step
# PRIMA che load_save_data() (l'implementazione NEUTRA di Action.gd, mai chiamata con effetto qui)
# venga invocata — nessun progresso interno da questa classe da ripristinare in più.
