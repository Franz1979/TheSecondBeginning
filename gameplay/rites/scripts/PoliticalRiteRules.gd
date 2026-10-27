class_name PoliticalRiteRules
extends SocialRiteRules

# Riunioni politiche (2026-10-26, richiesta utente — consiglio degli anziani, poi l'assemblea): riti politici al Cerchio del
# consiglio. Ai campi comuni dei riti sociali (raduno, attesa, durata, felicità e socialità, coesione) aggiunge l'Autorità
# dell'edificio, il valore politico del villaggio e la leadership, calcolati da PoliticalRiteService. Chi guida
# (organizzatore) ha almeno RiteRules.min_skill di leadership (RiteService.can_celebrate col tipo POLITICAL). Solo su
# ordine dal pannello (idle_cooldown_days 0): con il Capo villaggio si potranno programmare.

# Solo dove l'edificio è il centro del villaggio (Village.center_building_id).
@export var requires_village_center: bool = true
# Giorni minimi tra la fine di questo rito su un edificio e il suo ordine successivo, anche a mano (Building.last_rite_end_day).
@export var min_days_between: int = 30
# Leadership guadagnata a fine rito (interi, regola delle skill).
@export var leadership_gain_organizer: float = 1.0
@export var leadership_gain_participant: float = 1.0
# Lealtà data a ogni presente, chi guida compreso (2026-10-26, gran consiglio), per il fattore della leadership di chi guida.
@export var loyalty_gain: float = 0.0
# Autorità dell'edificio (punti di influenza POLITICAL): base + per partecipante presente, chi guida escluso.
@export var influence_points_base: float = 5.0
@export var influence_points_per_participant: float = 1.0
# Valore politico del villaggio (Village.add_influence_value), come la cultura per la lezione.
@export var village_political_gain: float = 1.0
@export var village_political_gain_per_participant: float = 0.2

@export_group("Quarrel")
# Lite (2026-10-26, richiesta utente — solo il gran consiglio): tirata a fine riunione, o va bene o va male, niente esiti
# intermedi. Probabilità = base + peso × quota di presenti scontenti (felicità sotto metà del massimo) + extra se la
# coesione del villaggio è sotto soglia − riduzione × leadership di chi guida / SKILL_MAX, tra 0 e il massimo.
# Base 0 = la riunione non litiga mai (consiglio degli anziani).
@export var quarrel_base_chance: float = 0.0
@export var quarrel_unhappy_weight: float = 0.5
@export var quarrel_low_cohesion_threshold: float = 25.0
@export var quarrel_low_cohesion_chance: float = 0.1
@export var quarrel_leadership_reduction: float = 0.25
@export var quarrel_max_chance: float = 0.8
# Effetti della lite: niente Autorità, valore politico, leadership né coesione positiva; lealtà persa dai presenti
# scontenti (gli altri non guadagnano nulla) e coesione del villaggio in calo.
@export var quarrel_loyalty_loss_unhappy: float = 25.0
@export var quarrel_cohesion_loss: float = 0.3

@export_group("Skipped")
# Rito saltato (2026-10-26, richiesta utente): attesa scaduta senza il minimo di partecipanti — non l'annullo con la X.
# Coesione persa dal villaggio e lealtà persa da tutti i suoi abitanti (solo dopo il battesimo, VillageService.
# is_loyalty_active). L'attesa tra due ordini (min_days_between) non parte: si può riprovare subito.
@export var skip_cohesion_loss: float = 0.0
@export var skip_loyalty_loss: float = 0.0
