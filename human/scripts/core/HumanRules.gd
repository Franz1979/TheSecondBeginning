class_name HumanRules
extends Resource

# Regole demografiche/fisiologiche condivise da tutti gli insediamenti di un Folk (un file per
# Folk, quando Folk.gd esisterà) — stesso principio di AnimalRules per specie: i parametri di
# popolazione restano dati, il codice che li legge (futuro, non ancora scritto in questo passo)
# resta generico. Nessuna dipendenza da AnimalRules — solo pattern di riferimento (gruppi
# @export tematici), stesso principio già seguito da AnimalRules.

@export_group("Demographics")
# Durata (anni) di ciascuna fascia di HumanTypes.AgeBand, indici allineati (0=CHILD, 1=TEENAGER,
# 2=FERTILE_ADULT, 3=MATURE_ADULT, 4=OLD) — DUE array paralleli invece di un
# Dictionary[HumanTypes.Sex, Array[float]] annidato: stesso idioma già usato da AnimalRules per
# ogni dato "per fascia" (fertility_multiplier_by_age, mortality_share_by_age,
# caloric_multiplier_by_age, dispersal_share_by_age — tutti Array[float] indicizzati
# posizionalmente dall'enum, mai un Dictionary a chiave enum). Un Dictionary annidato sarebbe
# meno tipizzato (i valori interni restano Variant, nessuna validazione di lunghezza/tipo) e
# nell'Inspector di Godot si presenta come editor generico invece che come lista a lunghezza
# fissa — due Array[float] paralleli restano coerenti con l'idioma già validato nel progetto e
# più semplici da leggere/editare. Le durate divergono tra i due sessi solo dove serve
# biologicamente (in particolare FERTILE_ADULT/MATURE_ADULT, vedi HumanTypes.AgeBand); nessuna
# logica li legge ancora in questo passo.
@export var age_band_durations_male: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
@export var age_band_durations_female: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
# Coefficiente di natalità annuale di GRUPPO (non per sesso — un individuo non ha una propria
# natalità, solo il gruppo/insediamento nel suo complesso), stesso principio di
# AnimalRules.base_birth_rate. Non ancora letto da nessuna logica.
@export var base_birth_rate: float = 0.0

@export_group("Hunger")
# Stesso principio di AnimalRules.daily_caloric_requirement/max_days_without_food — nessuna
# logica li legge ancora (nessun CaloricCalculator/service umano scritto in questo passo).
@export var daily_caloric_requirement: float = 0.0
@export var max_days_without_food: int = 0

@export_group("Physical")
# Forza di riferimento per un HumanIndividual materializzato appena creato e relativa varianza
# usata per una futura generazione casuale intorno a base_strength — nessuna logica la legge
# ancora.
@export var base_strength: float = 1.0
@export var strength_variance: float = 0.0

# Moltiplicatori di taglia (young->old, maschio/femmina) applicati a una taglia di riferimento —
# stesso principio di AnimalRules.size_multiplier_by_age (adult/FERTILE_ADULT=1.0 è il
# riferimento a cui le dimensioni base sono tarate), ma qui SPEZZATO in due assi indipendenti
# (età E sesso, applicati insieme per moltiplicazione) invece di un unico array come fa
# AnimalRules — necessario perché qui, a differenza degli animali tracciati oggi, la
# dimorfia di sesso è un asse a sé che si combina con quella d'età, non un'alternativa ad essa.
# by_age indicizzato come age_band_durations_male/female sopra (0=CHILD..4=OLD), by_sex
# indicizzato su HumanTypes.Sex (0=MALE, 1=FEMALE). Nessuna logica li legge ancora.
@export var size_multiplier_by_age: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
@export var size_multiplier_by_sex: Array[float] = [0.0, 0.0]
@export var size_variance: float = 0.0

# Moltiplicatori calorici (fabbisogno per età/sesso, stessi due assi di size_multiplier_by_age/
# by_sex sopra) — nel .tres di prova valorizzati con GLI STESSI numeri di size_multiplier_by_age/
# by_sex, deliberatamente: nessuna logica di derivazione scritta qui, solo dati duplicati fino a
# quando un service reale non li userà e si potrà decidere se calore e taglia devono davvero
# scalare allo stesso modo o divergere. Nessun caloric_variance separato: quando servirà una
# varianza per il fabbisogno calorico si riuserà size_variance sopra, non se ne aggiunge una
# seconda equivalente.
@export var caloric_multiplier_by_age: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
@export var caloric_multiplier_by_sex: Array[float] = [0.0, 0.0]

@export_group("Mortality")
# Curva di mortalità età-dipendente: due estremi scalari (non per-fascia come gli array sopra,
# perché descrivono una curva continua che attraversa MATURE_ADULT e OLD, non un valore fisso per
# singola fascia) più un tetto assoluto d'età. Nessuna logica li legge ancora in questo passo — la
# funzione di interpolazione arriva in uno step successivo.
@export var mortality_prob_at_mature_start: float = 0.001
@export var mortality_prob_at_old_end: float = 0.65
@export var absolute_max_age: int = 100

@export_group("Workforce")
# Capacità lavorativa giornaliera di riferimento per un adulto pieno (FERTILE_ADULT/MATURE_ADULT,
# moltiplicatore 1.0 sotto) — valore unico, non per-età: l'asse età è tutto in
# workforce_multiplier_by_age, stesso principio di size_multiplier_by_age/caloric_multiplier_by_age
# sopra. Unità arbitraria (nessun significato fisico ancora deciso — "punti lavoro/giorno" o
# simile), da tarare quando un consumatore reale esisterà. DECOUPLED dalle age band di
# aging/riproduzione: workforce_multiplier_by_age riusa lo stesso enum/array solo per comodità di
# storage (stesso idioma "per fascia" del progetto), non introduce alcun legame concettuale nuovo
# tra capacità lavorativa e fertilità/invecchiamento.
@export var base_daily_workforce: float = 500.0
# Indicizzato come size_multiplier_by_age/caloric_multiplier_by_age sopra (0=CHILD, 1=TEENAGER,
# 2=FERTILE_ADULT, 3=MATURE_ADULT, 4=OLD). CHILD=0.0 (nessuna workforce), TEENAGER/OLD ridotti
# (placeholder, da rivedere), FERTILE_ADULT/MATURE_ADULT=1.0 (riferimento). Nessuna logica li legge
# ancora oltre a HumanCalculator.get_base_workforce (solo base × moltiplicatore, senza
# stanchezza/wellness — quelli arriveranno in un passo successivo).
@export var workforce_multiplier_by_age: Array[float] = [0.0, 0.4, 1.0, 1.0, 0.5]
# Indicizzato su HumanTypes.Sex (0=MALE, 1=FEMALE), stessa convenzione di size_multiplier_by_sex/
# caloric_multiplier_by_sex sopra. Placeholder, da rivedere.
@export var workforce_multiplier_by_sex: Array[float] = [1.0, 0.85]
