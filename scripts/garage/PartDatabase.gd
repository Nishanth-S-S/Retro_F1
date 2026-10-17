extends Node
## Autoload "PartDB". Loads every VehiclePart from res://data/parts/<category>.json.

const CATEGORIES: PackedStringArray = ["chassis", "engine", "gearbox", "front_wing", "rear_wing", "suspension", "brakes", "tires", "ballast"]
const CATEGORY_LABELS := {
	"chassis": "CHASSIS", "engine": "ENGINE", "gearbox": "GEARBOX", "front_wing": "FRONT WING", "rear_wing": "REAR WING",
	"suspension": "SUSPENSION", "brakes": "BRAKES", "tires": "TIRES", "ballast": "BALLAST",
}

var _parts: Dictionary = {}          # id -> VehiclePart
var _by_category: Dictionary = {}    # category -> Array[VehiclePart]


func _ready() -> void:
	for category in CATEGORIES:
		var list: Array[VehiclePart] = []
		var data: Variant = SaveManager.load_json("res://data/parts/%s.json" % category)
		if data is Array:
			for entry: Variant in data:
				if entry is Dictionary:
					var part := VehiclePart.from_dict(entry, category)
					_parts[part.id] = part
					list.append(part)
		_by_category[category] = list


## Adds (or replaces) a part designed during a save, e.g. an engine your engineers built.
func register(entry: Dictionary, category: String) -> VehiclePart:
	var part := VehiclePart.from_dict(entry, category)
	var list: Array = _by_category.get(category, [])
	if _parts.has(part.id):
		list.erase(_parts[part.id])
	_parts[part.id] = part
	list.append(part)
	return part


## Removes the parts a save designed (when another save loads).
func clear_custom() -> void:
	for id: String in _parts.keys():
		var part: VehiclePart = _parts[id]
		if part.id.begins_with("custom_"):
			(_by_category.get(part.category, []) as Array).erase(part)
			_parts.erase(id)


func get_part(id: String) -> VehiclePart:
	return _parts.get(id, null)


func has_part(id: String) -> bool:
	return _parts.has(id)


func parts_in(category: String) -> Array[VehiclePart]:
	var empty: Array[VehiclePart] = []
	return _by_category.get(category, empty)


func all_ids() -> Array:
	return _parts.keys()
