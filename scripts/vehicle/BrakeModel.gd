class_name BrakeModel
extends RefCounted
## Analog brakes with front/rear bias and a simple disc temperature / fade model.

const AMBIENT_TEMP := 150.0
const FADE_START := 720.0
const FADE_RANGE := 260.0
const MAX_FADE := 0.32

var max_force := 16500.0
var front_bias := 0.56
var heat_capacity := 1.0
var cooling_rate := 1.0
var temperature := AMBIENT_TEMP


func configure(part: VehiclePart, bias: float, force_scale: float = 1.0) -> void:
	max_force = part.stat("max_brake_force", 16500.0) * force_scale
	heat_capacity = part.stat("heat_capacity", 1.0)
	cooling_rate = part.stat("cooling_rate", 1.0)
	front_bias = bias
	reset()


func reset() -> void:
	temperature = AMBIENT_TEMP


func fade_factor() -> float:
	return 1.0 - MAX_FADE * clampf((temperature - FADE_START) / FADE_RANGE, 0.0, 1.0)


func is_fading() -> bool:
	return temperature > FADE_START + 20.0


func front_force(pedal: float) -> float:
	return pedal * max_force * front_bias * fade_factor()


func rear_force(pedal: float) -> float:
	return pedal * max_force * (1.0 - front_bias) * fade_factor()


## `power` is the braking power actually dissipated (force * speed, in W).
func update(delta: float, power: float, speed: float) -> void:
	var heat := power * 0.0004 / heat_capacity
	var cooling := (temperature - AMBIENT_TEMP) * cooling_rate * (0.02 + speed * 0.0013)
	temperature += (heat - cooling) * delta
