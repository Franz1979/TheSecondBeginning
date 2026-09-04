class_name VegetationInfoPanel
extends VBoxContainer

# Corpo del pannello vegetazione dentro GameInfoPanel.body_container (click-detection su un
# singolo individuo, vedi VegetationSelectorController) — istanziato dinamicamente da GameScene
# (non pre-cablato nel .tscn di GameInfoPanel), stesso principio "muto" di CellGeographyInfo:
# questo componente non conosce MicroCellRenderer/GameScene/selezione, riceve solo dati già
# risolti — nemmeno il taglio vero e proprio (PlayerHarvestService): emette solo cut_requested,
# GameScene decide se/come agire. Nessun tr(): stesso trattamento hardcoded degli altri pannelli
# di ispezione (vedi MacroCellDetailPanel), nessuna CSV di traduzione esiste ancora. Nascosto di
# default (nessuna selezione all'apertura della scena) — il bottone dentro eredita
# automaticamente la non-interagibilità di un nodo nascosto, nessuno stato enabled/disabled
# separato da gestire per "cliccabile solo se selezionato qualcosa".
#
# TypeLabel (Step 6, richiesta utente 2026-09-04): rimossa da qui, sollevata dentro GameInfoTabs.
# title_label — sulla STESSA riga del bottone "🎯" invece che come prima riga di questo pannello.
# GameScene la imposta (game_info_tabs.set_selection_title) subito insieme a show_vegetation/
# show_cut_marker, con la stessa identica stringa che sarebbe finita qui in entrambi i casi.
signal cut_requested

@onready var subtype_label: Label = $SubtypeLabel
@onready var age_label: Label = $AgeLabel
@onready var cut_button: Button = $CutButton


func _ready() -> void:
	cut_button.text = "Cut"
	cut_button.pressed.connect(func(): cut_requested.emit())
	clear()


func show_vegetation(object_type: GameTypes.WorldObjectType, subtype_name: String, age_band: GameTypes.AgeBand, years_lived: int) -> void:
	visible = true
	subtype_label.text = "Subtype: " + subtype_name
	age_label.text = "Age: " + GameTypes.AgeBand.keys()[age_band].capitalize() + " (" + NumberFormatter.format_int(years_lived) + " years)"
	cut_button.visible = true


# Selezionato un ceppo/rovi/marker di morte invece di una pianta viva (vedi GameScene.
# _refresh_vegetation_panel, che decide quale dei due chiamare) — niente sottotipo/età da mostrare
# (dimenticati al momento del blocco, vedi PlayerHarvestService/NaturalMortalityVisualService).
# Bottone Cut nascosto: né un ceppo né una pianta morta sono ritagliabili. Il taglio mostra da
# quanti anni è bloccato (persistente, azione deliberata — vedi IndividualVegetationService.
# REENTRY_YEARS_BY_TYPE); la morte naturale NO: è solo un artificio grafico stagionale senza durata
# tracciata (vedi SeasonCalculator.is_within_natural_death_visibility_window), "quanti anni fa" non
# avrebbe alcun significato da mostrare.
func show_cut_marker(object_type: GameTypes.WorldObjectType, state: String, years_ago: int) -> void:
	visible = true
	if state == "cut":
		subtype_label.text = "Cut " + NumberFormatter.format_int(years_ago) + " years ago"
	else:
		subtype_label.text = "Dead plant"
	age_label.text = ""
	cut_button.visible = false


func clear() -> void:
	visible = false
