class_name DroppedWeaponMarker
extends Node2D

# Segnaposto visivo dell'arma scagliata a terra in attesa di recupero (2026-09-26, richiesta utente) — solo
# disegno, come i rametti del cantiere: non è un oggetto del mondo, nessuno può raccoglierlo. Creato e
# rimosso da GameScene._sync_dropped_weapon_markers finché il RecoverWeaponAction del cacciatore è lo step
# corrente. Origine = punto di caduta, in pixel locali della cella.
#
# Stesso disegno e stessa dimensione dell'arma nella griglia del magazzino (MicroCellRenderer.
# _draw_deposit_site_storage_grid): WoodenSpearIcon/StoneKnifeIcon.draw_into in un quadrato di lato
# MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE, centrato sul punto di caduta, senza lo sfondo quadrato.

var weapon_name: String = ""


func setup(p_weapon_name: String, seed_value: int) -> void:
	weapon_name = p_weapon_name
	# Inclinazione stabile per lancio (seed dall'id del cacciatore), non casuale a ogni ridisegno.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	rotation = rng.randf_range(-PI, PI)
	z_index = 1
	queue_redraw()


func _draw() -> void:
	var side: float = MicroCellRenderer.DEPOSIT_SITE_STORAGE_SQUARE_SIDE
	var top_left := Vector2(-side, -side) * 0.5
	match weapon_name:
		"wooden_spear":
			WoodenSpearIcon.draw_into(self, top_left, Vector2(side, side))
		"stone_knife":
			StoneKnifeIcon.draw_into(self, top_left, Vector2(side, side))
		_:
			# Arma futura senza disegno dedicato: stesso ripiego della griglia del magazzino.
			draw_circle(Vector2.ZERO, side * 0.25, IconRegistry.get_resource_color(weapon_name))
