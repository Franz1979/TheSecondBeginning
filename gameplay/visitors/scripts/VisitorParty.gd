class_name VisitorParty
extends RefCounted

# Gruppo di visitatori estranei al villaggio (2026-09-27, richiesta utente — infrastruttura dei visitatori).
# Dato di partita (RefCounted, come GroundPile), salvato in GameData.visitor_parties. Finché resta un
# gruppo i membri NON sono HumanIndividual: sono solo descrizioni (vedi `members`), fuori da
# human_individuals e quindi da ogni servizio del villaggio (vitali, fame, statistiche, selezione, comandi).
# Gli individui veri nascono solo all'accoglienza (VisitorService.materialize_members).
#
# Coordinate: microcella continue, locali a `macro_coords` (stesso spazio di HumanIndividual.position).
# Il gruppo vive sempre e solo nella macrocella del villaggio: entra e esce dal suo bordo.

var id: int = 0
var party_type: VisitorTypes.PartyType = VisitorTypes.PartyType.MIGRANTS
var phase: VisitorTypes.Phase = VisitorTypes.Phase.ARRIVING
var macro_coords: Vector2i = Vector2i(-1, -1)
# Posizione del gruppo (centro della formazione) e direzione di marcia.
var position: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var entry_point: Vector2 = Vector2.ZERO
# Uscita: valorizzata al rifiuto (VisitorService.dismiss), prima resta uguale all'ingresso.
var exit_point: Vector2 = Vector2.ZERO
# Destinazione corrente: il centro del villaggio in ARRIVING, l'uscita in LEAVING.
var target_point: Vector2 = Vector2.ZERO

# Descrizione dei membri, un Dictionary per membro:
#   "sex": HumanTypes.Sex, "age": int (età FISSA in anni, l'anno di nascita si calcola solo
#   all'accoglienza), "role": VisitorTypes.MemberRole, "hair_color"/"skin_color"/"clothing_color":
#   tratti d'aspetto (HumanTypes.*), sorteggiati alla creazione così la figura disegnata e l'individuo
#   accolto si somigliano, "offset": Vector2 (posto nella formazione, microcelle, nel riferimento della
#   direzione di marcia: x in avanti, y di lato), "partner_index"/"mother_index"/"father_index": indici
#   in questo stesso array (-1 = nessuno), trasformati in id veri all'accoglienza.
var members: Array[Dictionary] = []


func to_save_data() -> Dictionary:
	var members_data: Array = []
	for member in members:
		var offset: Vector2 = member.get("offset", Vector2.ZERO)
		members_data.append({
			"sex": int(member.get("sex", 0)),
			"age": int(member.get("age", 0)),
			"role": int(member.get("role", 0)),
			"hair_color": int(member.get("hair_color", 0)),
			"skin_color": int(member.get("skin_color", 0)),
			"clothing_color": int(member.get("clothing_color", 0)),
			"offset_x": offset.x,
			"offset_y": offset.y,
			"partner_index": int(member.get("partner_index", -1)),
			"mother_index": int(member.get("mother_index", -1)),
			"father_index": int(member.get("father_index", -1)),
		})
	return {
		"id": id,
		"party_type": int(party_type),
		"phase": int(phase),
		"macro_x": macro_coords.x,
		"macro_y": macro_coords.y,
		"position_x": position.x,
		"position_y": position.y,
		"facing_x": facing_direction.x,
		"facing_y": facing_direction.y,
		"entry_x": entry_point.x,
		"entry_y": entry_point.y,
		"exit_x": exit_point.x,
		"exit_y": exit_point.y,
		"target_x": target_point.x,
		"target_y": target_point.y,
		"members": members_data,
	}


# JSON non distingue int/float: ogni campo intero passa da int(). null se i dati non sono validi.
static func from_save_data(data: Dictionary) -> VisitorParty:
	var raw_members = data.get("members", [])
	if not raw_members is Array or (raw_members as Array).is_empty():
		return null
	var party := VisitorParty.new()
	party.id = int(data.get("id", 0))
	party.party_type = int(data.get("party_type", 0))
	party.phase = int(data.get("phase", 0))
	party.macro_coords = Vector2i(int(data.get("macro_x", -1)), int(data.get("macro_y", -1)))
	party.position = Vector2(float(data.get("position_x", 0.0)), float(data.get("position_y", 0.0)))
	party.facing_direction = Vector2(float(data.get("facing_x", 1.0)), float(data.get("facing_y", 0.0)))
	party.entry_point = Vector2(float(data.get("entry_x", 0.0)), float(data.get("entry_y", 0.0)))
	party.exit_point = Vector2(float(data.get("exit_x", 0.0)), float(data.get("exit_y", 0.0)))
	party.target_point = Vector2(float(data.get("target_x", 0.0)), float(data.get("target_y", 0.0)))
	for raw_member in raw_members:
		if not raw_member is Dictionary:
			continue
		party.members.append({
			"sex": int(raw_member.get("sex", 0)),
			"age": int(raw_member.get("age", 0)),
			"role": int(raw_member.get("role", 0)),
			"hair_color": int(raw_member.get("hair_color", 0)),
			"skin_color": int(raw_member.get("skin_color", 0)),
			"clothing_color": int(raw_member.get("clothing_color", 0)),
			"offset": Vector2(float(raw_member.get("offset_x", 0.0)), float(raw_member.get("offset_y", 0.0))),
			"partner_index": int(raw_member.get("partner_index", -1)),
			"mother_index": int(raw_member.get("mother_index", -1)),
			"father_index": int(raw_member.get("father_index", -1)),
		})
	if party.members.is_empty():
		return null
	return party
