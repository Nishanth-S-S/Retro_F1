class_name LapTimer
extends RefCounted
## Lap, sector and penalty timing for one car.

signal lap_finished(lap_time: float, valid: bool, lap_number: int)
signal sector_finished(sector: int, sector_time: float)
signal lap_invalidated

var track: TrackData
var gates: CheckpointManager
var started := false           # true once the car has crossed the start line
var laps_completed := 0
var lap_start := 0.0
var sector_start := 0.0
var sector := 0
var penalty := 0.0             # seconds added to the current lap (resets)
var current_valid := true
var last_lap := 0.0
var best_lap := 0.0
var lap_times: Array[float] = []
var lap_valid: Array[bool] = []
var current_sectors := PackedFloat32Array([0.0, 0.0, 0.0])
var last_sectors := PackedFloat32Array([0.0, 0.0, 0.0])
var best_sectors := PackedFloat32Array([0.0, 0.0, 0.0])
var finish_time := -1.0        # race time at which this car took the flag
var total_time := 0.0


func _init(track_data: TrackData) -> void:
	track = track_data
	gates = CheckpointManager.new(track_data)


func current_time(now: float) -> float:
	return (now - lap_start + penalty) if started else 0.0


func add_penalty(seconds: float) -> void:
	penalty += seconds


func invalidate() -> void:
	if current_valid and started:
		current_valid = false
		lap_invalidated.emit()


## Call once per physics step with the car's previous and current track progress.
func update(prev: float, now_progress: float, legal: bool, now: float, step: float) -> void:
	var result := gates.update(prev, now_progress, legal)
	var cross_time := now - step * (1.0 - gates.crossing_fraction)
	if started and not gates.lap_valid:
		invalidate()
	match result:
		CheckpointManager.Result.LAP:
			_finish_sector(2, cross_time)
			var lap_time := cross_time - lap_start + penalty
			laps_completed += 1
			last_lap = lap_time
			last_sectors = current_sectors.duplicate()
			lap_times.append(lap_time)
			lap_valid.append(current_valid)
			total_time += lap_time
			if current_valid and (best_lap <= 0.0 or lap_time < best_lap):
				best_lap = lap_time
			var was_valid := current_valid
			_begin_lap(cross_time)
			lap_finished.emit(lap_time, was_valid, laps_completed)
		CheckpointManager.Result.SHORTCUT:
			_begin_lap(cross_time)
			lap_invalidated.emit()
		CheckpointManager.Result.GATE:
			if not started:
				started = true
				_begin_lap(cross_time)
	if started and sector < 2:
		var f := CheckpointManager.crossing(track, prev, now_progress, track.sector_bounds[sector])
		if f >= 0.0:
			_finish_sector(sector, now - step * (1.0 - f))


func _begin_lap(time: float) -> void:
	lap_start = time
	sector_start = time
	sector = 0
	penalty = 0.0
	current_valid = true
	gates.lap_valid = true
	current_sectors = PackedFloat32Array([0.0, 0.0, 0.0])


func _finish_sector(index: int, time: float) -> void:
	if index != sector:
		return
	var sector_time := time - sector_start + (penalty if index == 2 else 0.0)
	current_sectors[index] = sector_time
	if current_valid and (best_sectors[index] <= 0.0 or sector_time < best_sectors[index]):
		best_sectors[index] = sector_time
	sector_start = time
	sector = mini(index + 1, 2)
	sector_finished.emit(index, sector_time)


static func format_time(seconds: float, show_sign: bool = false) -> String:
	if show_sign:
		return "%s%.3f" % ["+" if seconds >= 0.0 else "-", absf(seconds)]
	if seconds <= 0.0:
		return "-:--.---"
	var minutes := int(seconds) / 60
	return "%d:%06.3f" % [minutes, seconds - minutes * 60]
