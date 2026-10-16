# Progetto: socialità e teaching

> Documento di progetto. Ogni passo si implementa solo quando l'utente lo chiede esplicitamente.
> Tutto nasce già nella struttura definitiva (vedi `gamescene_refactoring.md`): servizi senza stato nella
> cartella della meccanica, stato in `GameData`/oggetti di partita, risultati mostrati dalla scena, in
> GameScene solo collegamenti.

## Ordine dei passi
1. **Skill Socialità** — fatto (2026-10-13).
2. **Talk** (livello 0) — codice scritto (2026-10-13), da provare in gioco.
3. **Idee** "Insegnamento orale" e "Organizzazione tribale" — fatte (2026-10-13), ancora senza sblocchi.
4. **Teaching** e **feste** — da popolare (prossima sessione).
5. **Riunioni** (riti politici) — a grandi linee.

### Organizzazione (decisa 2026-10-13)
```
livello 0:  talk (fatta) · feste al fuoco (campfire)
Costruzioni paleolitiche ─→ Insegnamento orale (30) ─→ pietre dell'insegnamento + teaching ─→ (ere dopo) scuola…
Costruzioni paleolitiche avanzate ─→ cerchio di pietre (nuovo centro del villaggio, e altro)
Costruzioni paleolitiche avanzate ─→ Organizzazione tribale (40) ─→ riti politici al cerchio di pietre
                                     (consiglio degli anziani; più avanti una riunione che coinvolga tutti)
```
- Le pietre per il teaching ci sono già con Costruzioni paleolitiche: l'estrazione manuale chiede solo il piccone
  d'osso (`bone_pick`, capanna dell'attrezzista); le zone di lavoro avanzate rendono solo la cava automatica.
- Il cerchio di pietre lo sblocca l'idea di costruzione, non Organizzazione tribale, perché servirà anche ad altro.
- Teaching, feste e riunioni condividono la convocazione di più persone in un punto (schema `ProcessionService`):
  da progettare una volta e riusare.

Solo il passo corrente si dettaglia fino in fondo; gli altri si rivedono quando ci si arriva.

---

## 1. Skill Socialità (`skill_social`)
- 10a skill su `HumanIndividual`, trovata in automatico da `get_skill_property_names()`.
- Inclusa nella semina iniziale casuale (dote innata, non esclusa come `skill_ritual`); eredità alla nascita
  automatica come le altre.
- Salvata/caricata con chiave `skill_social` (default 0.0 per i save vecchi); barra nel pannello individuo.
- Usi previsti: cresce con la talk (+1 a entrambi); scala la felicità della talk (chiave `talk` in
  `skill_action_effects.tres`); amplificherà feste e riunioni come `skill_ritual` fa con i riti.
- Distinta da `skill_leadership` (carisma di chi comanda); le riunioni useranno probabilmente entrambe.

## 2. Talk (livello 0, nessuna idea richiesta)
**Modello a estrazione (B):** `talk` entra nel sorteggio delle attività libere
(`IdleTaskAssignmentService`, `IDLE_FALLBACK_TASK_PATHS`).
- **Chi:** `allowed_age_bands = [2, 3, 4, 5]` (TEENAGER e oltre), sia chi lancia la talk sia il partner; i
  bambini hanno già *play*.
- **Peso nel sorteggio:** `idle_weight = 0.5` (2026-10-14, prima 1.0: talk troppo frequenti): ~7% per un adulto, ~9% per
  un ragazzo, meno nei fatti perché senza partner l'estrazione si scarta.
- **Raggio di chiamata:** `4 × (1 + skill_social / 1000)` microcelle (da 4 a 8), stessa formula e poco meno
  del richiamo del coordinatore (`CoordinatorService.CALL_RADIUS_BASE` = 5, fino a 10 con la leadership).
  Partner: stessa Folk, nelle stesse fasce d'età, chiamabile (vedi sotto); **a caso** tra i validi nel
  raggio (non il più vicino, altrimenti parlerebbero sempre gli stessi due).
- **Chiamata:** una sola, istantanea, nel momento dell'estrazione, dal posto in cui sono. Punto d'incontro =
  microcella libera e raggiungibile vicino al punto medio fra i due. Il partner abbandona la sua attività
  libera e riceve subito anche lui una task talk collegata (cammina al punto → aspetta → conversa). Nessun
  partner valido → l'estrazione si scarta e si ripesca subito un'altra attività; nessun richiamo ripetuto.
- **Frequenza:** solo dal sorteggio (a ogni fine di attività libera), nessun tempo d'attesa fra due talk.
- **Chiamate incrociate:** impossibili — gli individui si elaborano uno alla volta e la chiamata è
  istantanea: chi è già in una talk non è libero, non estrae e non è chiamabile.
- **Chi può essere chiamato:** nessun campo nuovo. Chiamabile = chi sta facendo un'attività libera del
  sorteggio (`IDLE_FALLBACK_TASK_PATHS`, elenco già esistente): wander, explore, leisure_rest,
  leisure_restock, daydreaming (perde il pensiero, regola invariata), leisure_rite (finisce senza effetto);
  play esclusa dall'età. Mai: bisogni, lavori, chi ha task in coda, chi è già in una talk. Scartata l'idea di
  usare "non sospendibile": quasi tutti i lavori lo sono (solo trasporto, carico e costruzione si sospendono).
- **Attesa:** chi arriva per primo aspetta l'altro al massimo mezza giornata; scaduto → talk chiusa senza
  effetto.
- **Tempi** (1 giorno = 8 s a x1; ~10 microcelle al giorno): cammino 0,2–0,4 gg, attesa massima 0,5 gg,
  conversazione 0,25 gg → totale tipico ~0,45–0,65 gg.
- **Conversazione:** 0,25 giorni; alla fine **+20 felicità fissa a entrambi** (solo ai due coinvolti,
  `vital_effects_by_task_name`) e **+1 `skill_social` a entrambi** (`skill_effects_by_task_name`). Nessun
  contagio di umore o fede.
- **Interruzione reciproca:** se uno dei due viene interrotto (emergenza, lavoro assegnato) anche l'altro
  chiude la sua talk e torna libero.
- **Visivo e suoni:** alla chiamata "hey" (hey_2) su chi chiama e "yeah" su chi risponde; a inizio conversazione
  un fumetto 💬 sale e svanisce sopra ciascuno (come la lampadina del pensiero) con talk_1 per chi ha chiamato e
  talk_2 per l'altro. Presentazione in GameScene (`_track_talk_tasks`, `_spawn_talk_effect`), suoni via
  `talk_sound_requested` → AudioEventListener → SoundEventMap.
- **Scelte di implementazione:** partner solo nella stessa macrocella (le posizioni sono nel riferimento della
  macrocella); lo stato del partner si legge dalla sua Task (nessun segnale né stato statico); se uno finisce un
  fotogramma prima, l'altro chiude con gli effetti. Debug: log `[TALK]`
  (`DebugLogging.SHOW_TALK_LOGS`, acceso).
- **Codice:** `gameplay/social/scripts/TalkService.gd` (scelta del partner, punto d'incontro, verifica
  chiamabilità), task `talk.tres`, nuovo case in `IdleTaskAssignmentService._build_idle_task`. GameScene non
  si tocca se non per l'icona.


## 3. Teaching (indipendente dalla socialità)
- **Chi insegna:** solo OLD (regola semplice da capire per il giocatore).
- **Cosa:** solo ciò che conosce meglio — la skill migliore (o una delle 3 migliori).
- **A chi:** l'anziano scelto convoca tutti i CHILD; ognuno guadagna una percentuale della skill dell'anziano.
- Sbloccato da **Insegnamento orale** (`oral_teaching`, 30 pensieri, prereq. Costruzioni paleolitiche), che sblocca
  anche l'edificio **pietre dell'insegnamento**; filone a sé che più avanti porterà alla scuola.
- Convocazione sullo schema di `ProcessionService`.
- **Punti aperti:**
  - la percentuale si *aggiunge* alla skill del bambino o la skill *sale fino* a quella soglia?
  - frequenza (una volta per stagione/anno?) per evitare abusi;
  - incrementi interi (regola delle skill);
  - costo per l'anziano (stamina) ed eventuale guadagno (felicità/leadership);
  - imitazione passiva a livello 0 (ragazzo vicino a un adulto che lavora) — da valutare.

## 4. Feste e riunioni
- Eventi distinti, in luoghi diversi.
- **Festa (livello 0, al fuoco):** consuma cibo dal magazzino; felicità ai partecipanti; influenza culturale.
  Possibile festa stagionale su `_on_season_ended` (oggi vuoto).
- **Riunioni = riti politici (Organizzazione tribale, `tribal_organization`, 40 pensieri, prereq. Costruzioni
  avanzate), solo al cerchio di pietre:** guidate dalla leadership più alta; lealtà e influenza politica (punti
  edificio + villaggio). Il consiglio degli anziani è uno di questi riti, non l'unico.
- Simmetria con i riti: riti → punti religiosi, riunioni → politici, feste → culturali
  (`InfluenceService.add_points`).
- **Codice:** `gameplay/social/` con `SocialEventRules` + `.tres` per tipo (schema `RiteRules`),
  `SocialEventService`, `SocialEffectService`; stato in `GameData`/`Building`; pulsante nel pannello
  dell'edificio (ordine dell'edificio) e popup del risultato in scena.
- **Punti aperti:** luoghi/edifici, convocazione (raggio come i riti o lista esplicita), costi, cooldown.

## 5. Coesione del villaggio (fatta 2026-10-14)
- Valore 0–100 del villaggio (`Village.cohesion`, salvato, 50 alla nascita e per i salvataggi precedenti); quella della
  popolazione è la media semplice dei villaggi (`Folk.get_cohesion()`), calcolata. Non è un'influenza (niente raggi,
  non si somma) e non c'entra con la skill socialità. Unico punto che la modifica: `VillageCohesionService`.
- **Calo annuale proporzionale** a fine anno: coesione / 50 (0 → 0, 50 → 1, 100 → 2); moltiplicatori in futuro.
- **Eventi a somma diretta:** talk +0.01 (una volta per talk), idea scoperta +1 al villaggio dell'edificio del pensiero
  che la completa, banchetto primitivo +0.1 (quando esisterà).
- **Nuovi arrivati:** media pesata con valore 20, contando solo i non CHILD/INFANT:
  (abitanti × coesione + nuovi × 20) / (abitanti + nuovi).
- **Statistiche:** scheda Influenza, grafico a parte (asse almeno 0–100), un punto di fine anno per villaggio
  (`GameData.village_cohesion_snapshots`) più la media della popolazione; log `[COESIONE]` acceso.
- **Effetti sul gioco:** primo uso deciso (2026-10-14, da fare più avanti): sotto una certa soglia di coesione qualcuno
  se ne va dal villaggio. Altri usi (lealtà, visitatori, lavori di gruppo) da decidere.

## 6. Riti: tipo e avvio dal pannello (passo A, fatto 2026-10-14)
- `RiteRules.rite_type` (RELIGIOUS / POLITICAL / CULTURAL / SOCIAL, default RELIGIOUS).
- I riti si ordinano dalla sezione "Riti" del pannello dell'edificio, come la produzione: senza l'idea dell'assegnazione
  mirino per scegliere chi celebra; con l'idea `Building.requested_rite_id` + lavoro "rite:<id>" in coda (finestra di
  assegnazione a mano come gli altri), riga del rito con "Assegna" (mirino) e X. L'ordine resta finché il rito non è
  celebrato davvero; abbandonato torna "mancante". Il destro su edificio non avvia più riti. Funerale e riti spontanei
  invariati; uno spontaneo non occupa un edificio con un rito ordinato in attesa.

## 7. Riti: base + specializzazione (2026-10-14)
| Classe | Ruolo |
|---|---|
| `RiteRules` | base generica (id, nome, tipo, edifici, durata, età, skill minima, spontaneo, sepolti, suono di fine) |
| `ReligiousRiteRules` | fede, corteo, sacralità, valore religioso del villaggio (rito semplice, ricordo dei defunti, funerale) |
| `SocialRiteRules` | raduno sociale: abitanti e partecipanti minimi, attesa, durata, felicità, socialità, coesione, icona e suono d'inizio |
| `BanquetRiteRules` | solo il banchetto: cibo da portare, carne da cuocere, bonus artigianato |
| `RiteService` | catalogo; `can_celebrate` con la skill del tipo (ritualità / socialità / leadership / cognizione) |
| `ReligiousRiteEffectService` | effetti dei riti religiosi (ex `RiteEffectService`) |
| `SocialRiteService` | raduno generico; cibo e cottura solo per `BanquetRiteRules`; stato in `GameData.active_social_rites` |
| `SocialRiteAttendAction` | ultimo step del partecipante (tipo d'azione `SOCIAL_RITE_ATTEND`) |

## 8. Banchetto paleolitico (fatto 2026-10-14, da provare in gioco)
- `paleolithic_banquet.tres` (`BanquetRiteRules`): focolare, solo ordinato dal pannello, organizzatore da adulto fertile in su;
  icona d'inizio 🍖 e suono `paleolithic_banquet`.
- Condizioni: ≥ 5 abitanti non CHILD/INFANT, ≥ 5 carni crude nel focolare, combustibile per cuocerne almeno 5
  (2026-10-15); si cuociono tanti pezzi quanti ne coprono insieme carne e combustibile.
- Convocazione come il corteo funebre: tutti tranne neonati, bisogni di sopravvivenza, chi porta un corpo; si viene
  anche con lo zaino carico (il lavoro va in coda). Niente cibo portato (2026-10-14, semplificato su richiesta).
- Inizio con 5 partecipanti da ragazzo in su arrivati (i bambini partecipano ma non contano; attesa massima 2 giorni,
  altrimenti salta); 1 giorno di festa in cui l'organizzatore presente cuoce **tutta** la carne cruda del focolare entro
  la giornata (più in fretta con la skill della Produce).
- Fine: ai presenti le calorie della carne cotta divise tra loro nelle provviste (eccedenza persa), +20 felicità,
  socialità +0.5 (+1 organizzatore, +1 artigianato se ha cotto), coesione +0.1 più 0.01 per ogni carne cotta; chi se n'è andato perde tutto. Log
  `[RITO SOCIALE]` acceso.
- Carne cruda nel gestore scorte (2026-10-16): ha di nuovo un livello proprio, la riserva in più (es. per i banchetti)
  che si somma al fabbisogno di carne cotta, affumicata ed essiccata. Prima si lavora, poi si riempie la riserva; la carne
  della riserva va al magazzino, l'eccesso alla destinazione della regola "Carne e pelli in eccesso".
- Giorni di autonomia (2026-10-16): cuociono solo la carne cruda libera (oltre la riserva e oltre quella per le
  lavorazioni); il cibo già in lavorazione (essiccatoio, ordini sulle postazioni) conta come calorie in arrivo.

## 9. Regola del gestore scorte: combustibile negli edifici (2026-10-16, da provare in gioco)
- "⚙ Regole di stoccaggio" del cassetto Gestione scorte: casella "Combustibile negli edifici che lo usano"
  (`GameData.stock_fuel_rule_enabled`) e sotto una riga per tipo di edificio sbloccato che brucia combustibile, con il
  suo minimo − [N] + (`GameData.stock_fuel_min_by_type`; default `BuildingRules.fuel_stock_min`: focolare 10,
  affumicatoio 20). Il minimo vale per tutti gli edifici di quel tipo. In unità di valore di combustibile.
- A ogni inventario `FuelStockService.plan_orders` guarda ogni edificio completo e in servizio di quei tipi: minimo −
  (presente + in viaggio) > 0 → un ordine (al massimo uno aperto per edificio) per quel combustibile mancante; coperto o
  edificio non più valido → l'ordine aperto si toglie.
- Gli ordini sono "transport" del cassetto (rinominato da "dry", lo stesso dell'essiccatoio) con `fuel_target_id` e
  `fuel_amount`: quale combustibile e da dove lo sceglie chi lo prende (il migliore nella sorgente più vicina,
  `FuelStockService.pick_fuel`) — la legna da ardere, con un valore più alto, verrà presa da sola. Il gestore amministra
  le scorte, non fa partire eventi.
