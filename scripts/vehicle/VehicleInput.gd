class_name VehicleInput
extends RefCounted
## Driver intent: steering (-1..1), throttle (0..1), brake (0..1) and shift requests.
## The player's version blends keyboard and touch; AI drivers write the fields directly.
## Either way the vehicle only ever sees these analog requests.

const KEY_STEER_RATE := 3.2          # keyboard steering ramps so digital keys still feel analog
const KEY_STEER_RETURN := 5.5
const KEY_THROTTLE_RATE := 3.5
const KEY_BRAKE_RATE := 4.5
const KEY_RELEASE_RATE := 9.0

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var shift_up := false
var shift_down := false

## Set by MobileControls every frame.
var touch_steer := 0.0
var touch_steer_active := false
var touch_pedal := 0.0               # +1 full throttle, -1 full brake
var touch_pedal_active := false

var _key_steer := 0.0
var _key_throttle := 0.0
var _key_brake := 0.0


func clear() -> void:
	steer = 0.0
	throttle = 0.0
	brake = 0.0
	_key_steer = 0.0
	_key_throttle = 0.0
	_key_brake = 0.0


func update_player(delta: float) -> void:
	var sensitivity := float(GameManager.setting("steering_sensitivity"))
	var smoothing := float(GameManager.setting("steering_smoothing"))
	# --- keyboard (desktop debugging)
	var key_target := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var rate := KEY_STEER_RATE if absf(key_target) > 0.01 and signf(key_target) == signf(_key_steer) or _key_steer == 0.0 else KEY_STEER_RETURN
	_key_steer = move_toward(_key_steer, key_target, rate * delta)
	var t_pressed := Input.is_action_pressed("throttle")
	var b_pressed := Input.is_action_pressed("brake")
	_key_throttle = move_toward(_key_throttle, 1.0 if t_pressed else 0.0, (KEY_THROTTLE_RATE if t_pressed else KEY_RELEASE_RATE) * delta)
	_key_brake = move_toward(_key_brake, 1.0 if b_pressed else 0.0, (KEY_BRAKE_RATE if b_pressed else KEY_RELEASE_RATE) * delta)
	# --- touch (primary interface)
	var steer_target := _key_steer
	if touch_steer_active:
		# Slight non-linearity gives precision around centre without losing full lock.
		var shaped := signf(touch_steer) * pow(absf(touch_steer), 1.35)
		steer_target = clampf(shaped * sensitivity, -1.0, 1.0)
	elif absf(_key_steer) < 0.001:
		steer_target = 0.0
	var smooth_rate := lerpf(28.0, 5.0, clampf(smoothing, 0.0, 1.0))
	steer = lerpf(steer, steer_target, minf(1.0, smooth_rate * delta))
	throttle = _key_throttle
	brake = _key_brake
	if touch_pedal_active:
		throttle = maxf(throttle, clampf(touch_pedal, 0.0, 1.0))
		brake = maxf(brake, clampf(-touch_pedal, 0.0, 1.0))
	if Input.is_action_just_pressed("shift_up"):
		shift_up = true
	if Input.is_action_just_pressed("shift_down"):
		shift_down = true
