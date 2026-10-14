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
	# Pace decides how much of the car's grip the driver dares to use.
	var grip_scale := lerpf(0.8, 1.0, clampf((pace - 0.8) / 0.2, 0.0, 1.0))
	# Wet track: less grip for everyone, and less still for drivers who dislike the rain.
	grip_scale *= float(profile.get("track_grip", 1.0))
	var brake_scale := lerpf(0.72, 0.98, braking_accuracy)
	if float(profile.get("track_grip", 1.0)) < 1.0:
		brake_scale *= 0.88          # brake earlier on a wet track
	_profile = line.speed_profile(car.physics.stats, car.physics_config, grip_scale, brake_scale)
	# Poor tire managers scrub and overheat their tires.
	var abuse := lerpf(1.3, 0.85, tire_management)
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
	var target := line.point(look_idx, overtake.offset + _line_error)
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
	# Off the racing surface: be gentle until back on track.
	if car.surface_rear >= VehiclePhysicsConfig.Surface.GRASS:
		target_v = minf(target_v, maxf(v, 14.0) + 2.0)
	target_v = minf(target_v, overtake.speed_cap)
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
	input.throttle = _throttle
	input.brake = brake
	if binary_pedals:
		input.throttle = 1.0 if throttle_target > 0.3 else 0.0
		input.brake = 1.0 if brake > 0.05 else 0.0
	state = "OVERTAKE" if overtake.passing else ("FOLLOW" if overtake.speed_cap < INF else ("BRAKE" if brake > 0.05 else "RACING"))

	# --- recovery if stuck or facing a wall
	if v < 1.5:
		_stuck_timer += delta
		if _stuck_timer > STUCK_TIME:
			_stuck_timer = 0.0
			state = "RECOVER"
			needs_recovery.emit(car)
	else:
		_stuck_timer = 0.0


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
