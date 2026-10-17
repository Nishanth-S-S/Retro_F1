class_name DriverPerformance
extends RefCounted
## How much of the car a driver can use. The car sets the ceiling (power, grip, downforce,
## brakes, mass); the driver's attributes decide how much of it is reachable. Player and AI
## cars use exactly the same numbers, so picking a driver changes how the car drives even when
## you are at the wheel.
##
## Calculation order, applied by VehiclePhysics every step:
##   1. car specification and setup (CarStats)
##   2. track surface, weather and tyres (grip coefficient, grip_scale)
##   3. driver baseline extraction (pace, consistency, starts, wet weather) - this class
##   4. one bounded traffic-execution adjustment (racecraft / overtaking / defending)
##   5. fatigue (fitness, race progress, exertion) and morale
##   6. final clamp: no multiplier ever goes above 1.0, so nobody beats the car's ceiling
##
## Nothing here touches engine output, top speed or mass: on a long straight with enough
## traction every driver reaches the same speed. Nothing is random either - no steering
## errors, no input lag, no phantom braking. The overall rating is never used.

## INITIAL TUNING VALUES. Each pair is [rating 60 or below, rating 99]; tune them against the
## lap times DriverPerfTest measures.
const CONFIG := {
	"grip": [0.86, 1.00],                 # pace: usable lateral grip (tuned from 0.88: 95 vs 70 measured 3.7%)
	"traction": [0.90, 1.00],             # pace: usable driven-wheel traction
	"braking": [0.86, 1.00],              # consistency: usable braking grip (tuned from 0.88)
	"brake_window": [0.65, 1.00],         # consistency: room to over-brake before a lock
	"forgiveness": [0.65, 1.00],          # consistency: room to over-throttle before wheelspin
	"launch": [0.80, 1.00],               # starts: traction off the line
	"launch_tolerance": [0.60, 1.00],     # starts: wheelspin forgiveness off the line
	"launch_fade": [12.0, 30.0],          # m/s: launch effects blend out between these speeds
	"wear": [1.35, 0.85],                 # tyre care: multiplier on tyre wear
	"wet_grip": [0.78, 1.00],             # wet weather: grip on a fully wet track
	"fatigue_rate": [1.00, 0.25],         # fitness: fatigue at full race distance
	"fatigue_grip": 0.06,                 # at full fatigue: lateral grip lost
	"fatigue_brake": 0.08,                # at full fatigue: braking lost
	"fatigue_forgiveness": 0.15,          # at full fatigue: input forgiveness lost
	"exertion": [0.8, 1.25],              # gentle driving to flat out
	"exertion_time": 40.0,                # s: how slowly exertion follows the driving
	"morale": [0.98, 1.02],               # morale 0 to 100: one execution factor
	"traffic_penalty": 0.25,              # forgiveness a 60-rated racer loses wheel to wheel
	"traffic_range": 22.0,                # m: how close counts as racing another car
	"traffic_close": 5.0,                 # m: full effect at this distance
	"window_sensitivity": 0.4,            # how sharply a narrow window turns over-demand into a lock
	"race_length_wear_scale": 1.0,        # raise for very short races so tyre care still shows
}
## Used for any attribute a driver does not have (free play, test drives).
const DEFAULT_RATING := 85.0
## Development presets for comparing drivers in the same car (DebugOverlay, F7).
const PRESETS: PackedInt32Array = [70, 85, 95]
const KEYS: PackedStringArray = ["pace", "consistency", "starts", "racecraft", "overtaking", "defending", "tyres", "wet", "fitness"]

## Development override for the player's car: 0 = off, otherwise every attribute at this value.
static var dev_preset := 0

var attributes: Dictionary = {}
## Baseline extraction (attributes only, step 3).
var grip_extraction := 1.0
var traction_extraction := 1.0
var braking_extraction := 1.0
var brake_window := 1.0
var traction_forgiveness := 1.0
var launch_efficiency := 1.0
var launch_tolerance := 1.0
var wear_multiplier := 1.0
var wet_extraction := 1.0
var fatigue_rate := 0.25
var morale_modifier := 1.0

# --- live state
var fatigue := 0.0                    # 0..1
var traffic := 0.0                    # 0..1: how much close racing is costing right now
var launch := 0.0                     # 0..1: launch phase weight
var wetness := 0.0                    # 0..1
var _exertion := 1.0

# --- outputs used by VehiclePhysics (all <= 1.0)
var lateral := 1.0                    # multiplies lateral grip
var braking := 1.0                    # multiplies the braking grip budget
var traction := 1.0                   # multiplies the driving grip budget
var wet_grip := 1.0                   # multiplies all grip on a wet track
var lock_sensitivity := 1.0           # >= 1: over-braking locks sooner
var spin_sensitivity := 1.0           # >= 1: over-throttle spins sooner


## 60 -> 0, 70 -> 0.26, 80 -> 0.51, 90 -> 0.77, 99 -> 1. Below 60 shares the minimum.
static func q(stat: float) -> float:
	return clampf((stat - 60.0) / 39.0, 0.0, 1.0)


static func _range(key: String, stat: float) -> float:
	var pair: Array = CONFIG[key]
	return lerpf(float(pair[0]), float(pair[1]), q(stat))


## Every attribute at one value: the development presets.
static func preset(value: float) -> Dictionary:
	var out := {"morale": 70.0, "ego": 50.0}
	for key: String in KEYS:
		out[key] = value
	return out


func configure(attrs: Dictionary) -> void:
	attributes = {}
	for key: String in KEYS:
		attributes[key] = clampf(float(attrs.get(key, DEFAULT_RATING)), 1.0, 99.0)
	attributes["morale"] = clampf(float(attrs.get("morale", 70.0)), 0.0, 100.0)
	attributes["ego"] = float(attrs.get("ego", 50.0))       # team orders and contracts only
	var a := attributes
	grip_extraction = _range("grip", a["pace"])
	traction_extraction = _range("traction", a["pace"])
	braking_extraction = _range("braking", a["consistency"])
	brake_window = _range("brake_window", a["consistency"])
	traction_forgiveness = _range("forgiveness", a["consistency"])
	launch_efficiency = _range("launch", a["starts"])
	launch_tolerance = _range("launch_tolerance", a["starts"])
	wear_multiplier = _range("wear", a["tyres"]) * float(CONFIG["race_length_wear_scale"])
	wet_extraction = _range("wet_grip", a["wet"])
	fatigue_rate = _range("fatigue_rate", a["fitness"])
	var m: Array = CONFIG["morale"]
	morale_modifier = lerpf(float(m[0]), float(m[1]), a["morale"] / 100.0)
	fatigue = 0.0
	traffic = 0.0
	launch = 0.0
	_exertion = 1.0
	_refresh()


## `race_progress` 0..1 (negative outside a race), `usage` how hard the tyres are worked
## (0..1+), `closeness` 0..1 from the nearest car, `attack` / `defend` 0..1 blends.
func update(delta: float, race_progress: float, usage: float, speed: float, closeness: float, attack: float, defend: float) -> void:
	# Exertion follows the driving slowly, so fatigue never jumps.
	var ex: Array = CONFIG["exertion"]
	var target := lerpf(float(ex[0]), float(ex[1]), clampf(usage, 0.0, 1.0))
	_exertion = lerpf(_exertion, target, minf(1.0, delta / float(CONFIG["exertion_time"])))
	fatigue = clampf(race_progress * fatigue_rate * _exertion, 0.0, 1.0) if race_progress > 0.0 else 0.0
	# One traffic skill, blended between plain racecraft, attacking and defending.
	var a := attributes
	var skill := float(a["racecraft"])
	skill = lerpf(skill, (float(a["racecraft"]) + float(a["overtaking"])) * 0.5, clampf(attack, 0.0, 1.0))
	skill = lerpf(skill, (float(a["racecraft"]) + float(a["defending"])) * 0.5, clampf(defend, 0.0, 1.0))
	traffic = clampf(closeness, 0.0, 1.0) * (1.0 - q(skill))
	if launch > 0.0:
		var fade: Array = CONFIG["launch_fade"]
		launch = minf(launch, 1.0 - smoothstep(float(fade[0]), float(fade[1]), speed))
	_refresh()


## The car is on the grid and the lights went out.
func begin_launch() -> void:
	launch = 1.0
	_refresh()


func _refresh() -> void:
	wet_grip = lerpf(1.0, wet_extraction, clampf(wetness, 0.0, 1.0))
	lateral = minf(1.0, grip_extraction * (1.0 - float(CONFIG["fatigue_grip"]) * fatigue) * morale_modifier)
	braking = minf(1.0, braking_extraction * (1.0 - float(CONFIG["fatigue_brake"]) * fatigue) * morale_modifier)
	traction = minf(1.0, traction_extraction * lerpf(1.0, launch_efficiency, launch) * morale_modifier)
	# Forgiveness: consistency, eaten into by fatigue and by close racing (once, bounded).
	var keep := (1.0 - float(CONFIG["fatigue_forgiveness"]) * fatigue) * (1.0 - float(CONFIG["traffic_penalty"]) * traffic)
	var window := clampf(brake_window * keep, 0.3, 1.0)
	var forgive := clampf(traction_forgiveness * lerpf(1.0, launch_tolerance, launch) * keep, 0.3, 1.0)
	lock_sensitivity = 1.0 + float(CONFIG["window_sensitivity"]) * (1.0 - window)
	spin_sensitivity = 1.0 + float(CONFIG["window_sensitivity"]) * (1.0 - forgive)


## Plain-language effects for the driver screens: [label, value text, 0..1 for a bar].
func effects() -> Array:
	return [
		["CORNERING GRIP", "%d%%" % int(round(grip_extraction * 100.0)), inverse_lerp(0.86, 1.0, grip_extraction)],
		["BRAKING", "%d%%" % int(round(braking_extraction * 100.0)), inverse_lerp(0.86, 1.0, braking_extraction)],
		["TRACTION", "%d%%" % int(round(traction_extraction * 100.0)), inverse_lerp(0.9, 1.0, traction_extraction)],
		["LAUNCH", "%d%%" % int(round(launch_efficiency * 100.0)), inverse_lerp(0.8, 1.0, launch_efficiency)],
		["TYRE WEAR", "x%.2f" % wear_multiplier, inverse_lerp(1.35, 0.85, wear_multiplier)],
		["WET GRIP", "%d%%" % int(round(wet_extraction * 100.0)), inverse_lerp(0.78, 1.0, wet_extraction)],
		["FATIGUE RESIST", "%d%%" % int(round((1.0 - fatigue_rate) / 0.75 * 100.0)), (1.0 - fatigue_rate) / 0.75],
	]


## The same effects for a driver's attributes, without a car.
static func effects_for(attrs: Dictionary) -> Array:
	var perf := DriverPerformance.new()
	perf.configure(attrs)
	return perf.effects()
