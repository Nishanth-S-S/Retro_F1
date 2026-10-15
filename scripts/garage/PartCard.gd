class_name PartCard
extends PanelContainer
## One entry in the parts list. Shows the trade-offs at a glance and can be tapped
## (select / act) or dragged sideways onto the car.

signal selected(part: VehiclePart)
signal action_pressed(part: VehiclePart)
signal drag_started(part: VehiclePart, card: PartCard)
signal drag_moved(global_pos: Vector2)
signal drag_released(global_pos: Vector2)

const DRAG_THRESHOLD := 14.0

var part: VehiclePart
var is_selected := false
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _name: Label
var _status: Label
var _lines: Label
var _action: Button
var _ovr: Label
## Set by the garage: what fitting this part would do to the car's overall, e.g. "OVR 64 -> 66".
var ovr_line := ""
var ovr_delta := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(0, 104)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	# Pixel-art picture of the part.
	var icon := Art.make(Vector2(72, 72), func(a: Control) -> void:
		var team := Career.my_team() if Career.active() else {"color": "#c8201e"}
		PixelArt.draw_part(a, Rect2(Vector2.ZERO, a.size), part, Color(str(team["color"]))))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_name = UIKit.label("", 20)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_name)
	_ovr = UIKit.label("", 18, UIKit.TEXT)
	_ovr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_ovr)
	_status = UIKit.label("", 12, UIKit.ACCENT)
	text.add_child(_status)
	_lines = UIKit.label("", 11, UIKit.TEXT_DIM)
	_lines.add_theme_constant_override("line_spacing", -2)
	text.add_child(_lines)
	_action = UIKit.button("", 15)
	_action.custom_minimum_size = Vector2(84, 60)
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action.pressed.connect(func() -> void: action_pressed.emit(part))
	row.add_child(_action)
	if part:
		refresh()


func setup(vehicle_part: VehiclePart) -> void:
	part = vehicle_part
	if _name:
		refresh()


func can_drag() -> bool:
	return part != null and GameManager.is_owned(part.id)


func refresh() -> void:
	_name.text = part.display_name
	_lines.text = part.summary_lines()[0]
	var owned := GameManager.is_owned(part.id)
	var installed := GameManager.setup.parts.values().has(part.id)
	_ovr.text = ovr_line
	_ovr.add_theme_color_override("font_color", UIKit.GOOD if ovr_delta > 0 else (UIKit.BAD if ovr_delta < 0 else UIKit.TEXT))
	var border := UIKit.LINE
	_action.disabled = false
	_action.visible = true
	if installed:
		_status.text = "INSTALLED"
		_status.add_theme_color_override("font_color", UIKit.GOOD)
		_action.text = "FITTED" if part.category != "suspension" else "FIT"
		_action.disabled = part.category != "suspension"
		border = UIKit.GOOD.darkened(0.3)
	elif owned:
		_status.text = "OWNED"
		_status.add_theme_color_override("font_color", UIKit.ACCENT)
		_action.text = "FIT"
	else:
		# Not developed yet: research points unlock it for good.
		var cost := GameManager.research_cost(part.id)
		_status.text = "NEEDS RESEARCH"
		_status.add_theme_color_override("font_color", UIKit.PURPLE)
		_action.text = "RESEARCH\n%d RP" % cost
		_action.disabled = GameManager.research() < cost
		border = UIKit.PURPLE.darkened(0.45)
	if Career.is_banned(part.id):
		_status.text = "BANNED BY THE FIA"
		_status.add_theme_color_override("font_color", UIKit.BAD)
	if is_selected:
		border = UIKit.WARM
	add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.PANEL_LIGHT, 0.95) if owned else Color(UIKit.PANEL, 0.9), border, 6, 2 if is_selected else 1, 8))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragging = false
			_press_pos = event.global_position
		else:
			if _dragging:
				drag_released.emit(event.global_position)
			elif _pressed and event.global_position.distance_to(_press_pos) < DRAG_THRESHOLD:
				selected.emit(part)
			_pressed = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressed:
		var moved: Vector2 = event.global_position - _press_pos
		if not _dragging and can_drag() and moved.length() > DRAG_THRESHOLD and absf(moved.x) > absf(moved.y) * 0.8:
			# A sideways pull lifts the part off the shelf; vertical movement still scrolls the list.
			_dragging = true
			drag_started.emit(part, self)
		if _dragging:
			accept_event()
			drag_moved.emit(event.global_position)
