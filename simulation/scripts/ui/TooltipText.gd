class_name TooltipText
extends RefCounted

# A capo automatico dei tooltip (2026-10-17, richiesta utente — regola generale): il tooltip di default di Godot non va a
# capo da solo, quindi un testo lungo diventa un'unica riga larghissima e faticosa da leggere. Ogni tooltip_text del
# progetto passa da wrap(): le righe più lunghe di MAX_LINE_CHARS vanno a capo tra una parola e l'altra; i testi corti e
# gli a capo già presenti restano come sono. Una parola più lunga della riga non viene spezzata.

const MAX_LINE_CHARS := 60


static func wrap(text: String, max_chars: int = MAX_LINE_CHARS) -> String:
	if text.length() <= max_chars:
		return text
	var wrapped: PackedStringArray = []
	for line in text.split("\n"):
		if line.length() <= max_chars:
			wrapped.append(line)
			continue
		var current := ""
		for word in line.split(" ", false):
			if current == "":
				current = word
			elif current.length() + 1 + word.length() <= max_chars:
				current += " " + word
			else:
				wrapped.append(current)
				current = word
		wrapped.append(current)
	return "\n".join(wrapped)
