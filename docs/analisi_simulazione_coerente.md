# Analisi: sostituire la simulazione "fisica" di fauna e flora con stati "simulati ma coerenti"

2026-10-26 — solo analisi, nessuna modifica al codice.

**Domanda.** Se si togliesse tutta la simulazione di fondo (mandrie `PopulationGroup` con predazione, territori, LOD
e fame; vegetazione per macrocella con crescita, encroachment, migrazione e mortalità) e la si sostituisse con
gruppi o stati "simulati ma coerenti", come il branco di lupi del villaggio (`gameplay/visitors/animals/`):
quanto lavoro sarebbe? Il gioco e le prestazioni ne guadagnerebbero? Si può fare anche per la vegetazione?

**Risposta breve.**
- Togliere tutto in blocco non conviene: il guadagno di CPU è piccolo, perché il costo vero non sta lì.
- Conviene invece sostituire i *motori* tenendo le *interfacce*: gli stessi campi e funzioni di lettura
  (`resource_quantity`, `dedicated_space`, `get_population_by_cell`, `get_age_composition_in_cell`,
  `apply_predation_loss`) restano, ma vengono riempiti da un modello più semplice.
- Lo si farebbe solo fuori da un anello attorno ai villaggi. Il LOD della fauna fa già metà di questo lavoro.

---

## 1. Cosa dipende oggi dalla simulazione fisica

### 1.1 Fauna selvatica (`PopulationGroup`)

| Chi legge o scrive | Cosa usa | Note |
|---|---|---|
| **Caccia** (`GameScene._on_prey_killed` → `HuntService.apply_prey_kill`) | `PopulationGroup.apply_predation_loss` per fascia d'età | La preda è un individuo dell'`AnimalGroupRenderer`; la morte scala di uno la popolazione del gruppo. |
| **Individui visibili** (`GameScene._refresh_animal_individuals`, `_update_animal_renderer_population`) | `get_population_groups_at`, `get_population_by_cell`, `get_age_composition_in_cell` | Ogni giorno il renderer allinea gli individui alla quota della cella: è il legame tra numeri e animali visibili. |
| **Salvataggio** (`GameSaveService`/`GameLoadService`) | gruppi completi (`age_composition`, `hunger_buckets`, territorio, `birth_mitigation_*`, `hunger_split_cooldown_days`) + `animal_individuals_by_cell` | Gli individui delle celle vive si salvano a parte. |
| **Pannelli** (`WorldInfoPanel` 36 riferimenti, `MacroCellDetailPanel`, `MacroCellInfoPanel`) | popolazioni per cella e per specie | Solo lettura. |
| **Scelta della cella di partenza** (`FirstStartMacroCellSelectionService`, `CellRichnessCalculator`) | ricchezza di fauna per cella | Solo lettura. |
| **Incontro per l'addomesticazione** (`GameScene._check_encountered_wild_species`) | un animale della specie visibile in una cella viva | Dipende dal renderer, quindi indirettamente dalla quota. |
| **Vegetazione** (`AnimalConsumptionService`, `AnimalConsumptionAggregateService`, `BrowsingMitigationService`, `LODOrchestrator.vegetation_feeding_active`) | gli erbivori mangiano erba e frenano l'encroachment; il LOD sblocca la crescita dove pascolano | **È l'accoppiamento più forte tra fauna e flora.** |
| **Debug** (`DebugBar`, strumenti in `tools/`) | quote e individui | Si può adattare in fretta. |

Il motore conta circa **7.000 righe**, quasi tutte in `simulation/scripts/core/`:
- `PredationService` 765, `PredatorPatrolService` 276;
- `TerritoryDynamicsService` 691, `TerritoryBuilderService` 252, `PopulationSplitService` 180;
- `AnimalConsumption*` 592, `AnimalHunger*` 548, `AnimalBirth*` 281, `AnimalSeedingService` 401;
- `LODOrchestrator` 381, `PopulationGroup` 513;
- `AnimalGroupRenderer` 1.825. Il renderer **resta in ogni scenario**: disegna gli individui, gestisce la fuga ed è il
  bersaglio della caccia.

### 1.2 Vegetazione per macrocella

| Chi legge o scrive | Cosa usa |
|---|---|
| **Taglio, raccolta, cantieri** (`PlayerHarvestService`, `ClearAction`, `BuildingSiteClearingService`, `VegetationCutPatchService`) | tolgono quantità o spazio e l'individuo dal layout |
| **Individui e layout** (`VegetationLayoutService`, `IndividualVegetationService`, `LotCapacityService`, `VegetationPoolService`) | quantità, sottotipi e fasce d'età → posizioni, lotti, capacità (bastoni, fibre, funghi) |
| **Frutti e foraggio** (`CaloricCalculator`, `_run_secondary_resource_stock_checkpoint`) | `resource_quantity` × `subtype_composition` → scorte stagionali |
| **Fauna** | gli erbivori consumano l'erba (sopra) |
| **Eventi naturali** (`NaturalEventService`, `VegetationDestructionService`, `active_growth_bonuses`) | distruggono spazio e modificano la crescita |
| **Pannelli, scelta della partenza, `worldRenderer`** | lettura |
| **Salvataggio** | `cell_states` (`dedicated_space`, quantità, sottotipi, fasce d'età, bonus, `vegetation_layout`) |

Il motore in senso stretto è piccolo: crescita 119 righe, encroachment 225, migrazione 217, mortalità 133, fasce d'età
35, riconciliazione 77, **in tutto ~800 righe**. Il resto (layout, lotti, individui, calcolatori) serve al gioco
qualunque sia il modello.

### 1.3 Quando gira cosa

Da `WorldTimeService.advance_day` e `docs/simulation_daily_services.csv`.

**Ogni giorno:**
- `AnimalConsumptionService`: solo gruppi di livello 2;
- `PredationService`: tutti i branchi non congelati;
- passaggio giornaliero di `TerritoryDynamicsService` sul livello 1;
- `AnimalHungerService`;
- pulizia dei gruppi estinti.

**A ogni stagione:**
- scorte secondarie;
- consumo e fame aggregati del livello 1;
- eventi naturali;
- territori e mitigazione delle nascite.

**A fine primavera:** crescita, encroachment, mitigazione da brucatura.

**Al cambio d'anno:** mortalità della vegetazione e riconciliazione dello spazio. Il ciclo di vita degli animali
cade a fine della stagione delle nascite di ogni specie.

---

## 2. Cosa si perderebbe e cosa si guadagnerebbe

### 2.1 Prestazioni: dove sta davvero il costo

I log `[DAY TIMING]`/`[LOD TIMING]` sono spenti (`DebugLogging.SHOW_DAILY_TIMING_LOGS = false`) e non c'è nessun
log salvato con quelle voci. Le misure sotto vengono quindi dalle memorie e dai commenti nel codice.

**Picco al cambio di anno o stagione (2026-10-22): ~1,7 s.**

| Voce | Tempo | Effetto del cambio di modello |
|---|---|---|
| `_apply_natural_…` (lato `GameScene`, individui e visuali) | ~682 ms | non lo tocca |
| `MicroCellRenderer` ×225 | ~575 ms | non lo tocca |
| **`WorldTimeService` ×13** | **~350 ms** | **unica parte che il cambio toccherebbe** |

**Checkpoint delle scorte secondarie: ~150–180 ms.** Gran parte è l'overhead di visitare 40.000 combinazioni
fonte×cella anche quando le salta (commento in `WorldTimeService._run_secondary_resource_stock_checkpoint`).
Si risolve con un indice delle celle rilevanti, senza cambiare modello.

**Profilo di un checkpoint di fase B: su ~1,2 s, ~500 ms sono `LotCapacityService`** (tutti i 15.116 lotti) e
~245 ms sono il rebuild delle multimesh. Anche questo è lato individui e layout, già in programma con le fasi 4–5
di B.

**Giorno normale.** Non c'è una misura recente. Predazione, consumo e fame girano solo sui gruppi non congelati
(decine), quindi si stima qualche ms al giorno. Va misurato prima di decidere (vedi §5).

> **Conclusione.** La simulazione di fondo pesa circa il 20% del picco stagionale e poco nel giorno normale. Il
> grosso è nella rappresentazione a individui delle celle vive (renderer, layout, lotti, visuali della mortalità),
> che serve in ogni caso. Togliere la simulazione fisica **non risolve gli scatti che l'utente vede**.

C'è poi un punto importante per la scala obiettivo: **il costo del mondo non cresce col numero di pipottini.**
Cresce col numero di celle vive e di gruppi a livello 2, quindi con l'estensione dei villaggi, non con la
popolazione. Con migliaia di pipottini i sistemi da curare sono i lavori, i percorsi e la vegetazione a individui.

### 2.2 Gioco: cosa si perderebbe

Si perdono meccaniche concrete e visibili, quelle che l'utente preferisce ai moltiplicatori:
- **Caccia eccessiva che svuota la zona.** I cervi calano, i lupi si spostano o patiscono la fame. Con un gruppo
  "garantito" la selvaggina non finisce mai, a meno di aggiungere a mano una regola di esaurimento.
- **Predatori che tolgono prede al villaggio** e branchi che cambiano territorio.
- **Pascolo che modella il paesaggio.** La brucatura frena il bosco: un prato pascolato resta prato.
- **Successione visibile:** il prato abbandonato si chiude in arbusteto e poi in bosco; le specie colonizzano le
  celle vicine.
- **Coerenza tra cella vista ora e cella vista fra dieci anni**, con eventi (incendi, siccità) che lasciano un segno
  che evolve.

### 2.3 Gioco: cosa si guadagnerebbe

- **Prevedibilità e controllo del designer.** Gli elementi chiave (lupi da addomesticare, selvaggina vicino al
  villaggio) ci sono di sicuro, senza estinzioni accidentali dovute alla taratura.
- **Meno taratura e meno bug di equilibrio.** Il codice ha molti commenti sui casi limite: contagio dei flag LOD, erba
  congelata da ripristinare, overshoot di `dedicated_space`, fame contro popolazione.
- **Salvataggi più piccoli e meno stato da tenere coerente.** Oggi `hunger_buckets`, territori e mitigazioni.
- **Codice più breve:** si possono togliere 3.000–4.500 righe di fauna e ~800 di flora.

---

## 3. Modelli alternativi concreti

Un principio vale per tutti i modelli: **cambiare chi scrive, non chi legge.** Più di 40 file leggono
`resource_quantity`/`dedicated_space` e una ventina leggono i gruppi di fauna. Se il nuovo modello produce gli stessi
campi in uscita, caccia, raccolta, renderer, pannelli e salvataggi restano quasi intatti.

### 3.1 Fauna — Modello F1: "riserva di selvaggina per cella" (consigliato fuori dall'anello)

**Stato per cella e specie:**
- `stock` (numero di capi, con composizione per fascia d'età);
- `capacity`: tetto fisso, ricavato una volta da bioma e vegetazione con una tabella in `AnimalRules`;
- `last_update_day`.

**Ricrescita.** Logistica *in forma chiusa*: al momento della lettura si applica in un colpo il tempo trascorso,
`N(t) = K / (1 + (K/N0 - 1)·e^(-r·t))`. Nessun tick giornaliero.

**Caccia.** Toglie dallo stock (`apply_predation_loss` invariata nella firma). La caccia eccessiva svuota davvero la
zona, che si ripopola con un tempo leggibile, ad esempio "i cervi tornano in ~3 anni".

**Predatori.** I lupi e gli altri predatori diventano gruppi coerenti come `AnimalVisitorGroup`. Se si vuole tenere la
concorrenza, la loro "caccia" toglie una quota fissa annua dallo stock delle prede nelle celle vicine, senza
simulazione giornaliera.

**Si toglierebbero:**
- `PredationService` e `PredatorPatrolService`;
- territori: `TerritoryDynamicsService`, `TerritoryBuilderService`, `PopulationTerritoryShuffleService`,
  `PopulationSplitService`;
- fame e consumo giornalieri e aggregati;
- mitigazione delle nascite;
- buona parte di `LODOrchestrator`.

**Si terrebbero:**
- `AnimalGroupRenderer`: gli individui nascono dallo stock della cella come oggi dalla quota;
- `HuntService` e `AnimalRules`, con le fasce d'età.

**File da toccare e ordine:**
1. Nuova classe `CellFaunaStock` (o campo su `MacroCellState`) e un `FaunaStockService` stateless che offre
   `get_population_by_cell`/`get_age_composition_in_cell`/`apply_predation_loss`, con la stessa forma usata da
   `GameScene`.
2. `World.get_population_groups_at`/`find_population_group` → adattatori sullo stock, oppure 4–5 punti di
   `GameScene` cambiati direttamente.
3. `AnimalSeedingService` → seme dello stock iniziale. Si riusano capacità e bioma.
4. `WorldTimeService`: si tolgono i passi giornalieri di fauna e il ciclo di vita stagionale. La ricrescita avviene
   alla lettura.
5. Vegetazione: il pascolo diventa una regola semplice, cioè una cella con stock di erbivori sopra una soglia ha
   l'encroachment bloccato o ridotto. È un effetto concreto, non un moltiplicatore. Si toglie
   `BrowsingMitigationService`.
6. Salvataggio e caricamento: chiave nuova; i vecchi `population_groups` convertiti al caricamento (somma per cella
   delle quote).
7. Pannelli (`WorldInfoPanel`, dettaglio cella), scelta della partenza, strumenti di `tools/`.
8. Rimozione dei servizi morti, solo alla fine, in un commit separato.

**Stima: 3–4 sessioni di lavoro**, più la taratura. Le parti a rischio sono la conversione dei salvataggi e la
riconciliazione individui/stock in `GameScene`, che però cambia solo la sorgente.

### 3.2 Fauna — Modello F2: "visitatori garantiti" esteso (solo per le specie di gioco)

È il modello del branco di lupi generalizzato: per ogni villaggio, pochi gruppi fissi con individui persistenti (età,
sesso, carattere) per le specie che servono a una meccanica, come addomesticazione, minaccia e prede speciali.

È **complementare a F1, non un sostituto**: va bene per pochi gruppi con identità. Come modello di tutta la
selvaggina toglierebbe l'esaurimento da caccia, che va invece tenuto.

Lavoro: incrementale, per specie, come già avviato in `AnimalVisitorService`.

### 3.3 Flora — Modello V1: "stadio di successione e anni dal disturbo" (il più "coerente")

**Stato per cella.** Al posto di crescita, encroachment e migrazione:
- uno **stadio** (prato → arbusteto → bosco giovane → bosco maturo);
- `anni_dal_disturbo`;
- un **climax** del bioma, il punto d'arrivo.

**Composizione.** Quantità, spazio e sottotipi di GRASS/SHRUB/TREE sono una *funzione pura* di
(bioma, stadio, anni nello stadio, interventi), letta da una tabella `.tres` per bioma. Gli stessi campi di oggi
vengono scritti solo quando la cella si attiva o al checkpoint.

**Interventi.** Tagli, cantieri, incendi e pascolo riportano indietro lo stadio o azzerano `anni_dal_disturbo`.
Sono meccaniche visibili: "questo bosco tagliato è un arbusteto, tornerà bosco tra ~15 anni".

**Si toglierebbero:** `ResourceGrowthService`, `ResourceEncroachmentService`, `ResourceMigrationService`,
`ResourceMortalityService`, `SpaceReconciliationService` e la logica dell'erba congelata (`_restore_frozen_grass…`,
baseline). In tutto ~800 righe più i passi in `WorldTimeService`.

**Si terrebbe tutto il lato individui:** layout, lotti, taglio a individuo, frutti.

**Limite.** Si perde la colonizzazione tra celle vicine. Si può reintrodurre in modo semplice: una cella aperta
accanto a un bosco avanza di stadio più in fretta, come regola concreta sullo stadio e non come flusso di quantità.

**File da toccare e ordine:**
1. Campi su `MacroCellState` (`succession_stage`, `years_since_disturbance`) e una tabella per bioma
   (`SuccessionRules` `.tres`).
2. `SuccessionService` con `materialize(cell_state)`, che scrive quantità, spazio e sottotipi, e `advance(years)`.
3. `InitialResourceSetupService`: stadio iniziale invece del seme di quantità. `ParametricResourceSetupService` da
   rivedere.
4. Gli interventi (`PlayerHarvestService`, `BuildingSiteClearingService`, eventi naturali) aggiornano lo stadio
   oltre a togliere individui.
5. `WorldTimeService`: un solo passo annuale, solo sulle celle rilevanti.
6. Salvataggio e caricamento: due campi nuovi, con lo stadio dedotto dalle quantità nei vecchi salvataggi.
7. Taratura delle tabelle contro l'equilibrio attuale (`tools/vegetation_equilibrium_test/`).

**Stima: 2–3 sessioni.** Nota: interagisce con le fasi 4–5 di B (checkpoint e attivazione). Va fatto dopo, non in
parallelo.

### 3.4 Flora — Modello V2: "aggiornamento pigro" del modello attuale (il minimo indispensabile)

Si tiene la matematica di oggi, ma una cella lontana dai villaggi non viene aggiornata finché qualcuno non la
guarda. In quel momento si applicano in un colpo N anni di crescita logistica in forma chiusa, più una mortalità
equivalente. Encroachment e migrazione girano solo nell'anello attorno ai villaggi.

È ciò che `vegetation_feeding_active` e l'erba congelata fanno già in parte, ma reso esplicito con `last_update_day`.

**Stima: 1–2 sessioni.** Pochi file:
- `WorldTimeService`;
- un `VegetationCatchUpService`;
- l'attivazione della cella in `GameScene`;
- il salvataggio di `last_update_day`.

---

## 4. Raccomandazione

1. **Non togliere la simulazione in blocco.** Il guadagno di CPU sarebbe circa il 20% del picco stagionale e
   trascurabile nel giorno normale. Si perderebbero le meccaniche più "concrete" del mondo: esaurimento da caccia,
   pascolo che tiene aperto il prato, successione.
2. **Ibrido per distanza, che in parte c'è già.** Il LOD della fauna è a tre livelli: pieno sulle celle vive,
   aggregato sulle scoperte, congelato sulle mai viste. Quello che manca è un **anello attorno ai villaggi** come
   criterio unico per fauna e flora:
   - **dentro l'anello** (celle vive + 1–2 macrocelle): simulazione piena come oggi, perché è dove il giocatore vede
     le conseguenze;
   - **fuori dall'anello:** fauna con F1 e flora con V2 (o V1), entrambi a ricalcolo pigro alla lettura;
   - **mai viste:** congelate come oggi.
3. **Lupi e specie di gioco con F2** (visitatori garantiti), come già avviato: identità, addomesticazione, minaccia.
4. **Prima misurare, poi decidere.** Accendere `SHOW_DAILY_TIMING_LOGS` e `SHOW_LOD_LOGS` per un anno di gioco su un
   salvataggio grande e annotare:
   - i ms al giorno di predazione, consumo e fame;
   - i ms dei checkpoint di crescita ed encroachment.

   Se la somma della fauna per giorno sta sotto ~2–3 ms, F1 si fa per semplicità di codice e di taratura, non per
   prestazioni.
5. **Priorità per le prestazioni vere:**
   - fasi 4–5 di B: `LotCapacityService` solo sui lotti toccati, ~500 ms al checkpoint;
   - indice delle celle rilevanti per le scorte secondarie, ~150 ms;
   - lato pipottini: lavori, percorsi.

   Rendono molto più del cambio di modello.

**Ordine proposto se si decide di procedere:**
1. Misura.
2. Fasi 4–5 di B.
3. V2 per la flora, il passo più piccolo, che chiarisce l'"anello".
4. F1 per la fauna fuori dall'anello.
5. Eventualmente V1, se si vuole la successione per stadi come meccanica visibile per il giocatore.
