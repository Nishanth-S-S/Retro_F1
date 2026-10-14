extends Node
## Dev tool: prints track facts and writes a top-down PNG. Run with
##   godot --headless res://scenes/tests/TrackCheck.tscn -- <out.png>

func _ready() -> void:
	var args0 := OS.get_cmdline_user_args()
	var t := TrackData.load_track("res://data/tracks/%s.json" % (args0[0] if args0.size() > 0 else "falcon_ridge"))
	print("length %.0f m, samples %d, spacing %.2f" % [t.length, t.count, t.spacing])
	var min_r := INF
	for k in t.curvature:
		min_r = minf(min_r, 1.0 / maxf(absf(k), 1e-5))
	print("min radius %.1f m" % min_r)
	print("%s: %d corners" % [t.display_name, t.corners.size()])
	var straight := 0.0
	for i in range(0, 90):
		if absf(t.curvature[i]) > 0.002:
			break
		straight = i * t.spacing
	print("straight after start line: %.0f m" % straight)
	var min_gap := INF
	for i in t.count:
		for j in range(i + 30, t.count):
			if t.count - (j - i) < 30:
				continue
			min_gap = minf(min_gap, t.points[i].distance_to(t.points[j]) / 10.0)
	print("min gap between separate sections %.1f m" % min_gap)
	var args := OS.get_cmdline_user_args().slice(1)
	if args.size() > 0:
		var scale := 0.1
		var b := t.bounds.grow(400.0)
		var img := Image.create(int(b.size.x * scale), int(b.size.y * scale), false, Image.FORMAT_RGB8)
		img.fill(Color("3d7a3a"))
		for i in t.count:
			for s in range(-30, 31):
				var lat := s / 30.0 * maxf(t.barrier_left[i], t.barrier_right[i])
				if lat < -t.barrier_left[i] or lat > t.barrier_right[i]:
					continue
				var p := (t.points[i] + t.normals[i] * lat * 10.0 - b.position) * scale
				var col := Color("c9b58a") if t.surface_at(lat, i) == 3 else (Color("d43d3d") if t.surface_at(lat, i) == 1 else (Color("2d3036") if absf(lat) <= t.half_width else Color("4c8f47")))
				if absf(lat - -t.barrier_left[i]) < 0.8 or absf(lat - t.barrier_right[i]) < 0.8:
					col = Color.WHITE
				for dx in 2:
					for dy in 2:
						img.set_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1), col)
		img.save_png(args[0])
	get_tree().quit()
