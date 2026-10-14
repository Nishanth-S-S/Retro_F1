class_name CarVisual
extends Node2D
## Draws a car from its CarSetup, so every installed part is visible: wing profiles,
## engine block, ballast position, tire compound stripes... Used both on track and
## (in blueprint style) in the garage.
##
## Local frame: +x forward, origin at the rear axle, units = metres * PPM.

const S := VehiclePhysicsConfig.PPM
const WHEELBASE := 3.0
const FRONT_TRACK := 0.8
const REAR_TRACK := 0.79
const COMPOUND_COLORS := {"tires_hard": Color("f2f2f2"), "tires_medium": Color("f5c542"), "tires_soft": Color("e5484d")}
const BRAKE_COLORS := {"brakes_standard": Color("8b95a3"), "brakes_lightweight": Color("7fd4ff"), "brakes_racing": Color("ff9d3c")}
const BLUEPRINT_LINE := Color("c9f2d9")
const BLUEPRINT_FILL := Color(0.18, 0.56, 0.38, 0.35)

var setup: CarSetup
var body_color := Color("e8eef6")
## Second livery colour: wings, nose stripe and engine-cover flash.
var accent_color := Color("23272e")
var blueprint := false
var line_width := 0.6
var alpha := 1.0
var front_steer := 0.0:
	set(value):
		front_steer = value
		for wheel in _front_wheels:
			wheel.rotation = value

var _front_wheels: Array[Node2D] = []
var _wheel_root: Node2D


func _ready() -> void:
	_wheel_root = Node2D.new()
	add_child(_wheel_root)
	refresh()


func refresh() -> void:
	modulate.a = alpha
	queue_redraw()
	if _wheel_root == null:
		return
	for child in _wheel_root.get_children():
		child.queue_free()
	_front_wheels.clear()
	if setup == null or setup.part("tires") == null:
		return
	var stripe: Color = COMPOUND_COLORS.get(setup.parts.get("tires", ""), Color.WHITE)
	for side: float in [-1.0, 1.0]:
		_front_wheels.append(_make_wheel(Vector2(WHEELBASE, side * FRONT_TRACK), Vector2(0.66, 0.31), stripe))
		_make_wheel(Vector2(0.0, side * REAR_TRACK), Vector2(0.7, 0.42), stripe)
	front_steer = front_steer


func _make_wheel(pos_m: Vector2, size_m: Vector2, stripe: Color) -> Node2D:
	var wheel := Node2D.new()
	wheel.position = pos_m * S
	var half := size_m * 0.5 * S
	var tire := Polygon2D.new()
	tire.polygon = _rounded_rect(half, half.y * 0.45)
	tire.color = Color("0a0a0a") if blueprint else Color("2b2e34")
	wheel.add_child(tire)
	if blueprint:
		var outline := Line2D.new()
		outline.points = tire.polygon
		outline.closed = true
		outline.width = line_width
		outline.default_color = BLUEPRINT_LINE
		wheel.add_child(outline)
	# Compound marking: coloured sidewall bands.
	for band: float in [-0.62, 0.62]:
		var mark := Polygon2D.new()
		var bx := half.x * band
		var w := half.x * 0.09
		mark.polygon = PackedVector2Array([Vector2(bx - w, -half.y), Vector2(bx + w, -half.y), Vector2(bx + w, half.y), Vector2(bx - w, half.y)])
		mark.color = stripe
		wheel.add_child(mark)
	_wheel_root.add_child(wheel)
	return wheel


func _rounded_rect(half: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half.x + r, -half.y), Vector2(half.x - r, -half.y), Vector2(half.x, -half.y + r), Vector2(half.x, half.y - r),
		Vector2(half.x - r, half.y), Vector2(-half.x + r, half.y), Vector2(-half.x, half.y - r), Vector2(-half.x, -half.y + r),
	])


func _fill(color: Color) -> Color:
	return BLUEPRINT_FILL if blueprint else color


func _line(color: Color) -> Color:
	return BLUEPRINT_LINE if blueprint else color.darkened(0.45)


func _shape(points_m: Array, fill: Color, outline: bool = true) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in points_m:
		pts.append(p * S)
	draw_colored_polygon(pts, _fill(fill))
	if outline:
		pts.append(pts[0])
		draw_polyline(pts, _line(fill), line_width, true)


## Mirrors a half outline (y >= 0, front to back) into a closed symmetric polygon.
func _symmetric(half: Array, fill: Color) -> void:
	var pts: Array = half.duplicate()
	for i in range(half.size() - 1, -1, -1):
		var p: Vector2 = half[i]
		if absf(p.y) > 0.001:
			pts.append(Vector2(p.x, -p.y))
	_shape(pts, fill)


func _box(center: Vector2, size: Vector2, fill: Color, outline: bool = true) -> void:
	var h := size * 0.5
	_shape([center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y), center + Vector2(h.x, h.y), center + Vector2(-h.x, h.y)], fill, outline)


func _draw() -> void:
	if setup == null:
		return
	var chassis := setup.part("chassis")
	var dark := Color("23272e")
	_draw_suspension()
	if chassis:
		var wide := clampf((chassis.mass - 240.0) / 90.0, 0.0, 1.0)   # heavier tubs are visibly bulkier
		var pod := 0.66 + 0.1 * wide
		# Floor.
		_symmetric([Vector2(3.25, 0.2), Vector2(2.5, 0.5), Vector2(2.0, pod + 0.06), Vector2(0.45, pod + 0.06), Vector2(-0.2, 0.42), Vector2(-0.32, 0.0)], dark)
		# Monocoque, sidepods and engine cover.
		_symmetric([Vector2(4.05, 0.0), Vector2(4.0, 0.09), Vector2(3.0, 0.24 + 0.03 * wide), Vector2(2.35, 0.36 + 0.04 * wide), Vector2(2.05, pod), Vector2(0.95, pod - 0.05), Vector2(0.4, 0.4), Vector2(-0.25, 0.22), Vector2(-0.3, 0.0)], body_color)
	else:
		_ghost_outline([Vector2(4.05, 0.0), Vector2(3.0, 0.26), Vector2(2.05, 0.7), Vector2(0.95, 0.66), Vector2(-0.3, 0.2)])
	if chassis and not blueprint:
		# Team livery: a stripe down the nose and flashes on the sidepods.
		_symmetric([Vector2(4.02, 0.0), Vector2(3.9, 0.06), Vector2(2.3, 0.09), Vector2(2.3, 0.0)], accent_color)
		for side: float in [-1.0, 1.0]:
			_shape([Vector2(1.9, side * 0.42), Vector2(1.9, side * 0.62), Vector2(1.0, side * 0.6), Vector2(1.25, side * 0.42)], accent_color, false)
	_draw_gearbox()
	_draw_engine()
	if chassis:
		# Cockpit opening and driver.
		_symmetric([Vector2(2.2, 0.0), Vector2(2.1, 0.2), Vector2(1.55, 0.25), Vector2(1.4, 0.0)], Color("15171b"))
		draw_circle(Vector2(1.74, 0) * S, 0.19 * S, Color("ffb347") if not blueprint else BLUEPRINT_LINE)
		draw_circle(Vector2(1.8, 0) * S, 0.08 * S, Color("1d2026"))
	_draw_wing("front_wing", 3.92, 0.95, setup.front_wing_angle, 0.07)
	_draw_wing("rear_wing", -0.52, 0.78, setup.rear_wing_angle, 0.12)
	_draw_brakes()
	_draw_ballast()


func _ghost_outline(half: Array) -> void:
	if not blueprint:
		return
	var pts := PackedVector2Array()
	for p: Vector2 in half:
		pts.append(p * S)
	for i in range(half.size() - 1, -1, -1):
		var p: Vector2 = half[i]
		pts.append(Vector2(p.x, -p.y) * S)
	pts.append(pts[0])
	for i in pts.size() - 1:
		draw_dashed_line(pts[i], pts[i + 1], Color(BLUEPRINT_LINE, 0.35), line_width, 1.6)


func _draw_suspension() -> void:
	for info: Array in [["front_suspension", WHEELBASE, FRONT_TRACK, 0.22], ["rear_suspension", 0.0, REAR_TRACK, 0.3]]:
		var part := setup.part(info[0])
		if part == null:
			continue
		var x: float = info[1]
		var track_half: float = info[2]
		var inner: float = info[3]
		# Stiffer springs are drawn as heavier wishbones.
		var width := line_width * (1.0 + part.stat("spring_rate", 120.0) / 80.0)
		var color := BLUEPRINT_LINE if blueprint else Color("3a3f48")
		for side: float in [-1.0, 1.0]:
			var hub := Vector2(x, side * (track_half - 0.12)) * S
			draw_line(Vector2(x + 0.42, side * inner) * S, hub, color, width, true)
			draw_line(Vector2(x - 0.42, side * inner) * S, hub, color, width, true)
			draw_line(Vector2(x, side * inner) * S, hub, color, width * 0.7, true)


func _draw_engine() -> void:
	var engine := setup.part("engine")
	if engine == null:
		if blueprint:
			_ghost_outline([Vector2(1.15, 0.0), Vector2(1.15, 0.24), Vector2(0.42, 0.24), Vector2(0.42, 0.0)])
		return
	var length := 0.45 + engine.mass / 260.0
	var width := 0.3 + engine.mass / 520.0
	var center := Vector2(CarSetup.SLOT_POSITION["engine"], 0.0)
	var block := Color("596270")
	_box(center, Vector2(length, width), block)
	# Cylinder count is readable from the part name's trailing digit (4 / 6 / 8).
	var cylinders := maxi(4, int(engine.display_name.right(1)))
	var per_bank := cylinders / 2
	for i in per_bank:
		var cx := center.x - length * 0.5 + length * (i + 0.5) / per_bank
		for side: float in [-1.0, 1.0]:
			draw_circle(Vector2(cx, side * width * 0.24) * S, minf(length / per_bank, width) * 0.17 * S, Color("ffb347") if blueprint else Color("c9ced6"))
	if engine.id.contains("turbo"):
		draw_arc(Vector2(center.x - length * 0.5 - 0.02, width * 0.5 + 0.06) * S, 0.13 * S, 0.0, TAU, 14, Color("ff9d3c"), line_width * 2.2, true)
		draw_circle(Vector2(center.x - length * 0.5 - 0.02, width * 0.5 + 0.06) * S, 0.05 * S, Color("ff9d3c"))


func _draw_gearbox() -> void:
	var gearbox := setup.part("gearbox")
	if gearbox == null:
		if blueprint:
			_ghost_outline([Vector2(0.38, 0.0), Vector2(0.38, 0.17), Vector2(-0.18, 0.12), Vector2(-0.18, 0.0)])
		return
	var w := 0.14 + gearbox.mass / 300.0
	_symmetric([Vector2(0.38, 0.0), Vector2(0.38, w), Vector2(-0.18, w * 0.7), Vector2(-0.18, 0.0)], Color("7a6f58"))
	var marks := 3 if gearbox.stat("shift_time", 0.2) > 0.1 else 5
	for i in marks:
		var gx := 0.3 - 0.4 * i / maxf(marks - 1, 1)
		draw_line(Vector2(gx, -w * 0.5) * S, Vector2(gx, w * 0.5) * S, _line(Color("d8c9a3")) if blueprint else Color("2d2a22"), line_width, true)


func _draw_wing(slot: String, x: float, half_span: float, angle: int, endplate: float) -> void:
	var wing := setup.part(slot)
	if wing == null:
		if blueprint:
			_ghost_outline([Vector2(x + 0.18, 0.0), Vector2(x + 0.18, half_span), Vector2(x - 0.18, half_span), Vector2(x - 0.18, 0.0)])
		return
	var df := wing.stat("downforce_coefficient", 0.8)
	var elements := clampi(int(round(df / 0.42)), 1, 4)
	# Steeper wing angle shows as a deeper chord.
	var chord := 0.1 + 0.012 * angle
	var gap := 0.035
	var total := elements * chord + (elements - 1) * gap
	var wing_color := accent_color
	for e in elements:
		var cx := x + total * 0.5 - chord * 0.5 - e * (chord + gap)
		_box(Vector2(cx, 0.0), Vector2(chord, half_span * 2.0), wing_color)
	var plate := Vector2(total + 0.14, endplate)
	for side: float in [-1.0, 1.0]:
		_box(Vector2(x, side * (half_span + endplate * 0.5)), plate, body_color if not blueprint else Color("23272e"))
	if slot == "rear_wing":
		for side: float in [-1.0, 1.0]:
			draw_line(Vector2(-0.25, side * 0.16) * S, Vector2(x + total * 0.5, side * 0.16) * S, _line(Color("596270")), line_width * 1.6, true)


func _draw_brakes() -> void:
	var brakes := setup.part("brakes")
	if brakes == null:
		return
	var color: Color = BRAKE_COLORS.get(brakes.id, Color("8b95a3"))
	var size := 0.2 + brakes.stat("max_brake_force", 16000.0) / 110000.0
	for x: float in [WHEELBASE, 0.0]:
		for side: float in [-1.0, 1.0]:
			var track_half := FRONT_TRACK if x > 1.0 else REAR_TRACK
			_box(Vector2(x, side * (track_half - 0.24)), Vector2(size, 0.07), color, false)


func _draw_ballast() -> void:
	var ballast := setup.part("ballast")
	if ballast == null or ballast.mass <= 0.0:
		return
	var size := Vector2(0.16 + ballast.mass * 0.008, 0.22 + ballast.mass * 0.006)
	var center := Vector2(setup.ballast_x(), 0.0)
	_box(center, size, Color("f5c542"))
	var h := size * 0.5 * S
	draw_line(center * S + Vector2(-h.x, h.y), center * S + Vector2(h.x, -h.y), Color("1d2026"), line_width * 1.5, true)
