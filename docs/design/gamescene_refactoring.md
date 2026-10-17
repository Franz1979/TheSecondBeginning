# Piano: estrarre la logica di gioco da GameScene.gd

> Questo è un documento di progetto. Approvarlo **non** significa partire con il codice: ogni blocco si
> implementa solo quando l'utente lo chiede esplicitamente.

## Contesto
`gameplay/scenes/game/GameScene.gd` ha circa 21.900 righe e 778 funzioni. Circa un terzo (6.000–7.500 righe)
è logica di gioco, cioè regole che decidono e modificano lo stato. È cresciuta soprattutto con le ultime
meccaniche: bacheca lavori, coordinatore, cassetto ordini, scorte, ciclo di vita degli edifici e costruzione
delle task.

Il 2D è di debug: la versione vendibile sarà in 3D e dovrà riusare tutta la logica senza ricopiarla dalla
scena. L'obiettivo è che GameScene si limiti a presentazione e collegamento, che la logica stia in servizi
divisi per meccanica e che lo stato stia in un modello dati.

Il piano è un refactoring puro: **nessuna regola di gioco cambia**.

---

## 1. Architettura definitiva (vale da subito per ogni nuova meccanica)

| Strato | Cosa contiene | Dove | Passa al 3D? |
|---|---|---|---|
| **Dati di tipo** | `*Rules.gd` più `.tres` | invariato | sì, al 100% |
| **Stato** | tutto ciò che descrive la partita: `GameData`, `World`, `Building`, `HumanIndividual`, `Folk` | `simulation/scripts/game/` | sì, al 100% |
| **Servizi** | regole senza stato: ricevono lo stato, lo modificano e restituiscono un risultato | una cartella per meccanica (vedi sotto) | sì, al 100% |
| **Effetti** | cosa la presentazione deve mostrare: notifica, suono, ridisegno di una cella, refresh di un pannello | oggetto `GameEffects` restituito dai servizi | sì; cambia solo chi li consuma |
| **Driver del tempo** | ordine dei tick (al secondo e al giorno) e chiamata dei servizi | `GameSimulation` (RefCounted, senza nodi) | sì, al 100% |
| **Presentazione** | scena, input, telecamera, pannelli, renderer | GameScene e gli altri nodi | **no**: in 3D si rifà |

### Regole fisse
1. **Nessuna logica di gioco** in GameScene, nei pannelli o nei renderer.
2. **Nessuno stato di gioco** in variabili della scena. Va in `GameData` (o nell'oggetto di stato della sua
   meccanica), con un commento che dice se viene salvato o no; i campi salvati si caricano con
   `.get(key, default)`.
3. **I servizi non toccano mai i nodi.**
   - Niente `live_cells`, renderer, popup o suoni.
   - Restituiscono un `GameEffects` (o lo ricevono come parametro e lo riempiono).
   - Si estende lo schema già usato da `RandomEventService` ("restituisce dati, la scena mostra").
   - Niente nuovi hook `static var Callable` né stato in `static var`: è lo schema di `CoordinatorService`,
     che nasconde stato non salvato.
4. **I testi** (`tr()` o `TranslationServer`) nei servizi sono ammessi come in `BuildingInfoLines`, perché
   restano validi anche in 3D.
5. **Clic destro** = comando a un individuo scelto dal giocatore. **Pulsante nel pannello** = ordine
   dell'edificio. In entrambi i casi la logica sta nel servizio; la UI risolve solo "cosa ho cliccato".
6. **Il disegno 2D** va nei renderer e negli overlay dedicati, mai in GameScene. Non serve renderlo
   scalabile, perché verrà buttato.

### Regola transitoria, finché il blocco 0 non esiste (decisa il 2026-10-13)
- Le nuove meccaniche nascono già nella struttura definitiva: servizio nella cartella della meccanica e stato
  in `GameData`.
- Il servizio restituisce un risultato (come `RandomEventService`) e la scena si limita a mostrarlo.
- Quando arriverà `GameEffects`, quei risultati si convertiranno in effetti con poco lavoro.
- Le piccole correzioni alla logica già presente in GameScene restano in GameScene fino all'estrazione del
  loro blocco.

### Cartelle (stesso schema di `gameplay/rites/`)
- **`gameplay/jobs/scripts/`**
  - `TaskBuilderService`: i builder puri.
  - `JobBoardService` e `CoordinatorService`: spostati qui con il loro `.uid`.
  - Un fornitore di lavori per tipo: edifici, riparazioni, corpi, mucchi, prodotti, ordini di produzione.
  - `DrawerOrderService`: ordini Produci e di zona, serie di caccia senza prede.
  - `ToolFetchService`: prestito e restituzione degli attrezzi.
- **`gameplay/buildings/scripts/`**
  - `BuildingLifecycleService`: demolizione (marcatura e annullo), crollo e macerie, miglioramento (avvio e
    annullo), completamento della costruzione.
  - `BuildingMaintenanceService`: edifici danneggiati, richieste di riparazione automatiche, sgombero
    automatico delle macerie.
- **`gameplay/stock/scripts/WarehouseManagerService`**: caccia, produzione, essiccazione e giorni di cibo
  automatici. Gli helper puri vanno in `StockRequestService` (già esistente).
- **Logica condivisa in un unico punto**
  - `AssignHouseService.release_building_residents` ed `evict_overflow` sostituiscono le 6 copie di
    "libera i residenti e riassegna".
  - Una sola funzione "chiudi le task sull'edificio" sostituisce le circa 7 copie.
- **`gameplay/scripts/core/GameSimulation.gd`** è il driver del tempo (nasce con il primo passo del tick estratto).
- **`gameplay/scripts/core/GameEffects.gd`** contiene gli effetti per la presentazione.

---

## 2. Blocchi

### Campanella (2026-10-16)
- Ha casa in `gameplay/pending/scripts/PendingEntryService.gd`: costruzione comune delle voci (`make_entry`), voce
  "nessuna idea in sviluppo", villaggi senza centro. Le altre raccolte `_collect_*_entries` di GameScene si spostano lì
  (o nel servizio della loro meccanica) con il blocco che tocca la meccanica: bacheca → 2, edifici → 3, scorte → 4.

### Blocco 0 — Fondamenta (piccolo)
Corretto il 2026-10-17: creare subito `GameSimulation` con l'ordine completo non regge, perché quasi tutti i
passi del tick sono ancora funzioni di GameScene e il driver dovrebbe richiamare la scena. Quindi:
1. Creare `GameEffects`: un elenco di effetti (notifica, ridisegno cella, refresh pannelli, refresh "In
   sospeso") più `_apply_effects(effects)` in GameScene, che li traduce in popup e refresh. Nessuno lo usa
   ancora: comportamento invariato.
2. Separare in GameScene logica e interfaccia: `_tick_simulation_second()` (oggi dentro
   `_refresh_pending_entries`) e `_tick_simulation_day()` (oggi dentro `_on_day_advanced`). L'ordine dei passi
   sta scritto in un punto solo.
3. `GameSimulation` nasce quando si estrae il primo passo del tick (manutenzione edifici o bacheca); da lì
   ogni blocco gli sposta dentro i suoi passi, finché la scena non chiama solo lui.

Ordine attuale dei tick:
  - **al secondo** (oggi `_refresh_pending_entries`):
    1. cut orders
    2. danneggiati
    3. chiusura delle richieste di riparazione
    4. riparazioni automatiche
    5. macerie automatiche
    6. restituzione attrezzi
    7. `CoordinatorService.tick`
    8. bacheca lavori
  - **al giorno** (oggi `_on_day_advanced`):
    1. crollo
    2. sfratti
    3. riconciliazione della produzione

### Blocco 1 — Costruzione delle task → `TaskBuilderService`
- Esistono già `TaskFactory.build_task`, i `TaskDefinition` e circa 90 `.tres`. Si spostano solo le
  funzioni `_build_*` di GameScene, che calcolano il contesto (offset della macrocella, punti, chiavi extra).
- Builder puri da spostare:
  - transport (2651), hunt zone (4340), cut (5925), quarry (5985), repair (6698), produce (7832);
  - rite (estratto da 7134–7143), bury (9195, verso `BodyBurialService`);
  - pile (10891, ricevendo `macro_state`), output (11175);
  - tool ed equip (14546/14554), inventory (18326), dry transport (19044).
- Builder con collegamento di segnali: pickup (3972), haul zone (5188), butcher (7918). Il builder diventa
  puro e il collegamento resta nella scena in un unico `_wire_task_signals(task, owner)`.
- Dote dei visitatori (8859): oggi è l'unica task costruita a mano; si sostituisce con un `.tres`
  "unload_resource".
- ~~Le circa 10 copie dello schema `_assign_*` diventano un solo helper `_assign_with_feedback`.~~ Rimandato
  al blocco 5 (2026-10-17): le copie differiscono troppo (dove va l'icona, comportamento "silenzioso" della
  bacheca, coda speciale di taglio/estrazione, pannelli aggiornati); sono la risoluzione dei comandi e vanno
  ripensate con i servizi di comando.

**Stato (2026-10-17):** fatto. `gameplay/jobs/scripts/TaskBuilderService.gd` contiene transport, hunt zone,
cut, quarry, repair, produce, output, tool/equip, inventory, pickup, haul zone, pile job, butcher, unload
resource (dote dei visitatori, nuovo `unload_resource.tres`) e rite; bury è in
`BodyBurialService.build_bury_task`. I segnali li collega la scena dopo la costruzione (`_wire_pickup_task`,
`_wire_butcher_task`, `_connect_haul_zone_step_appended`), solo per le task usate davvero. Resta in scena
`_transport_order_task` (ordini di trasporto del magazzino): dipende dalle regole delle scorte, va col blocco 4.

### Blocco 2 — Bacheca lavori, cassetto ordini, attrezzi → `gameplay/jobs/`
- **Nucleo** (9768–10227): `_takeable_jobs_for`, `_take_listed_job_for`, `_open_job_keys`,
  `_collect_job_board_candidates` e il calcolo dell'attesa passano in `JobBoardService`, ricevendo `now` e
  lo stato.
- **Fornitori per tipo** (10238–11410): un servizio per tipo, ognuno con `collect(context) -> Array[entry]`.
  Sostituiscono la tabella `_job_board_providers`.
- **Ordini del cassetto** (11415–12855) passano in `DrawerOrderService`. Restano nella scena solo i popup
  di scelta (`_on_drawer_*`).
- **Attrezzi** (11925–12198) passano in `ToolFetchService`.
- **Stato oggi nella scena** che passa in un oggetto di stato della bacheca dentro `GameData`, non salvato
  come oggi:
  - `_job_board_clock`, `_job_board_waiting_since`
  - `_coordinator_open_job_keys`, `_pile_job_memory`
  - `_pending_*`, `_in_progress_log_signatures`
- **Decisione da prendere:** se salvare `_drawer_hunt_no_prey_alerts` e `_unbutchered_carcass_alerts`, che
  oggi si perdono al caricamento, forse senza volerlo.
- **Lo stato statico di `CoordinatorService`** (`_actions`, `_log_info`) va spostato nello stesso oggetto di
  stato, e gli hook Callable diventano parametri.

### Blocco 3 — Ciclo di vita degli edifici → `gameplay/buildings/`
- **Manutenzione** (10434–10555): edifici danneggiati, chiusura delle richieste, riparazioni automatiche,
  macerie automatiche. Lo stato `_last_damaged_building_ids`, `_auto_repair_checked_*` e
  `_auto_clear_checked_day` passa nello stato di gioco. Il crollo che azzera `_auto_clear_checked_day`
  diventa una chiamata esplicita del servizio.
- **Ciclo di vita** (17214–18026, 20837–20906):
  - `_demolish_building` è il nucleo;
  - `_collapse_building`;
  - marcatura e annullo della demolizione;
  - avvio e annullo del miglioramento (la trasformazione oggi in scena, mentre `BuildingUpgradeService` resta
    dati e costi);
  - completamento della costruzione e della demolizione;
  - sfratti.
- **Nella scena restano:**
  - il dialogo di conferma;
  - i placeholder dei cantieri;
  - `_refresh_building_visuals` e il refresh dei vicini (terra battuta), pilotati dagli effetti.

### Blocco 4 — Gestore scorte → `gameplay/stock/`
- **Si sposta** (18206–19456): `_auto_request_stock` → hunt → produce → dry → food_days, nello stesso
  ordine, con i loro helper.
- **Variabili da spostare nello stato:** `_stock_hunt_pause_until` (scritta anche dal cassetto caccia, riga
  12460), `_stock_dry_warnings`, `_stock_inventory_*` e `_stock_fill_names`.
- **I collegamenti verso il cassetto** (creare e rimuovere ordini) chiamano direttamente
  `DrawerOrderService` del blocco 2, quindi il blocco 4 viene dopo il 2.
- **`_refresh_pending_entries`**, oggi richiamata da dentro la logica, diventa un effetto "refresh In
  sospeso".

### Blocco 5 — In coda, da decidere più avanti
- Il ciclo per fotogramma degli individui (`_process`, 1307), `human_individuals` e `human_folk` passano
  dentro `GameSimulation`.
- La risoluzione dei comandi da clic destro (`_try_assign_*`) passa in servizi di comando, insieme allo
  schema ripetuto delle `_assign_*` (rimandato dal blocco 1).

---

## 3. Stime

**Tempi**, in sessioni di lavoro mie più la tua prova in gioco per ogni passo:

| Blocco | Sessioni |
|---|---|
| 0 — Fondamenta | ~1 |
| 1 — Costruzione task | ~1–2 |
| 2 — Bacheca, cassetto, attrezzi (il più grande) | ~3–4 |
| 3 — Ciclo di vita edifici | ~2 |
| 4 — Gestore scorte | ~1–2 |
| **Totale blocchi 0–4** | **~8–11** |
| 5 — Ciclo individui e comandi | ~3–4 in più |

**GameScene dopo i blocchi 0–4:** da circa 21.900 a circa 13.000–15.000 righe. Si tolgono la logica e le
copie duplicate; restano UI, input e celle vive. Con il blocco 5 e la divisione dei pannelli in
sotto-componenti si può scendere molto di più.

**Riuso nel 3D:**
- oggi circa un terzo della logica andrebbe riscritta o ricopiata a mano dalla scena;
- dopo i blocchi 0–4, la logica di bacheca, ordini, scorte, edifici e task si riusa al 100%: la scena 3D
  chiama `GameSimulation` e consuma `GameEffects`;
- dopo il blocco 5 si riusa praticamente tutta la simulazione umana.

---

## 4. Verifica (per ogni blocco)
- Un solo controllo di compilazione headless con
  `C:\Users\crfra\GodotProjects\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path .`.
- L'utente prova in gioco gli scenari del blocco:
  - blocco 2: assegnazione e coordinatore;
  - blocco 3: crollo, macerie, demolizione e miglioramento;
  - blocco 4: inventario e ordini automatici.
- Salvataggio e caricamento devono restare compatibili: nessuna chiave cambia; eventuali chiavi nuove usano
  `.get` con default.
- Opzionale, dal blocco 2 in poi: un test headless in `tools/`, nello stile di `ZombieTaskTest`, che fa girare
  `GameSimulation` senza scena. È anche la prova che la logica è davvero indipendente dal 2D.
- Il commit lo fa l'utente.
