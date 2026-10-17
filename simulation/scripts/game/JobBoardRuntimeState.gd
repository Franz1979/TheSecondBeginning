class_name JobBoardRuntimeState
extends RefCounted

# Stato della lista dei lavori che vive solo durante la partita, MAI salvato (2026-10-17, refactoring GameScene blocco 2a
# — prima variabili di GameScene, spostato qui così la logica in JobBoardService non dipende dalla scena). Tenuto in
# GameData.job_board_runtime; lo stato salvato della lista resta nei campi job_board_* di GameData.
#
# Attesa per l'assegnazione a mano (2026-10-07, JobBoardService.get_manual_assign_window_seconds): ogni lavoro della lista
# senza nessuno assegnato (bloccato o no) ha in `waiting_since` il momento (`clock`: secondi reali a gioco in corso) in
# cui è entrato in lista. Entra quando compare tra i candidati, esce quando non c'è più o subito all'assegnazione, così un
# ritorno in lista fa ripartire l'attesa. Non salvato apposta: alla prima lettura (anche dopo un caricamento o all'arrivo
# dell'idea) i lavori già in lista sono subito prendibili (`waits_initialized` false).

# Secondi reali a gioco in corso (fermo in pausa, uguale a ogni velocità); lo fa avanzare la scena.
var clock: float = 0.0
# Chiave del lavoro -> `clock` all'ingresso in lista.
var waiting_since: Dictionary = {}
var waits_initialized: bool = false
# Lavori prendibili all'ultimo giro della lista (chiave -> true), per accorgersi di quelli nuovi (richiamo del
# coordinatore, 2026-10-09).
var open_job_keys: Dictionary = {}
# Mucchi svuotati dall'ultima raccolta con la consegna ancora in corso (2026-10-09): la riga "Mucchio" resta in "In corso"
# finché chi porta il carico non l'ha consegnato (PileJobProvider). Chiave del mucchio -> {"id", "name", "macro",
# "microcell"} dell'ultima volta che era elencato.
var pile_job_memory: Dictionary = {}
