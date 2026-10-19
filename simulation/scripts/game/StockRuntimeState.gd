class_name StockRuntimeState
extends RefCounted

# Stato del gestore delle scorte che vive solo durante la partita, MAI salvato (2026-10-17, refactoring GameScene blocco 4
# — prima variabili di GameScene). Tenuto in GameData.stock_runtime; letto e scritto da WarehouseManagerService. Dopo un
# caricamento riparte da capo: gli ordini salvati restano in GameData.drawer_orders, questo è solo il giro in corso.

# Inventario in corso di decisione (_on_inventory_started): gli ordini nuovi nascono nascosti finché il conteggio non
# finisce (StockRequestService.INVENTORY_PENDING_KEY); quanti ne sono nati, per la durata del conteggio.
var inventory_pending: bool = false
var inventory_new_orders: int = 0
# Nomi che il magazzino sta chiedendo (aggiornati a ogni giro): risorse raccoglibili sotto il loro livello e, se mancano
# giorni di autonomia, tutto il cibo raccoglibile. Servono a riempire lo zaino nelle sue raccolte (HaulZoneService).
var fill_names: Array[String] = []
# Dopo un ordine di caccia del magazzino finito senza prede: niente nuove cacce automatiche fino a questo momento (giorni
# di gioco, -1 = nessuna pausa).
var hunt_pause_until: float = -1.0
# Avvisi dell'essiccatoio del magazzino (ricetta -> motivo), ricalcolati a ogni giro.
var dry_warnings: Dictionary = {}
# Regola "Rifornisci le Attrezzerie" (2026-10-18): attrezzo -> pezzi che mancano alle Attrezzerie e nessun magazzino ha,
# ricalcolati a ogni Inventario (avviso in campanella).
var toolkit_warnings: Dictionary = {}
