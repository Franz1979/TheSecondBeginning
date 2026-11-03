# Vegetazione "ad hoc" a richiesta: togliere il motore annuale e generare solo ciò che serve

> Proposta del 2026-11-03, non ancora iniziata: lavoro previsto per sabato 2026-11-07, in una sessione nuova.
> **Da ricontrollare prima di partire:** un'altra sessione sta togliendo dal gioco il vecchio sistema della fauna. `grow_fauna`, `_run_growth_checkpoint` e i numeri di riga o di occorrenze qui citati possono essere cambiati.

## Contesto
L'utente vuole semplificare la vegetazione come la fauna, per togliere gli scatti al cambio cella: il giocatore non percepisce il realismo. Se i dati non devono più tornare con i numeri aggregati, propone di generare solo le piante che il pipottino vede, ricordarle e dimenticarle dopo molti anni.

Conclusione dell'analisi:
- **Motore annuale: via.** Con la fauna ad hoc è caduto il legame con gli animali, e nelle celle già viste il suo effetto si vede poco.
- **Generazione a richiesta: sì, è il vantaggio vero.** Oggi `ResourcePositionService` deve scegliere un numero **esatto** di lotti (`dedicated_space`) e per farlo guarda tutta la cella; `_distribute_individuals` fa lo stesso con `resource_quantity`. Senza numeri esatti, ogni lotto si decide da solo.
- **Spazio continuo: no, non ora.** 148 file su 597 usano coordinate macro e i blocchi caricati resterebbero comunque. Da decidere col 3D.

## Il modello: la pianta è una funzione, non un dato
- `vegetation_at(macro_state, lot)` risponde solo con seme, bioma e posizione: c'è bosco? quanti posti? che sottotipo? La stessa domanda dà sempre la stessa risposta.
- **Niente registro delle piante viste e niente pulizia dopo tot anni:** una pianta che riappare è uguale perché si ricalcola. Si salva solo ciò che il giocatore ha cambiato (`vegetation_cut_exceptions`, edifici), che già esiste e in parte già scade.
- **Età e ricambio a data:** `(anno + hash) mod durata di vita`. Nessun recupero da fare al ritorno sulla cella.
- Il disegno è già limitato al visibile (`_filter_vegetation_positions_by_visibility`): si riusa `get_visible_changes_since` per sapere quali microcelle sono entrate in vista.

## Atteso (stima da misurare)
- Prima visita: da circa 240 ms verso 70-100 (come il ritorno, 66 ms). Calano disposizione (125) e capacità dei lotti (44); restano acqua (26) e il resto dell'attivazione.
- Vicino attivato a 15 microcelle dal bordo: quasi niente da generare, perché nessuna sua pianta è ancora visibile.
- Scatti stagionali: spariscono per la parte vegetazione. Restano le scorte (167 ms, giorno 273).
- Memoria e salvataggi: niente più anno di nascita e sottotipo per ogni pianta (fino a ~62.000 in una cella fitta).

## Metodo (come la fauna)
- Interruttore `SimulationSettings.VEGETATION_AD_HOC`; servizi vecchi intatti e spenti, cancellazione solo a modello confermato.
- Prima il commit, il tag e il ramo fatti dall'utente. Niente commit da parte mia.
- Un passo alla volta, con prova dell'utente dopo ognuno. Lavoro in una sessione nuova, con questo piano come partenza.

## Passi

### 1. Ridisegno solo se la vegetazione è cambiata (piccolo, vale in ogni caso)
- `vegetation_checkpoint_count` in `WorldTimeService._run_seasonal_checkpoints` sale solo dove la vegetazione cambia davvero; `GameScene._on_day_advanced` segna il rebuild solo in quei giorni.
- Da verificare: reset dei lotti e capacità si aggiornano anche senza rebuild.
- Atteso: giorno 272 da 374 ms a circa 30; giorno 273 da 546 a circa 200.
- **Fermarsi qui e decidere se proseguire.**

### 2. Prova della funzione, senza toccare il gioco
Nuovo servizio con `vegetation_at`, più una misura temporanea: tempo per lotto e per 100x100 lotti, confronto a occhio con l'aspetto di oggi (macchie, densità per bioma). **Se qui il costo o l'aspetto non reggono, ci si ferma con poco lavoro perso.**

### 3. Interruttore: motore spento
Non girano `ResourceGrowthService`, `ResourceEncroachmentService`, `ResourceMigrationService`, `ResourceMortalityService`, `ResourceAgeBandService`, `NaturalEventService`. Restano in `_run_growth_checkpoint`: `grow_fauna` e il reset dei lotti.

### 4. Disegno a richiesta
`GameScene._refresh_resource_visuals` chiede solo i lotti visibili, aggiungendo quelli entrati in vista. Età e sottotipo per il renderer arrivano dalla funzione. Taglio, ceppi e ricrescita: i ceppi scaduti tornano nello stesso posto.

### 5. Gli altri lettori dell'elenco completo
222 occorrenze in 27 file, a parte salvataggi e renderer. Passano a domande per lotto o per area:
- `CutZoneService`, `VegetationSelectorController`, `ClearAction`, `BuildingSiteClearingService`, `PlantCutService`, `PlayerHarvestService`
- `VegetationPoolService`, `VegetationLotIndex`, `MovementTerrainService._forest_cells`, `GameSimulation.relocate_start_group`
- Nebbia: `set_vegetation_presence` (vegetazione sfocata)

### 6. Erba, bastoni, uova, verdure selvatiche
`compute_egg_nest_positions`, `refresh_grass_patch_lot_capacity` e `tree_claimed_lots` come fonte dei bastoni diventano domande per lotto. Le scorte già consumate restano salvate. Erba e lotti ripuliti tornano a data.

### 7. Frutti e numeri coerenti
- `CaloricCalculator` e scorte secondarie: stima dal bioma e dalla densità, più il taglio reale. Le cifre non devono più coincidere con le piante contate.
- Il taglio di alberi da frutto deve ridurre le scorte: oggi non lo fa.

### 8. Pannelli, strumenti, salvataggi
Adattare `WorldInfoPanel`, `MacroCellDetailPanel`, `worldRenderer`. Salvataggi vecchi: da decidere con l'utente se convertirli o ripartire. `VegetationEquilibriumTest` diventa inutile.

### 9. Cancellazione (più avanti, su decisione dell'utente)
Motori, generatore vecchio, registri delle piante. **Restano** `tree_growth.tres` e `shrub_growth.tres` (registro dei sottotipi).

## Stima
- Passo 1: una sessione al massimo.
- Passo 2: una sessione.
- Passi 3-8: 5-7 sessioni più la taratura. Stima a occhio; il rischio maggiore è nei passi 5 e 7.

## Cosa si perde
Bosco che si allarga col tempo, colonizzazione tra celle, incendi e siccità come numeri, conteggi esatti delle piante nei pannelli. Un incendio visibile si potrà rifare come meccanica vera.

## Verifica
- Compilazione: GameScene headless, un solo controllo.
- Passo 1: `SHOW_DAILY_TIMING_LOGS` acceso, giorni 272 e 273 confrontati con 374 e 546 ms.
- Passo 4: stessi log del cambio cella, prima visita confrontata con 237 ms e ritorno con 66 ms; camminando nella nebbia non devono comparire scatti nuovi.
- Passi 4-6: uscire, rientrare, salvare e ricaricare: piante identiche, ceppi al loro posto, tagli conservati. Avanzare molti anni: ceppi che ricrescono, erba che torna, bosco che non invecchia tutto insieme.
- Passo 7: tagliare alberi da frutto e controllare il calo delle scorte; col solo passare degli anni non devono calare.
