class_name DrivingStyle
extends RefCounted
## Reads how the player takes each corner and races the cars around them, and turns it into
## five playing styles. Nobody picks a style: a lap of late braking, clean exits or careful
## tyre spending simply shows up here. Each corner is split into the four phases:
##   APPROACH  where the braking started, against what the car needed
##   TURN-IN   braking while steering (lockups, understeer)
##   APEX      slowest speed and where on the road it was taken
##   EXIT      how soon full throttle came, wheelspin, speed down the next straight
## Overtakes are credited to the phase they happened in: under braking or on the exit.

const STYLES: PackedStringArray = ["LATE BRAKER", "SMOOTH DRIVER", "EXIT SPECIALIST", "RACE TACTICIAN", "DEFENSIVE RACER"]
const BLURBS := {
	"LATE BRAKER": "Gains places on the brakes. Watch the lockups and the exits.",
	"SMOOTH DRIVER": "Clean lines, gentle inputs, tyres that last.",
	"EXIT SPECIALIST": "Gives up the entry to straighten the exit and pass down the straight.",
	"RACE TACTICIAN": "Spends the tyres where it wins places and saves them where it doesn't.",
	"DEFENSIVE RACER": "Places the car so faster cars have nowhere to go.",
}
## Metres past the corner's end where exit speed is measured.
const EXIT_PROBE := 60.0
## Metres before the apex where a braking zone may start.
const APPROACH := 260.0
## How close another car must be to count as a battle (m along the track).
const BATTLE := 35.0

var reports: Array[Dictionary] = []
## The latest corner, for the on-screen card.
var last: Dictionary = {}
var last_time := -100.0

var _track: TrackData
var _corner := -1
var _phase := ""
var _c: Dictionary = {}
var _time := 0.0
# Whole-session tallies.
var _scores := {"LATE BRAKER": 0.0, "SMOOTH DRIVER": 0.0, "EXIT SPECIALIST": 0.0, "RACE TACTICIAN": 0.0, "DEFENSIVE RACER": 0.0}
var _weights := 0.0
var _stops := 0.0                     # corners that needed real braking
var _passes_braking := 0
var _passes_exit := 0
var _held := 0
var _lost := 0
var _push_attacking := 0.0     # hard on the throttle with a car close ahead
var _push_alone := 0.0         # hard on the throttle with nobody around
var _preserve_time := 0.0      # easing the throttle in with nobody around
var _drive_time := 0.0
var _slide_time := 0.0
var _steer_jerk := 0.0
var _last_steer := 0.0
var _gaps: Dictionary = {}           # other car -> signed gap last frame (m, + = they are ahead)
var _wear_start := 1.0


func _init(track: TrackData) -> void:
	_track = track


func update(car: VehicleController, delta: float) -> void:
	if _track == null or _track.corners.is_empty() or not car.controls_enabled:
		return
	_time += delta
	var p := car.physics
	var input := car.input
	var progress := car.progress
	var moving := car.speed > 8.0
	if moving:
		_drive_time += delta
		_steer_jerk += absf(input.steer - _last_steer)
		_slide_time += delta * (1.0 if p.front_tire.locked or p.rear_tire.spinning or p.oversteer else 0.0)
	_last_steer = input.steer
	var battle := _battles(car)
	# How the tyre budget is spent: flat out and hard on the tyres, or fed in gently.
	var hard := moving and input.throttle > 0.9 and maxf(p.front_tire.usage, p.rear_tire.usage) > 0.8
	if hard:
		if battle.x > 0.0:
			_push_attacking += delta
		else:
			_push_alone += delta
	elif moving and battle == Vector2.ZERO and input.throttle > 0.05 and input.throttle < 0.75:
		_preserve_time += delta
	_track_corner(car, progress, battle, delta)


## x = a car close ahead (1/0), y = a car close behind (1/0). Also books passes.
func _battles(car: VehicleController) -> Vector2:
	var out := Vector2.ZERO
	var parent := car.get_parent()
	if parent == null:
		return out
	for node in parent.get_children():
		if node == car or not node is VehicleController:
			continue
		var other := node as VehicleController
		var gap := _track.progress_delta(car.progress, other.progress)
		if absf(gap) > _track.length * 0.5:
			continue
		if gap > 0.0 and gap < BATTLE:
			out.x = 1.0
		elif gap < 0.0 and gap > -BATTLE:
			out.y = 1.0
		if _gaps.has(other) and absf(gap) < 30.0:
			var before: float = _gaps[other]
			if before > 0.0 and gap <= 0.0:
				# Passed them: on the brakes or on the exit / straight?
				if _phase == "approach" or _phase == "turn_in":
					_passes_braking += 1
				else:
					_passes_exit += 1
			elif before < 0.0 and gap >= 0.0:
				_lost += 1
		_gaps[other] = gap
	return out


func _track_corner(car: VehicleController, progress: float, battle: Vector2, delta: float) -> void:
	var p := car.physics
	var input := car.input
	var kmh := car.speed * 3.6
	if _corner == -1:
		# Waiting for the next corner's approach.
		for i in _track.corners.size():
			var corner: Dictionary = _track.corners[i]
			var to_apex := _track.progress_delta(progress, float(corner["apex"]))
			if to_apex > 0.0 and to_apex < APPROACH:
				_corner = i
				_phase = "approach"
				_c = {"name": corner["name"], "apex": float(corner["apex"]), "end": float(corner["end"]), "dir": float(corner["direction"]),
					"entry": kmh, "brake_at": -1.0, "apex_kmh": 999.0, "apex_lat": 0.0, "lock": 0.0, "trail": 0.0, "spin": 0.0,
					"throttle_at": -1.0, "wide": false, "behind": battle.y, "ahead": battle.x, "min_at": 0.0, "peak_brake": 0.0, "lost0": _lost, "release_at": INF, "release_kmh": -1.0}
				break
		return
	var to_apex := _track.progress_delta(progress, float(_c["apex"]))
	var past_end := _track.progress_delta(float(_c["end"]), progress)
	if car.off_track:
		_c["wide"] = true
	_c["ahead"] = maxf(float(_c["ahead"]), battle.x)
	_c["behind"] = maxf(float(_c["behind"]), battle.y)
	match _phase:
		"approach", "turn_in":
			_c["entry"] = maxf(float(_c["entry"]), kmh) if _c["brake_at"] < 0.0 else _c["entry"]
			if input.brake > 0.5 and float(_c["brake_at"]) < 0.0:
				_c["brake_at"] = to_apex
			_note_release(to_apex, input.brake, kmh)
			_c["peak_brake"] = maxf(float(_c["peak_brake"]), input.brake)
			if absf(input.steer) > 0.3 and input.brake > 0.5:
				_c["trail"] = float(_c["trail"]) + delta
				_phase = "turn_in"
			if p.front_tire.locked or p.rear_tire.locked:
				_c["lock"] = float(_c["lock"]) + delta
			if kmh < float(_c["apex_kmh"]):
				_c["apex_kmh"] = kmh
				_c["apex_lat"] = car.lateral * float(_c["dir"]) / maxf(_track.half_width, 1.0)
				_c["min_at"] = -to_apex
			if to_apex <= 0.0:
				_phase = "exit"
		"exit":
			_note_release(to_apex, input.brake, kmh)
			if kmh < float(_c["apex_kmh"]):
				_c["apex_kmh"] = kmh
				_c["min_at"] = -to_apex
			if input.throttle > 0.9 and float(_c["throttle_at"]) < 0.0:
				_c["throttle_at"] = -to_apex
			if p.rear_tire.spinning:
				_c["spin"] = float(_c["spin"]) + delta
			if past_end >= EXIT_PROBE:
				_c["exit"] = kmh
				_finish(car)
				_corner = -1
				_phase = ""


## The end of the braking zone: the brake comes off after a firm press.
func _note_release(to_apex: float, brake: float, kmh: float) -> void:
	if float(_c["brake_at"]) >= 0.0 and float(_c["release_kmh"]) < 0.0 and brake < 0.2:
		_c["release_at"] = to_apex
		_c["release_kmh"] = kmh


func _finish(car: VehicleController) -> void:
	var c := _c
	var stats := car.physics.stats
	var entry := float(c["entry"]) / 3.6
	var apex := clampf(float(c["apex_kmh"]), 0.0, 400.0) / 3.6
	# The braking zone the driver used (firm press to release) against the distance the car
	# needed for the same speed drop at about three quarters of its 200 km/h braking figure
	# (downforce fades as it slows).
	var released := float(c["release_kmh"]) / 3.6 if float(c["release_kmh"]) >= 0.0 else apex
	var needed := maxf(5.0, (entry * entry - released * released) / (2.0 * maxf(stats.braking_g, 0.8) * VehiclePhysicsConfig.GRAVITY * 0.75))
	var release_at := float(c["release_at"]) if float(c["release_kmh"]) >= 0.0 else -float(c["min_at"])
	var used := float(c["brake_at"]) - release_at if float(c["brake_at"]) >= 0.0 else -1.0
	var lateness := clampf(needed / maxf(used, 1.0), 0.0, 1.6) if used > 0.0 else 0.0
	# Braking point only matters where the corner really asks for a stop; fast sweepers are
	# about carrying speed, so they are judged on the line and the exit instead.
	var stop := float(c["entry"]) - float(c["apex_kmh"]) > 40.0
	if not stop:
		lateness = -1.0
	var throttle_at := float(c["throttle_at"])
	var verdict := ""
	if bool(c["wide"]):
		verdict = "TOO LATE ON THE BRAKES - RAN WIDE" if lateness > 1.0 else "RAN WIDE"
	elif float(c["lock"]) > 0.15:
		verdict = "LOCKED UP - EASE THE BRAKE AS YOU TURN"
	elif float(c["spin"]) > 0.25:
		verdict = "WHEELSPIN - FEED THE THROTTLE IN"
	elif stop and used > 0.0 and lateness < 0.55:
		verdict = "BRAKED EARLY - TIME LEFT ON THE TABLE"
	elif throttle_at >= 0.0 and throttle_at < 25.0:
		verdict = "GREAT EXIT"
	elif lateness > 0.95:
		verdict = "LATE BRAKING, CLEAN"
	elif not stop:
		verdict = "CARRIED THE SPEED"
	else:
		verdict = "CLEAN"
	var report := {"name": c["name"], "entry": int(round(float(c["entry"]))), "apex": int(round(float(c["apex_kmh"]))),
		"exit": int(round(float(c.get("exit", 0.0)))), "verdict": verdict, "lateness": lateness, "braking_m": used, "needed_m": needed}
	reports.append(report)
	last = report
	last_time = _time
	# --- style evidence from this corner (each 0..1)
	var clean := 0.0 if (bool(c["wide"]) or float(c["lock"]) > 0.15 or float(c["spin"]) > 0.25) else 1.0
	var late := clampf((lateness - 0.7) / 0.35, 0.0, 1.0)
	if stop:
		_stops += 1.0
	var smooth := clean * clampf(1.0 - float(c["trail"]) * 0.8, 0.0, 1.0)
	var early_power := clampf(1.0 - throttle_at / 60.0, 0.0, 1.0) if throttle_at >= 0.0 else 0.0
	var late_apex := clampf(float(c["min_at"]) / 15.0, 0.0, 1.0)
	var exit_gain := clampf((float(c.get("exit", 0.0)) - float(c["apex_kmh"])) / 90.0, 0.0, 1.0)
	var exit_style := (early_power * 0.5 + late_apex * 0.2 + exit_gain * 0.3) * (0.4 + 0.6 * clean)
	var inside := clampf(float(c["apex_lat"]), 0.0, 1.0)
	var defend := float(c["behind"]) * (0.5 + 0.5 * inside)
	if stop:
		_scores["LATE BRAKER"] += late * (0.6 + 0.4 * clean)
	_scores["SMOOTH DRIVER"] += smooth
	_scores["EXIT SPECIALIST"] += exit_style
	_scores["DEFENSIVE RACER"] += defend
	if float(c["behind"]) > 0.0 and _lost == int(c["lost0"]):
		_held += 1            # someone sat on your gearbox through the corner and stayed there
	_weights += 1.0
	GameManager.last_style = summary()


## Five scores 0..100 plus the strongest one and one line about it.
func summary() -> Dictionary:
	var n := maxf(_weights, 1.0)
	var out := {}
	out["LATE BRAKER"] = _scores["LATE BRAKER"] / maxf(_stops, 1.0) * 80.0 + minf(20.0, _passes_braking * 7.0)
	out["SMOOTH DRIVER"] = _scores["SMOOTH DRIVER"] / n * 70.0 + 30.0 * clampf(1.0 - _slide_time / maxf(_drive_time * 0.08, 1.0), 0.0, 1.0) - minf(20.0, _steer_jerk / maxf(_drive_time, 1.0) * 2.0)
	out["EXIT SPECIALIST"] = _scores["EXIT SPECIALIST"] / n * 80.0 + minf(20.0, _passes_exit * 7.0)
	var push := _push_attacking + _push_alone
	var push_aim := _push_attacking / push if push > 0.5 else 0.0
	out["RACE TACTICIAN"] = 55.0 * push_aim + 25.0 * clampf(_preserve_time / maxf(_drive_time * 0.3, 1.0), 0.0, 1.0) + minf(20.0, (_passes_braking + _passes_exit) * 4.0) if push + _preserve_time > 1.0 else 0.0
	out["DEFENSIVE RACER"] = _scores["DEFENSIVE RACER"] / n * 60.0 + minf(40.0, _held * 10.0) - minf(30.0, _lost * 10.0)
	var best := ""
	for key: String in STYLES:
		out[key] = clampf(float(out[key]), 0.0, 100.0)
		if best == "" or float(out[key]) > float(out[best]):
			best = key
	return {"scores": out, "top": best, "blurb": BLURBS[best], "corners": reports.size(),
		"passes_braking": _passes_braking, "passes_exit": _passes_exit, "lost": _lost}

