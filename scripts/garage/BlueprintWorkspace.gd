class_name BlueprintWorkspace
extends Control
## The assembly table: blueprint grid, the car seen from above, measurement lines,
## centre-of-mass marker, hardpoint slots and the optional MASS / AERO overlays.

signal slot_tapped(slot: String)

const SNAP_DISTANCE := 70.0
## Hardpoint on the car (metres ahead of rear axle, lateral metres) and which side its tag sits.
const SLOT_LAYOUT := {
	"front_wing": [3.92, 0.0, 1.0],
	"front_suspension": [3.0, -0.5, -1.0],
	"tires": [3.0, 0.8, 1.0],
	"chassis": [2.45, 0.0, -1.0],
	"ballast": [1.3, -0.5, -1.0],
	"engine": [0.78, 0.0, 1.0],
	"brakes": [0.0, -0.8, -1.0],
	"gearbox": [0.1, 0.0, -1.0],
	"rear_suspension": [0.25, 0.42, 1.0],
	"rear_wing": [-0.6, 0.0, -1.0],
}

var preview: CarPreview
var stats: CarStats
var slots: Dictionary = {}          # slot name -> PartSlot
var show_mass := false:
	set(value):
		show_mass = value
		queue_redraw()
var show_aero := false:
	set(value):
		show_aero = value
		queue_redraw()
var _com_y := 0.0
var _com_target := 0.0
var _time := 0.0
var _press_pos := Vector2.ZERO
var _overlay: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	preview = CarPreview.new()
	add_child(preview)
	var team := Career.my_team() if Career.active() else {"color": "#c8201e", "color2": "#f4f6f2"}
	preview.set_livery(Color(str(team["color"])), Color(str(team["color2"])))
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	for slot: String in SLOT_LAYOUT:
		var node := PartSlot.new()
		node.slot = slot
		node.tag_side = SLOT_LAYOUT[slot][2]
		add_child(node)
		slots[slot] = node
	resized.connect(_layout)
	_layout()


func car_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5 + 34.0)


func _layout() -> void:
	if preview == null:
		return
	preview.display_scale = clampf(minf((size.y - 190.0) / 46.5, (size.x - 260.0) / 22.0), 6.0, 11.0)
	preview.scale = Vector2(preview.display_scale, preview.display_scale)
	if preview.visual:
		preview.visual.line_width = 2.0 / preview.display_scale
		preview.visual.refresh()
	preview.position = car_center()
	for slot: String in SLOT_LAYOUT:
		var node: PartSlot = slots[slot]
		var layout: Array = SLOT_LAYOUT[slot]
		node.hotspot = car_center() + preview.car_point(layout[0], layout[1])
	queue_redraw()


func refresh(car_stats: CarStats) -> void:
	stats = car_stats
	preview.show_setup(GameManager.setup)
	_com_target = preview.car_point(stats.cg_x, 0.0).y
	for slot: String in slots:
		(slots[slot] as PartSlot).queue_redraw()
	queue_redraw()


func select_slot(slot: String) -> void:
	for name: String in slots:
		(slots[name] as PartSlot).selected = name == slot


# ---------------------------------------------------------------- drag support

func compatible_slots(part: VehiclePart) -> Array:
	var out: Array = []
	for slot: String in CarSetup.SLOT_CATEGORY:
		if CarSetup.SLOT_CATEGORY[slot] == part.category:
			out.append(slot)
	return out


## Updates slot highlights for a dragged part and returns the slot it would drop into ("" if none).
func update_drag(part: VehiclePart, local_pos: Vector2) -> String:
	var valid := compatible_slots(part)
	var nearest := ""
	var nearest_d := SNAP_DISTANCE
	for slot: String in slots:
		var node: PartSlot = slots[slot]
		var d := local_pos.distance_to(node.hotspot)
		if d < nearest_d:
			nearest_d = d
			nearest = slot
	# Dropping anywhere on the car is enough when only one hardpoint fits the part.
	var over_car := absf(local_pos.x - car_center().x) < 170.0
	if (nearest == "" or not valid.has(nearest)) and over_car and valid.size() == 1 and nearest_d > 44.0:
		nearest = valid[0]
	for slot: String in slots:
		var node: PartSlot = slots[slot]
		if slot == nearest:
			node.highlight = PartSlot.Highlight.TARGET if valid.has(slot) else PartSlot.Highlight.INVALID
		else:
			node.highlight = PartSlot.Highlight.VALID if valid.has(slot) else PartSlot.Highlight.NONE
	return nearest if valid.has(nearest) else ""


func end_drag() -> void:
	for slot: String in slots:
		(slots[slot] as PartSlot).highlight = PartSlot.Highlight.NONE


func snap_feedback(slot: String) -> void:
	if slots.has(slot):
		(slots[slot] as PartSlot).flash()
	preview.bounce()


func slot_position(slot: String) -> Vector2:
	return (slots[slot] as PartSlot).hotspot if slots.has(slot) else car_center()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < 12.0:
			var best := ""
			var best_d := PartSlot.HIT_RADIUS
			for slot: String in slots:
				var d: float = event.position.distance_to((slots[slot] as PartSlot).hotspot)
				if d < best_d:
					best_d = d
					best = slot
			# Tapping empty blueprint clears the selection.
			slot_tapped.emit(best)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	_time += delta
	if absf(_com_y - _com_target) > 0.1:
		_com_y = lerpf(_com_y, _com_target, minf(1.0, 9.0 * delta))
	_overlay.queue_redraw()


func _draw() -> void:
	# A pixel-art pit garage: back wall with a chequered band and lamps, the painted pit
	# box, and a few props. Kept dark and quiet so the car is the only loud thing here.
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("e4e7e3"))
	var tile := 72.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 76), Vector2(x, size.y), Color(0, 0, 0, 0.05), 2.0)
		x += tile
	var y := 76.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.05), 2.0)
		y += tile
	draw_rect(Rect2(0, 0, size.x, 64), UIKit.LINE)
	PixelArt.draw_checker(self, Rect2(0, 64, size.x, 12), 12.0, Color(0.9, 0.9, 0.9), UIKit.INK)
	var c := car_center()
	for i in 3:
		var lx := size.x * (0.2 + 0.3 * i)
		PixelArt.draw_lamp(self, Vector2(lx - 24.0, 0), 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(lx - 24.0, 28), Vector2(lx + 24.0, 28), Vector2(lx + 150.0, size.y), Vector2(lx - 150.0, size.y)]), Color(1.0, 1.0, 1.0, 0.22))
	var team := Career.my_team() if Career.active() else {"id": "has", "color": "#c8201e", "color2": "#f4f6f2", "short": "APX"}
	PixelArt.draw_logo(self, Rect2(14, 6, 52, 52), team)
	PixelArt.draw_logo(self, Rect2(size.x - 66.0, 6, 52, 52), team)
	# Pit box.
	var half := Vector2(preview.display_scale * 14.5, preview.display_scale * 27.5)
	var box := Rect2(c - half, half * 2.0)
	draw_rect(box, Color("3a3d45"))
	draw_rect(box, Color.WHITE, false, 4.0)
	for edge_y: float in [box.position.y - 12.0, box.end.y + 2.0]:
		var bx := box.position.x
		var k := 0
		while bx < box.end.x:
			draw_rect(Rect2(bx, edge_y, minf(18.0, box.end.x - bx), 10), UIKit.WARM if k % 2 == 0 else Color(0.9, 0.9, 0.9))
			bx += 18.0
			k += 1
	# Props.
	var band: Color = CarVisual.COMPOUND_COLORS.get(GameManager.setup.parts.get("tires", ""), Color.WHITE)
	PixelArt.draw_tire_stack(self, Vector2(26, size.y - 96.0), 5.0, band, 3)
	PixelArt.draw_tire_stack(self, Vector2(96, size.y - 72.0), 5.0, band, 2)
	PixelArt.draw_toolbox(self, Vector2(size.x - 110.0, size.y - 104.0), 5.0, UIKit.WARM)
	PixelArt.draw_cone(self, Vector2(box.position.x - 44.0, box.position.y - 6.0), 3.0)
	PixelArt.draw_cone(self, Vector2(box.end.x + 20.0, box.end.y - 30.0), 3.0)


## Drawn on a child control so the markers sit on top of the car.
func _draw_overlay() -> void:
	if stats == null:
		return
	var c := car_center()
	var font := get_theme_default_font()
	var front_axle := c + preview.car_point(3.0, 0.0)
	var rear_axle := c + preview.car_point(0.0, 0.0)
	var half_w := preview.display_scale * 11.5
	if show_mass:
		_draw_mass(c, font)
		_overlay.draw_string(font, front_axle + Vector2(half_w - 26.0, -26.0), "FRONT %.1f%%" % (stats.front_weight * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.HOT)
		_overlay.draw_string(font, rear_axle + Vector2(half_w - 26.0, 40.0), "REAR %.1f%%" % ((1.0 - stats.front_weight) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.HOT)
		_draw_com(c + Vector2(0.0, _com_y), font)
	if show_aero:
		_draw_aero(c, font, front_axle, rear_axle, half_w)


func _draw_com(p: Vector2, font: Font) -> void:
	var pulse := 1.0 + 0.08 * sin(_time * 3.0)
	var r := 11.0 * pulse
	_overlay.draw_circle(p, r + 5.0, Color(UIKit.WARM, 0.14))
	# Classic centre-of-mass symbol: quartered circle.
	_overlay.draw_circle(p, r, UIKit.BG_DEEP)
	for quarter in 2:
		var pts := PackedVector2Array([p])
		for k in 9:
			pts.append(p + Vector2.RIGHT.rotated(quarter * PI + PI * 0.5 * k / 8.0) * r)
		_overlay.draw_colored_polygon(pts, UIKit.WARM)
	_overlay.draw_arc(p, r, 0.0, TAU, 28, UIKit.WARM, 2.0, true)
	_overlay.draw_line(p - Vector2(r + 7.0, 0), p + Vector2(r + 7.0, 0), UIKit.WARM, 1.2)
	_overlay.draw_line(p - Vector2(0, r + 7.0), p + Vector2(0, r + 7.0), UIKit.WARM, 1.2)
	_overlay.draw_string(font, p + Vector2(r + 10.0, -6.0), "CoM", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.HOT)


func _draw_mass(c: Vector2, font: Font) -> void:
	var side := 1.0
	for item: Dictionary in stats.mass_items:
		var mass: float = item["mass"]
		var p := c + preview.car_point(item["x"], 0.0)
		var radius := 5.0 + sqrt(mass) * 1.9
		var offset := Vector2(side * (preview.display_scale * 3.0 + radius), 0.0) if mass < 100.0 else Vector2.ZERO
		side = -side
		_overlay.draw_circle(p + offset, radius, Color(UIKit.WARM, 0.22))
		_overlay.draw_arc(p + offset, radius, 0.0, TAU, 24, Color(UIKit.WARM, 0.85), 1.2, true)
		_overlay.draw_string(font, p + offset + Vector2(-40.0, 4.0), "%d" % int(round(mass)), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, UIKit.TEXT)
		_overlay.draw_string(font, p + offset + Vector2(-50.0, radius + 11.0), (item["name"] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, Color(UIKit.HOT, 0.9))
	_overlay.draw_string(font, Vector2(12.0, size.y - 12.0), "MASS  ·  %d kg total  ·  circle area = part mass" % int(round(stats.mass)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.HOT)


func _draw_aero(c: Vector2, font: Font, front_axle: Vector2, rear_axle: Vector2, half_w: float) -> void:
	var q := 0.5 * 1.225 * 55.56 * 55.56
	var front := q * stats.front_downforce_area
	var rear := q * stats.rear_downforce_area
	var drag := q * stats.drag_area
	var scale_n := 0.028
	var color := UIKit.ACCENT
	# Downforce presses into the page: shown as arrows converging on each axle.
	for info: Array in [[front_axle, front, "FRONT"], [rear_axle, rear, "REAR"]]:
		var axle: Vector2 = info[0]
		var force: float = info[1]
		var length := force * scale_n
		for side: float in [-1.0, 1.0]:
			var tip := axle + Vector2(side * (half_w - 12.0), 0.0)
			var tail := tip + Vector2(side * length, 0.0)
			_overlay.draw_line(tail, tip, color, 4.0, true)
			_overlay.draw_colored_polygon(PackedVector2Array([tip - Vector2(side * 2.0, 0), tip + Vector2(side * 12.0, -8.0), tip + Vector2(side * 12.0, 8.0)]), color)
		_overlay.draw_string(font, axle + Vector2(half_w + 6.0, 20.0), "%s DOWNFORCE  %d N" % [info[2], int(force)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
	# Drag trails behind the car.
	var tail_start := rear_axle + Vector2(0.0, preview.display_scale * 9.0)
	var drag_len := drag * scale_n
	_overlay.draw_line(tail_start, tail_start + Vector2(0.0, drag_len), UIKit.BAD, 4.0, true)
	_overlay.draw_colored_polygon(PackedVector2Array([tail_start + Vector2(0, drag_len + 12.0), tail_start + Vector2(-8.0, drag_len), tail_start + Vector2(8.0, drag_len)]), UIKit.BAD)
	_overlay.draw_string(font, tail_start + Vector2(14.0, drag_len * 0.5 + 8.0), "DRAG  %d N" % int(drag), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.BAD)
	_overlay.draw_string(font, Vector2(12.0, size.y - 12.0), "AERO @ 200 km/h  ·  balance %.0f%% front / %.0f%% rear" % [stats.front_aero * 100.0, (1.0 - stats.front_aero) * 100.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
