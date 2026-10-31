class_name DangerProfile
extends Resource

# Profilo di un tipo di pericolo (2026-10-30, richiesta utente — lupi L5a): come reagisce chi lo subisce. La fuga è una
# sola (DangerFleeService + flee.tres: corri al riparo, aspetta che passi, riprendi il lavoro); cosa cambia da un
# pericolo all'altro sta qui. Dati in res://gameplay/dangers/data/{nome}.tres (predator.tres per i predatori; i nemici
# avranno il loro). Chi reagisce (oggi solo la persona caricata) e il contrattacco arriveranno con i passi successivi.

@export var danger_name: String = ""

@export_group("Shelter")
# Riparo verso cui si scappa, il più vicino tra quelli ammessi: la propria casa (completata, nella stessa macrocella) e i
# punti sicuri passati da chi crea il pericolo (per i lupi il focolare).
@export var flee_to_own_house: bool = true
@export var flee_to_safe_points: bool = true
# Distanza dal punto sicuro a cui fermarsi (microcelle): dentro la zona sicura, senza finire sul fuoco.
@export var safe_point_stop_distance: float = 1.5

@export_group("No shelter")
# Senza un riparo raggiungibile (o con il pericolo più vicino al riparo di chi scappa): corre via, nella direzione
# opposta al pericolo, per questa distanza (microcelle); false = resta dov'è.
@export var run_away_when_no_shelter: bool = true
@export var run_away_distance: float = 8.0

@export_group("Waiting")
# Tetto di sicurezza dell'attesa al riparo (giorni), se il pericolo non viene chiuso.
@export var max_wait_days: float = 1.0

@export_group("Drive off")
# Scacciare il pericolo in gruppo (2026-10-30, richiesta utente — lupi L6.1): all'inizio del pericolo gli adulti
# disponibili entro drive_off_radius (microcelle) da chi è preso di mira, se sono almeno drive_off_min_helpers e almeno
# uno ogni drive_off_threats_per_helper minacce (animali), corrono verso il pericolo (compito drive_off.tres) e si
# fermano a drive_off_stop_distance da lui. Meno di così: non si muove nessuno. false = nessuno lo scaccia.
@export var drive_off_enabled: bool = false
@export var drive_off_radius: float = 6.0
@export var drive_off_min_helpers: int = 2
@export var drive_off_threats_per_helper: int = 2
@export var drive_off_stop_distance: float = 2.0
# Chi può aiutare: fasce d'età ammesse.
@export var drive_off_age_bands: Array[HumanTypes.AgeBand] = [
	HumanTypes.AgeBand.FERTILE_ADULT, HumanTypes.AgeBand.MATURE_ADULT, HumanTypes.AgeBand.OLD]
