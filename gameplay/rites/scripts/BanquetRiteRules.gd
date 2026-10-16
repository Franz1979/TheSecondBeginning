class_name BanquetRiteRules
extends SocialRiteRules

# Banchetto (2026-10-14, richiesta utente — primo rito sociale): ai campi comuni dei riti sociali (SocialRiteRules)
# aggiunge solo la cottura della carne del focolare, le cui calorie si dividono tra i presenti (dal 2026-10-14 niente cibo
# portato dai partecipanti). SocialRiteService la usa solo per i riti di questo tipo.

# Carne cruda da cuocere: ricetta del focolare e quantità minima nel suo deposito per organizzarlo. Si cuoce tutta
# durante la festa (feast_days).
@export var raw_meat_resource: String = "meat"
@export var cooked_resource: String = "cooked_meat"
@export var min_raw_meat: int = 5
# Bonus della Produce per l'organizzatore se ha cotto almeno un pezzo (skill_crafting, come task_produce_name).
@export var crafting_gain_organizer: float = 1.0
# Coesione in più per ogni carne cotta (2026-10-14, richiesta utente — più si festeggia, più il villaggio si unisce), oltre
# alla quota fissa SocialRiteRules.cohesion_gain.
@export var cohesion_gain_per_meat: float = 0.01
