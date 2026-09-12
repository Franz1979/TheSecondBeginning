class_name TaskTypes

# Single source di verità per gli enum del dominio Task/Action (2026-09-07, richiesta utente,
# riorganizzazione Action/Task) — stesso ruolo/stesso principio di GameTypes.gd (mondo simulato) e
# HumanTypes.gd (dominio umano): un file dedicato per dominio, nessuno dei tre referenzia gli
# altri due. Nessun `extends` (stesso stile di HumanTypes.gd) — puro contenitore di enum, mai
# istanziato.

# Un valore per ogni sottoclasse concreta di Action esistente (WalkAction/RestAction/ThinkAction/
# UnloadAction/PickUpAction) — usato da TaskStepDefinition (vedi task_step_definition.gd) per
# dichiarare QUALE Action istanziare senza che una TaskDefinition/.tres debba referenziare
# direttamente uno script Action concreto; TaskFactory.build_task (vedi task_factory.gd) legge
# questo enum per decidere il case giusto. THINK/UNLOAD aggiunti (2026-09-08, richiesta utente —
# persistenza Task/Action su save/load, vedi TaskPersistenceService; UNLOAD rinominato da DEPOSIT
# il 2026-09-09 insieme a DepositAction->UnloadAction, stesso valore intero — vedi
# TaskPersistenceService per la nota di compatibilità): TaskFactory.build_task NON li
# supporta ancora (nessuna TaskDefinition li usa oggi, solo Task costruite a mano in debug/
# TaskPersistenceService), ma servono comunque a IDENTIFICARE il tipo concreto di uno step salvato —
# stesso enum, due consumatori. PICKUP aggiunto (2026-09-08, richiesta utente, Step 2 del piano
# raccolta/trasporto) — stesso trattamento di THINK/UNLOAD: solo il valore enum, PickUpAction
# esiste (vedi gameplay/scripts/actions/PickUpAction.gd) ma non è ancora cablata in TaskFactory né
# in TaskPersistenceService, testabile solo via i debug hook di GameScene in questo passo. Estendere
# qui (mai altrove) quando arriveranno nuove Action concrete — HARVEST/BUILD, ... — aggiungendo il
# case corrispondente in TaskFactory E in TaskPersistenceService quando toccherà anche a loro.
enum ActionType {
	WALK,
	REST,
	THINK,
	UNLOAD,
	PICKUP,
	# SETUP_SITE (2026-09-10, richiesta utente — prima porzione della Build Task: trigger di
	# piazzamento + SetupSiteAction) — AGGIUNTO IN CODA, mai inserito in mezzo: gli enum precedenti
	# sono già persistiti come interi grezzi nei save esistenti (vedi TaskPersistenceService), un
	# inserimento a metà lista sposterebbe i valori di UNLOAD/PICKUP rompendo quei salvataggi. Vedi
	# gameplay/scripts/actions/SetupSiteAction.gd.
	SETUP_SITE,
	# CLEAR (2026-09-11, richiesta utente — terzo step della Build Task: rimozione vegetazione +
	# riserva spazio edificio, dopo Walk→SetupSite) — STESSO principio di SETUP_SITE sopra, AGGIUNTO
	# IN CODA. Vedi gameplay/scripts/actions/ClearAction.gd.
	CLEAR,
	# BUILD (2026-09-11, richiesta utente — quarto e ultimo step della Build Task: accumulo lavoro
	# giornaliero fino a required_labor, dopo Walk→SetupSite→Clear) — STESSO principio di SETUP_SITE/
	# CLEAR sopra, AGGIUNTO IN CODA. Vedi gameplay/scripts/actions/BuildAction.gd.
	BUILD,
	# LOOK_AROUND (2026-09-12, richiesta utente — Wander Task: Walk→LookAround→Walk→LookAround→Walk)
	# — STESSO principio di SETUP_SITE/CLEAR/BUILD sopra, AGGIUNTO IN CODA. Vedi
	# gameplay/scripts/actions/LookAroundAction.gd.
	LOOK_AROUND,
}

# Categorie di tool richiedibili da un'Action (2026-09-08, richiesta utente — SOLO struttura dati,
# nessuna logica di verifica/possesso ancora: vedi Action.required_tool_categories). Valori
# INDICATIVI, solo per fissare il pattern — da espandere quando arriverà il vero sistema tool
# (equip/verifica/PickUp), stesso principio "non un caso ipotetico anticipato" già seguito per
# BuildingTypes.Category/SecondaryResourceTypes.Category: si aggiungono voci qui quando servirà
# davvero, mai in anticipo.
enum ToolCategory {
	HUNTING,
	CUTTING,
	DIGGING,
	CRAFTING,
}
