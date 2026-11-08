# Vegetazione a richiesta: togliere il motore annuale e calcolare le piante per lotto

> Proposta del 2026-11-03, aggiornata il 2026-11-08 con le decisioni dell'utente. Passo 1 fatto il 2026-11-08 (manca una prova, vedi sotto); dal passo 2 in poi non ancora iniziato.
> **Da ricontrollare prima di partire:** il codice cambia in fretta. Il vecchio sistema della fauna è stato tolto il 2026-11-03: verificare `grow_fauna` e `_run_growth_checkpoint`. I numeri di riga e di occorrenze possono essere cambiati.

## Contesto
L'utente vuole semplificare la vegetazione come la fauna, per togliere gli scatti al cambio cella: il giocatore non percepisce i calcoli. Se i dati non devono più tornare con i numeri aggregati, si può calcolare solo ciò che il pipottino vede.

Conclusione dell'analisi:
- **Motore annuale: via.** Con la fauna ad hoc è caduto il legame con gli animali.
- **Calcolo a richiesta: sì, è il vantaggio vero.** Oggi `ResourcePositionService` deve scegliere un numero **esatto** di lotti (`dedicated_space`) e per farlo guarda tutta la cella; `_distribute_individuals` fa lo stesso con `resource_quantity`. Senza numeri esatti, ogni lotto si decide da solo.
- **Spazio continuo: no, non ora.** 148 file su 597 usano coordinate macro e i blocchi caricati resterebbero comunque. Da decidere col 3D.

## Decisioni dell'utente (2026-11-08)
1. **Il bosco continua a cambiare:** a vederlo come ora, non con gli stessi calcoli. Un prato può diventare arbusteto e poi bosco, e tornare indietro.
2. **Incendi, siccità e mareggiate spariscono del tutto.** Nuove catastrofi si penseranno dopo, come meccaniche vere.
3. **Ricrescita sicura dopo il taglio:** stesso ceppo, stesso posto, attesa di 8 anni per gli alberi e 2 per gli arbusti. Le stesse attese valgono dopo una demolizione, dal momento della demolizione.
4. **Pannelli:** contano quelli di `GameScene`. L'ispezione della microcella resta uguale. `MacroCellScene` e `WorldScene` possono mostrare stime.
5. **Frutta dalle piante del lotto,** non da una scorta per cella (proposta dell'utente).
6. **I vecchi salvataggi si perdono:** niente conversione.

**Da tarare:** velocità del cambiamento del bosco; si parte da cambi visibili in qualche decennio.

## Il modello: la pianta è una funzione, non un dato
Una funzione del tipo `vegetation_at(macro_state, lot, anno)` risponde usando solo seme, bioma, posizione e anno. La stessa domanda dà sempre la stessa risposta.

- **Maturità del lotto:** un valore che varia lentamente con gli anni (rumore su x, y e tempo). Basso = prato, medio = arbusti, alto = alberi, con una fascia in cui alberi e arbusti convivono come oggi. Salendo passa prima dagli arbusti, quindi il prato non salta a bosco, e ai margini dei boschi resta una fascia di arbusti.
- **Ciclo di ogni pianta:** ogni posto ha un ciclo di vita dato dal suo hash. Alla fine del ciclo la pianta muore, con il segno di pianta morta, e al ciclo dopo rinasce solo se la maturità del lotto in quell'anno lo consente. Età e sottotipo derivano dal ciclo.
- **Aggiornamento in primavera,** come oggi, e solo sui lotti in vista: nessun giro sul mondo.
- **Niente registro delle piante viste e niente pulizia dopo tot anni:** una pianta che riappare è uguale perché si ricalcola.
- **Si salva solo ciò che il giocatore ha cambiato:** tagli e ceppi (`vegetation_cut_exceptions`), demolizioni, edifici, raccolto per lotto, rametti in più di un albero tagliato. Una pianta ricresciuta dopo un taglio ha bisogno di una piccola voce con il suo anno di nascita, finché il suo ciclo non torna quello normale.
- Il disegno è già limitato al visibile (`_filter_vegetation_positions_by_visibility`): si riusa `get_visible_changes_since` per sapere quali microcelle sono entrate in vista.

## Risorse delle piante: una sola formula per lotto
| Risorsa | Formula |
|---|---|
| Rametti, funghi | alberi adulti del lotto × `units_per_mature_plant` − raccolto (`VegetationPoolService._compute_capacity_for_lot`, già così, oggi per tutta la cella) |
| Fibra vegetale | arbusti adulti del lotto, stessa formula |
| Bacche, ghiande, frutta | piante del sottotipo nel lotto × resa per età × stagione − raccolto. **Oggi è diversa:** scorta di cella divisa per peso (`TerrainScatteredResourceService`) |
| Verdure, erbe medicinali, uova | lotti d'erba: l'hash decide se il lotto ne ha e quanta (`refresh_grass_patch_lot_capacity`, già così). Serve solo sapere se lì c'è erba |
| Sassi, argilla | invariati, non dipendono dalla vegetazione |

- Tagliare un albero da frutto toglie la sua frutta senza codice in più.
- Sparisce il giro stagionale sulle scorte di frutta (`_run_secondary_resource_stock_checkpoint`, 162-167 ms al giorno 273).
- Se un prato diventa arbusteto, verdure e uova di quel lotto spariscono e tornano se ridiventa prato. Da confermare con l'utente in prova.
- Da tarare: resa per pianta, per restare vicino alle quantità di oggi.

## Atteso (stima da misurare)
- Prima visita: da circa 240 ms verso 70-100 (come il ritorno, 66 ms). Calano disposizione (125) e capacità dei lotti (44); restano acqua (26) e il resto dell'attivazione.
- Vicino attivato a 15 microcelle dal bordo: quasi niente da calcolare, perché nessuna sua pianta è ancora visibile.
- Scatti stagionali: spariscono per la parte vegetazione e frutta.
- Memoria e salvataggi: niente più anno di nascita e sottotipo per ogni pianta (fino a ~62.000 in una cella fitta).

## Metodo (come la fauna)
- Interruttore `SimulationSettings.VEGETATION_AD_HOC`, spento finché il lavoro non è finito: spento, il gioco funziona come oggi.
- Servizi vecchi intatti e spenti; cancellazione solo a modello confermato.
- Prima commit e tag fatti dall'utente. Niente commit da parte di Claude.
- Un passo alla volta, con prova dell'utente dopo ognuno.
- **Con un'altra sessione aperta nella stessa cartella:** non cambiare ramo, committare indicando i file, misurare a sessione ferma. Il passo 4 tocca `microCellRenderer.gd`, dove si disegnano anche gli edifici: farlo a edifici finiti.

## Passi

### 1. Ridisegno solo se la vegetazione è cambiata (fatto il 2026-11-08)
- `vegetation_checkpoint_count` sale solo per migrazione, crescita, mortalità e quando scatta un evento naturale. `GameScene._on_day_advanced` confronta il contatore con `vegetation_layout_checkpoint` di ogni cella.
- Tre casi: piante cambiate = ridisegno completo; solo inizio stagione (`SeasonCalculator.is_season_start_day`) = ridisegno leggero, motivo "cambio stagione", stesse piante e stessa memoria della geometria; altrimenti nessun ridisegno.
- Una cella viva lontana, a inizio stagione senza piante cambiate, si segna da ricalcolare senza generatore: all'arrivo del player rilegge la disposizione tenuta.
- Reset dei lotti e capacità: si aggiornano anche senza rigenerare. A vista è tutto a posto, bacche comprese.
- Misurato in una partita all'anno 14, una sola cella viva, nessun evento in quei giorni (`[DAY TOTAL]`):

| Giorno | Prima | Adesso | Note |
|---|---|---|---|
| 90 | non misurato | 80 ms | ridisegno 0 ms; il resto è probabilmente l'arrivo dei lupi (non misurato) |
| 91 | non misurato | 669 ms | ridisegno completo 425 ms |
| 181 | non misurato | 1097 ms | ridisegno completo 890 ms |
| 182 | non misurato | 226 ms | ridisegno leggero 78 ms |
| 272 | 374 ms | **29 ms** | atteso circa 30 |
| 273 | 546 ms | **253 ms** | atteso circa 200; ridisegno leggero 104 ms, scorte di frutta 127 ms |
| 0 | non misurato | 784 ms | ridisegno completo 582 ms |

- Limite: nei giorni 182 e 273 con un evento ovunque sulla mappa il ridisegno resta completo (circa un anno su due al 182, uno su cinque al 273). Non si restringe perché gli eventi spariranno (decisione 2).
- **Prova ancora da fare, prima del passo 4:** in una partita, tagliare qualche pianta, uscire dalla cella tra il giorno 183 e il 272, restare fuori al 273, tornare tra il 274 e il 364. Devono esserci le stesse piante, i ceppi al loro posto e i colori d'autunno. Se la riga `[LOD TIMING]` del 273 mostra una mareggiata, ripetere l'anno dopo. Per la riga serve `SHOW_DAILY_TIMING_LOGS` acceso. Non provato neanche il caso della cella lontana viva per un edificio.
- Da correggere se si riaccende il log: `[GAMESCENE DAY]` scrive "celle vive rinfrescate" anche quando non ne ridisegna nessuna.
- Il controllo headless di GameScene non mostra errori di script, ma Godot si chiude in crash (codice 139), causa non cercata; nella partita provata non si è visto.

### 2. Prova della funzione, senza toccare il gioco
Nuovo servizio con la funzione, più una misura temporanea: tempo per lotto e per 100x100 lotti. Confronto a occhio con l'aspetto di oggi: macchie, densità per bioma, prato che diventa arbusteto e bosco nei decenni. **Se costo o aspetto non reggono, ci si ferma con poco lavoro perso.**

### 3. Interruttore: motore spento
Non girano `ResourceGrowthService`, `ResourceEncroachmentService`, `ResourceMigrationService`, `ResourceMortalityService`, `ResourceAgeBandService`, `NaturalEventService`. Resta il reset dei lotti (e `grow_fauna`, se esiste ancora).

### 4. Disegno a richiesta
`GameScene._refresh_resource_visuals` chiede solo i lotti visibili, aggiungendo quelli entrati in vista. Età e sottotipo per il renderer arrivano dalla funzione. Taglio, ceppi e ricrescita secondo la decisione 3.

### 5. Gli altri lettori dell'elenco completo
219 occorrenze in 27 file al 2026-11-08, salvataggi e renderer compresi. Passano a domande per lotto o per area:
- `CutZoneService`, `VegetationSelectorController`, `ClearAction`, `BuildingSiteClearingService`, `PlantCutService`, `PlayerHarvestService`
- `VegetationPoolService`, `VegetationLotIndex`, `MovementTerrainService._forest_cells`, `GameSimulation.relocate_start_group`
- Nebbia: `set_vegetation_presence` (vegetazione sfocata)
- Ispezione della microcella in `GameScene` (`_build_vegetation_lot_breakdown`): stessi valori di oggi.

### 6. Risorse delle piante
La formula per lotto della sezione sopra, comprese le uova (`lot_source` GRASS_PATCH). Il raccolto resta salvato per lotto.

### 7. Frutta
Bacche, ghiande e frutta passano alla formula per lotto; si toglie la scorta di cella dal giro stagionale. Taratura della resa. `CellRichnessCalculator` e `FirstStartMacroCellSelectionService` usano ancora numeri di cella: tenerli o sostituirli con una stima.

### 8. Pannelli e salvataggi
Stime in `WorldInfoPanel` e `MacroCellDetailPanel`, `worldRenderer` adattato. Nuovi dati nei salvataggi, senza conversione dei vecchi. `VegetationEquilibriumTest` diventa inutile.

### 9. Cancellazione (più avanti, su decisione dell'utente)
Motori, generatore vecchio, registri delle piante, file degli eventi naturali. **Restano** `tree_growth.tres` e `shrub_growth.tres` (registro dei sottotipi).

## Stima (a occhio)
- Passi 1-3: circa 3 ore, prove comprese. Il passo 1 vale anche da solo.
- Passo 4: 2-3 ore, il più delicato.
- Passi 5-8: altre 2-3 giornate, con la taratura. Il rischio maggiore è nel passo 5.
- Il guadagno sulla prima visita arriva dal passo 4 in poi, e per intero solo con i passi 5 e 6.

## Cosa si perde
Crescita e colonizzazione calcolate davvero, incendi e siccità, conteggi esatti nei pannelli di `MacroCellScene` e `WorldScene`, vecchi salvataggi.

## Verifica
- Compilazione: GameScene headless, un solo controllo.
- Passo 1: `SHOW_DAILY_TIMING_LOGS` acceso, giorni 272 e 273 confrontati con 374 e 546 ms.
- Passo 4: stessi log del cambio cella, prima visita confrontata con 237 ms e ritorno con 66 ms; camminando nella nebbia non devono comparire scatti nuovi.
- Passi 4-6: uscire, rientrare, salvare e ricaricare: piante identiche, ceppi al loro posto, tagli conservati.
- Molti anni in avanti: ceppi che ricrescono dopo 8 e 2 anni, piante che muoiono e rinascono, prato che cambia senza saltare gli arbusti, bosco che non invecchia tutto insieme.
- Demolizione: piante di nuovo sul lotto dopo le stesse attese.
- Passi 6-7: l'ispezione della microcella mostra valori coerenti; tagliare un albero da frutto toglie la sua frutta; col solo passare degli anni le quantità non calano da sole.
