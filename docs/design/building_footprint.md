# Edifici più grandi di una microcella (ingombro)

Stato: progetto deciso il 2026-10-17; passo 1 fatto e provato lo stesso giorno (`BuildingFootprint`). Primo utilizzo:
lo Spiazzo delle feste 2x2 (vedi `feast_ground.md`).

## Situazione di partenza (ricognizione del 2026-10-17)
- Oggi ogni edificio occupa una sola microcella, `micro_x/micro_y`, e non esiste nessun concetto di forma.
  `BuildingRules.required_space` è solo un conteggio (vale 1 ovunque): dice quanto spazio si toglie alla macrocella
  (`MacroCellState.dedicated_space[BUILDING]`) e moltiplica i rametti del cantiere.
- Gli edifici lineari (sentieri, muri) sono tanti 1x1 disegnati attaccati con le maschere dei vicini: non aiutano.
- `BuildingVerificationService.gd:10-16` ha già un promemoria sulle tre cose che servono: forma, controllo di ogni
  cella, lato della porta.
- La rotazione è a 4 direzioni (`Building.rotation`, `GameTypes.Direction`: dove guarda la porta), scelta con R durante
  il piazzamento e già salvata.
- Passaggio: gli edifici bloccano la loro cella, tranne quelli della categoria MOVEMENT (`MicrocellObstacles`,
  `PathfindingService`).
- Il nodo più grosso per gli edifici grandi che **bloccano**: ~30 punti mandano il pipottino "nella cella
  dell'edificio" (`random_point_in_microcell(Vector2(micro_x, micro_y))`). Funziona perché `find_path` sblocca
  temporaneamente la cella bersaglio; in un rettangolo che blocca, l'angolo sarebbe circondato dalle sue stesse celle.

## Decisioni
1. **Ingombro**: `BuildingRules.footprint: Vector2i = Vector2i(1, 1)`, larghezza (lungo il lato della porta) ×
   profondità, descritto con la porta verso sud. Gli edifici attuali restano 1x1 senza toccare i `.tres`.
2. **Rotazione**: R ruota tutto, porta compresa. Con la porta a est o a ovest larghezza e profondità si scambiano.
3. **Ancora**: `micro_x/micro_y` è l'angolo in alto a sinistra del rettangolo già ruotato. Durante il piazzamento il
   mouse sta al centro della sagoma (ancora = cella del mouse − metà ingombro).
4. **Porta**, una sola, descritta con la porta a sud:
   - **lato**: sempre quello della larghezza, in basso. Corto o lungo si sceglie da come si scrive l'ingombro: 3x2 =
     porta sul lato lungo, 2x3 = porta sul lato corto;
   - **punto**: `BuildingRules.door_offset: int = -1`, la cella del lato contando da sinistra da 0. Con -1 sta al centro
     (con lato pari, la cella a sinistra del centro); con 0 nell'angolo sinistro, con larghezza − 1 nel destro;
   - `has_door = false`: nessuna porta, come oggi;
   - "davanti alla porta" = la cella fuori dalla porta. I criteri 7 (porta non bloccata) e 8 (non bloccare la porta
     altrui) del piazzamento lavorano su quella cella.
5. **Passaggio**: blocca chi non è calpestabile. Dal 2026-10-17 lo decide il flag `BuildingRules.walkable` (prima la
   categoria MOVEMENT, che resta "tappeto/strada": elenco, conteggi, preferenza del pathfinding).
   - Un edificio grande calpestabile (lo spiazzo, categoria Ricreativo) ci si entra: chi ci lavora ci entra e i ~30 punti dei percorsi non
     cambiano.
   - Gli edifici grandi che **bloccano** (punto di lavoro davanti alla porta, sostituito nei ~30 punti) si progettano
     quando servirà il primo.
6. **Spazio della macrocella**: `required_space` = area dell'ingombro, calcolata in automatico (avviso se un `.tres`
   dice altro).
7. **Cantiere**:
   - rametti = `setup_site_material_per_cell` × area, come oggi;
   - allestimento **1 giorno per cella, senza tetto** (`SetupSiteAction.DURATION_DAYS` × area: un 3x2 sono 6 giorni, un
     4x4 16);
   - sgombero (`ClearAction`) su tutte le celle;
   - **un solo costruttore** all'inizio (vedi passo 5).
8. **Bordo**: per ora un edificio non può uscire dalla sua macrocella (un controllo in verifica:
   `micro + misura − 1 < World.WIDTH/HEIGHT`). Supportarlo toccherebbe ostacoli, renderer, pathfinding e spazio, che
   sono tutti per macrocella.
9. **Macerie**: ~~ereditano l'ingombro dell'edificio crollato~~ — cambiato il 2026-10-18 (richiesta utente): un edificio
   grande che crolla lascia **una maceria 1x1 per ogni microcella** del suo ingombro, con i detriti divisi tra loro
   (`BuildingLifecycleService.split_debris`), sgomberabili una per una.
10. **Miglioramenti** (`upgrades_to`): solo verso un tipo con lo stesso ingombro.
11. **Salvataggi**: nessun cambiamento. L'ingombro viene dal tipo; ancora e rotazione sono già salvate.

## Funzioni comuni
Una classe senza stato in `simulation/`, per esempio `BuildingFootprint`:
- misura ruotata;
- celle occupate (`Array[Vector2i]`);
- `covers(building, macro, cell)`;
- centro (ancora + misura / 2);
- lato della porta;
- cella davanti alla porta.

Per un 1x1 restituiscono esattamente ciò che si usa oggi, quindi gli edifici attuali non cambiano comportamento.

## Punti da toccare (dalla ricognizione)
- **Ostacoli e passaggio**:
  - `MicrocellObstacles.refresh_buildings`: tutte le celle. Così si sistemano anche pathfinding, `is_microcell_free` e
    la caduta dei mucchi;
  - `MovementTerrainService.rebuild`: i moltiplicatori su tutte le celle.
- **Vegetazione e terreno**:
  - `GameScene._building_positions_for_cell`: altrimenti la vegetazione cresce sulle altre celle;
  - `_collect_complete_dirt_tiles`, `_collect_ground_tiles`.
- **Piazzamento**:
  - `BuildingVerificationService.is_position_buildable`: criteri 2-6 e 9-12 su ogni cella, più il bordo;
  - `is_door_blocked`, `_blocks_existing_building_door`, `_door_target_macro_micro`, `get_door_front`;
  - `GameScene._is_placement_buildable_or_report`, `_place_building_at` (sgombero di tutte le celle),
    `_start_building_task_at`;
  - `BuildingGhost`: sagoma e porta.
- **Disegno**:
  - `MicroCellRenderer._draw_buildings`: il dato dell'edificio porta centro, misura e rotazione;
  - `get_building_screen_position`;
  - `_draw_selected_building_highlight`: raggio in base all'ingombro;
  - `GameScene._create_build_site_placeholder_nodes`: rametti sugli angoli del rettangolo.
- **Clic**:
  - `BuildingSelectorController.try_select`: test sul rettangolo;
  - `GameScene._find_building_at_microcell`;
  - `StickLotSelectorController` / `PlantFiberLotSelectorController._is_occupied_by_building`;
  - `GroundPileService` (:276).
- **Cantiere**: `ClearAction` (durata, ceppi e piante vive, `clear_ground` per ogni cella), `SetupSiteAction` (durata
  per cella).
- **Nebbia e influenza**:
  - `GameScene._building_visible_positions_for_cell`: dal rettangolo;
  - `InfluenceService.building_absolute_center`, `InfluenceFootprintOverlay.building_center_px`: dal centro.
- **Macerie**: `BuildingLifecycleService.spawn_rubble`.
- **Solo per i grandi che bloccano (dopo)**: tutti i `get_required_position` delle azioni (Build, Clear, SetupSite,
  Demolish, Inventory, Produce, Repair, RestockPouch, Retrieve, Rite, Unload), `MaterialSupplyService._building_point`,
  `TaskBuilderService`, `RiteJobProvider`, `JobBoardService`, `IdleTaskAssignmentService`,
  `HumanIndividualActionService`, `NeedTaskAssignmentService` (riposo in casa), `RiteService`, `VisitorService`,
  `Building.get_resumable_task_context`, `PathfindingService.reachability_for`, `FollowIndividualAction._pick_slot`,
  `BodyBurialService.get_put_down_point`.

## Ordine di lavoro
Ogni passo si prova in gioco prima del successivo.
1. **Base dell'ingombro** con un edificio di prova (per esempio un 3x2 di movimento): dati, classe comune, piazzamento,
   ostacoli, vegetazione, disegno, clic, cantiere. Gli edifici 1x1 devono comportarsi esattamente come prima.
2. **Spiazzo delle feste 2x2** e il suo banchetto (`feast_ground.md`): 2a l'edificio (fatto), 2b deposito e banchetto.
3. **Macerie e miglioramenti** con ingombro. Macerie fatte (2026-10-18: una 1x1 per microcella, vedi decisione 9); restano i
   miglioramenti.
4. **Edifici grandi che bloccano**: punto di lavoro davanti alla porta nei ~30 punti, quando servirà il primo.
5. **Più costruttori**:
   - `max_builders` esiste già e il lavoro si accumula sull'edificio (`construction_progress`);
   - da fare: posti multipli nel lavoro della bacheca, ognuno in una cella diversa del cantiere, eventualmente
     `max_builders` derivato dall'area;
   - allestimento e sgombero a una persona o divisi, da decidere.
