class_name CheckpointManager
extends RefCounted
## Ordered checkpoint gates for one car. A lap only counts when every gate was crossed in
## order; a gate crossed while outside track limits marks the lap invalid.

enum Result { NONE, GATE, LAP, SHORTCUT }

## Largest progress change in one physics step still treated as continuous driving (m).
const MAX_STEP := 30.0

var track: TrackData
var next_gate := 0             # index of the gate we expect next; 0 = start/finish line
var lap_valid := true
var crossing_fraction := 0.0   # where inside the last step the line was crossed (0..1)
var _armed := false            # becomes true after the first start-line crossing


func _init(track_data: TrackData) -> void:
	track = track_data


func reset() -> void:
	next_gate = 0
	lap_valid = true
	_armed = false


## Fraction (0..1) of the step at which `target` was crossed, or -1 if it was not.
static func crossing(track_data: TrackData, prev: float, now: float, target: float) -> float:
	var step := track_data.progress_delta(prev, now)
	if step <= 0.0 or step > MAX_STEP:
		return -1.0
	var to_target := track_data.progress_delta(prev, target)
	if to_target < 0.0 or to_target > step:
		return -1.0
	return to_target / step


func update(prev: float, now: float, legal: bool) -> Result:
	var gates := track.checkpoints
	# The start line itself.
	var f := crossing(track, prev, now, gates[0])
	if f >= 0.0:
		crossing_fraction = f
		if not _armed:
			_armed = true
			next_gate = 1
			lap_valid = true
			return Result.GATE
		if next_gate == 0:
			next_gate = 1
			return Result.LAP
		# Crossed the line without collecting every gate: shortcut, lap not counted.
		next_gate = 1
		return Result.SHORTCUT
	if next_gate > 0:
		f = crossing(track, prev, now, gates[next_gate])
		if f >= 0.0:
			if not legal:
				lap_valid = false
			next_gate = (next_gate + 1) % gates.size()
			return Result.GATE
	return Result.NONE
