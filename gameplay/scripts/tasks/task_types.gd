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
