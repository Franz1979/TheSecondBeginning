class_name SocialRiteRules
extends RiteRules

# Riti sociali (2026-10-14, richiesta utente — base + specializzazione): campi comuni a ogni raduno sociale (banchetto,
# in futuro danze, racconti…), gestiti da SocialRiteService. Il banchetto aggiunge cibo e cottura (BanquetRiteRules).

# Abitanti del villaggio (esclusi CHILD e INFANT) necessari per organizzarlo.
@export var min_village_adults: int = 5
# Partecipanti necessari per cominciare (da ragazzo in su; per il banchetto: arrivati con il cibo).
@export var min_participants: int = 5
# Chi si convoca e chi conta per cominciare (2026-10-16, lezione: solo i bambini). Fasce d'età (HumanTypes.AgeBand);
# vuoto = di sempre (convocati tutti; contano da ragazzo in su). L'organizzatore conta sempre.
@export var convoked_age_bands: Array[int] = []
@export var counted_age_bands: Array[int] = []
# Convocati al massimo, organizzatore escluso (0 = nessun limite).
@export var max_participants: int = 0
# Nome della task mostrato al giocatore (chiave tr, 2026-10-17 — lezione: "Insegnamento orale"); vuoto = "Rito sociale".
# Solo l'etichetta (Task.ACTIVITY_LABEL_KEY): task_name resta SocialRiteService.TASK_NAME per la logica.
@export var task_label_key: String = ""
# Stamina consumata al giorno dall'organizzatore mentre il raduno è in corso (2026-10-17, richiesta utente: banchetto 150
# come la Produce, lezione 100 come chi celebra un rito). Gli altri partecipanti non consumano stamina.
@export var organizer_stamina_per_day: float = 0.0
# Attesa massima dei partecipanti (giorni di gioco): scaduta con meno di min_participants, il rito salta.
@export var wait_days: float = 1.0
# Durata del raduno vero e proprio (giorni di gioco).
@export var feast_days: float = 1.0
# Effetti a fine rito per ogni partecipante presente (bambini compresi).
@export var happiness_gain: float = 20.0
@export var social_gain_participant: float = 0.5
@export var social_gain_organizer: float = 1.0
# Coesione del villaggio (VillageCohesionService).
@export var cohesion_gain: float = 0.1
# Inizio del raduno (2026-10-14): icona che sale sopra l'edificio (emoji) e suono (id di un banco audio, evento
# "social_rite_started:<id>" di SoundEventMap). Vuoti = niente.
@export var start_icon: String = ""
@export var start_sound_id: StringName = &""
