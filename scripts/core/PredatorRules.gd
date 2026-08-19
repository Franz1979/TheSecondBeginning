class_name PredatorRules
extends AnimalRules

# Sottoclasse di AnimalRules per le specie predatrici (prima: lupo) — stesso pattern polimorfico
# già in uso per NaturalEventRules/FireEventRules: AnimalCalculator.get_animal_rules() carica il
# .tres con load(path) as AnimalRules, che risolve al tipo runtime effettivo (script_class nel
# .tres) senza bisogno di alcuna modifica al loader. I service predatore-specifici faranno il
# downcast esplicito (rules as PredatorRules), stesso schema di NaturalEventService.
#
# AnimalRules.max_density_per_cell resta ereditato ma concettualmente DORMIENTE per questa
# sottoclasse: i predatori non hanno un tetto di densità sociale per cella (non "occupano"
# fisicamente lo spazio come gli erbivori), il vincolo di popolazione INTESO è invece
# max_population sotto. Nessun service PREDATORE-SPECIFICO (PredationService/PredatorPatrolService)
# legge mai max_density_per_cell — ma TerritoryDynamicsService, generico e condiviso con gli
# erbivori, SÌ (criterio di espansione/contrazione a densità e moltiplicatore di mitigazione
# natalità): non è stato escluso per i predatori come invece lo è stato il criterio calorico (vedi
# TerritoryDynamicsService.update_territories_and_mitigation), perché con territorio statico
# (min_territory_cells == max_territory_cells, oggi 200 per wolf) quel criterio è strutturalmente
# no-op — ma il campo VIENE letto, non è puramente "mai letto" come suggerirebbe una lettura troppo
# larga di questo commento. Va tenuto a mente se in futuro min/max_territory_cells smettessero di
# coincidere. Stesso trattamento (dormiente per i service specifici, non per quelli generici) già
# riservato ad altri campi non pertinenti in questo codebase (es. old_duration_years prima che la
# mortalità per vecchiaia esistesse).

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

# Divisore usato da PredationService per derivare i tentativi di caccia giornalieri
# dall'efficacia_branco (attempt_count = round(efficacia_branco / attempts_per_efficiency)) —
# prima un letterale hardcoded in PredationService, ora dato di specie, stesso refactor già fatto
# per i parametri di movimento cluster (rabbit/deer). Default 2.0 = valore storico hardcoded,
# nessun cambio di comportamento.
@export var attempts_per_efficiency: float = 2.0

# Efficacia minima (moltiplicatore di successo) raggiunta dall'ultimo tentativo di caccia della
# giornata — la stanchezza decresce linearmente da 1.0 (primo tentativo) a questo valore
# (ultimo), vedi PredationService._run_hunting_attempts. Default 0.5 = valore storico hardcoded.
@export var fatigue_floor: float = 0.5

# Moltiplicatore di convenienza applicato (Livello 1 di selezione preda) a una specie già
# bersagliata da un tentativo, riuscito o fallito, in precedenza nella stessa giornata — scoraggia
# senza vietare. Default 0.7 = valore storico hardcoded.
@export var repeat_target_malus: float = 0.7

# min_territory_cells/max_territory_cells sono ereditati da AnimalRules (gruppo "Territory" —
# vedi lì, non ridichiarabile qui: GDScript non permette lo shadowing di una @export var già
# presente nella classe padre, parser error "already exists in parent class") — riusati con la
# stessa semantica ma un range atteso molto più ampio (150-300) — il territorio di un branco di
# lupi copre un'area enormemente maggiore di quella di un branco di erbivori. Il default ereditato
# (1) è pensato per gli erbivori: ogni specie predatrice deve comunque sovrascriverlo esplicitamente
# nel proprio .tres.
@export_group("Pack Limits")
# Nome del gruppo deliberatamente diverso da "Territory" (il gruppo ereditato da AnimalRules sopra,
# min_territory_cells/max_territory_cells/max_density_per_cell): due @export_group con lo STESSO
# nome in una catena di ereditarietà non si fondono nell'Ispettore Godot, compaiono come due sezioni
# "Territory" separate e identiche nell'etichetta — confuso, non un problema di dati (i campi restano
# comunque corretti), solo di leggibilità dell'Ispettore.

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
