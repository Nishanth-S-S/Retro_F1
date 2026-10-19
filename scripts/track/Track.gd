class_name Track
extends Node2D
## Builds the visible circuit and its collision from TrackData: asphalt, curbs, runoff,
## barriers and trackside scenery, all as procedural vertex-coloured geometry.

const PPM := VehiclePhysicsConfig.PPM
const COLOR_GRASS := Color("3d7a3a")
const COLOR_GRASS_STRIPE := Color("44853f")
const COLOR_GRAVEL := Color("c9b58a")
const COLOR_ASPHALT := Color("2d3036")
const COLOR_ASPHALT_ALT := Color("31343b")
const COLOR_LINE := Color("e9edf2")
const COLOR_CURB_RED := Color("d43d3d")
const COLOR_CURB_WHITE := Color("f1f1f1")
const COLOR_BARRIER_A := Color("dfe5ec")
const COLOR_BARRIER_B := Color("3a78c2")
const COLOR_TREE := Color("275c2c")
const COLOR_TREE_LIGHT := Color("347a39")
const BARRIER_THICKNESS := 1.3

@export_file("*.json") var track_file := "res://data/tracks/monza.json"

var data: TrackData
## Where the grandstands and the floodlights are (pixels): crowd noise and night lighting.
var stand_positions := PackedVector2Array()
var lamp_positions := PackedVector2Array()
var _st: SurfaceTool
var _scenery: TrackScenery
var _mesh_instance: MeshInstance2D


func _ready() -> void:
	if data == null:
		data = TrackData.load_track(GameManager.track_file())
	_build_path()
	_build_mesh()
	_build_barriers()


func _build_path() -> void:
	var path := Path2D.new()
	path.name = "CenterLine"
	path.curve = data.curve
	path.visible = false
	add_child(path)


func _edge(i: int, offset: float) -> Vector2:
	var j := data.wrap_index(i)
	return data.points[j] + data.normals[j] * offset * PPM


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_st.set_color(color)
	_st.add_vertex(Vector3(a.x, a.y, 0)); _st.add_vertex(Vector3(b.x, b.y, 0)); _st.add_vertex(Vector3(c.x, c.y, 0))
	_st.add_vertex(Vector3(a.x, a.y, 0)); _st.add_vertex(Vector3(c.x, c.y, 0)); _st.add_vertex(Vector3(d.x, d.y, 0))


## A strip measured from the local track edge on one side (side = -1 left, +1 right): from
## `from_edge` to `to_edge` metres outside it. Follows narrow sections.
func _edge_strip(i: int, side: float, from_edge: float, to_edge: float, color: Color) -> void:
	var a := data.half_width_at(i)
	var b := data.half_width_at(i + 1)
	_quad(_edge(i, side * (a + from_edge)), _edge(i + 1, side * (b + from_edge)), _edge(i + 1, side * (b + to_edge)), _edge(i, side * (a + to_edge)), color)


func _strip_segment(i: int, inner: float, outer: float, color: Color) -> void:
	_quad(_edge(i, inner), _edge(i + 1, inner), _edge(i + 1, outer), _edge(i, outer), color)


func _disc(center: Vector2, radius: float, color: Color, segments: int = 10) -> void:
	_st.set_color(color)
	for s in segments:
		var a0 := TAU * s / segments
		var a1 := TAU * (s + 1) / segments
		_st.add_vertex(Vector3(center.x, center.y, 0))
		_st.add_vertex(Vector3(center.x + cos(a0) * radius, center.y + sin(a0) * radius, 0))
		_st.add_vertex(Vector3(center.x + cos(a1) * radius, center.y + sin(a1) * radius, 0))


func _rect(center: Vector2, half: Vector2, angle: float, color: Color) -> void:
	var x := Vector2.RIGHT.rotated(angle) * half.x
	var y := Vector2.DOWN.rotated(angle) * half.y
	_quad(center - x - y, center + x - y, center + x + y, center - x + y, color)


func _build_mesh() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Ground, water, roads and runways come from the circuit's theme and sit under the track.
	_scenery = TrackScenery.new(data, _st)
	_scenery.ground(data.bounds.grow(450.0 * PPM))
	var gravel := Color(str(_scenery.theme["gravel"]))
	var hw := data.half_width
	var n := data.count
	# Gravel traps.
	for i in n:
		var j := data.wrap_index(i + 1)
		var wi := data.half_width_at(i)
		var wj := data.half_width_at(i + 1)
		if data.gravel_left[i] == 1 and data.gravel_left[j] == 1:
			_quad(_edge(i, -wi), _edge(i + 1, -wj), _edge(i + 1, -data.barrier_left[j]), _edge(i, -data.barrier_left[i]), gravel)
		if data.gravel_right[i] == 1 and data.gravel_right[j] == 1:
			_quad(_edge(i, wi), _edge(i + 1, wj), _edge(i + 1, data.barrier_right[j]), _edge(i, data.barrier_right[i]), gravel)
	# Asphalt, 6.32 car widths wide (narrower in a few sections): two alternating tones every few
	# samples give the surface a readable flow at speed.
	for i in n:
		var wi := data.half_width_at(i)
		var wj := data.half_width_at(i + 1)
		_quad(_edge(i, -wi), _edge(i + 1, -wj), _edge(i + 1, wj), _edge(i, wi), COLOR_ASPHALT if (i / 3) % 2 == 0 else COLOR_ASPHALT_ALT)
	# Painted run-off beyond the curbs where there is no gravel, striped like a modern track.
	for i in n:
		for side: float in [-1.0, 1.0]:
			var curb := data.curb_right[i] if side > 0.0 else data.curb_left[i]
			var trap := data.gravel_right[i] if side > 0.0 else data.gravel_left[i]
			if curb == 1 and trap == 0:
				var color := Color("3a3d45") if (i / 2) % 3 != 0 else (Color("2f5fae") if side > 0.0 else Color("b8312c"))
				_edge_strip(i, side, data.curb_width, data.curb_width + 5.0, color)
	# Curbs.
	for i in n:
		var curb_color := COLOR_CURB_RED if i % 2 == 0 else COLOR_CURB_WHITE
		if data.curb_left[i] == 1:
			_edge_strip(i, -1.0, 0.0, data.curb_width, curb_color)
		if data.curb_right[i] == 1:
			_edge_strip(i, 1.0, 0.0, data.curb_width, curb_color)
	# White edge lines.
	for i in n:
		_edge_strip(i, -1.0, -0.3, 0.0, COLOR_LINE)
		_edge_strip(i, 1.0, -0.3, 0.0, COLOR_LINE)
	_build_start_area()
	_build_pit_lane()
	# Barriers.
	for i in n:
		var j := data.wrap_index(i + 1)
		var color := COLOR_BARRIER_A if (i / 2) % 2 == 0 else COLOR_BARRIER_B
		if _scenery.theme.get("walls", false):
			# Street circuit: bare concrete walls.
			color = Color("c9ccd1") if (i / 2) % 2 == 0 else Color("b4b8be")
		_quad(_edge(i, -data.barrier_left[i]), _edge(i + 1, -data.barrier_left[j]), _edge(i + 1, -data.barrier_left[j] - BARRIER_THICKNESS), _edge(i, -data.barrier_left[i] - BARRIER_THICKNESS), color)
		_quad(_edge(i, data.barrier_right[i]), _edge(i + 1, data.barrier_right[j]), _edge(i + 1, data.barrier_right[j] + BARRIER_THICKNESS), _edge(i, data.barrier_right[i] + BARRIER_THICKNESS), color)
	_build_scenery()
	var mesh_instance := MeshInstance2D.new()
	mesh_instance.name = "TrackMesh"
	mesh_instance.mesh = _st.commit()
	mesh_instance.z_index = -10
	add_child(mesh_instance)
	_mesh_instance = mesh_instance


## Darkens and cools the whole scene for rain (0 dry, 1 light, 2 heavy).
func set_wet(level: int) -> void:
	if _mesh_instance:
		_mesh_instance.modulate = [Color.WHITE, Color(0.8, 0.85, 0.93), Color(0.62, 0.68, 0.8)][clampi(level, 0, 2)]


func _build_start_area() -> void:
	var hw := data.half_width
	var p := data.points[0]
	var t := data.tangents[0]
	var nrm := data.normals[0]
	# Chequered start/finish line.
	var cells := 14
	var cell := hw * 2.0 / cells * PPM
	for row in 2:
		for c in cells:
			var color := Color.WHITE if (c + row) % 2 == 0 else Color(0.08, 0.08, 0.09)
			var origin := p + nrm * (-hw * PPM + c * cell) + t * (row * cell - cell)
			_quad(origin, origin + nrm * cell, origin + nrm * cell + t * cell, origin + t * cell, color)
	# Grid boxes for a full twenty-car grid.
	for slot in 20:
		var info := data.grid_slot(slot)
		var pos: Vector2 = info["position"]
		var ang: float = info["rotation"]
		var fwd := Vector2.RIGHT.rotated(ang)
		_rect(pos + fwd * 2.9 * PPM, Vector2(0.12, 1.5) * PPM, ang, COLOR_LINE)
		_rect(pos + fwd * 1.7 * PPM + fwd.orthogonal() * 1.44 * PPM, Vector2(1.2, 0.1) * PPM, ang, COLOR_LINE)
		_rect(pos + fwd * 1.7 * PPM - fwd.orthogonal() * 1.44 * PPM, Vector2(1.2, 0.1) * PPM, ang, COLOR_LINE)


func _build_pit_lane() -> void:
	var hw := data.half_width
	var outer := hw + TrackData.PIT_WIDTH
	var first := int(data.pit_start / data.spacing)
	var last := int(data.pit_end / data.spacing)
	for i in range(first, last):
		_strip_segment(i, -outer, -hw, Color("3a3d45") if (i / 3) % 2 == 0 else Color("3e424a"))
		_strip_segment(i, -outer, -outer + 0.3, COLOR_LINE)
		if i % 2 == 0:
			_strip_segment(i, -hw - 0.3, -hw, Color("f5c542"))       # dashed pit-lane line
	# Service box with a chequered apron in front of it.
	var box := int(data.pit_box / data.spacing)
	for i in range(box - 2, box + 2):
		_strip_segment(i, -outer + 0.8, -hw - 1.2, Color("c8201e"))
	for i in range(box - 1, box + 1):
		_strip_segment(i, -outer + 1.6, -hw - 2.0, Color("2b2e34"))
	for k in 6:
		var a := _edge(box + 2, -hw - 1.2 - k)
		var t := data.tangents[data.wrap_index(box + 2)]
		var n := data.normals[data.wrap_index(box + 2)]
		_quad(a, a + t * 10.0, a + t * 10.0 - n * 10.0, a - n * 10.0, Color.WHITE if k % 2 == 0 else Color(0.08, 0.08, 0.09))
	# Pit wall garages behind the lane.
	for i in range(first + 4, last - 4, 8):
		var j := data.wrap_index(i)
		_rect(_edge(j, -outer - 4.5), Vector2(14, 3.2) * PPM, data.tangents[j].angle(), Color("d7dbe0"))
		_rect(_edge(j, -outer - 4.5), Vector2(12, 1.0) * PPM, data.tangents[j].angle(), Color("c8201e") if (i / 8) % 2 == 0 else Color("14532d"))


## A packed crowd: rows of tiny coloured heads on a stand.
func _crowd(center: Vector2, half: Vector2, angle: float, rng: RandomNumberGenerator) -> void:
	var shirts := [Color("c8201e"), Color("f4f6f2"), Color("14532d"), Color("f5c542"), Color("2f6fde"), Color("ff8a2e"), Color("1f2a3a")]
	var x_axis := Vector2.RIGHT.rotated(angle)
	var y_axis := Vector2.DOWN.rotated(angle)
	var step := 1.7 * PPM
	var cols := int(half.x * 2.0 / step)
	var rows := int(half.y * 2.0 / step)
	for ry in rows:
		for cx in cols:
			if rng.randf() < 0.12:
				continue
			var p := center + x_axis * (-half.x + (cx + 0.5) * step) + y_axis * (-half.y + (ry + 0.5) * step)
			_rect(p, Vector2(0.55, 0.55) * PPM, angle, shirts[rng.randi() % shirts.size()])


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240
	var n := data.count
	# Brake marker boards ahead of heavy braking zones (gravel = big stop).
	for i in n:
		var next := data.wrap_index(i + 26)
		var entering := (data.gravel_left[next] == 1 or data.gravel_right[next] == 1) and data.gravel_left[i] == 0 and data.gravel_right[i] == 0
		var prev_next := data.wrap_index(i + 25)
		var first := data.gravel_left[prev_next] == 0 and data.gravel_right[prev_next] == 0
		if entering and first and absf(data.curvature[i]) < 0.002:
			for k in 3:
				var j := data.wrap_index(i + k * 12 - 8)
				var side := 1.0 if data.gravel_left[next] == 1 else -1.0
				var pos := _edge(j, side * (data.half_width_at(j) + 3.0))
				_rect(pos, Vector2(0.25, 1.1) * PPM, data.tangents[j].angle(), Color("f5c542"))
				for b in (3 - k):
					_rect(pos + data.tangents[j] * 0.3 * PPM + data.normals[j] * (b - (2 - k) * 0.5) * 0.6 * PPM, Vector2(0.1, 0.18) * PPM, data.tangents[j].angle(), Color(0.1, 0.1, 0.1))
	# Grandstands along the start straight (behind the pit garages), and on race day in the
	# career a few more at the big corners - all of them full.
	var crowd := true
	var stands: Array = []
	for i in range(-40, 80, 20):
		stands.append([data.wrap_index(i), -1.0])
	if crowd:
		for corner: Dictionary in data.corners:
			if float(corner["radius"]) < 70.0:
				# Outside of the corner is where the action is.
				stands.append([data.index_at(float(corner["apex"])), -float(corner["direction"])])
	for stand: Array in stands:
		var j: int = stand[0]
		var side: float = stand[1]
		if side < 0.0 and stands.find(stand) < 6 and absf(data.curvature[j]) > 0.001:
			continue
		var offset := (data.barrier_left[j] if side < 0.0 else data.barrier_right[j]) + 16.0
		var pos := _edge(j, side * offset)
		var ang := data.tangents[j].angle()
		_rect(pos + Vector2(4, 5), Vector2(34, 7.5) * PPM, ang, Color(0, 0, 0, 0.22))
		_rect(pos, Vector2(34, 7.5) * PPM, ang, Color("58616e"))
		stand_positions.append(pos)
		for k in 5:
			_scenery.reserve(pos + data.tangents[j] * (k - 2) * 15.0 * PPM, 10.0)
		if crowd:
			_crowd(pos, Vector2(33, 6.8) * PPM, ang, rng)
		else:
			for row in 5:
				_rect(pos + data.normals[j] * (row - 2) * 2.6 * PPM, Vector2(33, 0.8) * PPM, ang, [Color("d95050"), Color("e8e8e8"), Color("3a78c2"), Color("e8e8e8"), Color("f5c542")][row])
	_floodlights()
	_scenery.details()
	# Buildings, vegetation, rocks, boats and landmarks for this location.
	_scenery.objects()


## Light towers all the way round, alternating sides just behind the barriers. At night
## RaceManager lights them up; by day they are just poles with lamp heads.
func _floodlights() -> void:
	var step := int(95.0 / data.spacing)
	var k := 0
	for i in range(step / 2, data.count, step):
		k += 1
		var side := 1.0 if k % 2 == 0 else -1.0
		var offset := (data.barrier_right[i] if side > 0.0 else data.barrier_left[i]) + 3.2
		var pos := data.points[i] + data.normals[i] * side * offset * PPM
		var ang := data.tangents[i].angle()
		_rect(pos + Vector2(6, 9), Vector2(0.9, 2.8) * PPM, ang, Color(0, 0, 0, 0.25))
		_rect(pos, Vector2(0.5, 0.5) * PPM, ang, Color("3a3d44"))
		# Lamp head leaning over the track.
		var head := pos - data.normals[i] * side * 1.4 * PPM
		_rect(head, Vector2(1.6, 0.6) * PPM, ang, Color("23262e"))
		_rect(head, Vector2(1.3, 0.35) * PPM, ang, Color("fff3b0"))
		lamp_positions.append(head - data.normals[i] * side * 5.0 * PPM)
		_scenery.reserve(pos, 4.0)


func _build_barriers() -> void:
	var body := StaticBody2D.new()
	body.name = "Barriers"
	body.collision_layer = 2
	body.collision_mask = 0
	var material := PhysicsMaterial.new()
	material.friction = 0.25
	material.bounce = 0.12
	body.physics_material_override = material
	var segments := PackedVector2Array()
	var n := data.count
	for i in n:
		var j := data.wrap_index(i + 1)
		for depth: float in [0.0, BARRIER_THICKNESS]:
			segments.append(_edge(i, -data.barrier_left[i] - depth))
			segments.append(_edge(i + 1, -data.barrier_left[j] - depth))
			segments.append(_edge(i, data.barrier_right[i] + depth))
			segments.append(_edge(i + 1, data.barrier_right[j] + depth))
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segments
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
