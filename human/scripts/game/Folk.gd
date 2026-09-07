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

var id: int = 0
var name: String = ""
var human_rules_ref: HumanRules = null

# Contatore aggregato condiviso da TUTTE le popolazioni/villaggi di questo Folk (2026-09-07,
# richiesta utente) — vive qui, non su HumanPopulationGroup, perché il design deciso lo vuole
# condiviso tra insediamenti diversi dello stesso Folk, non per singolo villaggio (vedi ricognizione
# Folk/contatore aggregato). Nessuna logica lo incrementa ancora in questo passo: solo il campo
# dichiarato, pronto per essere scritto da un futuro DepositThoughtAction. Raggiungibile da un
# HumanIndividual via individual.source_group_ref.folk_ref.thoughts_count, stessa catena già in uso
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
