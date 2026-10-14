class_name GhostRecorder
extends RefCounted
## Records position / rotation / timestamp for one lap and plays a stored lap back.
## Samples are stored flat as [t, x, y, rot, t, x, y, rot, ...] to keep the save small.

const INTERVAL := 0.1

var samples: Array = []
var _next_time := 0.0


func begin_lap() -> void:
	samples = []
	_next_time = 0.0


func record(lap_time: float, pos: Vector2, rot: float) -> void:
	if lap_time < _next_time:
		return
	_next_time = lap_time + INTERVAL
	samples.append(snappedf(lap_time, 0.001))
	samples.append(snappedf(pos.x, 0.1))
	samples.append(snappedf(pos.y, 0.1))
	samples.append(snappedf(rot, 0.001))


## Interpolated transform of a stored ghost at `lap_time`. Returns false when out of range.
static func sample(data: Array, lap_time: float, out: Dictionary) -> bool:
	var count := data.size() / 4
	if count < 2:
		return false
	var last_time: float = data[(count - 1) * 4]
	if lap_time > last_time + 0.5:
		return false
	var idx := clampi(int(lap_time / INTERVAL), 0, count - 2)
	while idx < count - 2 and float(data[(idx + 1) * 4]) < lap_time:
		idx += 1
	while idx > 0 and float(data[idx * 4]) > lap_time:
		idx -= 1
	var a := idx * 4
	var b := a + 4
	var span := maxf(float(data[b]) - float(data[a]), 0.001)
	var t := clampf((lap_time - float(data[a])) / span, 0.0, 1.0)
	out["position"] = Vector2(float(data[a + 1]), float(data[a + 2])).lerp(Vector2(float(data[b + 1]), float(data[b + 2])), t)
	out["rotation"] = lerp_angle(float(data[a + 3]), float(data[b + 3]), t)
	return true
