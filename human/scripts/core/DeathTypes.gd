class_name DeathTypes

# Single source of truth per le cause di morte umana — stesso ruolo/stile di NotificationTypes.gd,
# ma per il log eventi grezzo (vedi GameData.death_events, Step 8 del piano mortalità, 2026-09-05).
# Solo OLD_AGE per ora (unica causa implementata, vedi HumanMortalityIndividualService) — pensato
# per crescere quando arriveranno starvation/malattie/predazione, nessun caso ipotetico anticipato.
enum DeathCause {
	OLD_AGE,
}
