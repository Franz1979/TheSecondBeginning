# Progetto B: piante salvate come individui

Stato: proposta (2026-10-24), nessun codice toccato. Da applicare **dopo un commit** dello stato attuale, una fase alla volta, con un commit tra una fase e l'altra.

## 1. Perché

Oggi un taglio, un cantiere o un checkpoint segnano `needs_full_vegetation_recompute`, e si rifà tutta la vegetazione della macrocella:
- la distribuzione degli individui per lotto (`IndividualVegetationService._distribute_individuals`);
- tutta l'erba (`ResourcePositionService`);
- le disponibilità di bastoni, sassi e uova;
- tutti i MultiMesh.

Un singolo taglio costa così 300–400 ms, e il cambio di stagione ~575 ms solo di renderer. Con centinaia di pipottini che tagliano non è sostenibile.

## 2. Come è oggi (in breve)

Buona parte dell'**identità** degli alberi e degli arbusti è **già salvata**:
- `tree_/shrub_claimed_lots`;
- `tree_/shrub_individual_subtype` (che fa anche da "è viva");
- `tree_/shrub_virtual_birth_year`;
- le eccezioni di taglio e di morte.

Restano invece **ricalcolati** a ogni giro:
1. **quanti individui ha ogni lotto**: si ricava da quantità / lotti più un resto distribuito con un hash, e `known_extent` impedisce che il numero cali;
2. **tutta l'erba**: i lotti nascono dal rumore e da `dedicated_space[GRASS]`. Uova, verdure selvatiche e capacità dei lotti d'erba dipendono da questi lotti, che sono stabili solo per caso;
3. **dove sta la pianta dentro il lotto**: la posizione sul disco dipende da quanti individui ha il lotto, quindi aggiungerne o toglierne uno sposta i vicini.

La simulazione (crescita, invasione, mortalità, migrazione, eventi, pascolo) lavora solo sui **numeri aggregati**:
- `dedicated_space`;
- `resource_quantity`;
- `subtype_composition`;
- `age_composition`.

Gli individui vengono poi "inseguiti" da questi numeri, e da qui nascono due fonti di verità che divergono. Per esempio il taglio non aggiorna `age_composition`.

## 3. Idea

**Per le macrocelle materializzate, cioè già scoperte, la fonte di verità sono gli individui.** I numeri aggregati se ne ricavano (o si tengono allineati a ogni modifica) e non comandano più.

- **Le macrocelle mai scoperte restano aggregate**, come oggi. È il livello di dettaglio "statistico" adatto a scalare: costano poco e la simulazione sui numeri resta valida.
- **La materializzazione avviene una sola volta, alla prima vista**: è l'attuale prima vista (`_freeze_new_individual`, `_seed_first_sight_death_markers`), eseguita una volta e poi salvata.
- **Ogni modifica diventa un'operazione su individui**: nasce, muore, viene tagliato, viene sgomberato. Ogni operazione registra cosa è cambiato, e il disegno aggiorna solo quello.

## 4. Modello dati (nuovo)

Un nuovo oggetto `VegetationStore` per macrocella materializzata, dentro `MacroCellState`:

- **`lots`**: lotto Vector2i → dati del lotto:
  - `capacity` (posti fissi del lotto, decisi alla prima vista da `max_density` del terreno e bioma, arrotondati);
  - per ogni posto (indice 0..capacity-1): tipo (TREE/SHRUB/vuoto), sottotipo, anno di nascita, e stato (vivo, ceppo con anno di taglio, morto con marcatore).
- **`grass_lots`**: insieme di Vector2i, salvato, con eventuale anno di comparsa. L'erba diventa stabile.
- **Contatori per tipo, sottotipo e fascia d'età**, aggiornati a ogni operazione. Da questi si leggono i numeri aggregati di oggi, così i servizi che li leggono non cambiano.
- **`changes`** (non salvato): elenco dei posti cambiati dall'ultimo disegno, letto e svuotato dal disegno.

Con questo modello **l'indice delle piante per microcella è già la struttura stessa** (`lots`): la proposta separata dell'indice decade.

**Posti fissi per lotto.** Il disegno calcola la posizione sul disco da `capacity` e non dal numero di individui vivi. Una nascita o una morte non sposta i vicini, e la geometria di ogni pianta si calcola una volta sola.

## 5. Operazioni (`VegetationStoreService`, statico, in `simulation/scripts/core/`)

- `materialize(macro_state, ...)`: alla prima vista. Riusa la logica di oggi, poi la generazione non si rifà più.
- `birth(type, count, subtype_weights, rng)`:
  1. posti vuoti nei lotti già del tipo, i più vicini a macchie esistenti;
  2. poi lotti nuovi, nell'ordine stabile di `ResourcePositionService`, che continua a dare forme organiche.
  Il sottotipo si sceglie con i pesi del bioma di oggi (`get_biome_weighted_subtype_composition`).
- `kill(type, count, weights, cause)`: mortalità, eventi, invasione (lato perdente). Sceglie gli individui con pesi per fascia d'età e sottotipo (inversi del bioma, come oggi) e mette il marcatore di morte.
- `cut(key)`, `clear_lot(lot)`: taglio e cantiere, cioè l'attuale `PlayerHarvestService.cut_individual` e `BuildingSiteClearingService._clear_type`, ma senza ricalcolo.
- `graze_grass(count)` / `grow_grass(count)`: pascolo giornaliero e crescita dell'erba sui `grass_lots`.
- `expire_markers(year)`: ceppi che tornano liberi e morti che spariscono a primavera.

## 6. Simulazione

I servizi annuali **continuano a calcolare quanto** cambia sui numeri, esattamente come oggi, quindi bilanciamento e curve restano uguali. Per le macrocelle materializzate traducono la differenza in operazioni:
- crescita → `birth`;
- mortalità → `kill`;
- invasione → `kill` del tipo debole e `birth` del forte nello stesso lotto;
- migrazione → `birth` nella cella di arrivo;
- eventi → `kill` nei lotti colpiti.

Per le macrocelle aggregate non cambia nulla.

Al checkpoint il lavoro cresce con il numero di individui che cambiano, non con il totale delle piante. Se servisse si potrà dare un budget per fotogramma, ma solo dopo aver misurato.

## 7. Disegno e consumatori

- **`MicroCellRenderer`**: ogni MultiMesh tiene una mappa posto → istanza. Una modifica aggiorna solo quell'istanza (scala 0 per nascondere), e si rifanno solo i gruppi da 256 toccati. Niente più `_rebuild_*` completi, salvo alla prima apertura.
- **Nebbia**: quando cambia la visibilità di una microcella, si accendono o spengono solo i posti di quel lotto (lettura diretta da `lots`). Sparisce `_filter_vegetation_positions_by_visibility` sulle ~62.000 piante.
- **`cached_vegetation_positions`** sparisce. `CutZoneService`, `MovementTerrainService._forest_cells`, uova e capacità dei lotti leggono `lots` / `grass_lots` per il rettangolo che serve.
- **`needs_full_vegetation_recompute`** sparisce.

## 8. Salvataggi

- È un nuovo blocco compatto per macrocella, con array impacchettati per lotto: è più piccolo dei dizionari attuali di anno di nascita e sottotipo, che salvano `{x,y,i,year}` per ogni individuo.
- **Vecchi salvataggi**: al caricamento si materializza dagli store di oggi (claimed lots, sottotipi, anni di nascita, eccezioni), mentre erba e capacità dei lotti si generano una volta e da lì restano salvate. Tutto con `.get(key, default)` come di consueto.

## 9. Scelte (tutte approvate dall'utente il 2026-10-24, come proposte)

1. **Dimenticanza della nebbia** (`forget_known_individuals`). Oggi, quando la memoria della nebbia si svuota, le piante vengono cancellate e rigenerate. Proposta: **non cancellarle più**. Si dimentica solo ciò che il giocatore vede, la vegetazione vera resta.
2. **Erba salvata**: proposta sì (rende stabili uova e verdure).
3. **Posti fissi per lotto**: proposta sì. Il prezzo è che un lotto non può superare la sua `capacity`: oggi `known_extent` lo permette.
4. **Lotti misti albero + arbusto** (`MIX_TREE_AND_SHRUB`): restano, con i posti condivisi nel lotto.

## 10. Fasi (ognuna provabile, commit tra una e l'altra)

| Fase | Cosa | Effetto visibile | Rischio |
|---|---|---|---|
| 0 | Commit dello stato attuale; profili di riferimento di taglio, cambio stagione e movimento | — | nullo |
| 1 | `VegetationStore` + `materialize` + salvataggi + caricamento dai vecchi; il disegno legge ancora come oggi | nessuno (stesso aspetto) | medio |
| 2 | Taglio, cantiere, morte naturale e pascolo come operazioni sullo store; disegno per differenza solo per le rimozioni | **sparisce il picco del taglio** | medio |
| 3 | Disegno a posti fissi e aggiornamenti mirati; nebbia per lotto; `cached_vegetation_positions` tolto | spariscono i picchi di movimento/nebbia | medio-alto |
| 4 | Simulazione annuale tradotta in operazioni per le celle materializzate | spariscono i ricalcoli del cambio stagione | alto |
| 5 | Pulizia: `known_extent`, distribuzione per resto, flag, `MacroCellScene`, CLAUDE.md | — | basso |

La fase 2 da sola risolve gran parte di ciò che si vede oggi. La 4 è la più delicata, perché lì gli individui diventano davvero la fonte di verità della simulazione.

## 11. Rischi principali

- **Divergenza tra individui e numeri** durante le fasi intermedie: si può aggiungere un controllo di debug che confronta i contatori con gli aggregati.
- **Bilanciamento**: invariato, perché il "quanto" lo calcolano gli stessi servizi.
- **Migrazione dei vecchi salvataggi**: da provare su un salvataggio reale prima della fase 2.
