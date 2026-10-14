class_name LapTrace
extends RefCounted
## Elapsed lap time sampled against track distance. Comparing the current lap to the
## personal-best trace at the same distance gives the live delta.

const BIN := 20.0     # metres

var times := PackedFloat32Array()
var _bins := 0
var _last_bin := -1


func _init(track_length: float) -> void:
	_bins = int(ceil(track_length / BIN)) + 1
	clear()


func clear() -> void:
	times.resize(_bins)
	times.fill(-1.0)
	_last_bin = -1


func record(progress: float, lap_time: float) -> void:
	var bin := clampi(int(progress / BIN), 0, _bins - 1)
	if bin > _last_bin:
		# Fill any bins skipped in one step so the trace has no holes.
		for b in range(_last_bin + 1, bin + 1):
			times[b] = lap_time
		_last_bin = bin


## Reference lap time at a given distance, or -1 when unknown.
static func time_at(reference: Array, progress: float) -> float:
	if reference.is_empty():
		return -1.0
	var f := progress / BIN
	var i := clampi(int(f), 0, reference.size() - 1)
	var j := mini(i + 1, reference.size() - 1)
	var a: float = reference[i]
	var b: float = reference[j]
	if a < 0.0:
		return -1.0
	if b < a:
		return a
	return lerpf(a, b, clampf(f - i, 0.0, 1.0))


func to_array() -> Array:
	var out: Array = []
	var last := 0.0
	for t in times:
		if t >= 0.0:
			last = t
		out.append(snappedf(last, 0.001))
	return out
