class_name SetupSiteAction
extends Action

# Primo step "di lavoro" della Build Task (2026-09-10, richiesta utente — prima porzione del piano
# Build Task: trigger di piazzamento + SetupSiteAction; ClearAction è arrivata il 2026-09-11 come
# terzo step, vedi ClearAction.gd — BuildAction come quarto e ultimo). Stile ThinkAction (bersaglio
# TEMPORALE, un accumulatore confrontato con una durata fissa, stesso schema esatto get_stamina_
# delta/is_complete) — a differenza di ThinkAction, qui la durata NON arriva dal chiamante: è una
# costante interna fissa (vedi DURATION_DAYS sotto), perché oggi ogni edificio è monocella (nessuna
# variazione per dimensione/tipo ancora modellata — un futuro edificio multi-microcella richiederà
# probabilmente una durata derivata da rules, non più questa costante).
#
# target_building (2026-09-10) — iniettato dal costruttore, stesso principio "chi crea la Task
# decide già QUALE edificio" già seguito da UnloadAction.target_building/PickUpAction.macro_state:
# nessuna ricerca automatica qui. Serve a on_complete() per segnalare SU QUALE edificio il cantiere
# è stato allestito (vedi signal sotto).
#
# PROGRESSO SU Building.construction_progress["site_setup_days_done"], NON su un campo interno
# dell'istanza (2026-09-11, richiesta utente — "vogliamo che il progresso sopravviva a
# un'interruzione [riassegnazione della Task allo stesso individuo a metà step], stesso principio
# già applicato a BuildAction") — BUG CONFERMATO nella versione precedente di questo file: _elapsed
# viveva SOLO sull'istanza Action, mai scritto su Building. Un'interruzione (nuova Task assegnata
# allo stesso individuo, la vecchia Task/Action scartata SENZA passare da TaskPersistenceService —
# quel percorso esiste solo per un salvataggio/reload, non per una riassegnazione in-sessione)
# perdeva quindi silenziosamente ogni progresso maturato, ripartendo sempre da 0 alla prossima
# SetupSiteAction creata per lo stesso edificio. STESSA soluzione di BuildAction.labor_accumulated:
# _get_site_setup_days_done() sotto legge SEMPRE dal vivo da Building.construction_progress, mai da
# una cache interna — una nuova istanza costruita dopo un'interruzione la trova già lì e riparte
# da quel valore per costruzione, nessun intervento esplicito di "ripristino" necessario oltre a
# NON cachare mai il valore in un campo proprio (vedi il log in activate() sotto per la verifica a
# schermo). Nessun consumo di materiale — SOLO il passaggio di tempo/stamina e il segnale di
# completamento, per costruzione esplicita di questo passo (vedi discussione con l'utente).

# Emesso UNA VOLTA quando l'allestimento del cantiere si conclude (2026-09-10) — stesso principio
# di disaccoppiamento già seguito da PickUpAction.resource_collected/UnloadAction.thought_deposited:
# questa classe non conosce GameScene/MicroCellRenderer/live_cells, si limita a segnalare "il
# cantiere per QUESTO edificio è pronto", chi ha creato la Task (oggi GameScene._start_building_
# task_at) decide come reagire visivamente (i 4 placeholder "legnetti", vedi
# GameScene._spawn_build_site_placeholders).
signal site_setup_completed(building: Building)

# Drain di stamina al GIORNO — STESSO valore di ThinkAction.STAMINA_DRAIN_PER_DAY (10.0): nessun
# valore migliore noto per "allestire un cantiere" oggi, stesso trattamento "da bilanciare in
# seguito" di ogni altra costante di questo sistema. Costante separata (non condivisa/importata da
# ThinkAction) per lo stesso motivo già seguito ovunque nel progetto: nessuna costante condivisa
# tra Action diverse.
const STAMINA_DRAIN_PER_DAY: float = 100.0

# Durata FISSA — 1 giorno di gioco, edifici monocella (2026-09-10, richiesta esplicita utente: "per
# ora, edifici monocella"). Non un parametro di costruttore come ThinkAction.duration: finché ogni
# edificio occupa una sola microcella non c'è alcuna variazione da esprimere — un futuro edificio
# multi-microcella/con rules.required_space maggiore probabilmente vorrà una durata derivata,
# quel giorno questa costante diventerà un campo risolto dal chiamante, stesso schema di
# ThinkAction.duration.
const DURATION_DAYS: float = 1.0

var target_building: Building = null


func _init(p_target_building: Building = null) -> void:
	target_building = p_target_building
	target = null


# Lettura pura di Building.construction_progress["site_setup_days_done"] — 0.0 se target_building è
# null o se la chiave non esiste ancora (primissimo giorno di lavoro su questo cantiere). STESSA
# funzione/STESSO principio di BuildAction._get_labor_accumulated.
func _get_site_setup_days_done() -> float:
	if target_building == null:
		return 0.0
	return float(target_building.construction_progress.get("site_setup_days_done", 0.0))


# LOG DEBUG VERIFICA PROGRESSO (2026-09-11, richiesta utente — "verificare se un'Action riparte da
# zero o da un progresso preesistente") — override SOLO per questo log, super() invariato (Action.
# activate: individual.is_moving = false).
func activate(individual: Variant, context: Dictionary) -> void:
	super(individual, context)
	if DebugLogging.ENABLED and target_building != null:
		print("[BUILD PROGRESS DEBUG] SetupSiteAction attivata per building #%d: riparte da site_setup_days_done=%.2f (era 0.0 se prima volta)" % [
			target_building.id, _get_site_setup_days_done()
		])


# Scrive l'avanzamento INCREMENTALE direttamente su Building.construction_progress ad ogni drain
# (2026-09-11) — STESSO pattern di BuildAction.get_stamina_delta: nessun accumulatore interno,
# lettura+scrittura sempre dal vivo, così il progresso resta sempre coerente con Building anche se
# questa istanza viene distrutta a metà (interruzione) o ricostruita (reload).
func get_stamina_delta(individual: Variant, context: Dictionary, delta: float) -> float:
	if target_building == null:
		return 0.0
	if _get_site_setup_days_done() >= DURATION_DAYS:
		return 0.0
	target_building.construction_progress["site_setup_days_done"] = _get_site_setup_days_done() + delta
	return -STAMINA_DRAIN_PER_DAY * delta


func is_complete(individual: Variant, context: Dictionary) -> bool:
	return _get_site_setup_days_done() >= DURATION_DAYS


func on_complete(individual: Variant, context: Dictionary) -> void:
	site_setup_completed.emit(target_building)


# Persistenza (2026-09-11, richiesta utente, punto 4 del giro precedente) — SOLO target_building_id
# (dato "di identità" del costruttore): nessun progresso da salvare qui, vedi il commento in testa
# al file — site_setup_days_done vive su Building.construction_progress, già serializzato per
# intero da GameSaveService/GameLoadService, persiste "gratis" senza che questa classe debba fare
# nulla. Nessun load_save_data() sovrascritto (l'implementazione NEUTRA di Action.gd resta valida):
# nessuno stato interno da questa classe da ripristinare oltre a target_building, già risolto e
# passato al costruttore da TaskPersistenceService._build_step.
func get_save_data() -> Dictionary:
	var data := {}
	if target_building != null:
		data["target_building_id"] = target_building.id
	return data
