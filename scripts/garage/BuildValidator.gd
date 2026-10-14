class_name BuildValidator
extends RefCounted
## Checks whether a CarSetup is complete enough to leave the garage.


static func is_ready(setup: CarSetup) -> bool:
	return setup.missing_slots().is_empty()


static func missing_labels(setup: CarSetup) -> PackedStringArray:
	var labels := PackedStringArray()
	for slot in setup.missing_slots():
		labels.append(CarSetup.SLOT_LABELS[slot])
	return labels


static func report(setup: CarSetup) -> String:
	var missing := missing_labels(setup)
	if missing.is_empty():
		return ""
	var text := "CAR NOT READY\n\nMissing:"
	for label in missing:
		text += "\n•  " + label
	return text
