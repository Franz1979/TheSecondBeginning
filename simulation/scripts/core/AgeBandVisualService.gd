class_name AgeBandVisualService
extends RefCounted

# Stima di rendering, non simulazione: nessuna posizione microcella è persistita su disco per le
# risorse rinnovabili con sottotipi (vedi VegetationPositionService, rigenerate ogni anno), quindi
# non esiste un vero "anno di nascita" da tracciare per individuo. compute_virtual_birth_year
# approssima un anno di nascita plausibile per-posizione dai ratio young/adult/old REALI della
# cella (age_composition) — usata dal chiamante (MicroCellRenderer._resolve_age_band_and_size,
# condivisa da SHRUB e TREE) SOLO come stima "al buio" per il primo sguardo assoluto a una
# macrocella in una sessione,
# quando non c'è ancora nessuna cache di posizioni viste in anni precedenti a cui appoggiarsi.
# Da quel momento in poi il chiamante tiene fisso l'anno di nascita di ogni posizione già vista
# (mai ricalcolato da qui) e assegna l'anno corrente a ogni posizione genuinamente nuova — così
# la crescita di quest'anno risulta sempre YOUNG per costruzione, coerente con
# MacroCellState.add_age_band_gain, invece di dipendere dal caso dell'hash.
#
# band_for_age è invece un puro confronto a soglie, indipendente da come years_lived è stato
# ottenuto: quando in futuro le posizioni verranno persistite con un vero anno di nascita (LOD
# massimo, individui cliccabili), quella funzione si riusa identica — solo la stima "al buio"
# di compute_virtual_birth_year verrà sostituita da un anno di nascita reale persistito.

# Coda visiva oltre la soglia OLD, usata solo per dare varietà interna a compute_virtual_birth_year
# (OLD non ha comunque un tetto d'età: band_for_age tratta tutto ciò che è oltre la soglia come
# OLD a prescindere da quanto la coda si estenda).
const OLD_VISUAL_TAIL_YEARS: float = 10.0
const _EPS: float = 0.0001


# Anno di nascita virtuale stabile per (pos, salt): calibrato sui ratio [young, adult, old]
# correnti (non necessariamente normalizzati a somma 1, vengono normalizzati qui) in modo che,
# su molte posizioni, la distribuzione delle fasce risultante rispecchi statisticamente quei
# ratio. ratios vuoto o somma <= 0 => ripiega su terzi uguali (stesso idioma di fallback usato
# altrove per composizioni non tracciate).
static func compute_virtual_birth_year(
	pos: Vector2i,
	salt: Vector2i,
	index: int,
	current_year: int,
	youth_duration_years: int,
	adult_duration_years: int,
	ratios: Array
) -> int:
	var young_ratio: float = ratios[0] if ratios.size() > 0 else 1.0 / 3.0
	var adult_ratio: float = ratios[1] if ratios.size() > 1 else 1.0 / 3.0
	var old_ratio: float = ratios[2] if ratios.size() > 2 else 1.0 / 3.0

	var total: float = young_ratio + adult_ratio + old_ratio
	if total <= 0.0:
		young_ratio = 1.0 / 3.0
		adult_ratio = 1.0 / 3.0
		old_ratio = 1.0 / 3.0
	else:
		young_ratio /= total
		adult_ratio /= total
		old_ratio /= total

	var percentile: float = _stable_percentile(pos, salt, index)

	var age: float
	if percentile < young_ratio:
		var t: float = percentile / max(young_ratio, _EPS)
		age = t * float(youth_duration_years)
	elif percentile < young_ratio + adult_ratio:
		var t: float = (percentile - young_ratio) / max(adult_ratio, _EPS)
		age = float(youth_duration_years) + t * float(adult_duration_years)
	else:
		var t: float = (percentile - young_ratio - adult_ratio) / max(old_ratio, _EPS)
		age = float(youth_duration_years) + float(adult_duration_years) + t * OLD_VISUAL_TAIL_YEARS

	return current_year - int(floor(age))


# Fascia età da anni vissuti, indipendente da come years_lived è stato ottenuto — vedi commento
# di testa. OLD non ha mai un limite superiore: nessun "tetto" oltre cui una posizione smette di
# essere OLD, la morte reale è già gestita per intero da ResourceMortalityService.
static func band_for_age(years_lived: int, youth_duration_years: int, adult_duration_years: int) -> GameTypes.AgeBand:
	if years_lived < youth_duration_years:
		return GameTypes.AgeBand.YOUNG
	if years_lived < youth_duration_years + adult_duration_years:
		return GameTypes.AgeBand.ADULT
	return GameTypes.AgeBand.OLD


# Stesso pattern hash-vs-100000 usato per i test hash-based posizionalmente stabili di
# IndividualVegetationService (es. _resolve_new_shrub_subtype), qui isolato perché riusato da
# compute_virtual_birth_year indipendentemente da chi decide il sottotipo. `index` (granularità per-individuo,
# vedi IndividualVegetationService) è il solo termine che distingue due individui nello stesso
# lotto/microcella `pos`: senza di esso condividerebbero lo stesso percentile e quindi la stessa
# età stimata al primo sguardo.
static func _stable_percentile(pos: Vector2i, salt: Vector2i, index: int) -> float:
	return float(hash(pos * salt.x + Vector2i(salt.y, index)) % 100000) / 100000.0
