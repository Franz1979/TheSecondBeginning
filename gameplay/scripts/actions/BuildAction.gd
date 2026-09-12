class_name BuildAction
extends Action

# Quarto e ultimo step della Build Task (2026-09-11, richiesta utente — dopo Walk→SetupSite→Clear,
# "la costruzione vera"): accumula lavoro giorno per giorno su target_building.construction_progress
# finché non raggiunge target_building.rules.required_labor, poi marca l'edificio completo.
#
# BYPASS VOLONTARIO (richiesta esplicita utente, questo passo) — NESSUN consumo/verifica di
# rules.required_materials qui: se ne occuperà un giro futuro con una Bring Task dedicata (portare
# materiali al cantiere prima/durante la costruzione). Questa classe non legge required_materials,
# non decrementa alcun magazzino, non blocca il progresso per mancanza di materiali — il lavoro
# accumula sempre, a prescindere.
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
# (1000-1500, vedi hut/stone_circle/deposit_site.tres) resta completabile in pochi giorni di gioco.
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


# Lettura pura di Building.construction_progress["labor_accumulated"] — 0.0 se target_building è
# null o se la chiave non esiste ancora (primissimo giorno di lavoro su questo cantiere, o un
# edificio piazzato istantaneamente da _place_building_at che non passa mai da qui).
func _get_labor_accumulated() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get("labor_accumulated", 0.0))


# LOG DEBUG VERIFICA PROGRESSO (2026-09-11, richiesta utente — "verificare se un'Action riparte da
# zero o da un progresso preesistente", stesso trattamento esteso anche a SetupSiteAction/
# ClearAction lo stesso giorno) — override SOLO per questo log, super() invariato (Action.activate:
# individual.is_moving = false). CONFERMATO (punto 4 della richiesta): questa classe già leggeva
# SEMPRE labor_accumulated dal vivo via _get_labor_accumulated() fin dalla sua introduzione — mai
# un campo interno cachato — quindi una NUOVA istanza di BuildAction creata dopo un'interruzione
# (Task riassegnata allo stesso individuo a metà lavoro) riprende già correttamente da dove Building
# era rimasto, nessuna correzione necessaria, solo questo log per verificarlo a schermo.
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and target_building != null:
		print("[BUILD PROGRESS DEBUG] BuildAction attivata per building #%d: riparte da labor_accumulated=%.2f (era 0.0 se prima volta)" % [
			target_building.id, _get_labor_accumulated()
		])


# Nessuna guardia _restored_from_save (a differenza di PickUpAction/UnloadAction) — questa classe
# non ha nulla da RICALCOLARE in activate()/get_stamina_delta che dipenda dallo stato al momento
# dell'attivazione: ogni chiamata legge/scrive semplicemente l'accumulatore ESTERNO (Building.
# construction_progress), già corretto qualunque sia il momento (appena creato, ripristinato da un
# save, o già in corso da giorni) — nessun valore "interno" da perdere/duplicare a un reload.
#
# Già completo (labor_accumulated >= required_labor) → 0.0 senza ulteriore accumulo: difensivo,
# is_complete() sotto dovrebbe già aver fermato la Task prima che questo venga richiamato di nuovo,
# ma evita comunque un piccolo overshoot se mai chiamato un'ultima volta nello stesso frame.
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if target_building == null or target_building.rules == null:
		return 0.0
	if _get_labor_accumulated() >= float(target_building.rules.required_labor):
		return 0.0
	var stamina_spent_this_day: float = STAMINA_DRAIN_PER_DAY * delta
	var effective_work_this_day: float = stamina_spent_this_day * skill_multiplier * tool_multiplier
	target_building.construction_progress["labor_accumulated"] = _get_labor_accumulated() + effective_work_this_day
	return -stamina_spent_this_day


# false (mai "vero da subito") se target_building/rules non risolvibili — difensivo: nessun dato
# valido da cui decidere, meglio non completare mai un'Action mal costruita che fingere un
# completamento istantaneo che salterebbe on_complete con dati a metà.
func is_complete(individual: Variant, context: Dictionary) -> bool:
	if target_building == null or target_building.rules == null:
		return false
	return _get_labor_accumulated() >= float(target_building.rules.required_labor)


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
	if target_building.rules != null:
		target_building.current_durability = target_building.rules.max_durability
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
