class_name StockReserveService
extends RefCounted

# Riserva per la semina (2026-11-15, richiesta utente): il livello minimo del WM (GameData.stock_min_levels) delle
# Granaglie (categoria GRAIN) è la quantità che si conserva per seminare. Conta sul totale di tutti i magazzini e granai.
# Chi consuma granaglie per altro (zuppa, e domani farina, pane, birra...) chiede qui quanto può usare senza toccarla;
# la semina (TakeSeedsAction) invece prende tutto, riserva compresa. Le mangiatoie degli animali la rispettano già da sole
# (FeederStockService._plan_loads toglie i livelli minimi di ogni cibo). Minimo 0 = nessuna riserva.


# Once di `resource_name` tenute da parte per la semina (0 se non è una Granaglia o non ha un minimo).
static func seed_reserve(game_data: GameData, resource_name: String) -> int:
	if game_data == null:
		return 0
	var rules := CaloricCalculator.get_caloric_source_rules(resource_name)
	if rules == null or int(rules.category) != SecondaryResourceTypes.Category.GRAIN:
		return 0
	return maxi(int(game_data.stock_min_levels.get(resource_name, 0)), 0)


# Quanto di `total` (once nei magazzini di tutto il villaggio) si può usare senza toccare la riserva per la semina.
static func usable(game_data: GameData, resource_name: String, total: int) -> int:
	return maxi(total - seed_reserve(game_data, resource_name), 0)
