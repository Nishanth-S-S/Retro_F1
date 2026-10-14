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


func get_part(id: String) -> VehiclePart:
	return _parts.get(id, null)


func has_part(id: String) -> bool:
	return _parts.has(id)


func parts_in(category: String) -> Array[VehiclePart]:
	var empty: Array[VehiclePart] = []
	return _by_category.get(category, empty)


func all_ids() -> Array:
	return _parts.keys()
