class_name TelemetryRecorder
extends RefCounted
## Samples the player's car at ~20 Hz into flat packed arrays (bounded memory).

const INTERVAL := 0.05
const MAX_SAMPLES := 30000        # 25 minutes
const CHANNELS: PackedStringArray = ["time", "lap", "progress", "x", "y", "speed", "throttle", "brake", "steering", "gear", "rpm", "front_slip", "rear_slip", "front_temp", "rear_temp", "sliding"]

var data: Dictionary = {}
var count := 0
var max_speed := 0.0
var _next := 0.0


func _init() -> void:
	for channel in CHANNELS:
		data[channel] = PackedFloat32Array()


func record(time: float, lap: int, car: VehicleController) -> void:
	max_speed = maxf(max_speed, car.speed)
	if time < _next or count >= MAX_SAMPLES:
		return
	_next = time + INTERVAL
	var p := car.physics
	_push("time", time)
	_push("lap", lap)
	_push("progress", car.progress)
	_push("x", car.global_position.x)
	_push("y", car.global_position.y)
	_push("speed", car.speed)
	_push("throttle", car.input.throttle)
	_push("brake", car.input.brake)
	_push("steering", car.input.steer)
	_push("gear", p.transmission.gear)
	_push("rpm", p.display_rpm)
	_push("front_slip", p.front_tire.slip_angle)
	_push("rear_slip", p.rear_tire.slip_angle)
	_push("front_temp", p.front_tire.temperature)
	_push("rear_temp", p.rear_tire.temperature)
	_push("sliding", maxf(p.front_tire.sliding, p.rear_tire.sliding) if car.speed > 5.0 else 0.0)
	count += 1


func _push(channel: String, value: float) -> void:
	var arr: PackedFloat32Array = data[channel]
	arr.append(value)
	data[channel] = arr


func channel(name: String) -> PackedFloat32Array:
	return data[name]


## [first, last] sample indices belonging to a lap number, or [-1, -1].
func lap_range(lap: int) -> Vector2i:
	var laps: PackedFloat32Array = data["lap"]
	var first := -1
	var last := -1
	for i in count:
		if int(laps[i]) == lap:
			if first < 0:
				first = i
			last = i
	return Vector2i(first, last)
