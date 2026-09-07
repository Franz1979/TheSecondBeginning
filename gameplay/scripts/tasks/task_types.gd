class_name TaskTypes

# Single source di verità per gli enum del dominio Task/Action (2026-09-07, richiesta utente,
# riorganizzazione Action/Task) — stesso ruolo/stesso principio di GameTypes.gd (mondo simulato) e
# HumanTypes.gd (dominio umano): un file dedicato per dominio, nessuno dei tre referenzia gli
# altri due. Nessun `extends` (stesso stile di HumanTypes.gd) — puro contenitore di enum, mai
# istanziato.

# Un valore per ogni sottoclasse concreta di Action esistente (WalkAction/RestAction) — usato da
# TaskStepDefinition (vedi task_step_definition.gd) per dichiarare QUALE Action istanziare senza
# che una TaskDefinition/.tres debba referenziare direttamente uno script Action concreto;
# TaskFactory.build_task (vedi task_factory.gd) legge questo enum per decidere il case giusto.
# Estendere qui (mai altrove) quando arriveranno nuove Action concrete — HARVEST/PICK_UP/DEPOSIT/
# BUILD, ... — aggiungendo il case corrispondente in TaskFactory.
enum ActionType {
	WALK,
	REST,
}
