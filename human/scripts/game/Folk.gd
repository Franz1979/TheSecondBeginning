class_name Folk
extends RefCounted

# Cultura/etnia condivisa — nessun governo (quello sarà PoliticalEntity, non ancora costruita).
# RefCounted, non Resource: a differenza di HumanRules/EraRules (regole statiche, dati di
# bilanciamento caricati da .tres), un Folk è un'entità di PARTITA — esiste dal momento in cui
# viene creato in una sessione di gioco, ha un id progressivo, e andrà salvato/caricato come dato
# di partita quando arriverà la persistenza (mai come .tres) — stesso principio già seguito da
# PopulationGroup/Building lato animale/edifici.
#
# Solo il minimo per ora: nessun era_rules_ref/name_rules ancora, non collegati a nulla in questo
# passo.

const FOLK_NAMES_PATH := "res://human/data/names/folk_names.txt"

var id: int = 0
var name: String = ""
var human_rules_ref: HumanRules = null

# Villaggi di questo Folk (2026-10-12, richiesta utente): vuoto finché non viene completato il primo village center.
# I totali del popolo (abitanti, in futuro R/C/P) sono la somma dei villaggi, mai salvati a parte.
var villages: Array[Village] = []
var next_village_id: int = 1

# Contatore aggregato condiviso da TUTTE le popolazioni/villaggi di questo Folk (2026-09-07,
# richiesta utente) — vive qui, non su Village, perché il design deciso lo vuole
# condiviso tra insediamenti diversi dello stesso Folk, non per singolo villaggio (vedi ricognizione
# Folk/contatore aggregato). Nessuna logica lo incrementa ancora in questo passo: solo il campo
# dichiarato, pronto per essere scritto da un futuro DepositThoughtAction. Raggiungibile da un
# HumanIndividual via individual.folk_ref.thoughts_count, stessa catena già in uso
# per human_rules_ref (vedi HumanStaminaIndividualService).
var thoughts_count: int = 0

# --- Modello dati albero tecnologie (2026-09-07, richiesta utente — solo campi, nessuna logica di
# assegnazione/verifica ancora: vedi Idea.gd per le definizioni statiche) ---

# Id (Idea.id, non l'oggetto Idea stesso — stesso principio di riferimento-per-id già usato da
# Building.building_type_name verso BuildingRules) dell'idea che riceve i pensieri ORA — "" =
# nessuna idea attiva. Nessuna logica lo valorizza ancora in questo passo (né automaticamente né
# da un comando esplicito) — arriverà con un futuro ThinkAction/DepositThoughtAction.
var active_idea_id: String = ""

# Pensieri accumulati per idea — chiave Idea.id, valore int accumulato. PERSISTE anche cambiando
# active_idea_id (richiesta esplicita utente): investire in un'idea, passare a un'altra e tornare
# indietro non fa perdere il progresso già fatto su quella lasciata a metà.
var thoughts_invested: Dictionary = {}

# Id delle idee già completate (Idea.id, stesso principio di active_idea_id sopra) — usato in
# futuro per risolvere Idea.prerequisites e BuildingRules.required_idea_id, non ancora consultato
# da nessuna logica in questo passo.
var completed_ideas: Array[String] = []

# Decadimento dei pensieri (2026-09-21, richiesta utente — vedi IdeaDecayService): Idea.id ->
# giorno assoluto (GameData.get_absolute_day) del prossimo decadimento, SOLO per idee con pensieri
# investiti che non sono né attive né completate. Impostato da IdeaProgressService.select_idea
# quando un'idea smette di essere attiva, rimosso quando torna attiva o a thoughts_invested zero.
var idea_decay_due_day: Dictionary = {}


func find_village(village_id: int) -> Village:
	for village in villages:
		if village.id == village_id:
			return village
	return null


# Valore assoluto di influenza del popolo (2026-10-12, passo 4): somma dei suoi villaggi, mai salvato a parte.
func get_influence_value(influence_type: InfluenceService.InfluenceType) -> float:
	var total := 0.0
	for village in villages:
		total += village.get_influence_value(influence_type)
	return total


# Abitanti del popolo tra gli individui passati, con o senza villaggio.
func count_members(individuals: Array[HumanIndividual]) -> int:
	var count := 0
	for individual in individuals:
		if individual.folk_ref == self:
			count += 1
	return count


# Nome casuale di popolo (2026-10-12, richiesta utente): dalla lista folk_names.txt, stesso formato dei nomi dei
# pipottini. Usato dal 🎲 delle opzioni di nuova partita e alla semina quando il giocatore non ne sceglie uno.
static func pick_random_name() -> String:
	var pool := HumanIndividual.load_name_pool(FOLK_NAMES_PATH)
	return pool[randi() % pool.size()] if not pool.is_empty() else ""
