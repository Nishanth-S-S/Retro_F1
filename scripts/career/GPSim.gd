class_name GPSim
extends RefCounted
## Lap-by-lap grand prix simulation for the pit wall. One call to step() = one lap for the
## whole field. The player's two cars take orders (pit, tire, pace, team orders); every
## other car runs a simple strategy of its own.

const BASE_LAP := 90.0
const PIT_LOSS := 21.0
const PIT_LOSS_SC := 11.0
const COMPOUNDS := {
	"S": {"name": "SOFT", "pace": -0.8, "deg": 0.13, "life": 8.0, "color": "d8433b"},
	"M": {"name": "MEDIUM", "pace": -0.35, "deg": 0.075, "life": 13.0, "color": "e9b820"},
	"H": {"name": "HARD", "pace": 0.0, "deg": 0.045, "life": 20.0, "color": "c9ccd1"},
	"I": {"name": "INTER", "pace": 0.0, "deg": 0.06, "life": 16.0, "color": "2e9e5b"},
	"W": {"name": "WET", "pace": 0.0, "deg": 0.05, "life": 22.0, "color": "2f6fde"},
}
## Seconds lost per lap for each compound in [dry, light rain, heavy rain].
const WEATHER_LOSS := {"S": [0.0, 6.0, 14.0], "M": [0.0, 6.0, 14.0], "H": [0.0, 6.5, 15.0], "I": [3.0, 0.0, 3.5], "W": [6.0, 2.0, 0.0]}
const WEATHER_NAMES: PackedStringArray = ["DRY", "LIGHT RAIN", "HEAVY RAIN"]
const MODE_NAMES: PackedStringArray = ["SAVE", "NORMAL", "PUSH"]
const MODE_PACE: PackedFloat32Array = [0.4, 0.0, -0.35]
const MODE_WEAR: PackedFloat32Array = [0.6, 1.0, 1.5]

var cars: Array[Dictionary] = []
var lap := 0
var laps := 20
var weather := 0
var forecast_in := -1            # laps until the weather changes, -1 = stable
var forecast_to := 0
var safety_car := 0              # laps of safety car remaining
## "free" lets your drivers race, "hold" freezes them, "swap" lets the one behind through.
var team_order := "free"
var flags := {"collision": false, "held": "", "swapped": ""}
var messages: Array[String] = []
var pit_bonus := 0.0             # seconds saved per stop by the player's pit crew
var _rain_chance := 0.2
var _wear := 1.0
var _sc_chance := 0.05
var _rng := RandomNumberGenerator.new()


func setup(entries: Array, round_info: Dictionary, pit_level: int, seed_value: int) -> void:
	_rng.seed = seed_value
	laps = int(round_info.get("laps", 20))
	_rain_chance = float(round_info.get("rain", 0.2))
	_wear = float(round_info.get("wear", 1.0))
	_sc_chance = float(round_info.get("safety_car", 0.05))
	pit_bonus = pit_level * 0.5
	weather = 1 if _rng.randf() < _rain_chance * 0.5 else 0
	cars.clear()
	for e: Dictionary in entries:
		var car := e.duplicate()
		car.merge({"tire": "M", "age": 0.0, "total": 0.0, "last": 0.0, "mode": 1, "pit_request": "", "pits": 0, "dnf": false,
			"pitted": false, "position": 0, "gap": 0.0, "used": [], "status": ""})
		cars.append(car)
	# Qualifying: one flying lap each.
	for car in cars:
		car["quali"] = _pace(car) + _rng.randfn(0.0, 0.25)
	cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["quali"] < b["quali"])
	for i in cars.size():
		cars[i]["total"] = i * 0.35
		cars[i]["position"] = i + 1
		if not cars[i]["is_player"]:
			var roll := _rng.randf()
			cars[i]["tire"] = "I" if weather > 0 else ("S" if roll < 0.3 else ("H" if roll > 0.8 else "M"))
	_update_gaps()


func player_cars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for car in cars:
		if car["is_player"]:
			out.append(car)
	return out


func finished() -> bool:
	return lap >= laps


func order() -> Array[Dictionary]:
	return cars


func _pace(car: Dictionary) -> float:
	return BASE_LAP - (float(car["car"]) - 75.0) * 0.07 - (float(car["pace"]) - 75.0) * 0.045 - (float(car["morale"]) - 50.0) * 0.004


static func tire_wear_fraction(car: Dictionary) -> float:
	return clampf(float(car["age"]) / float(COMPOUNDS[car["tire"]]["life"]), 0.0, 1.3)


func _say(text: String) -> void:
	messages.append("L%d  %s" % [lap + 1, text])


# ---------------------------------------------------------------- one lap

func step() -> void:
	if finished():
		return
	messages.clear()
	_update_weather()
	var sc_now := safety_car > 0
	var previous: Array[Dictionary] = cars.duplicate()
	for car in cars:
		if car["dnf"]:
			continue
		car["pitted"] = false
		car["status"] = ""
		if not car["is_player"]:
			_ai_strategy(car, sc_now)
		var lap_time := _lap_time(car, sc_now)
		if car["pit_request"] != "":
			var loss := (PIT_LOSS_SC if sc_now else PIT_LOSS) + _rng.randf_range(-0.6, 1.4) - (pit_bonus if car["is_player"] else 1.0)
			lap_time += loss
			if not (car["used"] as Array).has(car["tire"]):
				car["used"].append(car["tire"])
			car["tire"] = car["pit_request"]
			car["age"] = 0.0
			car["pit_request"] = ""
			car["pits"] = int(car["pits"]) + 1
			car["pitted"] = true
			car["status"] = "PIT"
			if car["is_player"]:
				_say("%s pits for %s (%.1f s)" % [_short(car), COMPOUNDS[car["tire"]]["name"], loss])
		car["last"] = lap_time
		car["total"] = float(car["total"]) + lap_time
		car["age"] = float(car["age"]) + MODE_WEAR[car["mode"]] * _wear * (0.4 if sc_now else 1.0)
		_incidents(car, sc_now)
	if sc_now:
		_bunch_field()
		safety_car -= 1
		if safety_car == 0:
			_say("SAFETY CAR IN THIS LAP - green flag")
	else:
		_resolve_battles(previous)
	cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["dnf"] != b["dnf"]:
			return not a["dnf"]
		return a["total"] < b["total"])
	lap += 1
	_update_gaps()


func _update_weather() -> void:
	if forecast_in > 0:
		forecast_in -= 1
		if forecast_in == 0:
			weather = forecast_to
			forecast_in = -1
			_say("WEATHER: %s" % WEATHER_NAMES[weather])
	elif forecast_in < 0 and _rng.randf() < _rain_chance * 0.22:
		forecast_to = clampi(weather + (1 if _rng.randf() < (0.65 if weather == 0 else 0.4) else -1), 0, 2)
		if forecast_to != weather:
			forecast_in = _rng.randi_range(2, 4)
			_say("FORECAST: %s in about %d laps" % [WEATHER_NAMES[forecast_to], forecast_in])


func _lap_time(car: Dictionary, sc_now: bool) -> float:
	if sc_now:
		return 118.0
	var compound: Dictionary = COMPOUNDS[car["tire"]]
	var age: float = car["age"]
	var t := _pace(car) + float(compound["pace"]) + float(compound["deg"]) * age - 0.03 * lap
	if age > float(compound["life"]):
		t += 0.55 * (age - float(compound["life"]))          # the cliff
	t += float(WEATHER_LOSS[car["tire"]][weather])
	t += MODE_PACE[car["mode"]]
	t += _rng.randfn(0.0, 0.12 + (100.0 - float(car["consistency"])) * 0.012)
	return t


func _incidents(car: Dictionary, sc_now: bool) -> void:
	if sc_now:
		return
	var wrong_tire: bool = float(WEATHER_LOSS[car["tire"]][weather]) >= 6.0
	var risk := 0.004 * (1.0 + (1.5 if car["mode"] == 2 else 0.0) + weather * 1.5) + (0.05 if wrong_tire and weather > 0 else 0.0)
	risk *= 1.0 + (100.0 - float(car["consistency"])) / 60.0
	if _rng.randf() < risk:
		if _rng.randf() < 0.35:
			_retire(car, "crashes out")
		else:
			var lost := _rng.randf_range(5.0, 18.0)
			car["total"] = float(car["total"]) + lost
			car["status"] = "SPIN"
			if car["is_player"]:
				_say("%s spins and loses %.0f s" % [_short(car), lost])
	elif _rng.randf() < 0.0012:
		_retire(car, "stops with a mechanical failure")


func _retire(car: Dictionary, reason: String) -> void:
	car["dnf"] = true
	car["status"] = "OUT"
	car["crashed"] = not reason.contains("mechanical")
	_say("%s %s" % [_short(car), reason])
	if safety_car == 0 and lap < laps - 3 and _rng.randf() < _sc_chance * 8.0:
		safety_car = 3
		_say("SAFETY CAR DEPLOYED - cheap pit stop window")


func _short(car: Dictionary) -> String:
	return str(car["name"]).get_slice(" ", 1).to_upper()


func _ai_strategy(car: Dictionary, sc_now: bool) -> void:
	var left := laps - lap
	var compound: Dictionary = COMPOUNDS[car["tire"]]
	var wet_tire: bool = car["tire"] == "I" or car["tire"] == "W"
	var want := ""
	if weather == 0 and wet_tire and _rng.randf() < 0.7:
		want = "dry"
	elif weather > 0 and not wet_tire and _rng.randf() < 0.65:
		want = "W" if weather == 2 else "I"
	elif weather == 2 and car["tire"] == "I" and _rng.randf() < 0.4:
		want = "W"
	elif left > 3 and float(car["age"]) >= float(compound["life"]) + _rng.randf_range(-1.5, 1.0):
		want = "dry" if weather == 0 else car["tire"]
	elif sc_now and left > 4 and float(car["age"]) > float(compound["life"]) * 0.45 and _rng.randf() < 0.6:
		want = "dry" if weather == 0 else car["tire"]
	if want == "dry":
		want = "S" if left <= 8 else ("M" if left <= 14 else "H")
	car["pit_request"] = want
	car["mode"] = 2 if left <= 3 else 1


## Under the safety car the field closes up; pit stops cost far less track position.
func _bunch_field() -> void:
	var running: Array[Dictionary] = []
	for car in cars:
		if not car["dnf"]:
			running.append(car)
	running.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] < b["total"])
	if running.is_empty():
		return
	var lead: float = running[0]["total"]
	for i in running.size():
		running[i]["total"] = lead + i * 0.5


## Catching a car is not passing it. Each car that closed onto the one ahead has to make the move.
func _resolve_battles(previous: Array[Dictionary]) -> void:
	for i in range(1, previous.size()):
		var behind := previous[i]
		var ahead := previous[i - 1]
		if behind["dnf"] or ahead["dnf"] or behind["pitted"] or ahead["pitted"]:
			continue
		var teammates: bool = behind["is_player"] and ahead["is_player"]
		if teammates and team_order == "swap" and float(behind["total"]) - float(ahead["total"]) < 2.0:
			var t: float = ahead["total"]
			behind["total"] = t + 0.1
			ahead["total"] = t + 0.7
			flags["swapped"] = ahead["id"]
			team_order = "hold"
			_say("TEAM ORDERS: %s lets %s through" % [_short(ahead), _short(behind)])
			continue
		if float(behind["total"]) >= float(ahead["total"]):
			continue
		if teammates and team_order == "hold":
			behind["total"] = float(ahead["total"]) + 0.3
			flags["held"] = behind["id"]
			behind["status"] = "HELD"
			continue
		var advantage := float(ahead["total"]) - float(behind["total"])
		var chance := clampf(0.3 + advantage * 0.35 + (float(behind["racecraft"]) - float(ahead["racecraft"])) / 150.0, 0.08, 0.92)
		if teammates:
			# Letting them race risks contact; big egos make it worse.
			var clash := 0.04 + maxf(0.0, float(behind["ego"]) + float(ahead["ego"]) - 100.0) / 900.0
			if _rng.randf() < clash:
				flags["collision"] = true
				_say("CONTACT! %s and %s collide" % [_short(behind), _short(ahead)])
				for car: Dictionary in [behind, ahead]:
					car["total"] = float(car["total"]) + _rng.randf_range(6.0, 14.0)
					car["status"] = "HIT"
					if _rng.randf() < 0.25:
						_retire(car, "retires with damage")
				continue
		if _rng.randf() < chance:
			if behind["is_player"] or ahead["is_player"]:
				_say("%s passes %s" % [_short(behind), _short(ahead)])
		else:
			behind["total"] = float(ahead["total"]) + 0.25


func _update_gaps() -> void:
	var lead := 0.0
	var pos := 1
	for car in cars:
		if car["dnf"]:
			car["position"] = pos
			pos += 1
			continue
		if pos == 1:
			lead = car["total"]
		car["position"] = pos
		car["gap"] = float(car["total"]) - lead
		pos += 1
