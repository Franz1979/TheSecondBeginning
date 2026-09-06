class_name ExpiredObjectTypes

# Single source of truth per gli enum del futuro sistema di oggetti-scaduti (corpi morti, ruderi di
# edifici, carri rotti, ecc.) — stesso ruolo/stile di GameTypes.gd/HumanTypes.gd/DeathTypes.gd per i
# rispettivi domini, ma per ciò che serve a rimuovere/smaltire un oggetto scaduto dal mondo. Vive
# separato da ExpiredObjectRules (la classe Resource che lo consuma via @export) per lo stesso
# motivo per cui GameTypes.NaturalEventType vive separato da NaturalEventRules — enum condivisi
# tenuti fuori dalle classi Resource che li usano.
enum RemovalActionType {
	BURY,
	DISMANTLE,
	HARVEST,
}

# Step 2 (2026-09-05): il TIPO di oggetto scaduto stesso — necessario ora che esistono istanze
# runtime (GameData.expired_objects, un record per istanza nel mondo) che devono dire "sono
# UN corpo morto" per sapere quale ExpiredObjectRules risolvere (stesso principio di
# GameTypes.WorldObjectType/NaturalEventType: l'enum seleziona quale .tres caricare, per
# convenzione res://gameplay/data/expired_objects/{nome_minuscolo}_rules.tres). Solo DEAD_BODY per
# ora, stesso "non un caso ipotetico anticipato" già seguito da DeathTypes.DeathCause.
enum ExpiredObjectType {
	DEAD_BODY,
}
