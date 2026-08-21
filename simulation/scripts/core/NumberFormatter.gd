class_name NumberFormatter
extends RefCounted

# Formatta un intero con separatore delle migliaia in convenzione italiana (punto, non
# virgola): 1054354 -> "1.054.354". Usato dai pannelli info (MacroCellDetailPanel,
# MacroCellInfoPanel) per rendere leggibili le quantità di risorsa, che su celle dense possono
# facilmente superare le migliaia.
static func format_int(value: int) -> String:
	var is_negative := value < 0
	var digits := str(abs(value))

	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "." + grouped

	return ("-" if is_negative else "") + grouped
