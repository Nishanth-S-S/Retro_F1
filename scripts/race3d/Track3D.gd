class_name Track3D
extends Node3D
## The circuit in 3D, built from the same TrackData the simulation drives on: asphalt at the
## local width (6.32 car widths, narrower in a few places), raised red-and-white kerbs, gravel,
## painted run-off, barrier walls, the pit lane and garages, a start gantry, grid boxes,
## grandstands full of people and blocky trees in the circuit's theme colours.

const PPM := VehiclePhysicsConfig.PPM
const ASPHALT := Color("2d3036")
const ASPHALT_ALT := Color("32353c")
const LINE := Color("eef1f4")
const CURB_RED := Color("d22b25")
const CURB_WHITE := Color("f2f2f2")
const WALL_A := Color("e8ebef")
const WALL_B := Color("c8201e")

var data: TrackData
var theme: Dictionary
var _lights: Array[MeshInstance3D] = []
var _light_on: StandardMaterial3D
var _light_off: StandardMaterial3D


static func make(track: TrackData, track_theme: Dictionary) -> Track3D:
	var t := Track3D.new()
	t.data = track
	t.theme = track_theme
	t._build()
	return t


func _col(key: String, fallback: String) -> Color:
	return Color(str(theme.get(key, fallback)))


## A point `lateral` metres to the right of the centreline at sample `i`, `y` metres up.
func edge(i: int, lateral: float, y: float = 0.0) -> Vector3:
	var j := data.wrap_index(i)
	var p := data.points[j] / PPM
	var n := data.normals[j]
	return Vector3(p.x + n.x * lateral, y, p.y + n.y * lateral)


func _strip(kit: MeshKit, i: int, a0: float, b0: float, a1: float, b1: float, y: float, color: Color) -> void:
	kit.quad(edge(i, a0, y), edge(i + 1, a1, y), edge(i + 1, b1, y), edge(i, b0, y), color)


func _build() -> void:
	var kit := MeshKit.new()
	var n := data.count
	# Ground: big mown squares in the theme's two greens (or sands, or paving).
	var ground := _col("ground", "3d7a3a")
	var stripe := _col("stripe", "44853f")
	var area := data.bounds.grow(420.0 * PPM)
	var tile := 40.0
	var x0 := area.position.x / PPM
	var z0 := area.position.y / PPM
	var cols := int(area.size.x / PPM / tile) + 1
	var rows := int(area.size.y / PPM / tile) + 1
	for r in rows:
		for c in cols:
			var x := x0 + c * tile
			var z := z0 + r * tile
			kit.quad(Vector3(x, -0.06, z), Vector3(x + tile, -0.06, z), Vector3(x + tile, -0.06, z + tile), Vector3(x, -0.06, z + tile), ground if (r + c) % 2 == 0 else stripe)
	var gravel := _col("gravel", "c9b58a")
	for i in n:
		var wi := data.half_width_at(i)
		var wj := data.half_width_at(i + 1)
		var j := data.wrap_index(i + 1)
		# Gravel traps out to the barrier.
		if data.gravel_left[i] == 1 and data.gravel_left[j] == 1:
			_strip(kit, i, -data.barrier_left[i], -wi, -data.barrier_left[j], -wj, -0.03, gravel)
		if data.gravel_right[i] == 1 and data.gravel_right[j] == 1:
			_strip(kit, i, wi, data.barrier_right[i], wj, data.barrier_right[j], -0.03, gravel)
		# Asphalt with a readable two-tone flow.
		_strip(kit, i, -wi, wi, -wj, wj, 0.0, ASPHALT if (i / 3) % 2 == 0 else ASPHALT_ALT)
		# White edge lines.
		_strip(kit, i, -wi, -wi + 0.3, -wj, -wj + 0.3, 0.008, LINE)
		_strip(kit, i, wi - 0.3, wi, wj - 0.3, wj, 0.008, LINE)
		for side: float in [-1.0, 1.0]:
			var curb := data.curb_right[i] if side > 0.0 else data.curb_left[i]
			var trap := data.gravel_right[i] if side > 0.0 else data.gravel_left[i]
			var cw := data.curb_width
			if curb == 1:
				# Raised kerb: top and the face towards the track.
				var color := CURB_RED if i % 2 == 0 else CURB_WHITE
				if side > 0.0:
					_strip(kit, i, wi, wi + cw, wj, wj + cw, 0.05, color)
					kit.quad(edge(i, wi, 0.0), edge(i + 1, wj, 0.0), edge(i + 1, wj, 0.05), edge(i, wi, 0.05), color.darkened(0.25))
				else:
					_strip(kit, i, -wi - cw, -wi, -wj - cw, -wj, 0.05, color)
					kit.quad(edge(i, -wi, 0.0), edge(i + 1, -wj, 0.0), edge(i + 1, -wj, 0.05), edge(i, -wi, 0.05), color.darkened(0.25))
				if trap == 0:
					var paint := Color("3a3d45") if (i / 2) % 3 != 0 else (Color("2f5fae") if side > 0.0 else Color("b8312c"))
					if side > 0.0:
						_strip(kit, i, wi + cw, wi + cw + 5.0, wj + cw, wj + cw + 5.0, 0.004, paint)
					else:
						_strip(kit, i, -wi - cw - 5.0, -wi - cw, -wj - cw - 5.0, -wj - cw, 0.004, paint)
		# Barrier walls.
		var wall := WALL_A if (i / 2) % 2 == 0 else WALL_B
		if theme.get("walls", false):
			wall = Color("c9ccd1") if (i / 2) % 2 == 0 else Color("b4b8be")
		for side: float in [-1.0, 1.0]:
			var bi := data.barrier_right[i] if side > 0.0 else data.barrier_left[i]
			var bj := data.barrier_right[j] if side > 0.0 else data.barrier_left[j]
			kit.quad(edge(i, side * bi, 0.0), edge(i + 1, side * bj, 0.0), edge(i + 1, side * bj, 1.0), edge(i, side * bi, 1.0), wall)
			kit.quad(edge(i, side * bi, 1.0), edge(i + 1, side * bj, 1.0), edge(i + 1, side * (bj + 0.4), 1.0), edge(i, side * (bi + 0.4), 1.0), wall.darkened(0.2))
	_build_start(kit)
	_build_pits(kit)
	_build_stands(kit)
	_build_boards(kit)
	var mesh := MeshInstance3D.new()
	mesh.mesh = kit.commit()
	mesh.material_override = MeshKit.material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_build_trees()
	_build_gantry()


func _build_start(kit: MeshKit) -> void:
	var hw := data.half_width
	var cells := 14
	var cell := hw * 2.0 / cells
	for row in 2:
		for c in cells:
			var a := -hw + c * cell
			var color := Color.WHITE if (c + row) % 2 == 0 else Color(0.08, 0.08, 0.09)
			var p0 := data.points[0] / PPM
			var t := data.tangents[0]
			var nrm := data.normals[0]
			var base := Vector3(p0.x, 0.01, p0.y) + Vector3(nrm.x, 0, nrm.y) * a + Vector3(t.x, 0, t.y) * (row * cell - cell)
			var along := Vector3(t.x, 0, t.y) * cell
			var across := Vector3(nrm.x, 0, nrm.y) * cell
			kit.quad(base, base + across, base + across + along, base + along, color)
	# Twenty grid boxes.
	for slot in 20:
		var info := data.grid_slot(slot)
		var pos: Vector2 = info["position"] / PPM
		var ang: float = info["rotation"]
		var fwd := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-sin(ang), 0, cos(ang))
		var front := Vector3(pos.x, 0.012, pos.y) + fwd * 2.9
		kit.quad(front - side * 0.75 - fwd * 0.06, front + side * 0.75 - fwd * 0.06, front + side * 0.75 + fwd * 0.06, front - side * 0.75 + fwd * 0.06, LINE)


func _build_pits(kit: MeshKit) -> void:
	var hw := data.half_width
	var outer := hw + TrackData.PIT_WIDTH
	var first := int(data.pit_start / data.spacing)
	var last := int(data.pit_end / data.spacing)
	for i in range(first, last):
		_strip(kit, i, -outer, -hw, -outer, -hw, 0.0, Color("3a3d45") if (i / 3) % 2 == 0 else Color("3e424a"))
		if i % 2 == 0:
			_strip(kit, i, -hw - 0.3, -hw, -hw - 0.3, -hw, 0.008, Color("f5c542"))
	var box := int(data.pit_box / data.spacing)
	for i in range(box - 2, box + 2):
		_strip(kit, i, -outer + 0.8, -hw - 1.2, -outer + 0.8, -hw - 1.2, 0.008, Color("c8201e"))
	# Garages behind the lane: blocks with team-coloured doors.
	var team_colors := [Color("c8201e"), Color("14532d"), Color("1b4f9c"), Color("f08a24"), Color("101418")]
	for i in range(first + 4, last - 4, 8):
		var j := data.wrap_index(i)
		var pos := edge(j, -outer - 4.5, 0.0)
		var t := data.tangents[j]
		var basis := Basis(Vector3.UP, -t.angle())
		kit.box(pos + Vector3(0, 2.2, 0), Vector3(14, 4.4, 4.0), Color("d7dbe0"), basis)
		kit.box(pos + basis * Vector3(0, 1.4, 2.05), Vector3(10, 2.6, 0.1), team_colors[(i / 8) % team_colors.size()], basis)
		kit.box(pos + Vector3(0, 4.5, 0), Vector3(14.4, 0.25, 4.4), Color("9aa1aa"), basis)


func _build_stands(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shirts := [Color("c8201e"), Color("f4f6f2"), Color("14532d"), Color("f5c542"), Color("2f6fde"), Color("ff8a2e"), Color("1f2a3a")]
	var spots: Array = []
	for i in range(-40, 80, 20):
		spots.append([data.wrap_index(i), -1.0])
	for corner: Dictionary in data.corners:
		if float(corner["radius"]) < 90.0:
			var apex := data.index_at(float(corner["apex"]))
			spots.append([apex, -float(corner["direction"])])
	for spot: Array in spots:
		var i: int = spot[0]
		var side: float = spot[1]
		var barrier := data.barrier_right[i] if side > 0.0 else data.barrier_left[i]
		var dist := barrier + 6.0 + (TrackData.PIT_WIDTH + 12.0 if i < 80 and side < 0.0 else 0.0)
		var pos := edge(i, side * dist, 0.0)
		var t := data.tangents[i]
		var basis := Basis(Vector3.UP, -t.angle())
		# Stepped seating with a crowd on every step.
		for step in 5:
			var out := side * (step * 1.6)
			var y := 0.6 + step * 0.9
			var c := basis * Vector3(0, 0, out)
			kit.box(pos + c + Vector3(0, y * 0.5, 0), Vector3(30, y, 1.6), Color("8e96a1"), basis)
			for k in 18:
				if rng.randf() < 0.15:
					continue
				var along := -14.0 + k * 1.6 + rng.randf_range(-0.2, 0.2)
				kit.box(pos + basis * Vector3(along, 0, out) + Vector3(0, y + 0.3, 0), Vector3(0.5, 0.6, 0.5), shirts[rng.randi() % shirts.size()], basis)
		kit.box(pos + basis * Vector3(0, 0, side * 8.5) + Vector3(0, 6.5, 0), Vector3(32, 0.3, 8.0), Color("c8201e"), basis)


func _build_boards(kit: MeshKit) -> void:
	# Brake marker boards before every big stop.
	for i in data.count:
		var next := data.wrap_index(i + 26)
		var entering := (data.gravel_left[next] == 1 or data.gravel_right[next] == 1) and data.gravel_left[i] == 0 and data.gravel_right[i] == 0
		var prev := data.wrap_index(i + 25)
		var first := data.gravel_left[prev] == 0 and data.gravel_right[prev] == 0
		if entering and first and absf(data.curvature[i]) < 0.002:
			var side := 1.0 if data.gravel_left[next] == 1 else -1.0
			for k in 3:
				var j := data.wrap_index(i + k * 12 - 8)
				var pos := edge(j, side * (data.half_width_at(j) + 3.0), 0.0)
				kit.box(pos + Vector3(0, 0.9, 0), Vector3(0.12, 1.8, 0.12), Color("9aa1aa"))
				kit.box(pos + Vector3(0, 1.8, 0), Vector3(0.9, 0.6, 0.08), Color("f5c542"), Basis(Vector3.UP, -data.tangents[j].angle() + PI / 2.0))


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var a := _col("tree_a", "2f6b35")
	var b := _col("tree_b", "4f9a48")
	var tk := MeshKit.new()
	tk.box(Vector3(0, 0.9, 0), Vector3(0.6, 1.8, 0.6), Color("6b4a2b"))
	tk.box(Vector3(0, 2.6, 0), Vector3(2.6, 1.8, 2.6), a)
	tk.box(Vector3(0, 3.9, 0), Vector3(1.8, 1.2, 1.8), b)
	tk.box(Vector3(0.6, 2.9, 0.7), Vector3(0.8, 0.6, 0.8), b)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tk.commit()
	var spots: Array[Transform3D] = []
	var wanted := int(theme.get("tree_count", 300)) / 2
	var tries := 0
	while spots.size() < wanted and tries < wanted * 6:
		tries += 1
		var i := rng.randi() % data.count
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var barrier := data.barrier_right[i] if side > 0.0 else data.barrier_left[i]
		var p := edge(i, side * (barrier + rng.randf_range(4.0, 70.0)), 0.0)
		# Not on another part of the track.
		var p2 := Vector2(p.x, p.z) * PPM
		var near := data.nearest_index(p2)
		if absf(data.lateral_offset(p2, near)) < data.half_width_at(near) + data.curb_width + 6.0:
			continue
		var s := rng.randf_range(0.8, 1.4)
		spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	mm.instance_count = spots.size()
	for k in spots.size():
		mm.set_instance_transform(k, spots[k])
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = mm
	trees.material_override = MeshKit.material()
	add_child(trees)


func _build_gantry() -> void:
	var hw := data.half_width
	var p0 := data.points[0] / PPM
	var t := data.tangents[0]
	var basis := Basis(Vector3.UP, -t.angle())
	var pos := Vector3(p0.x, 0, p0.y) + Vector3(t.x, 0, t.y) * 6.0
	var kit := MeshKit.new()
	kit.box(Vector3(0, 3.0, -(hw + 1.0)), Vector3(0.4, 6.0, 0.4), Color("3a3f48"))
	kit.box(Vector3(0, 3.0, hw + 1.0), Vector3(0.4, 6.0, 0.4), Color("3a3f48"))
	kit.box(Vector3(0, 6.2, 0), Vector3(0.6, 0.8, hw * 2.0 + 2.6), Color("23262e"))
	var frame := MeshInstance3D.new()
	frame.mesh = kit.commit()
	frame.material_override = MeshKit.material()
	frame.transform = Transform3D(basis, pos)
	add_child(frame)
	_light_off = StandardMaterial3D.new()
	_light_off.albedo_color = Color("3a0a0a")
	_light_on = StandardMaterial3D.new()
	_light_on.albedo_color = Color("ff2a2a")
	_light_on.emission_enabled = true
	_light_on.emission = Color("ff2a2a")
	_light_on.emission_energy_multiplier = 3.0
	var lk := MeshKit.new()
	lk.box(Vector3.ZERO, Vector3(0.2, 0.5, 0.5), Color.WHITE)
	var light_mesh := lk.commit()
	for k in 5:
		var l := MeshInstance3D.new()
		l.mesh = light_mesh
		l.material_override = _light_off
		l.transform = Transform3D(basis, pos + basis * Vector3(-0.35, 6.2, -2.4 + k * 1.2))
		add_child(l)
		_lights.append(l)


## The start lights: how many of the five are on.
func set_lights(count: int) -> void:
	for k in _lights.size():
		_lights[k].material_override = _light_on if k < count else _light_off
