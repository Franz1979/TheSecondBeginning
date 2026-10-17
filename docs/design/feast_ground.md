# Spiazzo delle feste e banchetto

Stato: progetto deciso il 2026-10-17. Fatti lo stesso giorno: la base degli edifici grandi (`building_footprint.md`,
passo 1), l'edificio (2a), il deposito riservato agli eventi (2b-1, `BuildingRules.storage_event_only`) e il banchetto
sullo spiazzo (2b-2: il vecchio banchetto al focolare è stato sostituito, non affiancato). Da fare: il fuoco acceso
disegnato durante la festa.

## Perché
Il banchetto al focolare (`paleolithic_banquet`) era quasi impossibile da organizzare:
- la carne, cruda o pronta, è la risorsa più contesa: si mangia (l'essiccata per prima, perché è la più calorica per
  spazio), si lavora, deperisce e arriva solo dalla caccia;
- il focolare accetta solo gli ingredienti delle sue ricette, quindi la carne pronta va trasportata apposta;
- la "riserva" di carne cruda del magazzino serve solo a far partire le cacce.

Il 2026-10-17 è stata aggiunta la carne pronta al focolare (cotta, essiccata, affumicata), ma il problema di fondo è
rimasto. Lo stesso giorno il banchetto è stato **tolto dal focolare** (`building_types` vuoto in
`paleolithic_banquet.tres`): oggi non lo ammette nessun edificio.

## Lo spiazzo
- Edificio nuovo `feast_ground`, **2x2** (deciso il 2026-10-17, prima era 4x4), categoria **Ricreativo**
  (nuova, 2026-10-17: luoghi di gioia e unione, nessun raggio di influenza proprio), calpestabile col flag
  `BuildingRules.walkable` (decisione 5 di `building_footprint.md`).
- Moltiplicatori di velocità e stamina a 1.0, `has_door = false`.
- Si sblocca con le costruzioni paleolitiche (`required_idea_id = "paleolithic_constructions"`).
- Costruzione: 60 sassi + 10 tronchi, lavoro 3200, minimo 3 giorni; allestimento con i rametti di sempre (16, 4 giorni).
  Durata 20 anni, integrità 120, difesa 20, niente macerie.
- Disegno (`FeastGroundShape`): terra battuta con al centro un cerchio di sassi, cenere e legnetti spenti; il fuoco
  acceso durante la festa arriva col passo 2b.
- Deposito: **10 slot × 100** (deciso il 2026-10-17), solo cibo e combustibile, solo per i banchetti.
- Funziona come un deposito di solo cibo e combustibile **da cui non si preleva**:
  - **nessuno ci deposita di sua iniziativa**: `storage_accepts_recipe_materials_only = true` senza ricette, quindi lo
    stoccaggio libero rifiuta tutto. Entra solo ciò che chiede il banchetto, tramite la quota del rito (`material_quota`
    nel record → `BuildingStorageService._production_quota`, già scritta per il focolare il 2026-10-17);
  - **nessuno ci preleva**: nuovo flag in `BuildingRules` (per esempio `storage_withdraw_locked`). L'edificio è escluso
    come fonte da `WarehouseSelectionService` (pasti, rifornimenti, trasporti) e dal conteggio delle scorte del
    villaggio (`VillageStockService`), altrimenti il gestore crede di avere cibo in più.
- La preferenza per le strade del pathfinding (`ROAD_PREFERENCE`) vale solo per i moltiplicatori di movimento sotto 1:
  lo spiazzo li ha a 1, quindi non fa da scorciatoia.

## Il banchetto sullo spiazzo
Si tiene il motore dei riti sociali (`SocialRiteService`: convocazione, fasi, preparazione con i trasporti
dell'organizzatore, piatto comune, coesione) e si cambia solo la parte propria del banchetto.
1. Si avvia dal pulsante "Banchetto" nel pannello dello spiazzo: `paleolithic_banquet.tres`,
   `building_types = ["feast_ground"]`.
2. **Soglia di calorie impostabile sullo spiazzo**, nel pannello: minimo 500, valore di partenza nei dati.
3. **Preparazione**: trasporta **solo l'organizzatore**, nell'ordine:
   1. **20 di combustibile per il falò** (valore nei dati), per primo, perché non deperisce. Si riusa
      `MaterialSupplyService.FUEL_KEY`, e la quota del rito ammette i combustibili fino al mancante;
   2. poi **cibo di qualunque tipo** fino alla soglia, **prima il più deperibile** (`day_durability` più bassa). Il
      fabbisogno si ricalcola a ogni richiesta: dalle calorie mancanti si sceglie un cibo concreto che c'è in una fonte
      e se ne chiedono i pezzi che le coprono (come `_meat_to_fetch`, generalizzato).
4. Raggiunte soglia e combustibile si convoca il villaggio, come oggi.
5. **Inizio festa**: il combustibile si consuma (il falò), il cibo dello spiazzo va nel piatto comune.
6. **Fine festa**: le calorie si dividono tra i presenti, come oggi. Coesione fissa più `cohesion_gain_per_1000_calories`
   (0,1 ogni 1000 calorie servite, deciso il 2026-10-17 al posto della quota per pezzo di carne). Non c'è più l'abilità di cucina all'organizzatore.
7. **Annullato o saltato**: cibo e combustibile **restano nello spiazzo** e contano per il prossimo banchetto; intanto il
   cibo deperisce.
8. **All'avvio si controlla anche l'edificio** (`building_types`): un vecchio ordine rimasto sul focolare non deve farlo
   ripartire là. Oggi `SocialRiteService.start` / `get_start_rejection` non lo controllano.

## Da togliere
Il codice del banchetto al focolare, dopo che quello sullo spiazzo funziona:
- la cottura: `_banquet_cook`, `_banquet_open_cooking`, `_banquet_cookable_units`;
- la carne pronta: `ready_meat_resources`, `_ready_meat_units`, `_meat_to_fetch`, `_banquet_serve_ready_meat`;
- i campi `raw_meat_resource`, `cooked_resource`, `min_meat_units`, `crafting_gain_organizer`;
- l'esclusione dei banchetti dalle fonti di cibo (`get_banquet_building_ids` in
  `NeedTaskAssignmentService.find_restock_source`): con lo spiazzo da cui non si preleva non serve più.

La quota del rito (`material_quota`, `get_material_quota`, `_production_quota`) e
`WarehouseSelectionService.has_retrieval_source` invece **restano**: servono allo spiazzo.

## Dopo
- Banchetto come attività idle (come la lezione), quando lo spiazzo funziona.
- Felicità e salute dei singoli cibi applicate al banchetto, come nel pasto normale.
