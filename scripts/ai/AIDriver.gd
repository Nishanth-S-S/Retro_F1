class_name AIDriver
extends Node
## Drives a VehicleController by producing the same analog steering / throttle / brake
## requests a human does. The car's physics is identical to the player's.

signal needs_recovery(car: VehicleController)

const LOOKAHEAD_BASE := 9.0
const LOOKAHEAD_TIME := 0.4
const STUCK_TIME := 2.6

var car: VehicleController
var line: RacingLine
var track: TrackData
var others: Array = []
var overtake := AIOvertake.new()
var state := "GRID"

# --- profile (see data/progression/ai_drivers.json)
var pace := 0.92
var braking_accuracy := 0.9
var consistency := 0.9
var aggression := 0.5
var tire_management := 0.7
var error_rate := 0.08
## Most throttle this driver will use: below 1.0 feeds the power in to save the tyre budget.
var throttle_cap := 1.0
## Test hook: snap pedals to 0 % / 100 % to compare against smooth analog driving.
var binary_pedals := false

var _profile := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _corner_index := -1
var _speed_scale := 1.0
var _line_error := 0.0
var _line_error_target := 0.0
var _stuck_timer := 0.0
var _throttle := 0.0
var _brake_trim := 1.0
## The driver's grip reach when the speed profile was planned (fatigue lowers it later).
var _reach := 1.0
## Pit stop: "" (racing), "in" (down the pit lane to the box), "stop" (crew working), "out".
var pit_state := ""
var _pit_time := 0.0
## Set by RaceManager each frame: true while this car may open DRS.
var drs_allowed := false

const PIT_SPEED := 22.2               # 80 km/h pit lane limit


func setup(vehicle: VehicleController, racing_line: RacingLine, profile: Dictionary, seed_value: int) -> void:
	car = vehicle
	line = racing_line
	track = racing_line.track
	pace = float(profile.get("pace", pace))
	braking_accuracy = float(profile.get("braking_accuracy", braking_accuracy))
	consistency = float(profile.get("consistency", consistency))
	aggression = float(profile.get("aggression", aggression))
	tire_management = float(profile.get("tire_management", tire_management))
	error_rate = float(profile.get("error_rate", error_rate))
	_rng.seed = seed_value
	# The same driver model as the player: the car only gives this driver what their
	# attributes reach (career rivals bring their real card, free play uses the default).
	var attrs: Dictionary = profile.get("attrs", {})
	car.set_driver(attrs)
	car.perf.wetness = clampf(float(GameManager.session_weather) / 2.0, 0.0, 1.0) if car.wet else 0.0
	car.perf.update(0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	_reach = car.perf.lateral * car.perf.wet_grip
	# Pace decides how much of that grip the AI dares to use.
	var grip_scale := lerpf(0.8, 1.0, clampf((pace - 0.8) / 0.2, 0.0, 1.0)) * _reach
	var wet_track := car.wet
	if attrs.is_empty():
		# Wet track: less grip for everyone, and less still for drivers who dislike the rain.
		grip_scale *= float(profile.get("track_grip", 1.0))
	else:
		# The wet skill is already in the driver model; everyone leaves a margin in the rain.
		grip_scale *= car.physics.grip_scale * (0.92 if wet_track else 1.0)
	var brake_scale := lerpf(0.72, 0.98, braking_accuracy) * car.perf.braking
	if wet_track or float(profile.get("track_grip", 1.0)) < 1.0:
		brake_scale *= 0.88          # brake earlier on a wet track
	_profile = line.speed_profile(car.physics.stats, car.physics_config, grip_scale, brake_scale)
	# Poor tire managers scrub and overheat their tires (a real driver's tyre care is in
	# the driver model instead, so it is not counted twice).
	var abuse := lerpf(1.3, 0.85, tire_management) if attrs.is_empty() else 1.0
	car.physics.front_tire.abuse_scale = abuse
	car.physics.rear_tire.abuse_scale = abuse
	car.physics.tc_level = 1
	car.physics.abs_level = 1


func target_speed_at(index: int) -> float:
	return _profile[posmod(index, _profile.size())]


func _physics_process(delta: float) -> void:
	if car == null or not car.controls_enabled:
		state = "GRID"
		return
	var input := car.input
	var idx := car.track_index
	var v := car.speed
	_update_mistakes(idx)
	overtake.update(delta, car, others, track, line.offsets[idx], aggression)
	_line_error = move_toward(_line_error, _line_error_target, 1.2 * delta)

	# --- steering: pure pursuit of a look-ahead point on the (offset) racing line
	var look_dist := LOOKAHEAD_BASE + v * LOOKAHEAD_TIME
	var look_idx := idx + int(look_dist / track.spacing)
	var lateral_extra := overtake.offset + _line_error
	if pit_state != "":
		lateral_extra = _pit_offset(look_idx)
	var target := line.point(look_idx, lateral_extra)
	var to_target := (target - car.global_position).rotated(-car.rotation) / VehiclePhysicsConfig.PPM
	var dist := maxf(to_target.length(), 1.0)
	var wheel_angle := atan(2.0 * car.physics_config.wheelbase * to_target.y / (dist * dist))
	var steer := clampf(wheel_angle / car.physics_config.max_steer_angle(v), -1.0, 1.0)
	if to_target.x < 0.0:
		steer = signf(to_target.y) if to_target.y != 0.0 else 1.0       # facing the wrong way: full lock
	input.steer = lerpf(input.steer, steer, minf(1.0, 14.0 * delta))

	# --- speed: track the profile a short distance ahead
	var ahead := int(v * 0.12 / track.spacing) + 1
	var target_v := INF
	for k in range(0, ahead + 1):
		target_v = minf(target_v, _profile[posmod(idx + k, _profile.size())])
	target_v *= _speed_scale
	# Drive to the grip the tires actually have right now (cold, worn or overheated).
	var front := car.physics.front_tire
	var rear := car.physics.rear_tire
	var grip_now := minf(front.grip_coefficient() / front.base_grip, rear.grip_coefficient() / rear.base_grip)
	target_v *= sqrt(clampf(grip_now, 0.5, 1.0))
	# A tiring driver has less grip than when the plan was made.
	target_v *= sqrt(clampf(car.perf.lateral * car.perf.wet_grip / maxf(_reach, 0.01), 0.5, 1.0))
	# Off the racing surface: be gentle until back on track.
	if car.surface_rear >= VehiclePhysicsConfig.Surface.GRASS:
		target_v = minf(target_v, maxf(v, 14.0) + 2.0)
	target_v = minf(target_v, overtake.speed_cap)
	if pit_state != "":
		target_v = _pit_speed(delta)
	car.physics.aero.drs = drs_allowed and pit_state == "" and input.brake < 0.05
	var error := target_v - v
	var throttle_target := 0.0
	var brake := 0.0
	if error > 0.0:
		throttle_target = clampf(error * 0.55 + 0.12, 0.0, 1.0)
		# Feed power in as the steering unwinds.
		throttle_target *= clampf(1.25 - absf(input.steer) * 0.75, 0.35, 1.0)
	elif error < -0.6:
		brake = clampf(-error * 0.2, 0.0, 1.0)
	else:
		throttle_target = 0.1
	# Pedal feel, as a careful human would: back out of wheelspin, ease off a locking brake.
	if rear.spinning:
		throttle_target = minf(throttle_target, _throttle * 0.6)
	if front.locked or rear.locked:
		_brake_trim = maxf(0.35, _brake_trim - 4.0 * delta)
	else:
		_brake_trim = minf(1.0, _brake_trim + 1.5 * delta)
	brake *= _brake_trim
	_throttle = move_toward(_throttle, throttle_target, (5.0 if throttle_target > _throttle else 12.0) * delta)
	# The tyre budget: overspending against the plan to the stop means feeding the power in.
	var budget_target := car.tyre_target()
	var saving := budget_target >= 0.0 and car.tyre_life() < budget_target - 0.08 and not overtake.passing
	input.throttle = minf(_throttle, minf(throttle_cap, 0.75 if saving else 1.0))
	input.brake = brake
	if binary_pedals:
		input.throttle = 1.0 if throttle_target > 0.3 else 0.0
		input.brake = 1.0 if brake > 0.05 else 0.0
	if pit_state == "stop":
		input.throttle = 0.0
		input.brake = 1.0
		_throttle = 0.0
	state = "PIT" if pit_state != "" else "OVERTAKE" if overtake.passing else ("FOLLOW" if overtake.speed_cap < INF else ("BRAKE" if brake > 0.05 else "RACING"))

	# --- recovery if stuck or facing a wall
	if v < 1.5 and pit_state == "":
		_stuck_timer += delta
		if _stuck_timer > STUCK_TIME:
			_stuck_timer = 0.0
			state = "RECOVER"
			needs_recovery.emit(car)
	else:
		_stuck_timer = 0.0


## Called just after the car crosses the line on its pit lap.
func start_pit(stop_seconds: float) -> void:
	pit_state = "in"
	_pit_time = stop_seconds


func _lane_lateral() -> float:
	return -(track.half_width + TrackData.PIT_WIDTH * 0.55)


## Extra offset from the racing line that puts the look-ahead point in the pit lane, blended
## in at the entry and out again at the exit.
func _pit_offset(look_idx: int) -> float:
	var i := posmod(look_idx, track.count)
	var p := i * track.spacing
	var lane := _lane_lateral() - line.offsets[i]
	var blend := 1.0
	if pit_state == "in":
		blend = clampf((p - 5.0) / 45.0, 0.0, 1.0)
	elif pit_state == "out":
		blend = clampf((track.pit_end - 20.0 - p) / 60.0, 0.0, 1.0)
	return lane * blend


func _pit_speed(delta: float) -> float:
	var p := car.progress
	match pit_state:
		"in":
			var to_box := track.pit_box - p
			if to_box < 1.5 and car.speed < 1.0:
				pit_state = "stop"
			return minf(PIT_SPEED, sqrt(maxf(0.0, 2.0 * 7.0 * (to_box - 0.5))))
		"stop":
			_pit_time -= delta
			if _pit_time <= 0.0:
				pit_state = "out"
			return 0.0
		"out":
			if p > track.pit_end + 10.0 or p < track.pit_start:
				pit_state = ""
			return PIT_SPEED if p < track.pit_end - 20.0 else INF
	return INF


## Each corner gets a fresh roll: usually tiny variation from consistency, occasionally
## a real (but believable) mistake - braking early or late, or missing the line.
func _update_mistakes(idx: int) -> void:
	var progress := idx * track.spacing
	var current := -1
	for i in track.corners.size():
		var corner: Dictionary = track.corners[i]
		if progress >= float(corner["start"]) - 90.0 and progress <= float(corner["end"]):
			current = i
			break
	if current == _corner_index:
		return
	_corner_index = current
	_speed_scale = 1.0 + _rng.randfn(0.0, (1.0 - consistency) * 0.035)
	_line_error_target = _rng.randfn(0.0, (1.0 - consistency) * 1.6)
	if current >= 0 and _rng.randf() < error_rate:
		match _rng.randi() % 3:
			0:
				_speed_scale = 1.045      # brakes late, runs wide
			1:
				_speed_scale = 0.93       # brakes early
			2:
				_line_error_target = (1.0 if _rng.randf() > 0.5 else -1.0) * 2.2
	_speed_scale = clampf(_speed_scale, 0.9, 1.06)
