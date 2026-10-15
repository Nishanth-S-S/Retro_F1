class_name CarSetup
extends RefCounted
## The player's (or an AI's) build: which part sits in which hardpoint plus the tunable settings.
## Pure data - CarStats turns it into numbers, VehiclePhysics turns those into behaviour.

const SLOTS: PackedStringArray = ["chassis", "front_wing", "rear_wing", "engine", "gearbox", "front_suspension", "rear_suspension", "brakes", "tires", "ballast"]
const REQUIRED_SLOTS: PackedStringArray = ["chassis", "engine", "gearbox", "front_wing", "rear_wing", "front_suspension", "rear_suspension", "brakes", "tires"]
const SLOT_CATEGORY := {
	"chassis": "chassis", "front_wing": "front_wing", "rear_wing": "rear_wing", "engine": "engine", "gearbox": "gearbox",
	"front_suspension": "suspension", "rear_suspension": "suspension", "brakes": "brakes", "tires": "tires", "ballast": "ballast",
}
const SLOT_LABELS := {
	"chassis": "Chassis", "front_wing": "Front Wing", "rear_wing": "Rear Wing", "engine": "Engine", "gearbox": "Gearbox",
	"front_suspension": "Front Suspension", "rear_suspension": "Rear Suspension", "brakes": "Brakes", "tires": "Tires", "ballast": "Ballast",
}
## Longitudinal position of each hardpoint in metres ahead of the rear axle (front axle = wheelbase).
const SLOT_POSITION := {
	"chassis": 1.68, "front_wing": 3.85, "rear_wing": -0.5, "engine": 0.78, "gearbox": 0.12,
	"front_suspension": 3.0, "rear_suspension": 0.0, "brakes": 1.5, "tires": 1.4,
}
const BALLAST_FRONT_X := 3.3
const BALLAST_REAR_X := -0.2
const BALLAST_STEPS := 6
const WING_ANGLE_MIN := 1
const WING_ANGLE_MAX := 10
## Body sets: the shape of the bodywork. Each trades downforce against drag.
const BODY_SETS := {
	"modern": {"name": "MODERN", "downforce": 1.0, "drag": 1.0},
	"classic70": {"name": "70s CLASSIC", "downforce": 0.88, "drag": 0.93},
	"turbo80": {"name": "80s TURBO", "downforce": 0.94, "drag": 0.96},
	"wedge90": {"name": "90s WEDGE", "downforce": 0.97, "drag": 0.95},
	"winglet00": {"name": "00s WINGLETS", "downforce": 1.08, "drag": 1.07},
	"ground22": {"name": "GROUND EFFECT", "downforce": 1.05, "drag": 1.01},
	"streamliner": {"name": "STREAMLINER", "downforce": 0.84, "drag": 0.86},
}

var parts: Dictionary = {}
var front_wing_angle := 5
var rear_wing_angle := 5
var brake_bias := 0.56
## 0 = fully forward, 1 = fully rearward.
var ballast_position := 0.6
## 1 = slammed (more downforce, harsh over curbs) .. 10 = high.
var ride_height := 5
## 1 = soft (more grip, slow to warm, wears) .. 10 = hard (warms fast, less grip).
var tyre_pressure := 5
## -5 = soft front / stiff rear (more oversteer) .. +5 = stiff front (more understeer).
var anti_roll := 0
var body := "modern"
## Upgrade levels per part type (see GameManager.DEV_CATEGORIES). Empty for rival cars.
var dev: Dictionary = {}


func level(category: String) -> int:
	return int(dev.get(category, 0))


func part(slot: String) -> VehiclePart:
	var id: String = parts.get(slot, "")
	if id == "":
		return null
	return PartDB.get_part(id)


func install(slot: String, part_id: String) -> void:
	parts[slot] = part_id


func remove(slot: String) -> void:
	parts.erase(slot)


func ballast_x() -> float:
	return lerpf(BALLAST_FRONT_X, BALLAST_REAR_X, ballast_position)


func missing_slots() -> PackedStringArray:
	var missing := PackedStringArray()
	for slot in REQUIRED_SLOTS:
		if part(slot) == null:
			missing.append(slot)
	return missing


func duplicate_setup() -> CarSetup:
	return CarSetup.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"parts": parts.duplicate(),
		"front_wing_angle": front_wing_angle,
		"rear_wing_angle": rear_wing_angle,
		"brake_bias": brake_bias,
		"ballast_position": ballast_position,
		"ride_height": ride_height,
		"tyre_pressure": tyre_pressure,
		"anti_roll": anti_roll,
		"body": body,
		"dev": dev.duplicate(),
	}


static func from_dict(data: Dictionary) -> CarSetup:
	var setup := CarSetup.new()
	var saved_parts: Variant = data.get("parts", {})
	if saved_parts is Dictionary:
		for slot: Variant in saved_parts:
			var id: String = str(saved_parts[slot])
			if SLOT_CATEGORY.has(slot) and PartDB.has_part(id) and PartDB.get_part(id).category == SLOT_CATEGORY[slot]:
				setup.parts[slot] = id
	setup.front_wing_angle = clampi(int(data.get("front_wing_angle", 5)), WING_ANGLE_MIN, WING_ANGLE_MAX)
	setup.rear_wing_angle = clampi(int(data.get("rear_wing_angle", 5)), WING_ANGLE_MIN, WING_ANGLE_MAX)
	setup.brake_bias = clampf(float(data.get("brake_bias", 0.56)), 0.4, 0.75)
	setup.ballast_position = clampf(float(data.get("ballast_position", 0.6)), 0.0, 1.0)
	setup.ride_height = clampi(int(data.get("ride_height", 5)), 1, 10)
	setup.tyre_pressure = clampi(int(data.get("tyre_pressure", 5)), 1, 10)
	setup.anti_roll = clampi(int(data.get("anti_roll", 0)), -5, 5)
	setup.body = str(data.get("body", "modern")) if BODY_SETS.has(str(data.get("body", "modern"))) else "modern"
	var levels: Variant = data.get("dev", {})
	setup.dev = (levels as Dictionary).duplicate() if levels is Dictionary else {}
	return setup
