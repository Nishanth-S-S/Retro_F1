class_name TelemetryAnalyzer
extends RefCounted
## Turns raw telemetry into the post-session driving report and per-corner comparison.

const SLIDE_THRESHOLD := 0.45


static func driving_report(rec: TelemetryRecorder, track: TrackData) -> Dictionary:
	var speed := rec.channel("speed")
	var sliding := rec.channel("sliding")
	var front_temp := rec.channel("front_temp")
	var rear_temp := rec.channel("rear_temp")
	var progress := rec.channel("progress")
	var front_peak := 0.0
	var rear_peak := 0.0
	var slide_time := 0.0
	for i in rec.count:
		front_peak = maxf(front_peak, front_temp[i])
		rear_peak = maxf(rear_peak, rear_temp[i])
		if sliding[i] > SLIDE_THRESHOLD:
			slide_time += TelemetryRecorder.INTERVAL
	# Average corner entry speed over every corner entry seen in the session.
	var entry_sum := 0.0
	var entries := 0
	for corner: Dictionary in track.corners:
		var start: float = corner["start"]
		for i in range(1, rec.count):
			if progress[i - 1] < start and progress[i] >= start and progress[i] - progress[i - 1] < 30.0:
				entry_sum += speed[i]
				entries += 1
	return {
		"max_speed": rec.max_speed * 3.6,
		"avg_corner_entry": (entry_sum / entries * 3.6) if entries > 0 else 0.0,
		"front_peak": front_peak,
		"rear_peak": rear_peak,
		"sliding_time": slide_time,
	}


## Entry / minimum / exit speed (km/h) and time spent for every corner on one lap.
static func corner_stats(rec: TelemetryRecorder, track: TrackData, lap: int) -> Array:
	var out: Array = []
	var range_idx := rec.lap_range(lap)
	if range_idx.x < 0:
		return out
	var speed := rec.channel("speed")
	var progress := rec.channel("progress")
	var time := rec.channel("time")
	for corner: Dictionary in track.corners:
		var start: float = corner["start"]
		var end: float = corner["end"]
		var first := -1
		var last := -1
		var min_speed := INF
		for i in range(range_idx.x, range_idx.y + 1):
			if progress[i] >= start and progress[i] <= end:
				if first < 0:
					first = i
				last = i
				min_speed = minf(min_speed, speed[i])
		if first < 0 or last <= first:
			out.append({})
			continue
		out.append({
			"name": corner["name"],
			"entry": snappedf(speed[first] * 3.6, 0.1),
			"min": snappedf(min_speed * 3.6, 0.1),
			"exit": snappedf(speed[last] * 3.6, 0.1),
			"time": snappedf(time[last] - time[first], 0.001),
		})
	return out


## The corners where `lap` lost the most time against `reference`, worst first.
static func worst_corners(lap: Array, reference: Array, limit: int = 3) -> Array:
	var rows: Array = []
	for i in mini(lap.size(), reference.size()):
		var a: Dictionary = lap[i]
		var b: Dictionary = reference[i]
		if a.is_empty() or b.is_empty():
			continue
		rows.append({
			"name": a["name"], "min": a["min"], "best_min": b["min"],
			"entry": a["entry"], "best_entry": b["entry"], "exit": a["exit"], "best_exit": b["exit"],
			"loss": float(a["time"]) - float(b["time"]),
		})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["loss"] > y["loss"])
	return rows.slice(0, limit)


## Speed / throttle / brake against distance for one lap, downsampled for the graph.
static func lap_series(rec: TelemetryRecorder, lap: int) -> Dictionary:
	var range_idx := rec.lap_range(lap)
	var result := {"distance": [], "speed": [], "throttle": [], "brake": []}
	if range_idx.x < 0:
		return result
	var speed := rec.channel("speed")
	var progress := rec.channel("progress")
	var throttle := rec.channel("throttle")
	var brake := rec.channel("brake")
	var step := maxi(1, (range_idx.y - range_idx.x) / 400)
	for i in range(range_idx.x, range_idx.y + 1, step):
		result["distance"].append(snappedf(progress[i], 0.1))
		result["speed"].append(snappedf(speed[i] * 3.6, 0.1))
		result["throttle"].append(snappedf(throttle[i], 0.01))
		result["brake"].append(snappedf(brake[i], 0.01))
	return result
