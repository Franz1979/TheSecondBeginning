class_name PredatorRules
extends AnimalRules

# Sottoclasse di AnimalRules per le specie predatrici (prima: lupo) — stesso pattern polimorfico
# già in uso per NaturalEventRules/FireEventRules: AnimalCalculator.get_animal_rules() carica il
# .tres con load(path) as AnimalRules, che risolve al tipo runtime effettivo (script_class nel
# .tres) senza bisogno di alcuna modifica al loader. I service predatore-specifici faranno il
# downcast esplicito (rules as PredatorRules), stesso schema di NaturalEventService.
#
# AnimalRules.max_density_per_cell resta ereditato ma DORMIENTE per questa sottoclasse: i
# predatori non hanno un tetto di densità sociale per cella (non "occupano" fisicamente lo spazio
# come gli erbivori), il vincolo di popolazione è invece max_population sotto. Nessun service
# predatore-specifico legge mai max_density_per_cell — stesso trattamento già riservato ad altri
# campi non pertinenti in questo codebase (es. old_duration_years prima che la mortalità per
# vecchiaia esistesse).

@export_group("Predation")
# Master switch comportamentale: true = il branco caccia collettivamente (lupo). Dichiarato ora
# anche se nessuna logica lo legge ancora (arriverà con PredationService) — default true perché la
# prima specie concreta è il lupo, coerente col principio "default = comportamento della prima
# specie reale" già seguito altrove (es. AnimalRules.visual_group_size).
@export var hunts_in_pack: bool = true

# Specie preda (chiave = species_name di un PopulationGroup erbivoro) -> coefficiente di facilità
# di cattura, stesso schema concettuale di AnimalRules.diet_compatibility ma sull'asse
# specie-preda invece che fonte-calorica. Vuoto per ora: la logica di popolamento/lettura arriva
# in uno step successivo (PredationService) — nessun service legge ancora questo campo.
@export var prey_compatibility: Dictionary = {}

@export_group("Pack Hunting Efficiency")
# Efficacia di caccia per fascia d'età (young/adult/old), stesso pattern di
# AnimalRules.fertility_multiplier_by_age/caloric_multiplier_by_age/mortality_share_by_age.
# I giovani partecipano marginalmente alla caccia (restano vicino alla tana/osservano),
# gli adulti sono il pieno potenziale, gli anziani compensano il calo fisico con l'esperienza.
@export var hunting_efficiency_by_age: Array[float] = [0.2, 1.0, 0.8]

# Tetto assoluto all'efficacia di caccia del branco (somma pesata di
# hunting_efficiency_by_age × popolazione per fascia, clampata a questo valore).
# Cattura il rendimento decrescente della caccia di gruppo oltre una certa dimensione:
# un branco molto numeroso non è proporzionalmente più efficace di uno ben composto ma
# più piccolo. Nessun default forzato: ogni specie predatrice lo dichiara esplicitamente
# nel proprio .tres, stesso principio già seguito per min/max_territory_cells.
@export var max_pack_hunting_efficiency: float

@export_group("Territory")
# Home range minimo/massimo in macrocelle, stessa semantica di AnimalRules.min_territory_cells/
# max_territory_cells ma con range atteso molto più ampio (150-300) — il territorio di un branco
# di lupi copre un'area enormemente maggiore di quella di un branco di erbivori. Nessun default
# forzato: ogni specie predatrice lo dichiara esplicitamente nel proprio .tres, stesso principio
# già seguito da AnimalRules per questi due campi.
@export var min_territory_cells: int
@export var max_territory_cells: int

# Tetto assoluto di popolazione del branco — sostituisce concettualmente densità×territorio
# (AnimalRules.max_density_per_cell × celle) come criterio di split per questa sottoclasse: i
# predatori non hanno una capacità etologica per cella, solo un limite assoluto di individui.
# Quando superato scatta lo split esistente (PopulationSplitService), con un trigger diverso da
# quello a densità degli erbivori (vedi TerritoryDynamicsService) — logica ancora da scrivere,
# solo il dato è dichiarato qui.
@export var max_population: int

# Lato (in macrocelle) della finestra quadrata di pattugliamento giornaliero del branco attorno
# alla propria posizione corrente — es. 5 = finestra 5x5. Dato puro per ora: la logica di
# pattugliamento/caccia che lo consuma arriva con PredationService, non implementata in questo
# step.
@export var hunting_window_size: int = 5
