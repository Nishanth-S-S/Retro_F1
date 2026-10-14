class_name MobileControls
extends Control
## Two-thumb touch controls. Left: horizontal analog steering strip. Right: one vertical
## pedal - push up for throttle, pull down for brake. Each control tracks its own finger
## index, so steering + throttle or steering + brake work simultaneously.

const STEER_HALF_RANGE := 150.0
const PEDAL_HALF_RANGE := 135.0
const DEADZONE := 0.05

var input: VehicleInput
var _steer_finger := -1
var _pedal_finger := -1
var _steer_value := 0.0
var _pedal_value := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.settings_changed.connect(_apply_opacity)
	resized.connect(queue_redraw)
	_apply_opacity()


func _apply_opacity() -> void:
	modulate.a = clampf(float(GameManager.setting("control_opacity")), 0.1, 1.0)


func _steer_center() -> Vector2:
	return Vector2(maxf(STEER_HALF_RANGE + 50.0, size.x * 0.17), size.y - 110.0)


func _pedal_center() -> Vector2:
	return Vector2(size.x - maxf(110.0, size.x * 0.09), size.y - PEDAL_HALF_RANGE - 70.0)


## Screen areas of the two controls (used by the tutorial spotlight).
func steer_rect() -> Rect2:
	var c := _steer_center()
	return Rect2(c - Vector2(STEER_HALF_RANGE + 30.0, 40.0), Vector2(STEER_HALF_RANGE * 2.0 + 60.0, 80.0))


func pedal_rect() -> Rect2:
	var c := _pedal_center()
	return Rect2(c - Vector2(45.0, PEDAL_HALF_RANGE + 30.0), Vector2(90.0, PEDAL_HALF_RANGE * 2.0 + 60.0))


func _in_steer_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.42 and p.y > size.y * 0.3


func _in_pedal_zone(p: Vector2) -> bool:
	return p.x > size.x * 0.76 and p.y > size.y * 0.2


func _input(event: InputEvent) -> void:
	if not visible or input == null or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var p := touch.position
		if touch.pressed:
			if _steer_finger == -1 and _in_steer_zone(p):
				_steer_finger = touch.index
				_set_steer(p)
			elif _pedal_finger == -1 and _in_pedal_zone(p):
				_pedal_finger = touch.index
				_set_pedal(p)
		else:
			if touch.index == _steer_finger:
				_steer_finger = -1
				_steer_value = 0.0
			elif touch.index == _pedal_finger:
				_pedal_finger = -1
				_pedal_value = 0.0
		_push()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _steer_finger:
			_set_steer(drag.position)
		elif drag.index == _pedal_finger:
			_set_pedal(drag.position)
		_push()


func _set_steer(p: Vector2) -> void:
	var v := clampf((p.x - _steer_center().x) / STEER_HALF_RANGE, -1.0, 1.0)
	_steer_value = 0.0 if absf(v) < DEADZONE else signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


func _set_pedal(p: Vector2) -> void:
	var v := clampf((_pedal_center().y - p.y) / PEDAL_HALF_RANGE, -1.0, 1.0)
	_pedal_value = 0.0 if absf(v) < DEADZONE else signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


func _push() -> void:
	input.touch_steer_active = _steer_finger != -1
	input.touch_steer = _steer_value
	input.touch_pedal_active = _pedal_finger != -1
	input.touch_pedal = _pedal_value
	queue_redraw()


func release_all() -> void:
	_steer_finger = -1
	_pedal_finger = -1
	_steer_value = 0.0
	_pedal_value = 0.0
	if input:
		_push()


func _draw() -> void:
	var white := Color(1, 1, 1, 0.75)
	var dim := Color(1, 1, 1, 0.22)
	# --- steering strip
	var sc := _steer_center()
	draw_rect(Rect2(sc.x - STEER_HALF_RANGE - 26.0, sc.y - 30.0, STEER_HALF_RANGE * 2.0 + 52.0, 60.0), Color(0, 0, 0, 0.28))
	draw_line(sc - Vector2(STEER_HALF_RANGE, 0), sc + Vector2(STEER_HALF_RANGE, 0), dim, 3.0, true)
	for tick: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var tx := sc.x + tick * STEER_HALF_RANGE
		draw_line(Vector2(tx, sc.y - (12.0 if tick == 0.0 else 7.0)), Vector2(tx, sc.y + (12.0 if tick == 0.0 else 7.0)), dim, 2.0)
	_arrow(sc - Vector2(STEER_HALF_RANGE + 14.0, 0), Vector2.LEFT, dim)
	_arrow(sc + Vector2(STEER_HALF_RANGE + 14.0, 0), Vector2.RIGHT, dim)
	var knob := sc + Vector2(_steer_value * STEER_HALF_RANGE, 0)
	draw_circle(knob, 24.0, Color(Color("7fd4ff"), 0.85 if _steer_finger != -1 else 0.5))
	draw_arc(knob, 24.0, 0.0, TAU, 28, white, 2.0, true)
	# --- pedal
	var pc := _pedal_center()
	draw_rect(Rect2(pc.x - 34.0, pc.y - PEDAL_HALF_RANGE - 26.0, 68.0, PEDAL_HALF_RANGE * 2.0 + 52.0), Color(0, 0, 0, 0.28))
	draw_line(pc - Vector2(0, PEDAL_HALF_RANGE), pc, Color(Color("5fe08a"), 0.45), 4.0, true)
	draw_line(pc, pc + Vector2(0, PEDAL_HALF_RANGE), Color(Color("ff5d5d"), 0.45), 4.0, true)
	draw_line(pc - Vector2(14, 0), pc + Vector2(14, 0), white, 2.0)
	_arrow(pc - Vector2(0, PEDAL_HALF_RANGE + 12.0), Vector2.UP, Color(Color("5fe08a"), 0.7))
	_arrow(pc + Vector2(0, PEDAL_HALF_RANGE + 12.0), Vector2.DOWN, Color(Color("ff5d5d"), 0.7))
	var pk := pc - Vector2(0, _pedal_value * PEDAL_HALF_RANGE)
	var pedal_color := Color("5fe08a") if _pedal_value > 0.0 else (Color("ff5d5d") if _pedal_value < 0.0 else Color("c9ced6"))
	draw_circle(pk, 26.0, Color(pedal_color, 0.85 if _pedal_finger != -1 else 0.5))
	draw_arc(pk, 26.0, 0.0, TAU, 28, white, 2.0, true)


func _arrow(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal() * 7.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 8.0, tip - dir * 4.0 + side, tip - dir * 4.0 - side]), color)
