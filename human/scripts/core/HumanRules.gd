class_name HumanRules
extends Resource

# Regole demografiche/fisiologiche condivise da tutti gli insediamenti di un Folk (un file per
# Folk, quando Folk.gd esisterà) — stesso principio di AnimalRules per specie: i parametri di
# popolazione restano dati, il codice che li legge (futuro, non ancora scritto in questo passo)
# resta generico. Nessuna dipendenza da AnimalRules — solo pattern di riferimento (gruppi
# @export tematici), stesso principio già seguito da AnimalRules.

@export_group("Demographics")
# Durata (anni) di ciascuna fascia di HumanTypes.AgeBand, indici allineati (0=INFANT, 1=CHILD,
# 2=TEENAGER, 3=FERTILE_ADULT, 4=MATURE_ADULT, 5=OLD — ESTESO a 6 elementi 2026-09-12, richiesta
# utente, per la nuova fascia INFANT in testa: i valori CHILD/TEENAGER/ecc. preesistenti in ogni
# .tres sono stati spostati di UNA posizione in avanti, non re-inseriti da zero, vedi player_human_
# rules.tres) — DUE array paralleli invece di un Dictionary[HumanTypes.Sex, Array[float]] annidato:
# stesso idioma già usato da AnimalRules per ogni dato "per fascia" (fertility_multiplier_by_age,
# mortality_share_by_age, caloric_multiplier_by_age, dispersal_share_by_age — tutti Array[float]
# indicizzati posizionalmente dall'enum, mai un Dictionary a chiave enum). Un Dictionary annidato
# sarebbe meno tipizzato (i valori interni restano Variant, nessuna validazione di lunghezza/tipo) e
# nell'Inspector di Godot si presenta come editor generico invece che come lista a lunghezza
# fissa — due Array[float] paralleli restano coerenti con l'idioma già validato nel progetto e
# più semplici da leggere/editare. Le durate divergono tra i due sessi solo dove serve
# biologicamente (in particolare FERTILE_ADULT/MATURE_ADULT, vedi HumanTypes.AgeBand); nessuna
# logica li legge ancora in questo passo (INFANT incluso — collegamento al gameplay non ancora
# fatto, vedi EraRules.min_birth_spacing_years per il concetto imparentato ma indipendente).
@export var age_band_durations_male: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
@export var age_band_durations_female: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
# Coefficiente di natalità annuale di GRUPPO (non per sesso — un individuo non ha una propria
# natalità, solo il gruppo/insediamento nel suo complesso), stesso principio di
# AnimalRules.base_birth_rate. Non ancora letto da nessuna logica.
@export var base_birth_rate: float = 0.0

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
# by_age indicizzato come age_band_durations_male/female sopra (0=INFANT..5=OLD, ESTESO
# 2026-09-12, stesso motivo), by_sex indicizzato su HumanTypes.Sex (0=MALE, 1=FEMALE). Nessuna
# logica li legge ancora.
@export var size_multiplier_by_age: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
@export var size_multiplier_by_sex: Array[float] = [0.0, 0.0]
@export var size_variance: float = 0.0

# Capacità di trasporto di riferimento per un adulto pieno (2026-09-08, richiesta utente) —
# stessa unità astratta di SecondaryResourceRules.space_per_unit (nessun kg/microcelle, "spazio"
# generico, vedi quel campo per la verifica fatta sul resto del progetto), scalata dagli STESSI
# due assi già usati per la taglia fisica (size_multiplier_by_age/size_multiplier_by_sex sopra),
# MAI un nuovo array dedicato al trasporto — verificato: sono @export su questa stessa classe,
# quindi già accessibili ovunque HumanRules lo è, incluso HumanCalculator.get_max_stamina (stesso
# punto dove verrà calcolata la capacità di trasporto effettiva, vedi HumanCalculator.
# get_max_carry_capacity). Nessuna logica la legge ancora oltre a quel calcolo.
@export var base_carry_capacity: float = 30.0

# Spazio della "saccoccia" del cibo (2026-09-19, richiesta utente) — SPAZIO, non calorie: stessa unita' astratta di base_carry_capacity sopra e di SecondaryResourceRules.space_per_unit. Parametro INDIPENDENTE da base_carry_capacity (non derivato dal trasporto), scalato dagli STESSI due assi di taglia (size_multiplier_by_age/size_multiplier_by_sex) ma SENZA il bonus degli slot attrezzi liberi e senza equipment_multiplier - vedi HumanCalculator.get_max_food_space. Sostituisce concettualmente il vecchio parametro vitale "fame" (HumanIndividual.max_hunger, ora max_food_space).
@export var base_food_space: float = 30.0

# Riserva calorica del corpo (2026-09-19, richiesta utente): calorie di riserva di un individuo con
# taglia 1.0, scalate dagli STESSI due assi di taglia (size_multiplier_by_age/size_multiplier_by_sex,
# non dai caloric_multiplier) - vedi HumanCalculator.get_max_body_calories. Verra' intaccata quando le
# provviste sono a zero. Solo il parametro: nessun campo sull'individuo, nessun consumo, nessuna UI.
@export var base_body_calories: float = 200.0

# Slot tool (2026-09-08, richiesta utente; dal 2026-09-25 gli attrezzi si equipaggiano nella cintura
# HumanIndividual.equipped_tools, ancora senza usura né requisiti). tool_slot_count è il
# numero totale di slot che un individuo ha a disposizione; ogni slot VUOTO (non occupato da un
# tool equipaggiato) dà un bonus FLAT alla capacità di trasporto effettiva — un tool, quando il
# sistema di equip esisterà, presumibilmente offrirà il proprio bonus specifico al posto di questo
# generico "slot vuoto" (motivo per cui il bonus è per slot LIBERO, non per slot totale: un tool
# equipaggiato toglie il bonus generico ma non ne aggiunge ancora uno proprio, coerente col fatto
# che nessun tool esiste ancora). Vedi HumanCalculator.get_max_carry_capacity per la formula
# completa (bonus applicato DOPO il moltiplicatore di taglia, non dentro).
@export var tool_slot_count: int = 4
@export var carry_bonus_per_empty_tool_slot: float = 3.0

# Moltiplicatori calorici (fabbisogno per età/sesso, stessi due assi di size_multiplier_by_age/
# by_sex sopra) — nel .tres di prova valorizzati con GLI STESSI numeri di size_multiplier_by_age/
# by_sex, deliberatamente: nessuna logica di derivazione scritta qui, solo dati duplicati fino a
# quando un service reale non li userà e si potrà decidere se calore e taglia devono davvero
# scalare allo stesso modo o divergere. Nessun caloric_variance separato: quando servirà una
# varianza per il fabbisogno calorico si riuserà size_variance sopra, non se ne aggiunge una
# seconda equivalente.
# Indicizzato come size_multiplier_by_age sopra (0=INFANT..5=OLD, ESTESO 2026-09-12).
@export var caloric_multiplier_by_age: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
@export var caloric_multiplier_by_sex: Array[float] = [0.0, 0.0]

# Consumo calorico giornaliero di base (2026-09-19, richiesta utente): calorie consumate al giorno da
# un individuo con moltiplicatore 1.0, scalate da caloric_multiplier_by_age/caloric_multiplier_by_sex
# sopra (NON dai size_multiplier, che restano per saccoccia e trasporto) - vedi
# HumanCalculator.get_daily_calorie_consumption e HumanVitalsIndividualService.
# apply_daily_calorie_consumption.
@export var base_daily_calorie_consumption: float = 20.0

@export_group("Mortality")
# Curva di mortalità età-dipendente: due estremi scalari (non per-fascia come gli array sopra,
# perché descrivono una curva continua che attraversa MATURE_ADULT e OLD, non un valore fisso per
# singola fascia) più un tetto assoluto d'età. Nessuna logica li legge ancora in questo passo — la
# funzione di interpolazione arriva in uno step successivo.
@export var mortality_prob_at_mature_start: float = 0.001
@export var mortality_prob_at_old_end: float = 0.65
@export var absolute_max_age: int = 100

@export_group("Reproduction")
# Probabilità di concepimento annuale di BASE per una coppia idonea (FERTILE_ADULT/FERTILE_ADULT,
# senza figlio sotto soglia — vedi HumanConceptionIndividualService) — scalata per Era da
# EraRules.conception_probability_multiplier, stesso principio "base in HumanRules × moltiplicatore
# in EraRules" già seguito da age_band_durations_male/female/longevity_multiplier_by_age.
# PLACEHOLDER (richiesta utente, 2026-09-06): valore plausibile, da affinare quando esisterà un
# consumatore reale con cui bilanciare.
@export var conception_base_probability: float = 0.4
# Probabilità di sopravvivenza al parto, rispettivamente per il neonato e per la madre — due campi
# distinti perché i due rischi sono indipendenti (un parto può perdere l'uno, l'altra, entrambi o
# nessuno). Scalate per Era dai due moltiplicatori paralleli sotto in EraRules, stesso schema di
# conception_base_probability sopra. Nessuna logica li legge ancora in questo passo (solo dati,
# vedi Step 1 del piano riproduzione) — il parto vero e proprio è un task separato.
# PLACEHOLDER (richiesta utente, 2026-09-06): valori plausibili, da affinare in seguito.
@export var childbirth_survival_child_base_probability: float = 0.9
@export var childbirth_survival_mother_base_probability: float = 0.92

@export_group("Vital Parameters")
# 6 parametri vitali — stamina (il primo introdotto) + i 5 aggiunti dopo (hunger/thirst/health/
# happiness/loyalty) — STESSO identico schema per tutti (base_max_<nome> × <nome>_multiplier_by_age
# [age_band] × <nome>_multiplier_by_sex[sex], calcolato da HumanCalculator.get_max_<nome>, mai
# dentro questa classe), tre campi ciascuno. stamina SPOSTATA QUI (2026-09-13, richiesta utente) dal
# proprio @export_group("Stamina") precedente, RIMOSSO — puro riordino per coerenza visiva
# nell'Inspector (stamina è concettualmente un parametro vitale come gli altri 5, semplicemente il
# primo esistito): nessun cambio di nome/valore/logica su base_max_stamina/stamina_multiplier_by_
# age/stamina_multiplier_by_sex, solo la posizione nel file e nel gruppo Inspector. L'ordine dei
# campi in un .gd/.tres è puramente posizionale per l'Inspector — ogni lettura nel codebase avviene
# per NOME (human_rules.base_max_stamina, mai per indice), quindi il riordino non ha alcun effetto
# funzionale, verificato.
#
# Capacità lavorativa giornaliera di riferimento per un adulto pieno (FERTILE_ADULT/MATURE_ADULT,
# moltiplicatore 1.0 sotto) — valore unico, non per-età: l'asse età è tutto in
# stamina_multiplier_by_age, stesso principio di size_multiplier_by_age/caloric_multiplier_by_age
# sopra. Unità arbitraria (nessun significato fisico ancora deciso — "punti lavoro/giorno" o
# simile), da tarare quando un consumatore reale esisterà. DECOUPLED dalle age band di
# aging/riproduzione: stamina_multiplier_by_age riusa lo stesso enum/array solo per comodità di
# storage (stesso idioma "per fascia" del progetto), non introduce alcun legame concettuale nuovo
# tra capacità lavorativa e fertilità/invecchiamento.
#
# Rinominato da Workforce a Stamina (2026-09-06, richiesta utente) — solo rename, nessuna modifica
# di valori/logica: base_daily_workforce->base_max_stamina, workforce_multiplier_by_age/sex->
# stamina_multiplier_by_age/sex, gruppo export "Workforce"->"Stamina" (poi confluito in "Vital
# Parameters" il 2026-09-13, vedi sopra).
@export var base_max_stamina: float = 5000.0
# Indicizzato come size_multiplier_by_age/caloric_multiplier_by_age sopra (0=INFANT, 1=CHILD,
# 2=TEENAGER, 3=FERTILE_ADULT, 4=MATURE_ADULT, 5=OLD — ESTESO 2026-09-12 per la nuova fascia
# INFANT, valore 0.0 di default come CHILD, coerente: nessuna stamina). CHILD=0.0 (nessuna
# stamina), TEENAGER/OLD ridotti (placeholder, da rivedere), FERTILE_ADULT/MATURE_ADULT=1.0
# (riferimento). Nessuna logica li legge ancora oltre a HumanCalculator.get_max_stamina (solo base
# × moltiplicatore, senza stanchezza/wellness — quelli arriveranno in un passo successivo).
@export var stamina_multiplier_by_age: Array[float] = [0.0, 0.0, 0.4, 1.0, 1.0, 0.5]
# Indicizzato su HumanTypes.Sex (0=MALE, 1=FEMALE), stessa convenzione di size_multiplier_by_sex/
# caloric_multiplier_by_sex sopra. Placeholder, da rivedere.
@export var stamina_multiplier_by_sex: Array[float] = [1.0, 0.85]

# Parametri vitali (2026-09-13, richiesta utente) — thirst/health/happiness/loyalty (il parametro
# "hunger" e' stato rimosso il 2026-09-19: base_max_hunger e hunger_multiplier_by_age/sex non esistono
# piu', la saccoccia del cibo usa base_food_space e i moltiplicatori di taglia, e il futuro fabbisogno
# calorico usera' la taglia, non moltiplicatori di fame dedicati), STESSO identico schema di stamina sopra. Multiplier di default TUTTI NEUTRI (1.0, non i
# valori placeholder "a mano" di stamina sopra — es. CHILD=0.0 lì): questi 4 parametri sono
# dichiarazione pura in questo passo, nessun consumatore reale/Task/Action li legge ancora
# (arriverà in un giro successivo, quando si decideranno i moltiplicatori specifici) — un default
# neutro evita di inventare una curva per-età/sesso plausibile ora per poi doverla rifare da capo.
# base_max_<nome> = 5000.0 per ciascuno, STESSO valore di base_max_stamina sopra, stessa
# motivazione ("un numero coerente col resto del sistema", nessun significato fisico ancora deciso).
#
# thirst (fabbisogno fisiologico) — SOSTITUISCE concettualmente il precedente gruppo
# @export_group("Hunger") (daily_caloric_requirement/max_days_without_food, RIMOSSO in un passo
# precedente: verificato con un grep esaustivo che nessuna logica del progetto lo consultava
# mai, a differenza dell'omonimo AnimalRules.daily_caloric_requirement/max_days_without_food,
# quello sì usato ovunque nel dominio animale — i due erano campi distinti su classi distinte, mai
# collegati tra loro). thirst qui e' invece un parametro vitale 0..max stile stamina
# (consumato/recuperato da un futuro sistema di Task/Action), non più "giorni di digiuno prima
# della morte": stesso spostamento concettuale già maturato per stamina rispetto alla vecchia
# Workforce.
@export var base_max_thirst: float = 5000.0
@export var thirst_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var thirst_multiplier_by_sex: Array[float] = [1.0, 1.0]

@export var base_max_health: float = 5000.0
@export var health_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var health_multiplier_by_sex: Array[float] = [1.0, 1.0]

@export var base_max_happiness: float = 5000.0
@export var happiness_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var happiness_multiplier_by_sex: Array[float] = [1.0, 1.0]

# Loyalty verso chi/cosa non è ancora definito concettualmente — il parametro esiste già in
# previsione di un futuro sistema (fazioni? famiglia? leader?), ma senza ancora un bersaglio
# semantico.
@export var base_max_loyalty: float = 5000.0
@export var loyalty_multiplier_by_age: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var loyalty_multiplier_by_sex: Array[float] = [1.0, 1.0]
