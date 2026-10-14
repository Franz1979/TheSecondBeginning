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
- **Peso nel sorteggio:** `idle_weight = 1.0` (come daydreaming): ~13% per un adulto, ~17% per un ragazzo,
  meno nei fatti perché senza partner l'estrazione si scarta.
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
