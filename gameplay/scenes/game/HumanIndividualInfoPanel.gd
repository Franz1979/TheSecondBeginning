class_name HumanIndividualInfoPanel
extends VBoxContainer

# Corpo del pannello individuo dentro GameInfoTabs.selection_content — stesso principio "muto" di
# VegetationInfoPanel (istanziato dinamicamente da GameScene, non pre-cablato in nessun .tscn di
# livello superiore): non conosce GameScene/selezione/HumanRules, riceve solo dati già risolti.
# Label tr()-wrapped (richiesta utente 2026-09-06, insieme a VegetationInfoPanel/
# DeadBodyInfoPanel): solo le chiavi, nessuna riga aggiunta ancora a strings.csv/
# strings.it.translation — pronte per quando le traduzioni arriveranno. Nascosto di default
# (nessuna selezione all'apertura della scena).
#
# name/sex/età/age_band (Passo 1, 2026-09-01) + id/folk id/group id/mother id/father id/partner
# id (richiesta utente, 2026-09-02 — solo consultazione, nessuna interazione). strength resta
# fuori, non ancora richiesto.
#
# stamina_bar (2026-09-04, rinominato da workforce_bar il 2026-09-06 — rename completo Workforce->
# Stamina, richiesta utente, nessuna modifica di comportamento): display-only, nessun consumo
# reale ancora esistente (nessuna classe Action) — max/current arrivano già risolti dal chiamante
# (GameScene, stesso principio di age/age_band sopra: questo pannello non conosce HumanRules/
# HumanCalculator). current oggi coincide sempre col max (nessun campo HumanIndividual.
# current_stamina ancora esistente); il chiamante è già strutturato in modo che, quando quel campo
# arriverà, sostituire quell'UNICA lettura in GameScene basti — questo pannello resta invariato,
# prende solo i due float già risolti.
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
#
# KillButton (Step 9d del piano mortalità, 2026-09-05) — tasto di DEBUG per velocizzare i test
# ("Kill (debug)", non una vera meccanica di gioco): emette kill_requested con l'individuo
# attualmente mostrato (_current_individual, salvato da show_individual — stesso principio di
# HumanPopulationInfoPanel.individual_center_requested, che porta il payload direttamente nel
# segnale invece di far riscandire GameScene per is_selected). GameScene decide se/come agire
# (GameTimeService.kill_individual_now), questo pannello resta "muto" come il resto.
signal kill_requested(individual: HumanIndividual)

@onready var sex_label: Label = $SexLabel
@onready var age_label: Label = $AgeLabel
@onready var activity_label: Label = $ActivityLabel
@onready var stamina_label: Label = $StaminaLabel
@onready var stamina_bar: ProgressBar = $StaminaBarMargin/StaminaBar
@onready var id_label: Label = $IdLabel
@onready var mother_label: Label = $MotherLabel
@onready var father_label: Label = $FatherLabel
@onready var partner_label: Label = $PartnerLabel
@onready var kill_button: Button = $KillButton

var _current_individual: HumanIndividual


func _ready() -> void:
	kill_button.text = tr("individual_kill_debug_button")
	kill_button.pressed.connect(func(): kill_requested.emit(_current_individual))
	clear()


# Prende l'HumanIndividual intero (non piu' i soli name/sex, richiesta utente 2026-09-02: servono
# anche id/mother_id/father_id/partner_id/source_group_ref, tutti gia' sull'oggetto) — age/
# age_band restano calcolati dal chiamante (richiedono current_year/HumanRules, che questo
# pannello non conosce, stesso principio di prima). max_stamina/current_stamina stesso
# principio: gia' risolti dal chiamante (HumanCalculator.get_max_stamina), vedi commento
# stamina_bar sopra.
#
# activity_text (2026-09-07, richiesta utente — "cosa sta facendo questo individuo") già risolto e
# tr()-ato dal chiamante (GameScene, via HumanIndividual.current_task.get_activity_description() o
# la stringa "a riposo" se current_task è null) — stesso identico principio "questo pannello riceve
# solo dati già pronti" di ogni altro parametro qui.
func show_individual(
	individual: HumanIndividual, age: int, age_band: HumanTypes.AgeBand,
	max_stamina: float, current_stamina: float, activity_text: String
) -> void:
	visible = true
	_current_individual = individual
	sex_label.text = tr("sex_label").format({"sex": tr("sex_female") if individual.sex == HumanTypes.Sex.FEMALE else tr("sex_male")})
	# Incinta sulla STESSA riga dell'age_band (richiesta utente, 2026-09-06) — non più una
	# PregnantLabel separata sotto: appesa al valore di {band} invece che a un nodo/riga a parte.
	var band_text: String = HumanTypes.AgeBand.keys()[age_band].capitalize()
	if individual.is_pregnant:
		band_text += ", " + tr("pregnant")
	age_label.text = tr("individual_age_label").format({"age": age, "band": band_text})
	activity_label.text = activity_text

	stamina_label.text = tr("individual_stamina_label")
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	stamina_bar.tooltip_text = "%d/%d" % [int(current_stamina), int(max_stamina)]

	var group := individual.source_group_ref
	var folk_id: int = group.folk_ref.id if group != null and group.folk_ref != null else -1
	var group_id: int = group.id if group != null else -1
	id_label.text = tr("individual_id_label").format({"id": individual.id, "folk": _format_id(folk_id), "group": _format_id(group_id)})
	mother_label.text = tr("individual_mother_id_label").format({"id": _format_id(individual.mother_id)})
	father_label.text = tr("individual_father_id_label").format({"id": _format_id(individual.father_id)})
	partner_label.text = tr("individual_partner_id_label").format({"id": _format_id(individual.partner_id)})


func clear() -> void:
	visible = false
	_current_individual = null


# Sentinella -1 (genitore/gruppo/partner sconosciuto o non applicabile, vedi HumanIndividual) resa
# come "—" invece del numero grezzo — poco leggibile per chi guarda il pannello, "-1" sembra un
# errore piu' che un "non applicabile".
func _format_id(value: int) -> String:
	return "—" if value < 0 else str(value)
