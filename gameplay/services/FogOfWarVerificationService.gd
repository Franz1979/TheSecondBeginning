class_name FogOfWarVerificationService
extends RefCounted

# Verifica se una microcella è visibile con DETTAGLIO sufficiente per essere una fonte valida di
# comando (2026-09-13, richiesta utente — bugfix: _try_assign_pickup_command_on_right_click
# accettava comandi di raccolta anche su celle mai viste/con memoria scaduta, esponendo
# informazioni che il player non dovrebbe avere). Stesso principio "un solo Service stateless per
# compito" già in uso ovunque nel progetto (RefCounted, .new() mai chiamato — solo funzioni
# statiche, stesso pattern di BuildingVerificationService).
#
# STESSA guardia difensiva/STESSA composizione già presente in BuildingVerificationService.
# _is_position_clear (Criterio 2) — quella però consulta is_terrain_fresh (il tier più permissivo,
# per "posso costruire qui": basta conoscere il terreno) e vive annegata dentro una funzione più
# grande specifica del piazzamento edifici, non riusabile da un chiamante generico. Questa classe
# estrae lo STESSO pattern di accesso (live_cells -> cell -> fog_of_war_renderer -> fog_of_war_
# memory) in un punto condiviso, ma con il tier is_detail_fresh (il più stringente, per "questa
# posizione esatta/entità mobile è nota ORA o vista di recente") — quello corretto per comandi che
# dipendono dalla conoscenza precisa di COSA c'è su una singola microcella (es. un lotto di stick,
# una pietra), non solo del terreno che la ospita.
#
# `live_cells`/`macro_coords`/`microcell`/`current_absolute_day` — stessi tipi/stessa provenienza
# già in uso ovunque nel progetto per questo genere di lookup (GameScene.live_cells, coordinate
# macro assolute, coordinate micro locali alla macrocella, game_data.get_absolute_day()) — nessun
# nuovo concetto, solo la composizione in un punto riusabile.
static func is_detail_visible(live_cells: Dictionary, macro_coords: Vector2i, microcell: Vector2i, current_absolute_day: int) -> bool:
	if not live_cells.has(macro_coords):
		return false
	var cell: LiveMacroCell = live_cells[macro_coords]
	if cell.fog_of_war_renderer == null or cell.fog_of_war_renderer.fog_of_war_memory == null:
		return false
	return cell.fog_of_war_renderer.fog_of_war_memory.is_detail_fresh(
		microcell, current_absolute_day, cell.fog_of_war_renderer.detail_memory_days
	)
