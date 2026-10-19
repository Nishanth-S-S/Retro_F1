class_name Landmarks2D
extends RefCounted
## Each circuit's identity pieces on the 2D map, drawn top-down in the game's pixel style:
## Monza's old banking and footbridges, Monaco's tunnel and yachts, the Sakhir tower, the COTA
## tower, the Indianapolis Pagoda, stadium bowls, Marina Bay's hotel and Ferris wheel, the Yas
## hotel canopy, Baku's castle walls and Flame Towers, the Las Vegas Sphere, skylines,
## mountains and Mount Fuji, crowd banks and floodlights.
##
## Ground-level pieces go into the track mesh (before buildings and trees, which then avoid
## them); pieces that pass over the cars (bridges, the tunnel roof, the hotel canopy) go into a
## semi-transparent overlay drawn above the cars. Positions are artistic interpretations: they
## follow the atlas staging zones where those give a hint, otherwise authored spots on the lap.
## Everything is deterministic per circuit.

const PPM := VehiclePhysicsConfig.PPM
const SHADOW := Color(0, 0, 0, 0.24)
const CONCRETE := Color("c9ccd1")
const STONE := Color("b9a27c")

## How each landmark type is placed (see _place).
const RULES := {
	"old_banking": ["lap", 0.08, 0.3, 0.0, 60.0], "tunnel": ["lap", 0.52, 0.58, 0.0, 0.0],
	"castle_walls": ["lap", 0.35, 0.47, 0.0, 3.0], "yas_hotel": ["lap", 0.4, 0.48, 0.0, 0.0],
	"casino_towers": ["lap", 0.6, 0.95, 1.0, 40.0],
	"pedestrian_bridges": ["across", [0.2, 0.47, 0.72]], "overpass": ["across", [0.62]], "dunlop_bridge": ["across", [0.06]],
	"historic_pits": ["start", 120.0, -1.0, 26.0], "sakhir_tower": ["start", 160.0, -1.0, 60.0], "wing_building": ["start", 150.0, -1.0, 24.0],
	"pagoda": ["start", 200.0, -1.0, 50.0], "control_tower": ["start", 220.0, -1.0, 70.0],
	"umbrella_stands": ["start", 120.0, 1.0, 10.0], "grandstand_large": ["start", 160.0, 1.0, 10.0], "shanghai_stands": ["start", 150.0, 1.0, 10.0], "oval_stands": ["start", 140.0, 1.0, 10.0],
	"cota_tower": ["corner", 0, 45.0], "casino": ["corner", 1, 18.0], "hill_stands": ["corner", 2, 12.0], "foro_sol_stadium": ["corner", 3, 25.0],
	"motodrom_stadium": ["corner", 3, 25.0], "sphere": ["corner", 0, 80.0], "ferris_wheel": ["corner", 4, 60.0], "bull_sculpture": ["corner", 1, 40.0],
	"hard_rock_stadium": ["zone", "Architecture massing"], "olympic_stadium": ["zone", "Architecture massing"], "marina_hotel": ["zone", "Architecture massing"],
	"exhibition_halls": ["zone", "Architecture massing"], "airfield_hangars": ["zone", "Architecture massing"], "favela_housing": ["zone", "Architecture massing"],
	"skyline": ["zone", "Distant identity layer"], "flame_towers": ["zone", "Distant identity layer"], "mountains": ["zone", "Distant identity layer"],
	"mount_fuji": ["zone", "Distant identity layer"], "castle_hill": ["zone", "Distant identity layer"],
	"harbour_yachts": ["water"],
}

var data: TrackData
var scenery: TrackScenery
var ground: SurfaceTool
var overlay := SurfaceTool.new()
var overlay_used := false
## Extra night light pools (positions in pixels) for NightLights.
var lamps := PackedVector2Array()
var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()


func _init(track: TrackData, ground_st: SurfaceTool, scene: TrackScenery) -> void:
	data = track
	ground = ground_st
	scenery = scene
	overlay.begin(Mesh.PRIMITIVE_TRIANGLES)
	_rng.seed = hash(track.id + "landmarks2d")


func build() -> void:
	for entry: String in data.landmarks:
		var parts := entry.split(":")
		var type := parts[0]
		var arg := parts[1] if parts.size() > 1 else ""
		if not RULES.has(type) or not has_method("_" + type):
			continue
		for item: Dictionary in _place(type):
			item["arg"] = arg
			_st = ground
			call("_" + type, item)


# ---------------------------------------------------------------- placement

func _side_point(progress: float, side: float, offset: float) -> Dictionary:
	var i := data.index_at(progress)
	var s := side
	if s == 0.0:
		s = -signf(data.curvature[i]) if absf(data.curvature[i]) > 0.0005 else 1.0
	var barrier := data.barrier_right[i] if s > 0.0 else data.barrier_left[i]
	return {"pos": data.points[i] + data.normals[i] * s * (barrier + offset) * PPM, "angle": data.tangents[i].angle(), "progress": progress, "side": s, "index": i}


func _zone_center(purpose: String) -> Vector2:
	for z: Dictionary in data.zones:
		if str(z.get("purpose", "")) == purpose:
			var r: Array = z["rect_m"]
			return Vector2((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5) * PPM
	return data.bounds.get_center() + Vector2(data.bounds.size.x * 0.7, -data.bounds.size.y * 0.6)


func _place(type: String) -> Array:
	var rule: Array = RULES[type]
	match str(rule[0]):
		"lap":
			var item := _side_point(float(rule[1]) * data.length, float(rule[3]), float(rule[4]))
			item["to"] = float(rule[2]) * data.length
			return [item]
		"across":
			var out: Array = []
			for f: float in rule[1]:
				var i := data.index_at(f * data.length)
				out.append({"pos": data.points[i], "angle": data.tangents[i].angle(), "index": i, "progress": f * data.length, "side": 0.0})
			return out
		"start":
			return [_side_point(float(rule[1]), float(rule[2]), float(rule[3]))]
		"corner":
			var list := data.corners.filter(func(c: Dictionary) -> bool: return float(c["apex"]) > data.pit_end + 80.0 and float(c["apex"]) < data.length - 200.0)
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["radius"]) < float(b["radius"]))
			if list.is_empty():
				return []
			var c: Dictionary = list[mini(int(rule[1]), list.size() - 1)]
			return [_side_point(float(c["apex"]), 0.0, float(rule[2]))]
		"zone":
			return [{"pos": _zone_center(str(rule[1])), "angle": 0.0, "side": 0.0, "index": -1}]
		"water":
			return [{"pos": Vector2.ZERO, "angle": 0.0, "side": 0.0, "index": -1}]
	return []


# ---------------------------------------------------------------- drawing helpers

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_st.set_color(color)
	for p: Vector2 in [a, b, c, a, c, d]:
		_st.add_vertex(Vector3(p.x, p.y, 0))


func _rbox(centre: Vector2, half: Vector2, angle: float, color: Color) -> void:
	var x := Vector2.RIGHT.rotated(angle) * half.x * PPM
	var y := Vector2.DOWN.rotated(angle) * half.y * PPM
	_quad(centre - x - y, centre + x - y, centre + x + y, centre - x + y, color)


## A block with a cast shadow (taller = longer shadow), roof highlight.
func _block(centre: Vector2, half: Vector2, angle: float, roof: Color, height_m: float) -> void:
	_rbox(centre + Vector2(0.35, 0.5) * height_m * PPM * 0.5, half, angle, SHADOW)
	_rbox(centre, half, angle, roof)
	_rbox(centre, half - Vector2(0.8, 0.8), angle, roof.lightened(0.1))
	if scenery:
		scenery.reserve(centre, half.length() + 4.0)


func _disc(centre: Vector2, radius_m: float, color: Color, segments: int = 16) -> void:
	_st.set_color(color)
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		for p: Vector2 in [centre, centre + Vector2(cos(a1), sin(a1)) * radius_m * PPM, centre + Vector2(cos(a0), sin(a0)) * radius_m * PPM]:
			_st.add_vertex(Vector3(p.x, p.y, 0))


func _ring(centre: Vector2, radius_m: float, width_m: float, color: Color, segments: int = 28, squash: float = 1.0) -> void:
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		var r0 := radius_m * PPM
		var r1 := (radius_m + width_m) * PPM
		_quad(centre + Vector2(cos(a0) * r0, sin(a0) * r0 * squash), centre + Vector2(cos(a1) * r0, sin(a1) * r0 * squash),
			centre + Vector2(cos(a1) * r1, sin(a1) * r1 * squash), centre + Vector2(cos(a0) * r1, sin(a0) * r1 * squash), color)


func _line(a: Vector2, b: Vector2, width_m: float, color: Color) -> void:
	var d := (b - a).normalized().orthogonal() * width_m * 0.5 * PPM
	_quad(a - d, b - d, b + d, a + d, color)


func _crowd(centre: Vector2, half: Vector2, angle: float) -> void:
	var shirts := [Color("c8201e"), Color("f4f6f2"), Color("14532d"), Color("f5c542"), Color("2f6fde"), Color("ff8a2e"), Color("1f2a3a")]
	var x := Vector2.RIGHT.rotated(angle)
	var y := Vector2.DOWN.rotated(angle)
	var step := 1.7
	for r in int(half.y * 2.0 / step):
		for c in int(half.x * 2.0 / step):
			if _rng.randf() < 0.14:
				continue
			var p := centre + (x * (-half.x + (c + 0.5) * step) + y * (-half.y + (r + 0.5) * step)) * PPM
			_rbox(p, Vector2(0.3, 0.3), angle, shirts[_rng.randi() % shirts.size()])


# ---------------------------------------------------------------- landmarks

func _old_banking(item: Dictionary) -> void:
	# The preserved banking: a broad concrete band, darker towards its high outer lip, with a
	# shadow on the outside where it drops away.
	var side := float(item["side"])
	var p := float(item["progress"])
	var prev := []
	while p <= float(item["to"]):
		var i := data.index_at(p)
		var barrier := data.barrier_right[i] if side > 0.0 else data.barrier_left[i]
		var inner := data.points[i] + data.normals[i] * side * (barrier + 60.0) * PPM
		var outer := inner + data.normals[i] * side * 15.0 * PPM
		var lip := outer + data.normals[i] * side * 3.0 * PPM
		if not prev.is_empty():
			_quad(prev[0], inner, outer, prev[1], CONCRETE.darkened(0.04 if int(p / 20.0) % 2 == 0 else 0.1))
			_quad(prev[1], outer, lip, prev[2], Color("8e8676"))
			_quad(prev[2], lip, lip + data.normals[i] * side * 4.0 * PPM, prev[2] + data.normals[i] * side * 4.0 * PPM, SHADOW)
		if scenery:
			scenery.reserve((inner + outer) * 0.5, 14.0)
		prev = [inner, outer, lip]
		p += 10.0


func _bridge(item: Dictionary, width_m: float, color: Color, extra: float) -> void:
	# Over the cars: drawn into the overlay.
	_st = overlay
	overlay_used = true
	var i: int = item["index"]
	var half := maxf(data.barrier_left[i], data.barrier_right[i]) + extra
	var c: Vector2 = item["pos"]
	var n := data.normals[i]
	var t := data.tangents[i]
	var a := c - n * half * PPM
	var b := c + n * half * PPM
	_line(a + Vector2(10, 14), b + Vector2(10, 14), width_m, Color(0, 0, 0, 0.18))
	_line(a, b, width_m, Color(color, 0.92))
	_line(a + t * width_m * 0.45 * PPM, b + t * width_m * 0.45 * PPM, 0.3, Color("3a3f48"))
	_line(a - t * width_m * 0.45 * PPM, b - t * width_m * 0.45 * PPM, 0.3, Color("3a3f48"))
	_st = ground
	for side: float in [-1.0, 1.0]:
		_block(c + n * side * (half + 2.0) * PPM, Vector2(width_m * 0.6, 2.5), t.angle(), color.darkened(0.15), 6.0)


func _pedestrian_bridges(item: Dictionary) -> void:
	_bridge(item, 3.2, Color("d7dbe0"), 6.0)


func _overpass(item: Dictionary) -> void:
	_bridge(item, 11.0, CONCRETE, 18.0)


func _dunlop_bridge(item: Dictionary) -> void:
	_bridge(item, 4.5, Color("f5c542"), 5.0)


func _tunnel(item: Dictionary) -> void:
	# A roof over the road: shaded overlay with ceiling lights, cars visible beneath it.
	_st = overlay
	overlay_used = true
	var p := float(item["progress"])
	while p < float(item["to"]):
		var i := data.index_at(p)
		var j := data.index_at(p + 6.0)
		var hw := data.half_width_at(i) + 4.0
		var hj := data.half_width_at(j) + 4.0
		_quad(data.points[i] - data.normals[i] * hw * PPM, data.points[j] - data.normals[j] * hj * PPM, data.points[j] + data.normals[j] * hj * PPM, data.points[i] + data.normals[i] * hw * PPM, Color(0.42, 0.42, 0.44, 0.55))
		if int(p / 6.0) % 3 == 0:
			_rbox(data.points[i], Vector2(1.2, 0.3), data.tangents[i].angle(), Color(1.0, 0.93, 0.7, 0.75))
		lamps.append(data.points[i])
		p += 6.0
	_st = ground


func _castle_walls(item: Dictionary) -> void:
	var p := float(item["progress"])
	while p < float(item["to"]):
		var i := data.index_at(p)
		for side: float in [-1.0, 1.0]:
			var barrier := data.barrier_right[i] if side > 0.0 else data.barrier_left[i]
			var at := data.points[i] + data.normals[i] * side * (barrier + 2.5) * PPM
			_block(at, Vector2(3.2, 1.2), data.tangents[i].angle(), STONE, 8.0)
			if int(p / 6.0) % 2 == 0:
				_rbox(at, Vector2(0.8, 1.3), data.tangents[i].angle(), STONE.lightened(0.12))
			if int(p / 6.0) % 8 == 0:
				_block(at + data.normals[i] * side * 2.0 * PPM, Vector2(2.8, 2.8), data.tangents[i].angle(), STONE.darkened(0.1), 14.0)
		p += 6.0


func _yas_hotel(item: Dictionary) -> void:
	var i := data.index_at(float(item["progress"]))
	var c := data.points[i]
	var n := data.normals[i]
	var span := maxf(data.barrier_left[i], data.barrier_right[i]) + 14.0
	for side: float in [-1.0, 1.0]:
		_block(c + n * side * span * PPM, Vector2(45, 11), data.tangents[i].angle(), Color("e8ecef"), 30.0)
	# The gridshell canopy over the track (overlay), glowing at night.
	_st = overlay
	overlay_used = true
	for gx in range(-8, 9):
		var a := c + data.tangents[i] * gx * 5.5 * PPM - n * (span + 10.0) * PPM
		var b := c + data.tangents[i] * gx * 5.5 * PPM + n * (span + 10.0) * PPM
		_line(a, b, 0.5, Color(0.6, 0.72, 1.0, 0.55))
	for gz in range(-6, 7):
		var off := n * gz * (span + 10.0) / 6.0 * PPM
		_line(c - data.tangents[i] * 46.0 * PPM + off, c + data.tangents[i] * 46.0 * PPM + off, 0.5, Color(0.78, 0.58, 1.0, 0.5))
	lamps.append(c)
	_st = ground


func _casino_towers(item: Dictionary) -> void:
	var p := float(item["progress"])
	while p < float(item["to"]):
		var it := _side_point(p, 1.0, 40.0 + _rng.randf_range(0, 40))
		_block(it["pos"], Vector2(_rng.randf_range(15, 28), _rng.randf_range(12, 20)), float(it["angle"]), [Color("e8d2b0"), Color("d6cdbb"), Color("c9a27e"), Color("eef1f4")][int(p) % 4], 90.0)
		lamps.append(it["pos"])
		p += 240.0


func _historic_pits(item: Dictionary) -> void:
	_block(item["pos"], Vector2(75, 6), float(item["angle"]), Color("a0563c"), 10.0)
	for k in 15:
		_rbox(item["pos"] + Vector2.RIGHT.rotated(float(item["angle"])) * (-70.0 + k * 10.0) * PPM, Vector2(2.4, 5.5), float(item["angle"]), Color("8a4630"))


func _wing_building(item: Dictionary) -> void:
	_block(item["pos"], Vector2(120, 13), float(item["angle"]), Color("eef1f4"), 18.0)
	for k in 12:
		_rbox(item["pos"] + Vector2.RIGHT.rotated(float(item["angle"])) * (-110.0 + k * 20.0) * PPM, Vector2(0.4, 12.5), float(item["angle"]), Color("c9ced6"))


func _sakhir_tower(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	_disc(p + Vector2(18, 26) * PPM * 0.5, 15.0, SHADOW)
	_disc(p, 15.0, Color("eadcbc"))
	_disc(p, 11.0, Color("3a5a7a"))
	_disc(p, 8.0, Color("d8c49a"))
	if scenery:
		scenery.reserve(p, 20.0)


func _cota_tower(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	for k in 16:
		var a := TAU * k / 16.0
		_line(p, p + Vector2(cos(a), sin(a)) * 22.0 * PPM, 0.6, Color("c8201e"))
	_disc(p + Vector2(20, 30) * PPM * 0.4, 6.0, SHADOW)
	_disc(p, 6.0, Color("dfe3e8"))
	_disc(p, 2.0, Color("c8201e"))
	if scenery:
		scenery.reserve(p, 26.0)


func _pagoda(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	for s in 6:
		_block(p, Vector2(12 - s * 1.6, 12 - s * 1.6), float(item["angle"]), Color("eef1f4") if s % 2 == 0 else Color("3a3f48"), 40.0 - s * 6.0)


func _control_tower(item: Dictionary) -> void:
	_block(item["pos"], Vector2(4, 4), 0.0, CONCRETE, 30.0)
	_rbox(item["pos"], Vector2(6, 6), 0.0, Color("3a5a7a"))


func _casino(item: Dictionary) -> void:
	_block(item["pos"], Vector2(20, 13), float(item["angle"]), Color("efe3c8"), 18.0)
	_disc(item["pos"], 6.0, Color("7a8f6a"))


func _bull_sculpture(item: Dictionary) -> void:
	_block(item["pos"], Vector2(7, 2.5), float(item["angle"]), Color("c8201e"), 8.0)
	_rbox(item["pos"] + Vector2.RIGHT.rotated(float(item["angle"])) * 8.0 * PPM, Vector2(2, 2), float(item["angle"]), Color("c8201e"))


func _stands(item: Dictionary, half: Vector2, roof: bool) -> void:
	var p: Vector2 = item["pos"]
	var ang := float(item["angle"])
	for k: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		if data.distance_to_road_m((p + Vector2.RIGHT.rotated(ang) * k * half.x * PPM) / PPM, 40.0) < half.y + 4.0:
			return                      # would sit on another part of the circuit
	_rbox(p + Vector2(5, 7), half, ang, SHADOW)
	_rbox(p, half, ang, Color("58616e"))
	_crowd(p, half - Vector2(1, 1), ang)
	if roof:
		_st = overlay
		overlay_used = true
		_rbox(p + Vector2.DOWN.rotated(ang) * float(item["side"]) * half.y * 0.4 * PPM, Vector2(half.x, half.y * 0.6), ang, Color(0.93, 0.94, 0.95, 0.85))
		_st = ground
	if scenery:
		scenery.reserve(p, half.x)


func _hill_stands(item: Dictionary) -> void:
	_stands(item, Vector2(30, 6), false)


func _grandstand_large(item: Dictionary) -> void:
	_stands(item, Vector2(45, 9), true)


func _shanghai_stands(item: Dictionary) -> void:
	_stands(item, Vector2(55, 10), true)


func _oval_stands(item: Dictionary) -> void:
	_stands(item, Vector2(60, 8), true)


func _umbrella_stands(item: Dictionary) -> void:
	_stands(item, Vector2(45, 8), false)
	_st = overlay
	overlay_used = true
	for k in 8:
		var at: Vector2 = item["pos"] + Vector2.RIGHT.rotated(float(item["angle"])) * (-42.0 + k * 12.0) * PPM
		_rbox(at, Vector2(6, 6), float(item["angle"]) + PI / 4.0, Color(0.95, 0.96, 0.97, 0.85))
	_st = ground


func _stadium(p: Vector2, rx: float, rz: float, color: Color, roof: bool) -> void:
	_ring(p + Vector2(8, 12), rx, 18.0, SHADOW, 28, rz / rx)
	_ring(p, rx, 18.0, color, 28, rz / rx)
	for r in 3:
		_ring(p, rx + 3.0 + r * 5.0, 1.2, color.lightened(0.12), 28, rz / rx)
	if roof:
		_ring(p, rx + 10.0, 9.0, Color(0.95, 0.96, 0.97, 0.9), 28, rz / rx)
	if scenery:
		scenery.reserve(p, rx + 20.0)


func _hard_rock_stadium(item: Dictionary) -> void:
	_stadium(item["pos"], 90.0, 70.0, Color("e0742a"), true)
	_disc(item["pos"], 50.0, Color("3f8a3a"))


func _olympic_stadium(item: Dictionary) -> void:
	_stadium(item["pos"], 85.0, 70.0, Color("dfe3e8"), true)
	_disc(item["pos"], 45.0, Color("3f8a3a"))


func _foro_sol_stadium(item: Dictionary) -> void:
	_stadium(item["pos"], 45.0, 38.0, Color("e8c440"), false)


func _motodrom_stadium(item: Dictionary) -> void:
	_stadium(item["pos"], 55.0, 42.0, Color("dfe3e8"), true)


func _skyline(item: Dictionary) -> void:
	var c: Vector2 = item["pos"]
	for k in 34:
		var p := c + Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-200, 200)) * PPM
		if data.distance_to_road_m(p / PPM, 80.0) < 60.0:
			continue
		var h := _rng.randf_range(40, 190)
		_block(p, Vector2(_rng.randf_range(9, 17), _rng.randf_range(9, 17)), 0.0, [Color("aab4be"), Color("8e9aa6"), Color("c9ced6"), Color("6f7b88")][k % 4], h)
		lamps.append(p)


func _flame_towers(item: Dictionary) -> void:
	var c: Vector2 = item["pos"]
	for k in 3:
		var p := c + Vector2((k - 1) * 70.0, (k % 2) * 30.0) * PPM
		_block(p, Vector2(16, 11), 0.5 + k, Color("ff8a2e"), 150.0)
		_rbox(p, Vector2(10, 6), 0.5 + k, Color("ffd34d"))
		lamps.append(p)


func _marina_hotel(item: Dictionary) -> void:
	var c: Vector2 = item["pos"]
	for k in 3:
		_block(c + Vector2((k - 1) * 45.0, 0) * PPM, Vector2(12, 20), 0.0, Color("dfe3e8"), 190.0)
	_rbox(c, Vector2(85, 9), 0.0, Color("c9ced6"))
	lamps.append(c)


func _ferris_wheel(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	_ring(p, 34.0, 1.6, Color("dfe3e8"), 32)
	for k in 16:
		var a := TAU * k / 16.0
		_line(p, p + Vector2(cos(a), sin(a)) * 34.0 * PPM, 0.4, Color("b4b8be"))
		_disc(p + Vector2(cos(a), sin(a)) * 35.0 * PPM, 2.0, [Color("c8201e"), Color("f5c542"), Color("2f6fde"), Color("5fe08a")][k % 4], 6)
	if scenery:
		scenery.reserve(p, 40.0)
	lamps.append(p)


func _sphere(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	_disc(p + Vector2(30, 40) * PPM * 0.5, 45.0, SHADOW, 28)
	_disc(p, 45.0, Color("ff7a2a"), 28)
	_disc(p - Vector2(12, 12) * PPM, 30.0, Color("ffb347"), 24)
	_disc(p - Vector2(20, 20) * PPM, 12.0, Color("ffe0a0"), 16)
	if scenery:
		scenery.reserve(p, 50.0)
	lamps.append(p)


func _mountains(item: Dictionary) -> void:
	var c: Vector2 = item["pos"]
	for k in 6:
		var p := c + Vector2(_rng.randf_range(-500, 500), _rng.randf_range(-300, 300)) * PPM
		var r := _rng.randf_range(160, 320)
		_disc(p + Vector2(r * 0.25, r * 0.3) * PPM, r, Color(0.1, 0.15, 0.1, 0.3), 14)
		_disc(p, r, Color("5f7a58"), 14)
		_disc(p - Vector2(r * 0.25, r * 0.25) * PPM, r * 0.55, Color("74906a"), 12)
		_disc(p - Vector2(r * 0.35, r * 0.35) * PPM, r * 0.22, Color("e8eef2"), 10)


func _mount_fuji(item: Dictionary) -> void:
	var c: Vector2 = item["pos"]
	_disc(c, 420.0, Color("5a6f8a"), 24)
	_disc(c - Vector2(60, 60) * PPM, 260.0, Color("6c82a0"), 20)
	_disc(c - Vector2(90, 90) * PPM, 120.0, Color("f2f5f8"), 18)


func _castle_hill(item: Dictionary) -> void:
	var p: Vector2 = item["pos"]
	_disc(p, 140.0, Color("4f6a44"), 16)
	_block(p, Vector2(14, 10), 0.3, STONE, 20.0)


func _exhibition_halls(item: Dictionary) -> void:
	for k in 4:
		_block(item["pos"] + Vector2(0, (k - 1.5) * 70.0) * PPM, Vector2(85, 27), 0.0, Color("dfe3e8"), 18.0)


func _airfield_hangars(item: Dictionary) -> void:
	for k in 4:
		var p: Vector2 = item["pos"] + Vector2((k - 1.5) * 70.0, 0) * PPM
		_block(p, Vector2(27, 17), 0.0, Color("c9ced6"), 12.0)
		for s in 5:
			_rbox(p + Vector2(0, (s - 2) * 7.0) * PPM, Vector2(27, 0.4), 0.0, Color("8e96a1"))


func _favela_housing(item: Dictionary) -> void:
	for k in 110:
		var p: Vector2 = item["pos"] + Vector2(_rng.randf_range(-220, 220), _rng.randf_range(-160, 160)) * PPM
		if data.distance_to_road_m(p / PPM, 60.0) < 40.0:
			continue
		_block(p, Vector2(_rng.randf_range(3, 5), _rng.randf_range(3, 5)), _rng.randf() * 0.3, [Color("e8c440"), Color("d9471f"), Color("4fb3d9"), Color("f4f6f2"), Color("b5694f")][k % 5], 6.0)


func _harbour_yachts(item: Dictionary) -> void:
	var spots: Array = []
	if scenery and scenery._sea_dir != Vector2.ZERO:
		var dir: Vector2 = scenery._sea_dir
		var along := Vector2(absf(dir.y), absf(dir.x))
		var lo := data.bounds.position.dot(along)
		var hi := data.bounds.end.dot(along)
		for k in 44:
			spots.append(dir * (scenery._coast + _rng.randf_range(25.0, 170.0) * PPM) + along * _rng.randf_range(lo, hi))
	if scenery:
		for lake: Array in scenery._lakes:
			for k in 10:
				var a := _rng.randf() * TAU
				spots.append((lake[0] as Vector2) + Vector2(cos(a), sin(a)) * float(lake[1]) * 0.7 * PPM)
	for p: Vector2 in spots:
		var ang := _rng.randf() * TAU
		var length := _rng.randf_range(6.0, 15.0)
		_rbox(p + Vector2(3, 4), Vector2(length, length * 0.28), ang, Color(0, 0, 0, 0.15))
		_rbox(p, Vector2(length, length * 0.28), ang, Color("f4f6f2"))
		_rbox(p, Vector2(length * 0.5, length * 0.18), ang, Color("2f4a6a"))
