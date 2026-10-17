class_name JobBoardContext
extends RefCounted

# Quello che serve ai fornitori dei lavori della lista per decidere (2026-10-17, refactoring GameScene blocco 2b): dati
# della partita, mondo, popolazione e quali macrocelle sono vive. Lo costruisce chi chiama i fornitori (oggi GameScene,
# domani il driver della simulazione), così i fornitori in gameplay/jobs/scripts/providers/ non dipendono dalla scena.

var game_data: GameData
var world: World
var individuals: Array[HumanIndividual] = []
var folk: Folk
# Macrocelle vive (caricate nel dettaglio): Vector2i -> LiveMacroCell. Lo stesso dizionario della scena, per riferimento
# (mai modificato dai fornitori): i servizi delle zone (CutZoneService, HuntZoneService) lo ricevono così.
var live_cells: Dictionary = {}


# Fascia d'età di `member` con le durate EFFETTIVE dell'Era corrente (stessa formula di GameScene._resolve_age_band).
func age_band_of(member: HumanIndividual) -> HumanTypes.AgeBand:
	return HumanCalculator.get_age_band(
		game_data.era_effective_age_band_durations_male, game_data.era_effective_age_band_durations_female,
		member.sex, float(game_data.year - member.birth_year_virtual)
	)


# Testo tradotto (stesso risultato di tr(), usabile dalle funzioni statiche dei fornitori).
static func tr_text(key: String) -> String:
	return String(TranslationServer.translate(key))
