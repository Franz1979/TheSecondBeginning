class_name StarVigilRiteRules
extends SocialRiteRules

# Veglia delle stelle (2026-10-29, richiesta utente — rito del Cerchio delle stelle e del Cerchio sacro del consiglio): un
# raduno religioso a calendario. Si celebra solo il giorno prima di ogni cambio di stagione e dura un giorno, da solo,
# nelle stagioni spuntate sull'edificio (Building.star_vigil_seasons); in una stagione non spuntata la veglia salta. Ai
# campi del raduno (SocialRiteRules) aggiunge il tiro sul cielo e gli effetti di fede, che i riti religiosi hanno in
# ReligiousRiteRules (stessi nomi e significato). Chi guida: RiteRules.min_skill di skill_ritual e
# RiteRules.allowed_age_bands.

@export_group("Calendar")
# Giorni prima del cambio di stagione in cui la veglia si annuncia e si sceglie chi guida (manuale e automatica): nessuno
# smette di lavorare.
@export var convocation_days_before: int = 3
# Chiamata (2026-10-29, richiesta utente — "lavorano, poi vanno"): giorni prima dell'inizio della veglia in cui tutto il
# villaggio lascia il lavoro e cammina al cerchio (0.5 = a metà del giorno prima).
@export var call_days_before_start: float = 0.5
# Finestra d'inizio (2026-10-29, richiesta utente — chi è andato a mangiare ha tempo di tornare): dall'alba del giorno
# della veglia per questa frazione di giorno la veglia comincia appena ci sono la guida e la quota di adulti; salta solo
# se alla fine della finestra non ci sono ancora.
@export var start_window_days: float = 0.5

@export_group("Attendance")
# Quota minima, sugli abitanti del villaggio nelle fasce SocialRiteRules.counted_age_bands, presenti al cerchio
# all'inizio della veglia; sotto, la veglia salta. Il minimo di abitanti resta SocialRiteRules.min_village_adults.
@export var min_present_ratio: float = 0.5

@export_group("Sky")
# Probabilità di cielo sereno per stagione, indicizzata per GameTypes.Season (WINTER, SPRING, SUMMER, AUTUMN): la
# stagione del giorno della veglia, cioè quella che finisce.
@export var clear_sky_chance_by_season: Array[float] = [0.4, 0.6, 0.8, 0.5]
# Squarcio tra le nuvole: un solo tiro, con probabilità di sereno = base + (1 - base) × questo valore × skill_ritual di
# chi guida / SKILL_MAX. Un numero caduto oltre la base ma sotto il totale è merito della guida (riga del log apposta).
@export var max_cloud_break_chance: float = 0.5

@export_group("Clear sky")
# Effetti col sereno, come ReligiousRiteRules: fede a chi guida, ai presenti, agli altri abitanti del villaggio (questi
# ultimi due per il fattore della skill di chi guida), punti di influenza RELIGIOUS dell'edificio e valore religioso del
# villaggio. Coesione, felicità e socialità sono quelle di SocialRiteRules.
@export var faith_celebrant: float = 300.0
@export var faith_present: float = 100.0
@export var faith_population: float = 20.0
@export var influence_gain: float = 5.0
@export var village_religion_gain: float = 2.0

@export_group("Cloudy")
# Effetti col cielo coperto: piccolo calo, minore che saltare la veglia. Niente influenza né valore religioso.
@export var cloudy_faith_loss_present: float = 10.0
@export var cloudy_cohesion_loss: float = 0.1

@export_group("Skipped")
# Veglia saltata (non programmata, nessuno che guidi, troppo pochi presenti): fede persa da tutti gli abitanti del
# villaggio e coesione persa dal villaggio.
@export var skip_faith_loss_population: float = 30.0
@export var skip_cohesion_loss: float = 0.3

@export_group("Skill")
# skill_ritual guadagnata da chi guida a fine veglia, sereno o coperto (interi, regola delle skill).
@export var ritual_gain_organizer: float = 1.0
