extends Node
## Every imported circuit:  godot --headless res://scenes/tests/TrackImportTest.tscn
## Builds all 50 atlas tracks and checks: the lap closes without a seam jump, its length
## matches the importer, nothing is NaN, the pit lane and grid sit on a straight, heights stay
## in range, Suzuka's bridge separates its two levels, and track progress follows the route
## (nearest-sample lookups with a hint never jump to a neighbouring parallel section).

var _failures := 0


func _check(ok: bool, text: String) -> void:
	if not ok:
		print("FAIL  " + text)
		_failures += 1


func _ready() -> void:
	SaveManager.disabled = true
	var rows: Array = SaveManager.load_json("res://data/tracks/index.json")
	print("%d circuits in index.json" % rows.size())
	_check(rows.size() == 50, "the roster has exactly 50 circuits")
	for row: Dictionary in rows:
		var id: String = row["id"]
		var t := TrackData.load_track("res://data/tracks/%s.json" % id)
		_check(t.count > 200, "%s builds (%d samples)" % [id, t.count])
		_check(absf(t.length - float(row["length_m"])) < float(row["length_m"]) * 0.03, "%s length %.0f m vs %d m" % [id, t.length, int(row["length_m"])])
		var seam := t.points[0].distance_to(t.points[t.count - 1]) / TrackData.PPM
		_check(seam < t.spacing * 1.6, "%s closes cleanly (seam step %.1f m)" % [id, seam])
		var finite := true
		var max_step := 0.0
		for i in t.count:
			finite = finite and is_finite(t.points[i].x) and is_finite(t.points[i].y) and is_finite(t.heights[i])
			max_step = maxf(max_step, absf(t.heights[i] - t.heights[(i + 1) % t.count]))
		_check(finite, "%s has no NaN" % id)
		_check(max_step < 1.2, "%s elevation changes smoothly (%.2f m per sample)" % [id, max_step])
		# Pit lane on a straight: little curvature from just behind the line to the pit exit (the
		# pit lane is sized by the importer to the straight each circuit really has).
		var bend := 0.0
		for i in range(-int(40.0 / t.spacing), int(t.pit_end / t.spacing)):
			bend = maxf(bend, absf(t.curvature[t.wrap_index(i)]))
		_check(bend < 0.01, "%s start straight is straight enough (max curvature %.4f)" % [id, bend])
		# Progress follows the route: walk the centreline with hints like a car does.
		var hint := 0
		var jumps := 0
		for i in range(0, t.count, 2):
			var j := t.nearest_index(t.points[i], hint)
			if absi(posmod(j - i + t.count / 2, t.count) - t.count / 2) > 3:
				jumps += 1
			hint = j
		_check(jumps == 0, "%s progress never jumps sections (%d jumps)" % [id, jumps])
		if not t.bridges.is_empty():
			var b: Dictionary = t.bridges[0]
			var gap := t.height_at(t.index_at(float(b["over"]))) - t.height_at(t.index_at(float(b["under"])))
			_check(gap > 6.0, "%s bridge clears the road below by %.1f m" % [id, gap])
			print("     %s crossover: %.1f m vertical separation" % [id, gap])
	print("TRACK IMPORT TEST PASSED" if _failures == 0 else "TRACK IMPORT TEST FAILED (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
