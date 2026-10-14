class_name TrackScenery
extends RefCounted
## Paints the world around a circuit from its TrackTheme: ground, water, roads and runways
## (drawn under the track), then buildings, vegetation, rocks, boats and landmarks (drawn
## around it). Everything is flat-shaded, axis-aligned geometry so it reads as pixel art.

const PPM := VehiclePhysicsConfig.PPM
const CELL := 12.0                 # metres, resolution of the "how far is the track" grid
const REACH := 6                   # cells marked around every centreline sample
const TREE_CLEAR := 27.0
const BUILDING_CLEAR := 31.0
const SHADOW := Color(0, 0, 0, 0.22)
const WATER := Color("2f7fb8")
const WATER_DEEP := Color("27699c")
const WATER_LIGHT := Color("6fb4dc")

var data: TrackData
var theme: Dictionary
var st: SurfaceTool
var rng := RandomNumberGenerator.new()
var _dist: Dictionary = {}         # Vector2i cell -> metres to the nearest piece of track
var _area := Rect2()
## Sea: everything beyond `_coast` along `_sea_dir` is water.
var _sea_dir := Vector2.ZERO
var _coast := 0.0
var _lakes: Array = []             # [centre (px), radius (m)]
var _buildings: Array = []         # [centre (px), radius (m)]
var _strips: Array = []            # runways: [centre (px), angle, half length (m), half width (m)]


func _init(track: TrackData, tool: SurfaceTool) -> void:
	data = track
	st = tool
	theme = TrackTheme.of(track.id)
	rng.seed = hash(track.id) & 0x7fffffff
	for i in range(0, data.count, 2):
		var p := data.points[i] / PPM
		var base := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
		for dy in range(-REACH, REACH + 1):
			for dx in range(-REACH, REACH + 1):
				var cell := base + Vector2i(dx, dy)
				var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
				var d := centre.distance_to(p)
				if d < float(_dist.get(cell, 999.0)):
					_dist[cell] = d


# ---------------------------------------------------------------- primitives

func _col(key: String) -> Color:
	return Color(str(theme[key]))


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(Vector3(a.x, a.y, 0)); st.add_vertex(Vector3(b.x, b.y, 0)); st.add_vertex(Vector3(c.x, c.y, 0))
	st.add_vertex(Vector3(a.x, a.y, 0)); st.add_vertex(Vector3(c.x, c.y, 0)); st.add_vertex(Vector3(d.x, d.y, 0))


## Axis-aligned box: `centre` in pixels, `half` in metres.
func _box(centre: Vector2, half: Vector2, color: Color) -> void:
	var h := half * PPM
	_quad(centre + Vector2(-h.x, -h.y), centre + Vector2(h.x, -h.y), centre + Vector2(h.x, h.y), centre + Vector2(-h.x, h.y), color)


func _rot_box(centre: Vector2, half: Vector2, angle: float, color: Color) -> void:
	var x := Vector2.RIGHT.rotated(angle) * half.x * PPM
	var y := Vector2.DOWN.rotated(angle) * half.y * PPM
	_quad(centre - x - y, centre + x - y, centre + x + y, centre - x + y, color)


func _disc(centre: Vector2, radius_m: float, color: Color, segments: int = 8, wobble: float = 0.0) -> void:
	st.set_color(color)
	var radii := PackedFloat32Array()
	for s in segments:
		radii.append(radius_m * PPM * (1.0 + (rng.randf_range(-wobble, wobble) if wobble > 0.0 else 0.0)))
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		st.add_vertex(Vector3(centre.x, centre.y, 0))
		st.add_vertex(Vector3(centre.x + cos(a0) * radii[s], centre.y + sin(a0) * radii[s], 0))
		st.add_vertex(Vector3(centre.x + cos(a1) * radii[(s + 1) % segments], centre.y + sin(a1) * radii[(s + 1) % segments], 0))


## Metres from `pos` (pixels) to the nearest centreline sample; 999 when far away.
func track_distance(pos: Vector2) -> float:
	var p := pos / PPM
	return float(_dist.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), 999.0))


func _exact_distance(pos: Vector2) -> float:
	var best := INF
	for i in range(0, data.count, 4):
		best = minf(best, pos.distance_squared_to(data.points[i]))
	return sqrt(best) / PPM


func in_water(pos: Vector2, margin_m: float = 0.0) -> bool:
	if _sea_dir != Vector2.ZERO and pos.dot(_sea_dir) > _coast - margin_m * PPM:
		return true
	for lake: Array in _lakes:
		if pos.distance_to(lake[0]) < (float(lake[1]) + margin_m) * PPM:
			return true
	return false


func _free(pos: Vector2, clear_m: float, water_margin: float = 3.0) -> bool:
	for strip: Array in _strips:
		var local := (pos - (strip[0] as Vector2)).rotated(-float(strip[1])) / PPM
		if absf(local.x) < float(strip[2]) + 8.0 and absf(local.y) < float(strip[3]) + 14.0:
			return false
	return track_distance(pos) > clear_m and not in_water(pos, water_margin)


func _random_point(grow_m: float = 260.0) -> Vector2:
	var area := data.bounds.grow(grow_m * PPM)
	return Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))


## A point beside the circuit, between `near_m` and `far_m` from the centreline and biased
## toward the track - where the camera actually looks.
func _trackside_point(near_m: float, far_m: float) -> Vector2:
	var i := rng.randi() % data.count
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	return data.points[i] + data.normals[i] * side * (near_m + (far_m - near_m) * pow(rng.randf(), 1.5)) * PPM


## Most scenery hugs the track; the rest fills in the distance.
func _scatter_point(near_m: float, far_m: float, wide_m: float) -> Vector2:
	return _trackside_point(near_m, far_m) if rng.randf() < 0.72 else _random_point(wide_m)


## The roomiest spots near the circuit (infield or just outside), best first.
func _open_spots(count: int, spacing_m: float) -> Array:
	var found: Array = []
	var samples: Array = []
	for i in 260:
		var p := _random_point(90.0)
		if in_water(p, 20.0):
			continue
		samples.append([_exact_distance(p), p])
	samples.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for s: Array in samples:
		var ok := true
		for f: Array in found:
			if (f[1] as Vector2).distance_to(s[1]) < spacing_m * PPM:
				ok = false
		if ok:
			found.append(s)
		if found.size() >= count:
			break
	return found


# ---------------------------------------------------------------- ground (under the track)

func ground(area: Rect2) -> void:
	_area = area
	var base := _col("ground")
	_quad(area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y), base)
	# Mown / wind-blown stripes.
	var stripe := 30.0 * PPM
	var y := area.position.y
	while y < area.end.y:
		_quad(Vector2(area.position.x, y), Vector2(area.end.x, y), Vector2(area.end.x, y + stripe), Vector2(area.position.x, y + stripe), _col("stripe"))
		y += stripe * 2.0
	# Large patches of a third tone break up the flat colour.
	for i in 70:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		_disc(p, rng.randf_range(18.0, 55.0), Color(_col("patch"), 0.55), 9, 0.25)
	match str(theme["landmark"]):
		"harbour":
			_city_streets()
		"airfield":
			_runways()
		"snow":
			for i in 60:
				var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
				_disc(p, rng.randf_range(6.0, 26.0), Color(0.93, 0.96, 0.98, 0.8), 9, 0.3)
		"ponds":
			for spot: Array in _open_spots(3, 160.0):
				if float(spot[0]) > 62.0:
					_lake(spot[1], clampf(float(spot[0]) - 46.0, 14.0, 44.0))
	match str(theme["water"]):
		"sea":
			_sea()
		"lake":
			var spots := _open_spots(1, 100.0)
			if not spots.is_empty() and float(spots[0][0]) > 80.0:
				_lake(spots[0][1], clampf(float(spots[0][0]) - 48.0, 30.0, 150.0))
			else:
				# No room inside the lap: the lake sits beyond the far corner.
				_lake(data.bounds.end + Vector2(170, 150) * PPM, 190.0)


func _sea() -> void:
	# The coast runs along whichever edge of the lap faces away from the pit lane.
	var n := data.normals[0]
	_sea_dir = Vector2(signf(n.x), 0) if absf(n.x) > absf(n.y) else Vector2(0, signf(n.y))
	var b := data.bounds
	var edge := (b.end.x if _sea_dir.x > 0.0 else -b.position.x) if _sea_dir.x != 0.0 else (b.end.y if _sea_dir.y > 0.0 else -b.position.y)
	_coast = edge + 62.0 * PPM
	var a := _area
	var along := Vector2(absf(_sea_dir.y), absf(_sea_dir.x))
	var lo := a.position.dot(along)
	var hi := a.end.dot(along)
	var far := (a.end.dot(_sea_dir) if (_sea_dir.x > 0.0 or _sea_dir.y > 0.0) else -a.position.dot(_sea_dir.abs()))
	var shore := Color("d9d2bd") if str(theme["landmark"]) == "harbour" else (Color("8d949a") if str(theme["landmark"]) == "snow" else Color("e2d6a8"))
	var strips := [[-7.0, 0.0, shore], [0.0, 16.0, WATER_LIGHT], [16.0, 9999.0, WATER]]
	for strip: Array in strips:
		var d0 := _coast + float(strip[0]) * PPM
		var d1 := minf(_coast + float(strip[1]) * PPM, far)
		_quad(_sea_dir * d0 + along * lo, _sea_dir * d0 + along * hi, _sea_dir * d1 + along * hi, _sea_dir * d1 + along * lo, strip[2])
	# Wave crests.
	for i in 420:
		var d := _coast + rng.randf_range(20.0, 400.0) * PPM
		if d > far:
			continue
		var c := _sea_dir * d + along * rng.randf_range(lo, hi)
		var half := Vector2(rng.randf_range(3.0, 9.0), 0.45) if _sea_dir.x == 0.0 else Vector2(0.45, rng.randf_range(3.0, 9.0))
		_box(c, half, Color(WATER_LIGHT, 0.7) if i % 3 > 0 else Color(WATER_DEEP, 0.8))


func _lake(centre: Vector2, radius_m: float) -> void:
	_lakes.append([centre, radius_m])
	var shore := Color("d8cfa6") if str(theme["landmark"]) != "ponds" else Color("2c5e2f")
	st.set_color(shore)
	var segs := 26
	var radii := PackedFloat32Array()
	for s in segs:
		radii.append(radius_m * (0.86 + 0.14 * sin(s * 1.7 + radius_m) * cos(s * 0.6)))
	for layer: Array in [[1.0, 3.0, shore], [1.0, 0.0, WATER], [0.72, 0.0, WATER_DEEP]]:
		st.set_color(layer[2])
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var r0 := (radii[s] * float(layer[0]) + float(layer[1])) * PPM
			var r1 := (radii[(s + 1) % segs] * float(layer[0]) + float(layer[1])) * PPM
			st.add_vertex(Vector3(centre.x, centre.y, 0))
			st.add_vertex(Vector3(centre.x + cos(a0) * r0, centre.y + sin(a0) * r0, 0))
			st.add_vertex(Vector3(centre.x + cos(a1) * r1, centre.y + sin(a1) * r1, 0))
	for i in int(radius_m * 0.5):
		var p := centre + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf() * radius_m * 0.6 * PPM
		_box(p, Vector2(rng.randf_range(1.5, 5.0), 0.35), Color(WATER_LIGHT, 0.75))


func _city_streets() -> void:
	var a := data.bounds.grow(300.0 * PPM)
	var pitch := 92.0 * PPM
	var road := Color("565b63")
	var x := floorf(a.position.x / pitch) * pitch
	while x < a.end.x:
		_quad(Vector2(x - 45, a.position.y), Vector2(x + 45, a.position.y), Vector2(x + 45, a.end.y), Vector2(x - 45, a.end.y), road)
		var y := a.position.y
		while y < a.end.y:
			_box(Vector2(x, y), Vector2(0.25, 2.2), Color("e8e3c8"))
			y += 9.0 * PPM
		x += pitch
	var yy := floorf(a.position.y / pitch) * pitch
	while yy < a.end.y:
		_quad(Vector2(a.position.x, yy - 45), Vector2(a.end.x, yy - 45), Vector2(a.end.x, yy + 45), Vector2(a.position.x, yy + 45), road)
		var xx := a.position.x
		while xx < a.end.x:
			_box(Vector2(xx, yy), Vector2(2.2, 0.25), Color("e8e3c8"))
			xx += 9.0 * PPM
		yy += pitch


func _runways() -> void:
	var c := data.bounds.get_center()
	var length := data.bounds.size.length() / PPM * 0.62
	for info: Array in [[0.32, 21.0], [1.9, 16.0]]:
		var angle: float = info[0]
		var half_w: float = info[1]
		_strips.append([c, angle, length, half_w])
		_rot_box(c, Vector2(length, half_w), angle, Color("6d7177"))
		_rot_box(c, Vector2(length, half_w - 1.2), angle, Color("767a80"))
		var dir := Vector2.RIGHT.rotated(angle)
		var side := Vector2.DOWN.rotated(angle)
		var d := -length + 30.0
		while d < length - 30.0:
			_rot_box(c + dir * d * PPM, Vector2(7.0, 0.5), angle, Color("e9ecef"))
			d += 26.0
		for end: float in [-1.0, 1.0]:
			for k in 8:
				_rot_box(c + dir * end * (length - 12.0) * PPM + side * (k - 3.5) * half_w * 0.22 * PPM, Vector2(7.0, half_w * 0.06), angle, Color("e9ecef"))


# ---------------------------------------------------------------- objects (around the track)

## Close-up texture: grass tufts and gravel by the track, aggregate in the asphalt,
## rubber laid down in the braking zones, catch fencing and tyre walls at the barriers.
func details() -> void:
	var hw := data.half_width
	var tuft_a := _col("patch").darkened(0.12)
	var tuft_b := _col("stripe").lightened(0.1)
	for i in 7000:
		var j := rng.randi() % data.count
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var d := hw + 2.0 + rng.randf() * 60.0
		var p := data.points[j] + data.normals[j] * side * d * PPM
		if track_distance(p) < hw + 2.0 or in_water(p):
			continue
		_box(p, Vector2(0.25, 0.25) * rng.randf_range(0.8, 1.8), tuft_a if rng.randf() < 0.6 else tuft_b)
	# Asphalt aggregate.
	for i in 9000:
		var j := rng.randi() % data.count
		var lat := rng.randf_range(-hw + 0.4, hw - 0.4)
		var p := data.points[j] + data.normals[j] * lat * PPM + data.tangents[j] * rng.randf_range(0.0, data.spacing) * PPM
		_box(p, Vector2(0.16, 0.16), Color(1, 1, 1, 0.07) if rng.randf() < 0.5 else Color(0, 0, 0, 0.12))
	# Rubber: two dark tyre tracks through every braking zone into the apex.
	for corner: Dictionary in data.corners:
		var from := data.index_at(float(corner["start"]) - 60.0)
		var to := data.index_at(float(corner["apex"]))
		var steps := posmod(to - from, data.count)
		for k in steps:
			var j := data.wrap_index(from + k)
			var t := float(k) / maxf(steps, 1)
			var lat := -float(corner["direction"]) * lerpf(hw * 0.55, -hw * 0.5, t * t)
			for wheel: float in [-0.8, 0.8]:
				var p := data.points[j] + data.normals[j] * (lat + wheel) * PPM
				_rot_box(p, Vector2(data.spacing * 0.55, 0.22), data.tangents[j].angle(), Color(0, 0, 0, 0.16 * (1.0 - t * 0.5)))
	# Catch fence just behind the barriers, with posts.
	for j in data.count:
		var n := data.wrap_index(j + 1)
		for side: float in [-1.0, 1.0]:
			var off := (data.barrier_right[j] if side > 0.0 else data.barrier_left[j]) + 2.0
			var off_n := (data.barrier_right[n] if side > 0.0 else data.barrier_left[n]) + 2.0
			var a := data.points[j] + data.normals[j] * side * off * PPM
			var b := data.points[n] + data.normals[n] * side * off_n * PPM
			var w := data.normals[j] * 0.08 * PPM
			_quad(a - w, b - w, b + w, a + w, Color(0.75, 0.78, 0.82, 0.55))
			if j % 3 == 0:
				_box(a, Vector2(0.2, 0.2), Color("4a4f57"))
	# Tyre walls where the gravel traps end at the barrier.
	for j in range(0, data.count, 1):
		for side: float in [-1.0, 1.0]:
			var gravel := data.gravel_right[j] if side > 0.0 else data.gravel_left[j]
			if gravel != 1 or j % 2 == 1:
				continue
			var off := (data.barrier_right[j] if side > 0.0 else data.barrier_left[j]) - 0.9
			for row in 2:
				var p := data.points[j] + data.normals[j] * side * (off - row * 0.8) * PPM
				_disc(p, 0.42, Color("16181c"), 6)
				_disc(p, 0.18, Color("f4f6f2") if (j / 2 + row) % 2 == 0 else Color("c8201e"), 5)


func objects() -> void:
	_trackside()
	_landmark()
	_place_buildings()
	_rocks()
	_vegetation()
	_boats()


## Advertising boards and marshal posts just behind the barriers, all the way round.
func _trackside() -> void:
	var brands := [Color("c8201e"), Color("f5c542"), Color("2f6fde"), Color("f4f6f2"), Color("14532d"), Color("ff8a2e"), Color("1f2a3a")]
	var step := int(72.0 / data.spacing)
	var k := 0
	for i in range(0, data.count, step):
		k += 1
		var side := 1.0 if k % 2 == 0 else -1.0
		# The pit lane, garages and main grandstands own the left of the start straight.
		if side < 0.0 and (i * data.spacing < data.pit_end + 80.0 or i * data.spacing > data.length - 200.0):
			continue
		var offset := (data.barrier_right[i] if side > 0.0 else data.barrier_left[i]) + 4.5
		var pos := data.points[i] + data.normals[i] * side * offset * PPM
		var angle := data.tangents[i].angle()
		if k % 3 == 0:
			# Marshal post: an orange hut with a white roof and a flag.
			_rot_box(pos + Vector2(0.8, 1.0) * PPM, Vector2(2.0, 1.5), angle, SHADOW)
			_rot_box(pos, Vector2(2.0, 1.5), angle, Color("ff7a2e"))
			_rot_box(pos, Vector2(1.5, 1.0), angle, Color("f4f6f2"))
			_rot_box(pos + data.tangents[i] * 3.0 * PPM, Vector2(0.5, 0.5), angle, Color("f5c542"))
		else:
			var brand: Color = brands[rng.randi() % brands.size()]
			_rot_box(pos + Vector2(0.6, 0.8) * PPM, Vector2(11.0, 0.7), angle, SHADOW)
			_rot_box(pos, Vector2(11.0, 0.7), angle, brand)
			for m in 4:
				_rot_box(pos + data.tangents[i] * (m - 1.5) * 5.0 * PPM, Vector2(1.2, 0.35), angle, Color.WHITE if brand.get_luminance() < 0.6 else UIKit.INK)
		reserve(pos, 9.0)


func _shadowed_box(centre: Vector2, half: Vector2, roof: Color, height_m: float = 3.0) -> void:
	_box(centre + Vector2(height_m, height_m * 1.3) * PPM * 0.6, half, SHADOW)
	# South and east walls show a sliver of the building's height.
	_box(centre + Vector2(0.9, 1.2) * PPM, half, roof.darkened(0.45))
	_box(centre, half, roof)


func _building(centre: Vector2, half: Vector2, style: String, detail: bool) -> void:
	_buildings.append([centre, half.length()])
	match style:
		"city":
			var roofs := ["b9b2a3", "8e949c", "c9a27e", "6f7782", "a8b3b0", "d6cdbb", "7c8a93", "b5694f"]
			var roof := Color(str(roofs[rng.randi() % roofs.size()]))
			var tall := rng.randf_range(3.0, 9.0)
			_shadowed_box(centre, half, roof, tall)
			_box(centre, half - Vector2(1.6, 1.6), roof.lightened(0.12))
			if not detail:
				return
			var kind := rng.randi() % 6
			if kind == 0 and half.x > 10.0:
				# Rooftop pool.
				_box(centre + Vector2(-half.x * 0.3, 0) * PPM, Vector2(half.x * 0.32, half.y * 0.4), Color("e8e2d2"))
				_box(centre + Vector2(-half.x * 0.3, 0) * PPM, Vector2(half.x * 0.26, half.y * 0.32), Color("4fb3d9"))
			elif kind == 1 and half.x > 11.0 and half.y > 11.0:
				# Helipad.
				_disc(centre, 7.0, Color("4a4f57"), 12)
				_disc(centre, 5.6, Color("e8c33a"), 12)
				_disc(centre, 4.8, Color("4a4f57"), 12)
				_box(centre + Vector2(-1.6, 0) * PPM, Vector2(0.5, 2.4), Color.WHITE)
				_box(centre + Vector2(1.6, 0) * PPM, Vector2(0.5, 2.4), Color.WHITE)
				_box(centre, Vector2(1.6, 0.5), Color.WHITE)
			else:
				# Skylights in a grid, plus a couple of air-con units.
				var cols := maxi(1, int(half.x / 4.5))
				var rows := maxi(1, int(half.y / 4.5))
				for cy in rows:
					for cx in cols:
						if rng.randf() < 0.35:
							continue
						var p := centre + Vector2((cx + 0.5) / cols * 2.0 - 1.0, (cy + 0.5) / rows * 2.0 - 1.0) * (half - Vector2(3, 3)) * PPM
						_box(p, Vector2(1.1, 1.1), Color("3f5f7a") if rng.randf() < 0.75 else Color("f2d77a"))
			for k in 2:
				var p := centre + Vector2(rng.randf_range(-0.6, 0.6) * half.x, rng.randf_range(-0.6, 0.6) * half.y) * PPM
				_box(p + Vector2(0.5, 0.6) * PPM, Vector2(1.3, 1.0), Color(0, 0, 0, 0.3))
				_box(p, Vector2(1.3, 1.0), Color("dfe3e6"))
		"adobe":
			var roof := Color(str(["d9b98a", "cfa878", "e3c79b", "c79a6c"][rng.randi() % 4]))
			_shadowed_box(centre, half, roof, 2.2)
			_box(centre, half - Vector2(1.0, 1.0), roof.lightened(0.1))
			_box(centre + Vector2(0, half.y - 0.6) * PPM, Vector2(1.0, 0.7), Color("4a3524"))
			_box(centre + Vector2(-half.x * 0.5, -half.y * 0.4) * PPM, Vector2(0.9, 0.9), Color("5b7f93"))
		"villa":
			var roof := Color(str(["b5482f", "a63e2a", "c0573a"][rng.randi() % 3]))
			# Garden hedge around the plot.
			_box(centre, half + Vector2(5.0, 5.0), Color("2a5a2c"))
			_box(centre, half + Vector2(3.6, 3.6), Color("4d8f45"))
			_shadowed_box(centre, half, roof, 3.5)
			_box(centre, Vector2(half.x, 0.5), roof.lightened(0.22))
			_box(centre + Vector2(0, -half.y * 0.5) * PPM, Vector2(half.x, 0.25), roof.darkened(0.15))
			_box(centre + Vector2(0, half.y * 0.5) * PPM, Vector2(half.x, 0.25), roof.darkened(0.15))
			_box(centre + Vector2(half.x * 0.5, -half.y * 0.5) * PPM, Vector2(0.9, 0.9), Color("e9e2d5"))
		"hangar":
			var roof := Color("b9c0c6")
			_shadowed_box(centre, half, roof, 5.0)
			var ribs := int(half.x / 2.2)
			for k in ribs:
				_box(centre + Vector2((k + 0.5) / ribs * 2.0 - 1.0, 0) * half.x * PPM, Vector2(0.45, half.y), roof.darkened(0.14) if k % 2 == 0 else roof.lightened(0.12))
			_box(centre + Vector2(0, half.y - 0.8) * PPM, Vector2(half.x * 0.7, 0.8), Color("3a4047"))
			_box(centre, Vector2(half.x, 0.4), Color("e0352b"))
		"cabin":
			var wall := Color(str(["8f2a22", "a3352a", "7a231d", "c9a23a"][rng.randi() % 4]))
			_shadowed_box(centre, half, Color("f1ede4"), 2.4)
			_box(centre, half - Vector2(0.6, 0.6), wall)
			_box(centre, Vector2(half.x - 0.6, 0.35), wall.darkened(0.35))
			if rng.randf() < 0.6:
				_box(centre + Vector2(0, -half.y * 0.5) * PPM, Vector2(half.x - 0.6, half.y * 0.42), Color(0.95, 0.97, 0.99, 0.9))
			_box(centre + Vector2(half.x * 0.5, half.y * 0.4) * PPM, Vector2(0.7, 0.7), Color("4a4f57"))


func _place_buildings() -> void:
	var style := str(theme["buildings"])
	if style == "city":
		# Fill every city block that is clear of the circuit with two-by-two lots.
		var a := data.bounds.grow(240.0 * PPM)
		var pitch := 92.0 * PPM
		var bx := floorf(a.position.x / pitch) * pitch
		while bx < a.end.x:
			var by := floorf(a.position.y / pitch) * pitch
			while by < a.end.y:
				for lot: Vector2 in [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)]:
					var c := Vector2(bx, by) + lot * pitch
					var half := Vector2(rng.randf_range(11.0, 16.5), rng.randf_range(11.0, 16.5))
					if rng.randf() < 0.1 or not _free(c, BUILDING_CLEAR + maxf(half.x, half.y), 22.0) or not _spaced(c, half.length()):
						continue
					if rng.randf() < 0.08:
						# A small square with trees instead of a building.
						_box(c, half, Color("4d8f45"))
						for k in 4:
							_tree("round", c + Vector2(rng.randf_range(-0.6, 0.6) * half.x, rng.randf_range(-0.6, 0.6) * half.y) * PPM)
						continue
					_building(c, half, "city", track_distance(c) < 150.0)
				by += pitch
			bx += pitch
		return
	var placed := 0
	var attempts := 0
	while placed < int(theme["building_count"]) and attempts < 1500:
		attempts += 1
		var c := _scatter_point(BUILDING_CLEAR + 12.0, 170.0, 200.0)
		var half := Vector2(rng.randf_range(5.0, 9.0), rng.randf_range(4.0, 7.0))
		if style == "hangar":
			half = Vector2(rng.randf_range(14.0, 20.0), rng.randf_range(9.0, 12.0))
		if not _free(c, BUILDING_CLEAR + half.length(), 14.0) or not _spaced(c, half.length() + 14.0):
			continue
		_building(c, half, style, true)
		placed += 1
		if style == "hangar" and rng.randf() < 0.7:
			var apron := c + Vector2(0, half.y + 16.0) * PPM
			if _free(apron, BUILDING_CLEAR + 8.0, 12.0) and _spaced(apron, 10.0):
				_plane(apron, rng.randi() % 4 * PI * 0.5)
				_buildings.append([apron, 10.0])


## Keeps scenery off something the track itself put there (grandstands).
func reserve(pos: Vector2, radius_m: float) -> void:
	_buildings.append([pos, radius_m])


func _spaced(pos: Vector2, radius_m: float) -> bool:
	for b: Array in _buildings:
		if pos.distance_to(b[0]) < (radius_m + float(b[1])) * PPM:
			return false
	return true


func _plane(centre: Vector2, angle: float) -> void:
	var body := Color(str(["f1f1f1", "e8c33a", "d9534a", "9fc3e0"][rng.randi() % 4]))
	_rot_box(centre + Vector2(2.5, 3.0) * PPM, Vector2(7.0, 1.1), angle, SHADOW)
	_rot_box(centre + Vector2(2.5, 3.0) * PPM, Vector2(1.6, 7.5), angle, SHADOW)
	_rot_box(centre, Vector2(7.0, 1.1), angle, body)
	var fwd := Vector2.RIGHT.rotated(angle)
	_rot_box(centre + fwd * 1.5 * PPM, Vector2(1.5, 7.5), angle, body.darkened(0.08))
	_rot_box(centre - fwd * 6.0 * PPM, Vector2(0.9, 2.8), angle, body.darkened(0.08))
	_rot_box(centre + fwd * 4.6 * PPM, Vector2(1.1, 0.8), angle, Color("3f5f7a"))
	_rot_box(centre + fwd * 7.2 * PPM, Vector2(0.25, 1.6), angle, Color("23272e"))


func _rocks() -> void:
	var count := int(theme["rocks"])
	var desert := str(theme["landmark"]) == "solar"
	var base := Color("8a5a3a") if desert else Color("6c7278")
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 12:
		attempts += 1
		var c := _scatter_point(TREE_CLEAR + 6.0, 180.0, 250.0)
		var r := rng.randf_range(3.0, 11.0) if rng.randf() < 0.75 else rng.randf_range(14.0, 26.0)
		if not _free(c, TREE_CLEAR + r, 4.0) or not _spaced(c, r):
			continue
		var tone := base.darkened(rng.randf_range(0.0, 0.18))
		_disc(c + Vector2(r * 0.25, r * 0.38) * PPM, r, SHADOW, 7, 0.22)
		_disc(c, r, tone, 7, 0.22)
		_disc(c - Vector2(r * 0.18, r * 0.2) * PPM, r * 0.62, tone.lightened(0.16), 6, 0.2)
		_disc(c - Vector2(r * 0.3, r * 0.32) * PPM, r * 0.28, tone.lightened(0.32), 5, 0.2)
		if r > 13.0:
			_buildings.append([c, r])           # mesas keep trees off their tops
		placed += 1


func _tree(kind: String, pos: Vector2) -> float:
	var a := _col("tree_a").darkened(rng.randf_range(0.0, 0.18))
	var b := _col("tree_b")
	match kind:
		"pine":
			var r := rng.randf_range(2.2, 4.2)
			_disc(pos + Vector2(r * 0.3, r * 0.42) * PPM, r, SHADOW, 6)
			_disc(pos, r, a, 6)
			_box(pos, Vector2(r * 0.85, r * 0.2), b)
			_box(pos, Vector2(r * 0.2, r * 0.85), b)
			_box(pos, Vector2(r * 0.22, r * 0.22), Color(0.95, 0.97, 0.99) if rng.randf() < 0.3 else b.lightened(0.25))
			return r
		"palm":
			var r := rng.randf_range(3.0, 4.6)
			var fronds := 7
			for f in fronds:
				var ang := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
				_rot_box(pos + Vector2(1.6, 2.0) * PPM + Vector2.RIGHT.rotated(ang) * r * 0.5 * PPM, Vector2(r * 0.5, r * 0.13), ang, SHADOW)
			for f in fronds:
				var ang := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
				_rot_box(pos + Vector2.RIGHT.rotated(ang) * r * 0.5 * PPM, Vector2(r * 0.5, r * 0.14), ang, a if f % 2 == 0 else b)
			_box(pos, Vector2(0.55, 0.55), Color("6b4a2b"))
			return r
		"cactus":
			var h := rng.randf_range(1.2, 2.2)
			_box(pos + Vector2(0.8, 1.0) * PPM, Vector2(0.5, h), SHADOW)
			_box(pos, Vector2(0.5, h), a)
			_box(pos + Vector2(-1.0, -h * 0.2) * PPM, Vector2(0.55, 0.35), a)
			_box(pos + Vector2(-1.3, -h * 0.5) * PPM, Vector2(0.3, 0.6), a)
			_box(pos + Vector2(1.0, h * 0.1) * PPM, Vector2(0.55, 0.35), a)
			_box(pos + Vector2(1.3, -h * 0.2) * PPM, Vector2(0.3, 0.6), a)
			_box(pos + Vector2(-0.2, 0) * PPM, Vector2(0.14, h * 0.8), b)
			return 1.5
		"shrub":
			var r := rng.randf_range(0.9, 2.0)
			_disc(pos + Vector2(0.4, 0.5) * PPM, r, SHADOW, 6)
			_disc(pos, r, a.lerp(Color("9a8f4f"), 0.45), 6)
			_disc(pos - Vector2(r * 0.2, r * 0.2) * PPM, r * 0.5, b.lerp(Color("b8ad63"), 0.4), 5)
			return r
		"hedge":
			var half := Vector2(rng.randf_range(5.0, 12.0), 1.1)
			if rng.randf() < 0.5:
				half = Vector2(half.y, half.x)
			_box(pos + Vector2(0.8, 1.0) * PPM, half, SHADOW)
			_box(pos, half, a)
			_box(pos - Vector2(0.2, 0.2) * PPM, half - Vector2(0.4, 0.4), b)
			return half.length()
	var r := rng.randf_range(2.6, 5.2)
	_disc(pos + Vector2(r * 0.25, r * 0.35) * PPM, r, SHADOW, 10)
	_disc(pos, r, a, 10)
	_disc(pos - Vector2(r * 0.22, r * 0.22) * PPM, r * 0.55, b, 8)
	return r


func _vegetation() -> void:
	var kinds: Array = theme["trees"]
	var target := int(theme["tree_count"])
	var placed := 0
	var attempts := 0
	while placed < target and attempts < target * 14:
		attempts += 1
		var pos := _scatter_point(TREE_CLEAR + 4.0, 150.0, 260.0)
		if not _free(pos, TREE_CLEAR + 4.0, 3.0) or not _spaced(pos, 3.0):
			continue
		_tree(str(kinds[rng.randi() % kinds.size()]), pos)
		placed += 1
	if str(theme["landmark"]) == "ponds":
		# Flower beds in the park.
		var beds := 0
		var tries := 0
		while beds < 26 and tries < 400:
			tries += 1
			var c := _random_point(120.0)
			if not _free(c, TREE_CLEAR + 6.0, 4.0) or not _spaced(c, 6.0):
				continue
			var petal := Color(str(["e0457b", "f2d43a", "f4f4f4", "e8642e", "b05fd6"][rng.randi() % 5]))
			_disc(c, 4.6, Color("2c5e2f"), 10)
			for k in 9:
				_box(c + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf() * 3.2 * PPM, Vector2(0.55, 0.55), petal)
			beds += 1


func _boats() -> void:
	var targets: Array = []
	if _sea_dir != Vector2.ZERO:
		var along := Vector2(absf(_sea_dir.y), absf(_sea_dir.x))
		var b := data.bounds.grow(160.0 * PPM)
		for i in (16 if str(theme["landmark"]) == "harbour" else 7):
			targets.append(_sea_dir * (_coast + rng.randf_range(26.0, 230.0) * PPM) + along * rng.randf_range(b.position.dot(along), b.end.dot(along)))
	for lake: Array in _lakes:
		if float(lake[1]) > 55.0:
			for i in 4:
				targets.append((lake[0] as Vector2) + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf() * float(lake[1]) * 0.5 * PPM)
	for p: Vector2 in targets:
		var ang := rng.randf() * TAU
		var fwd := Vector2.RIGHT.rotated(ang)
		if rng.randf() < 0.18 and _sea_dir != Vector2.ZERO:
			# Cargo ship.
			_rot_box(p, Vector2(30.0, 6.0), ang, Color("2b3440"))
			_rot_box(p + fwd * 30.0 * PPM, Vector2(4.0, 3.5), ang, Color("2b3440"))
			_rot_box(p - fwd * 22.0 * PPM, Vector2(5.0, 4.5), ang, Color("eceae4"))
			for k in 5:
				_rot_box(p + fwd * (k * 8.0 - 12.0) * PPM, Vector2(3.4, 4.6), ang, Color(str(["c8201e", "2f6fde", "e8a23a", "2e9e5b", "8e949c"][rng.randi() % 5])))
			_rot_box(p - fwd * 40.0 * PPM, Vector2(9.0, 2.2), ang, Color(1, 1, 1, 0.35))
			continue
		# Yacht or sailing boat with a wake.
		var length := rng.randf_range(5.0, 11.0)
		_rot_box(p - fwd * (length + 4.0) * PPM, Vector2(4.5, length * 0.16), ang, Color(1, 1, 1, 0.35))
		_rot_box(p, Vector2(length, length * 0.3), ang, Color("f6f6f2"))
		_rot_box(p + fwd * length * PPM, Vector2(length * 0.28, length * 0.18), ang, Color("f6f6f2"))
		_rot_box(p - fwd * length * 0.2 * PPM, Vector2(length * 0.45, length * 0.18), ang, Color("c9a27e") if rng.randf() < 0.5 else Color("3f5f7a"))
		_rot_box(p + fwd * length * 0.3 * PPM, Vector2(length * 0.12, length * 0.3), ang, Color(str(["c8201e", "2f6fde", "f2d43a"][rng.randi() % 3])))


func _landmark() -> void:
	match str(theme["landmark"]):
		"solar":
			for spot: Array in _open_spots(2, 220.0):
				var origin: Vector2 = spot[1]
				for row in 5:
					for col in 8:
						var c := origin + Vector2((col - 3.5) * 9.0, (row - 2.0) * 7.5) * PPM
						if not _free(c, BUILDING_CLEAR, 4.0):
							continue
						_box(c + Vector2(0.7, 0.9) * PPM, Vector2(3.6, 2.4), SHADOW)
						_box(c, Vector2(3.6, 2.4), Color("23415f"))
						_box(c, Vector2(3.3, 2.1), Color("2f6aa0"))
						_box(c, Vector2(3.3, 0.12), Color("9fc3e0"))
						_box(c, Vector2(0.12, 2.1), Color("9fc3e0"))
				_buildings.append([origin, 40.0])
		"harbour":
			var along := Vector2(absf(_sea_dir.y), absf(_sea_dir.x))
			var b := data.bounds.grow(140.0 * PPM)
			var lo := b.position.dot(along)
			var hi := b.end.dot(along)
			# Container stacks on the quay.
			var s := lo
			while s < hi:
				var c := _sea_dir * (_coast - 22.0 * PPM) + along * s
				if track_distance(c) > BUILDING_CLEAR + 10.0 and rng.randf() < 0.7:
					for k in 3:
						var half := Vector2(6.0, 1.3) if _sea_dir.x == 0.0 else Vector2(1.3, 6.0)
						var cc := c - _sea_dir * k * 3.2 * PPM
						_box(cc + Vector2(0.6, 0.8) * PPM, half, SHADOW)
						_box(cc, half, Color(str(["c8201e", "2f6fde", "e8a23a", "2e9e5b", "8e949c", "7d4fa8"][rng.randi() % 6])))
					_buildings.append([c - _sea_dir * 3.2 * PPM, 9.0])
				s += 17.0 * PPM
			# Gantry cranes reaching out over the water.
			for k in 4:
				var c := _sea_dir * (_coast - 6.0 * PPM) + along * lerpf(lo, hi, (k + 0.5) / 4.0)
				if track_distance(c) < BUILDING_CLEAR:
					continue
				var boom := Vector2(2.0, 26.0) if _sea_dir.x == 0.0 else Vector2(26.0, 2.0)
				_box(c + _sea_dir * 12.0 * PPM + Vector2(2.5, 3.0) * PPM, boom, SHADOW)
				for side: float in [-1.0, 1.0]:
					_box(c + along * side * 7.0 * PPM, Vector2(1.5, 1.5), Color("8a6a10"))
				_box(c + _sea_dir * 12.0 * PPM, boom, Color("e8b820"))
				_box(c + _sea_dir * 12.0 * PPM, boom * 0.45, Color("c8201e"))
				_box(c, Vector2(3.0, 3.0), Color("f1f1f1"))
		"airfield":
			# Control tower beside the widest open space.
			for spot: Array in _open_spots(1, 100.0):
				var c: Vector2 = spot[1]
				if _free(c, BUILDING_CLEAR + 8.0, 10.0):
					_box(c + Vector2(7.0, 9.0) * PPM, Vector2(5.0, 5.0), SHADOW)
					_box(c, Vector2(5.0, 5.0), Color("d7dbe0"))
					_box(c, Vector2(4.0, 4.0), Color("2f5f7f"))
					_box(c, Vector2(2.6, 2.6), Color("eef1f4"))
					_box(c, Vector2(0.5, 0.5), Color("c8201e"))
					_buildings.append([c, 9.0])
