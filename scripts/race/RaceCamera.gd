class_name RaceCamera
extends Camera2D
## Smooth chase camera: looks ahead along the velocity, zooms out with speed,
## optionally rotates with the car, and adds small shakes for curbs and impacts.

@export var zoom_slow := 1.5
@export var zoom_fast := 0.72
@export var zoom_speed_range := 80.0     # m/s at which the camera is fully zoomed out
@export var look_ahead_time := 0.55
@export var max_look_ahead := 300.0      # pixels
@export var follow_rate := 6.0
@export var rotation_rate := 3.2

var target: VehicleController
var rotate_with_car := false
var _shake := 0.0
var _look := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	ignore_rotation = false
	position_smoothing_enabled = false
	zoom = Vector2(zoom_slow, zoom_slow)


func snap_to_target() -> void:
	if target:
		global_position = target.global_position
		_look = Vector2.ZERO
		rotation = (target.rotation + PI / 2.0) if rotate_with_car else 0.0


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if target == null:
		return
	var velocity := target.linear_velocity
	# With a rotating camera "ahead" is always up the screen, so less offset is needed.
	var want_look := (velocity * look_ahead_time).limit_length(150.0 if rotate_with_car else max_look_ahead)
	_look = _look.lerp(want_look, minf(1.0, 2.5 * delta))
	var goal := target.global_position + _look
	global_position = global_position.lerp(goal, minf(1.0, follow_rate * delta))
	var t := clampf(target.speed / zoom_speed_range, 0.0, 1.0)
	var want_zoom := lerpf(zoom_slow, zoom_fast, smoothstep(0.0, 1.0, t))
	var z := lerpf(zoom.x, want_zoom, minf(1.0, 1.8 * delta))
	zoom = Vector2(z, z)
	if rotate_with_car:
		# Slow, damped rotation keeps the horizon calm (no snap = no motion sickness).
		rotation = lerp_angle(rotation, target.rotation + PI / 2.0, minf(1.0, rotation_rate * delta))
	else:
		rotation = lerp_angle(rotation, 0.0, minf(1.0, 6.0 * delta))
	if target.on_curb and target.speed > 8.0:
		_shake = maxf(_shake, 1.6)
	if target.surface_rear >= VehiclePhysicsConfig.Surface.GRASS and target.speed > 8.0:
		_shake = maxf(_shake, 2.4)
	_shake = maxf(0.0, _shake - 14.0 * delta)
	offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
