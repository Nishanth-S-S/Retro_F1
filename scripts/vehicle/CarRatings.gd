class_name CarRatings
extends RefCounted
## The car's card: ratings out of 99 in the categories F1 teams talk about, plus an
## overall. Everything comes from CarStats, so every part, wing angle, ride height,
## pressure, anti-roll or body-set change moves the numbers and the overall.

## name, weight in the overall, what it measures.
const CATEGORIES := [
	["POWER", 0.12, "Engine output"],
	["ACCELERATION", 0.08, "Power for the weight"],
	["TOP SPEED", 0.07, "Flat out down the straight"],
	["DOWNFORCE", 0.12, "Aero grip at 200 km/h"],
	["DRAG EFFICIENCY", 0.08, "Downforce for each unit of drag"],
	["CORNERING", 0.12, "Mechanical grip and rotation"],
	["BRAKING", 0.08, "Stopping power from 200 km/h"],
	["BALANCE", 0.09, "Predictable, no under- or oversteer"],
	["WEIGHT", 0.06, "Lighter is quicker everywhere"],
	["TYRE LIFE", 0.08, "How long the tyres last"],
	["AERODYNAMICS", 0.10, "Aero that works at every speed, height and in traffic"],
]

## Upgrade levels also show on the card directly: what each level adds to a rating on top of
## the physics change (better brake cooling, suspension kinematics, quicker shifts...).
const DEV_RATING := {"brakes": [["BRAKING", 4]], "suspension": [["CORNERING", 3]], "gearbox": [["ACCELERATION", 4]],
	"front_wing": [["AERODYNAMICS", 2]], "rear_wing": [["AERODYNAMICS", 2]]}
## Overall points per upgrade level of any part type, so every package shows up in the overall.
const DEV_OVERALL := 1.0


static func _scale(value: float, low: float, high: float) -> int:
	return clampi(int(round(40.0 + 59.0 * inverse_lerp(low, high, value))), 30, 99)


## {"ratings": [[name, value, detail]], "overall": int, "overall_raw": float}
static func compute(setup: CarSetup, stats: CarStats) -> Dictionary:
	var g := VehiclePhysicsConfig.GRAVITY
	var q := 0.5 * 1.225 * 55.56 * 55.56
	var drag := q * stats.drag_area
	var cornering := stats.mech_grip_g + stats.downforce_200 / (stats.mass * g) * 0.5
	var tires := setup.part("tires")
	var wear := (tires.stat("wear_rate", 1.0) if tires else 1.0) * (1.0 - (setup.tyre_pressure - 5) * 0.04)
	var values := {
		"POWER": [_scale(stats.power_kw, 200.0, 400.0), "%d kW" % int(stats.power_kw)],
		"ACCELERATION": [_scale(stats.power_to_weight, 250.0, 560.0), "%d kW/t  ·  0-100 %.1f s" % [int(stats.power_to_weight), stats.accel_0_100]],
		"TOP SPEED": [_scale(stats.top_speed * 3.6, 220.0, 320.0), "%d km/h" % int(stats.top_speed * 3.6)],
		"DOWNFORCE": [_scale(stats.downforce_200, 2500.0, 8500.0), "%d N" % int(stats.downforce_200)],
		"DRAG EFFICIENCY": [_scale(stats.downforce_200 / maxf(drag, 1.0), 1.8, 3.6), "L/D %.2f" % (stats.downforce_200 / maxf(drag, 1.0))],
		"CORNERING": [_scale(cornering, 1.5, 2.4), "%.2f g" % cornering],
		"BRAKING": [_scale(stats.braking_g, 1.9, 3.3), "%.2f g" % stats.braking_g],
		"BALANCE": [clampi(int(round(99.0 - absf(stats.balance_index) * 650.0)), 30, 99), stats.balance_label()],
		"WEIGHT": [_scale(-stats.mass, -760.0, -600.0), "%d kg" % int(stats.mass)],
		"TYRE LIFE": [_scale(-wear, -3.5, -0.15), "wear x%.1f" % wear],
		"AERODYNAMICS": [_scale(aero_consistency(setup, stats), 0.35, 1.0), "%d%% consistent" % int(round(aero_consistency(setup, stats) * 100.0))],
	}
	var levels := 0
	for cat: String in setup.dev:
		levels += setup.level(cat)
		for boost: Array in DEV_RATING.get(cat, []):
			var v: Array = values[boost[0]]
			v[0] = mini(99, int(v[0]) + int(boost[1]) * setup.level(cat))
	var ratings: Array = []
	var total := 0.0
	for c: Array in CATEGORIES:
		var v: Array = values[c[0]]
		ratings.append([c[0], int(v[0]), str(v[1]), c[2]])
		total += float(v[0]) * float(c[1])
	total = minf(99.0, total + levels * DEV_OVERALL)
	return {"ratings": ratings, "overall": int(round(total)) if stats.valid else 30, "overall_raw": total if stats.valid else 30.0}


## 0..1: how reliably the aero works across speeds, ride heights and in dirty air. Loses out
## for an aero balance that moves between slow and fast corners, a ride height low enough to
## stall the floor, wings fighting each other, and body sets that are sensitive in traffic.
const BODY_AERO_RISK := {"modern": 0.0, "classic70": 0.04, "turbo80": 0.05, "wedge90": 0.03, "winglet00": 0.12, "ground22": 0.10, "streamliner": 0.06}


static func aero_consistency(setup: CarSetup, stats: CarStats) -> float:
	var migration := clampf(absf(stats.balance_high - stats.balance_low) / 0.12, 0.0, 1.0)
	var stall := clampf((4.0 - float(setup.ride_height)) / 3.0, 0.0, 1.0)
	var mismatch := clampf(absf(float(setup.front_wing_angle - setup.rear_wing_angle)) / 8.0, 0.0, 1.0)
	var q := 0.5 * 1.225 * 55.56 * 55.56
	var efficiency := clampf(inverse_lerp(1.8, 3.6, stats.downforce_200 / maxf(q * stats.drag_area, 1.0)), 0.0, 1.0)
	var score := 0.9 - 0.25 * migration - 0.22 * stall - 0.15 * mismatch - float(BODY_AERO_RISK.get(setup.body, 0.0)) + 0.15 * efficiency
	return clampf(score, 0.0, 1.0)
