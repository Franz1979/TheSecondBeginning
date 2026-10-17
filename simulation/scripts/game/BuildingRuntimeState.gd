class_name BuildingRuntimeState
extends RefCounted

# Stato della manutenzione degli edifici che vive solo durante la partita, MAI salvato (2026-10-17, refactoring GameScene
# blocco 3a — prima variabili di GameScene). Tenuto in GameData.building_runtime; letto e scritto da
# BuildingMaintenanceService. Dopo un caricamento riparte da capo: i controlli giornalieri si rifanno alla prima lettura.

# Edifici danneggiati all'ultimo giro (id -> true), per accorgersi di chi entra o esce dallo stato "Danneggiato".
var last_damaged_building_ids: Dictionary = {}
# Riparazione automatica: giorno di gioco e soglia dell'ultimo controllo (-1 = da rifare).
var auto_repair_checked_day: int = -1
var auto_repair_checked_percent: int = -1
# Sgombero automatico delle macerie: giorno di gioco e regola dell'ultimo controllo (-1 = da rifare; un crollo lo azzera).
var auto_clear_checked_day: int = -1
var auto_clear_checked_enabled: bool = false
# Riti sociali spontanei (2026-10-17, lezione e banchetto): giorno assoluto di fine dell'ultimo rito sociale per edificio
# (id edificio -> giorno), per l'attesa SocialRiteRules.idle_cooldown_days. Dopo un caricamento è vuoto: il primo rito
# spontaneo può partire subito.
var last_social_rite_end_day: Dictionary = {}
