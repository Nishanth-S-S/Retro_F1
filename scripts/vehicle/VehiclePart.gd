class_name VehiclePart
extends Resource
## Data-driven vehicle component. Base fields are shared by every part;
## category-specific numbers live in `stats` so new part types need no new code.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var category := ""
@export var price := 0
@export var research_cost := 0
@export var mass := 0.0
@export var unlocked := true
@export var visual_icon := ""
@export var stats: Dictionary = {}


func stat(key: String, fallback: float = 0.0) -> float:
	return float(stats.get(key, fallback))


static func from_dict(data: Dictionary, part_category: String) -> VehiclePart:
	var part := VehiclePart.new()
	part.id = data.get("id", "")
	part.display_name = data.get("display_name", part.id)
	part.description = data.get("description", "")
	part.category = part_category
	part.price = int(data.get("price", 0))
	part.research_cost = int(data.get("research_cost", 0))
	part.mass = float(data.get("mass", 0.0))
	part.unlocked = part.research_cost <= 0
	part.visual_icon = data.get("visual_icon", part_category)
	part.stats = data.get("stats", {})
	return part


## Short human readable stat lines for part cards (pros/cons at a glance).
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	match category:
		"engine":
			lines.append("%d kW  ·  %d rpm" % [stat("power_kw"), stat("redline_rpm")])
			lines.append("Efficiency %d%%  ·  Heat %d%%" % [stat("fuel_efficiency") * 100.0, stat("heat_generation") * 100.0])
			lines.append("Response %d%%" % [stat("throttle_response") * 100.0])
		"gearbox":
			lines.append("Final drive %.2f  ·  Shift %.2fs" % [stat("final_drive"), stat("shift_time")])
			lines.append("Efficiency %d%%" % [stat("efficiency") * 100.0])
		"front_wing", "rear_wing":
			lines.append("Downforce %.2f  ·  Drag %.2f" % [stat("downforce_coefficient"), stat("drag_coefficient")])
			lines.append("Adjust range ±%d%%" % [stat("adjustability") * 100.0])
		"suspension":
			lines.append("Spring %d N/mm  ·  Grip %+.1f%%" % [stat("spring_rate"), (stat("mechanical_grip_modifier") - 1.0) * 100.0])
			lines.append("Response %d%%  ·  Curbs %d%%" % [stat("response_modifier") * 100.0, stat("curb_compliance") * 100.0])
		"brakes":
			lines.append("Force %.1f kN  ·  Heat cap %d%%" % [stat("max_brake_force") / 1000.0, stat("heat_capacity") * 100.0])
		"tires":
			lines.append("Grip %.2f  ·  Wear x%.1f" % [stat("base_grip"), stat("wear_rate")])
			lines.append("Window %d ± %d °C" % [stat("optimal_temperature"), stat("temperature_window")])
		"chassis":
			lines.append("Rigidity %d%%" % [stat("rigidity") * 100.0])
	lines.append("Mass %d kg" % mass)
	return lines
