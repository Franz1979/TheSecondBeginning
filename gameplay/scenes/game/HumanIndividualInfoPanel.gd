class_name HumanIndividualInfoPanel
extends VBoxContainer

# Corpo del pannello individuo dentro GameInfoTabs.selection_content — stesso principio "muto" di
# VegetationInfoPanel (istanziato dinamicamente da GameScene, non pre-cablato in nessun .tscn di
# livello superiore): non conosce GameScene/selezione/HumanRules, riceve solo dati già risolti.
# Nessun tr(): stesso trattamento hardcoded di VegetationInfoPanel, nessuna CSV di traduzione
# esiste ancora. Nascosto di default (nessuna selezione all'apertura della scena).
#
# name/sex/età/age_band (Passo 1, 2026-09-01) + id/folk id/group id/mother id/father id/partner
# id (richiesta utente, 2026-09-02 — solo consultazione, nessuna interazione). strength resta
# fuori, non ancora richiesto.
#
# workforce_bar (2026-09-04): display-only, nessun consumo reale ancora esistente (nessuna
# classe Action) — max/residual arrivano già risolti dal chiamante (GameScene, stesso principio
# di age/age_band sopra: questo pannello non conosce HumanRules/HumanCalculator). residual oggi
# coincide sempre col max (nessun campo HumanIndividual.residual_workforce ancora esistente); il
# chiamante è già strutturato in modo che, quando quel campo arriverà, sostituire quell'UNICA
# lettura in GameScene basti — questo pannello resta invariato, prende solo i due float già
# risolti.
#
# Il "🎯 centra" è vissuto qui brevemente (2026-09-04) ma si è spostato di nuovo, stavolta
# nell'header di GameInfoTabs.SelectionTab (Step 3 del piano "centra generalizzato", stessa
# richiesta utente): un bottone condiviso lì funziona per QUALUNQUE cosa sia selezionata
# (individuo, vegetazione, edifici), non solo per l'individuo mostrato da questo pannello — vedi
# GameInfoTabs.center_requested/GameScene._center_camera_on_selection.
#
# NameLabel (Step 6, richiesta utente 2026-09-04): rimossa da qui, sollevata dentro GameInfoTabs.
# title_label — sulla STESSA riga del bottone "🎯" invece che come prima riga di questo pannello
# (richiesta esplicita: il bottone deve leggersi allineato all'inizio delle info). GameScene la
# imposta (game_info_tabs.set_selection_title) subito insieme a questa show_individual, con la
# stessa identica stringa che sarebbe finita qui.

@onready var sex_label: Label = $SexLabel
@onready var age_label: Label = $AgeLabel
@onready var workforce_label: Label = $WorkforceLabel
@onready var workforce_bar: ProgressBar = $WorkforceBarMargin/WorkforceBar
@onready var id_label: Label = $IdLabel
@onready var mother_label: Label = $MotherLabel
@onready var father_label: Label = $FatherLabel
@onready var partner_label: Label = $PartnerLabel


func _ready() -> void:
	clear()


# Prende l'HumanIndividual intero (non piu' i soli name/sex, richiesta utente 2026-09-02: servono
# anche id/mother_id/father_id/partner_id/source_group_ref, tutti gia' sull'oggetto) — age/
# age_band restano calcolati dal chiamante (richiedono current_year/HumanRules, che questo
# pannello non conosce, stesso principio di prima). max_workforce/residual_workforce stesso
# principio: gia' risolti dal chiamante (HumanCalculator.get_base_workforce), vedi commento
# workforce_bar sopra.
func show_individual(
	individual: HumanIndividual, age: int, age_band: HumanTypes.AgeBand,
	max_workforce: float, residual_workforce: float
) -> void:
	visible = true
	sex_label.text = "Sex: " + ("Female" if individual.sex == HumanTypes.Sex.FEMALE else "Male")
	age_label.text = "Age: " + str(age) + " (" + HumanTypes.AgeBand.keys()[age_band].capitalize() + ")"

	workforce_label.text = "Workforce:"
	workforce_bar.max_value = max_workforce
	workforce_bar.value = residual_workforce
	workforce_bar.tooltip_text = "%d/%d" % [int(residual_workforce), int(max_workforce)]

	var group := individual.source_group_ref
	var folk_id: int = group.folk_ref.id if group != null and group.folk_ref != null else -1
	var group_id: int = group.id if group != null else -1
	id_label.text = "ID: %d (Folk %s, Group %s)" % [individual.id, _format_id(folk_id), _format_id(group_id)]
	mother_label.text = "Mother ID: " + _format_id(individual.mother_id)
	father_label.text = "Father ID: " + _format_id(individual.father_id)
	partner_label.text = "Partner ID: " + _format_id(individual.partner_id)


func clear() -> void:
	visible = false


# Sentinella -1 (genitore/gruppo/partner sconosciuto o non applicabile, vedi HumanIndividual) resa
# come "—" invece del numero grezzo — poco leggibile per chi guarda il pannello, "-1" sembra un
# errore piu' che un "non applicabile".
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
