# Assegnatore unico dei lavori: il coordinatore decide al punto

Stato: approvato (2026-10-24), logica e scelte decise dall'utente lo stesso giorno, nessun codice toccato. Da applicare su un ramo suo, una fase alla volta, con un commit (dell'utente) tra una fase e l'altra.

## 1. Perché

Oggi **ogni pipottino che si libera si chiede da solo** "c'è un lavoro che posso prendere io?", **prima** di andare al punto di assegnazione. Per rispondere ricostruisce e filtra tutta la lista dei lavori. Misure col profilatore di Godot:

| Dove | Tempo |
|---|---|
| `HumanIndividualActionService.finish_current_step` (un solo pipottino che finisce un'azione) | ~72 ms |
| di cui `JobBoardService.try_seek_job` | ~56 ms |
| di cui `GameScene._has_listed_job_for` (`job_available_checker`) | ~55 ms |
| `IdleTaskAssignmentService.assign_idle_fallback` | ~12 ms a pipottino |
| fine di un rito, tutti i partecipanti liberi insieme | picco ~220 ms |

Con centinaia o migliaia di pipottini non regge: il costo cresce come **pipottini liberi × (lavori + pipottini)**.

L'idea concordata è che il pipottino **vada a vedere di persona** e che **decida il coordinatore**, al punto, una persona alla volta. Il viaggio a vuoto è accettato.

## 2. Dove va il tempo oggi

Il piano "bersaglio scelto dall'ordine" per taglio ed estrazione (`DrawerOrderTargetService`) è già nel codice: toglie il giro su tutte le zone per quei due tipi, ma non il resto. Quella che segue è una lettura del codice; la ripartizione esatta in ms va confermata con la fase 0.

### 2.1 Catena delle chiamate

```
resolve_idle_individual
└─ JobBoardService.try_seek_job
   ├─ find_assignment_point             (SpatialSelectionService.find_nearest su world.buildings)
   └─ job_available_checker = GameScene._has_listed_job_for     ← la domanda da ~55 ms, PRIMA di partire
      ├─ JobBoardService.cached_availability   (vale 1,5 s e finché nessuno prende un lavoro)
      └─ _compute_listed_job_for → _takeable_jobs_for(worker, false)
         ├─ JobBoardService.is_enabled → has_assignment_point   (giro su tutti gli edifici)
         ├─ _current_job_board_candidates()                      ← A
         ├─ JobBoardService.find_takeable_jobs(...)              ← B
         └─ _sync_job_board_wait_icons(candidates)               ← C
```

Se la risposta è no, il pipottino non parte e va subito allo svago (`assign_idle_fallback`).

### 2.2 A — la lista intera, rifatta quasi sempre

`_current_job_board_candidates()` tiene la lista in memoria **solo per il fotogramma in corso** (`frame == _job_board_candidates_frame`). Un pipottino che si libera da solo, in un fotogramma qualunque, la trova sempre scaduta e la rifà da capo:

- `JobWorkScanService.collect_assignments(human_individuals)`: tutte le task in corso e in coda di tutti. Gira **anche quando la lista è in memoria**, perché serve a calcolare la firma.
- Firma: su `main` anche un giro su tutti i pipottini (task e coda). Su `vegetazione-b` è già ridotta a `take_revision`, ma resta legata al fotogramma.
- `_collect_job_board_jobs` → `collect` di **tutti i 10 fornitori**:
  - `DrawerOrderJobProvider.collect`:
    - `DrawerOrderService.collect_zone_claims(individuals)`;
    - per ogni ordine "Produci": `choose_produce_building` e, se non c'è posto, `ProductionEvictionService.find_evictable`, che gira su tutti i pipottini;
    - per ogni ordine di zona: `zone_blocked_reason`. Per raccolta e caccia fa ancora `zone_areas` + `zone_reserved(individuals)` + `area_has_targets` su **tutte le zone**; per taglio ed estrazione, `ensure_target`.
  - `PileJobProvider`: `collect_claims` / `_emptied_pile_jobs`, cioè tutti i pipottini × task × passi.
  - `OutputJobProvider`: per ogni edificio, giro su tutte le ricette (`_rack_full_with_products`).
  - `SiteCutJobProvider`: una voce per **ogni microcella con piante** di ogni cantiere nel bosco.
  - `BuildingJobProvider`, `RepairJobProvider`, `RiteJobProvider`, `ProduceJobProvider`, `BodyJobProvider`, `InventoryJobProvider`: giri su edifici, ordini e corpi.

La lista intera si rifà comunque già **una volta al secondo** in `_refresh_pending_entries` (cassetto, attese, `notify_new_open_jobs`), che tiene da parte i **lavori aperti** in `job_board_runtime.open_job_keys`. Quel lavoro oggi non viene riusato da `_has_listed_job_for`.

### 2.3 B — l'idoneità, rifatta per ogni pipottino

`JobBoardService.find_takeable_jobs`, per **ogni** pipottino:

1. `sync_waits` e `stamp_entered`. Quest'ultimo gira ogni volta su tutti i valori di `job_board_entered_at`.
2. Per ogni `probe_key` diverso chiama la `rejection` del fornitore. Qui ci sono le operazioni pesanti:
   - **Task di prova**: `TaskFactory.build_task` (`BuildingJobProvider`, `RiteJobProvider`), `TaskBuilderService.build_produce_task` (Produci), `build_cut_task` / `build_quarry_task` / `build_haul_zone_task` / `build_hunt_zone_task` (ordini di zona). Ogni volta si crea una Task con i suoi passi solo per chiamare `get_assign_rejection_reason`;
   - **`ToolFetchService.rejection`** (ordini di zona, Produci): se al pipottino manca l'attrezzo, `has_available_equipped_member` gira su **tutti i pipottini × le loro task** (`_holds_zone_order_of_type`), poi c'è `missing_tools_in_storage`;
   - **raccolta e caccia**: `pick_zone_target` → `HaulZoneService.choose_work_area` / `HuntZoneService.choose_work_area` **per pipottino**;
   - **mucchi e Prodotti finiti**: `WarehouseSelectionService.find_best` per ogni risorsa.
3. Raggiungibilità (economica) e `MaterialSupplyService.get_uncarryable_materials` per ogni cantiere o riparazione.

### 2.4 C e il resto

- `_sync_job_board_wait_icons` a ogni domanda, su tutti i candidati.
- `is_enabled` → `has_assignment_point`, giro su tutti gli edifici, più volte per decisione.

### 2.5 La stessa domanda, fatta tante volte

Ogni lavoro preso costa **almeno due** calcoli completi:
- `try_seek_job` alla partenza;
- `try_take_job` all'arrivo al punto: la lista in memoria è ormai scaduta.

Il coordinatore (`CoordinatorService`) rifà la stessa domanda per altre persone:
- `_is_only_worker`: **per ogni individuo** del gruppo;
- `_call_idle_individuals`: per ogni candidato al richiamo;
- attesa scaduta e autoassegnazione.

A fine rito si liberano in tanti nello stesso fotogramma, e la prima presa (`take_revision += 1`) annulla le risposte in memoria di tutti. Da qui il picco di ~220 ms.

## 3. La logica concordata

### 3.1 Il pipottino libero: va a vedere, senza chiedersi se il lavoro è per lui

In `resolve_idle_individual`, al posto di `try_seek_job` con `job_available_checker`, con un punto di assegnazione raggiungibile:

1. **Si va al punto solo se c'è almeno un lavoro aperto** nell'ultimo calcolo, cioè `job_board_runtime.open_job_keys` del giro al secondo (`notify_new_open_jobs`). Aperti vuol dire: senza nessuno, non bloccati, fuori dall'attesa per l'assegnazione a mano. Non si controlla se il lavoro è adatto a lui: lo saprà al punto.
2. **E solo se i lavori aperti sono più di quanti stanno già camminando verso un punto** con "Cerca lavoro": la stessa regola del richiamo ("lavori aperti − chi è in cammino"). Con 1 lavoro e 10 liberi ne parte uno solo; gli altri vanno allo svago, e se quello non era adatto il coordinatore richiama qualcun altro.
3. Altrimenti svago, come oggi.

I due controlli costano un conteggio: un dizionario già pronto e un numero. Il numero di chi è in cammino si conta nel giro al secondo e si aggiorna a ogni `start_seek_job` e a ogni arrivo o interruzione, senza un giro su tutti i pipottini a ogni domanda. Dalla fine di un'azione sparisce così tutta la parte della lista.

Se al punto non c'è niente per lui: viaggio a vuoto e svago, accettato.

### 3.2 Il coordinatore: l'assegnatore, al punto

Il ruolo resta quello di oggi ed è il **solo** a decidere chi fa cosa:

- **chi arriva** si mette in fila. Senza coordinatore, il primo della fila diventa coordinatore;
- **gente in fila**: il coordinatore istruisce una persona alla volta. A fine istruzione sceglie il lavoro per quella persona: è il solo calcolo per persona rimasto, `try_take_job` come oggi. Se non c'è niente per lei: viaggio a vuoto e svago;
- **gente in cammino**: il coordinatore la aspetta (limite di attesa `SELF_ASSIGN_WAIT_DAYS`, come oggi);
- **nessuno in fila né in cammino**:
  - lavori aperti ma nessuno nel raggio: il coordinatore **si prende lui il primo lavoro** (autoassegnazione);
  - lavori aperti e persone in svago nel raggio: **richiama** chi è in svago, fino a "lavori aperti − chi è in cammino − 1". Senza verificare persona per persona: chi viene richiamato e non è adatto fa il viaggio a vuoto;
  - coda vuota: fine del turno.

Domande per persona che spariscono dal coordinatore:
- **`_is_only_worker`**, che chiedeva a ogni individuo del gruppo: si toglie (scelta 1 in §6);
- **il richiamo** non chiama più `job_available_checker` per ogni candidato;
- resta una sola domanda vera per **sé stesso**, all'autoassegnazione (attesa scaduta o nessuno in arrivo): una persona, una volta.

### 3.3 Perché resta a costo limitato

- **Alla fine di un'azione**: due letture, nessun calcolo, qualunque sia il numero di pipottini.
- **Al punto**: un'istruzione dura un'ora di gioco (`ASSIGNMENT_DURATION_DAYS`), quindi il coordinatore fa **al massimo una scelta di lavoro per istruzione e per punto**. Il ritmo lo dà il gioco, non un tetto artificiale.
- **A fine rito**: i partecipanti partono (al massimo quanti sono i lavori aperti) e fanno fila. Nessuno calcola alla partenza, quindi niente picco.
- **La singola scelta** (`try_take_job`, oggi ~55 ms) si rende economica con le fasi 2 e 3: lista unica e requisiti dei lavori calcolati una volta. Così regge anche con tanti lavori e tanti punti.

Con migliaia di pipottini il collo di bottiglia diventa il **ritmo** dei coordinatori (un'ora di gioco per persona per punto), non il processore. È una scelta di gioco: più punti di assegnazione, o in futuro istruzioni più brevi con la Leadership.

## 4. Cosa cambia nel gioco

### 4.1 Cambia

- **Viaggi a vuoto**: chi va al punto può scoprire lì che nessun lavoro aperto fa per lui (età, attrezzi, raggiungibilità, materiali troppo pesanti) e tornare allo svago. Oggi non parte nemmeno.
- **Meno gente in cammino insieme**: partono al massimo quanti sono i lavori aperti, meno chi è già in cammino. Oggi parte chiunque abbia un lavoro adatto, anche in dieci per un solo lavoro.
- **Il richiamo** chiama chi è in svago nel raggio senza sapere se è adatto: più viaggi a vuoto, ma è il coordinatore a decidere, come vuole la logica.
- **`_is_only_worker`**: il coordinatore non si autoassegna più "subito perché unico adatto". Prima richiama o aspetta chi arriva, poi si autoassegna come oggi se nessuno è in fila né in cammino, o allo scadere dell'attesa.
- **Log [COORDINATORE] / [JOB BOARD]**: righe nuove per il viaggio a vuoto ("arriva, niente per lui") e per la partenza ("va a vedere: N lavori aperti, M in cammino").

### 4.2 Resta uguale

- Modi di priorità, ordine "Personalizzata", età dei lavori.
- Attesa per l'assegnazione a mano, bloccati e sbloccati, "Rimetti in coda", H con `skip_job_board_once`.
- Le regole di idoneità e la presa: `find_takeable_jobs` / `take_job` / `assign` del fornitore, chiamate dal coordinatore a fine istruzione.
- Fila, istruzione, limite di attesa, raggio del richiamo, Leadership.
- Senza punto di assegnazione nessuno prende lavori dalla coda (`is_enabled`).
- Bisogni, coda personale, travois, attrezzi in prestito e vestiario vengono prima, come oggi.
- Lo svago con la coda vuota: identico.

## 5. Fasi (ognuna provabile, commit dell'utente tra una e l'altra)

Scenario di misura fisso per tutte le fasi:
- **lo stesso salvataggio**, con almeno: un punto di assegnazione, ordini del cassetto di tutti i tipi (taglio, estrazione, raccolta, caccia, Produci), un cantiere, mucchi a terra, e un rito con 15–20 partecipanti;
- la stessa velocità;
- le stesse tre prove:
  1. **un pipottino che finisce un'azione** (profilatore: `finish_current_step`);
  2. **fine del rito** (picco del fotogramma);
  3. **un minuto di gioco normale** (quante volte al secondo partono i calcoli pesanti, quanti viaggi a vuoto).

Tempi con `Time.get_ticks_usec()` sotto un filtro nuovo `DebugLogging.SHOW_JOB_BOARD_TIMING_LOGS` (spento di norma), righe `[JOB BOARD TIMING]`, come `[VEG REFRESH TIMING]`.

| Fase | Cosa | Come si misura | Fatto quando |
|---|---|---|---|
| **0. Misura** | Solo righe di tempo, nessun cambio di comportamento. Si misurano separatamente: `collect_assignments`, ogni `collect` di fornitore per nome, `sync_waits`/`stamp_entered`, ogni `rejection` per tipo, raggiungibilità/materiali, icone. Contatore delle chiamate a `_has_listed_job_for`, per chiamante (partenza, arrivo, coordinatore) e per secondo. | Le tre prove: ripartizione dei ~55 ms per voce. | Sappiamo quali voci di §2 pesano davvero. |
| **1. Il pipottino va a vedere** | §3.1: partenza decisa da lavori aperti > chi è in cammino, senza `job_available_checker`. Contatore di chi è in cammino. Coordinatore senza `_is_only_worker` e richiamo senza domanda per persona (§3.2). | Prova 1: `finish_current_step` senza la parte della lista (obiettivo < 5 ms). Prova 2: picco di fine rito. Prova 3: viaggi a vuoto al minuto. | Nessun calcolo della lista alla fine di un'azione; fine rito senza picco da lista. |
| **2. Lista unica** | La lista dei fornitori la fa il giro al secondo, o un evento (presa, ordine nuovo o tolto, edificio cambiato). `_current_job_board_candidates` la riusa senza legarsi al fotogramma. `collect_assignments` una volta sola. | Prova di una presa a fine istruzione: la voce A deve sparire. Prova 3: `collect` ≤ 1/s + eventi. | A < 1 ms per presa. |
| **3. Requisiti dei lavori** | `profile(job)` nei fornitori: età minima, attrezzi, skill, `reach_target`, materiali, calcolati una volta per lista. `find_takeable_jobs` scarta prima con questi e fa la `rejection` vera solo per il lavoro scelto (e i successivi se rifiuta). | Costo di una presa (B). In debug, per qualche giro, confronto tra l'esito vecchio (tutte le `rejection`) e il nuovo; ogni differenza nel log. | Presa di pochi ms; nessuna differenza nel confronto. |
| **4. Scala** (solo se serve) | Salvataggio di prova con 200, 500 e 1000 pipottini (generato in debug). Se il giro al secondo supera il budget: fornitori incrementali (si segna solo ciò che è cambiato), poi eventuale C++ (GDExtension) sul nucleo, come da piano per la scala. | Tempo del giro al secondo e di una presa contro il numero di pipottini e di lavori: deve crescere circa in linea, non al quadrato. | Giro < 16 ms a 1000 pipottini, o una decisione presa con l'utente. |

La fase 1 da sola toglie il costo dalla fine di ogni azione e il picco di fine rito; le fasi 2 e 3 rendono economica la presa del coordinatore.

`assign_idle_fallback` (~12 ms) non fa parte di questo progetto, ma a fine rito si somma. Si misura nella fase 0; se pesa, si propone a parte.

## 6. Scelte (decise dall'utente il 2026-10-24)

1. **`_is_only_worker`**: si toglie del tutto. Il coordinatore richiama o aspetta, poi si autoassegna come oggi.
2. **Viaggi a vuoto ripetuti** (un pipottino non adatto a nessun lavoro aperto torna al punto a ogni nuova liberazione): per ora non si tocca. Si guarda nella prova 3 della fase 1.
3. **Chi è in cammino**: un solo conteggio per tutto il villaggio, il più economico (i lavori aperti sono già di tutti).

## 7. Rischi principali

- **Conteggio di chi è in cammino sbagliato**: se non scende all'arrivo o all'interruzione ("Cerca lavoro" interrotta da un bisogno, da H, da un caricamento), nessuno parte più. Si ricalcola da capo nel giro al secondo, così un errore dura al massimo un secondo.
- **Richiamo che chiama persone non adatte**: più viaggi a vuoto con un villaggio molto vario (bambini, persone senza attrezzi). Da guardare nella prova 3; se pesa, il richiamo può escludere almeno gli esclusi per età, che è un controllo economico.
- **Ritmo del coordinatore**: con tanti lavori aperti e un solo punto, la fila si allunga (un'ora di gioco a persona). È già così oggi; diventa più visibile perché la gente va al punto più spesso.
- **Filtri della fase 3 più severi della verifica vera**: un lavoro che oggi si prende non verrebbe mai scelto. Si previene col confronto in debug, prima di togliere il vecchio calcolo.
