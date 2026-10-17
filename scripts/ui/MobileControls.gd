class_name MobileControls
extends Control
## Touch controls. Left thumb: a horizontal analog steering strip. Right thumb, in the default
## SPLIT layout: a BRAKE button whose pressure follows where you hold it (low on the button =
## full brake, slide up to bleed it off for trail braking) and a THROTTLE slider that springs
## back when you let go. The classic PEDAL layout keeps one up/down pedal. Above the pedals,
## the pace control (PRESERVE / BALANCED / PUSH) and the energy PUSH spends.
## Every control tracks its own finger, so steering, braking and throttle overlap freely.

const STEER_HALF_RANGE := 150.0
const PEDAL_HALF_RANGE := 135.0
const DEADZONE := 0.05
## Lightest brake a touch on the button gives (top edge); the bottom edge is full brake.
const BRAKE_MIN := 0.3
const PACE_COLORS := ["5fb7ff", "c9ced6", "ff9d3a"]

var input: VehicleInput
## The player's car (pace control and energy). Set by RaceManager.
var car: VehicleController
var _steer_finger := -1
var _pedal_finger := -1
var _throttle_finger := -1
var _brake_finger := -1
var _steer_value := 0.0
var _pedal_value := 0.0
var _throttle_value := 0.0
var _brake_value := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.settings_changed.connect(_apply_opacity)
	resized.connect(queue_redraw)
	_apply_opacity()


func _apply_opacity() -> void:
	modulate.a = clampf(float(GameManager.setting("control_opacity")), 0.1, 1.0)
	release_all()
	queue_redraw()


func _split() -> bool:
	return int(GameManager.setting("control_layout")) == 0


func _process(_delta: float) -> void:
	# The energy bar moves on its own.
	if car:
		queue_redraw()


# ---------------------------------------------------------------- geometry

func _steer_center() -> Vector2:
	return Vector2(maxf(STEER_HALF_RANGE + 50.0, size.x * 0.17), size.y - 110.0)


func _pedal_center() -> Vector2:
	return Vector2(size.x - maxf(110.0, size.x * 0.09), size.y - PEDAL_HALF_RANGE - 70.0)


func _throttle_rect() -> Rect2:
	# Short enough to stay clear of the BOX and DRS buttons above it.
	var w := 74.0
	var h := minf(210.0, size.y * 0.29)
	return Rect2(size.x - maxf(40.0, size.x * 0.03) - w, size.y - 50.0 - h, w, h)


func _brake_rect() -> Rect2:
	var t := _throttle_rect()
	var w := 118.0
	var h := minf(170.0, size.y * 0.24)
	return Rect2(t.position.x - 26.0 - w, t.end.y - h, w, h)


## The pace buttons sit above the steering strip, clear of the pit and DRS buttons.
func _pace_rect(mode: int) -> Rect2:
	var sc := _steer_center()
	var w := 92.0
	var left := sc.x - (w * 1.5 + 6.0)
	return Rect2(left + mode * (w + 6.0), sc.y - 30.0 - 92.0, w, 44.0)


func _energy_rect() -> Rect2:
	var a := _pace_rect(0)
	var b := _pace_rect(2)
	return Rect2(a.position.x, a.end.y + 8.0, b.end.x - a.position.x, 12.0)


## Screen areas of the controls (used by the tutorial spotlight).
func steer_rect() -> Rect2:
	var c := _steer_center()
	return Rect2(c - Vector2(STEER_HALF_RANGE + 30.0, 40.0), Vector2(STEER_HALF_RANGE * 2.0 + 60.0, 80.0))


func pedal_rect() -> Rect2:
	if _split():
		return _brake_rect().merge(_throttle_rect()).grow(10.0)
	var c := _pedal_center()
	return Rect2(c - Vector2(45.0, PEDAL_HALF_RANGE + 30.0), Vector2(90.0, PEDAL_HALF_RANGE * 2.0 + 60.0))


func pace_rect() -> Rect2:
	return _pace_rect(0).merge(_pace_rect(2)).merge(_energy_rect()).grow(8.0)


## Tutorial text for the pedal area.
func pedal_hint() -> String:
	if _split():
		return "BRAKE: press low for full brake, slide up to ease off as you turn in. THROTTLE: slide up to accelerate - feed it in as the steering straightens."
	return "The PEDAL: push up to accelerate, pull down to brake."


# ---------------------------------------------------------------- input

func _in_steer_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.42 and p.y > size.y * 0.3


func _in_pedal_zone(p: Vector2) -> bool:
	return p.x > size.x * 0.76 and p.y > size.y * 0.2


func _input(event: InputEvent) -> void:
	if not visible or input == null or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_3:
			set_pace(key - KEY_1)
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var p := touch.position
		if touch.pressed:
			for mode in 3:
				if _pace_rect(mode).grow(6.0).has_point(p):
					set_pace(mode)
					return
			if _steer_finger == -1 and _in_steer_zone(p):
				_steer_finger = touch.index
				_set_steer(p)
			elif _split():
				if _throttle_finger == -1 and _throttle_rect().grow(12.0).has_point(p):
					_throttle_finger = touch.index
					_set_throttle(p)
				elif _brake_finger == -1 and _brake_rect().grow(12.0).has_point(p):
					_brake_finger = touch.index
					_set_brake(p)
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
			elif touch.index == _throttle_finger:
				_throttle_finger = -1
				_throttle_value = 0.0
			elif touch.index == _brake_finger:
				_brake_finger = -1
				_brake_value = 0.0
		_push()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _steer_finger:
			_set_steer(drag.position)
		elif drag.index == _pedal_finger:
			_set_pedal(drag.position)
		elif drag.index == _throttle_finger:
			_set_throttle(drag.position)
		elif drag.index == _brake_finger:
			_set_brake(drag.position)
		_push()


## 0 = PRESERVE, 1 = BALANCED, 2 = PUSH.
func set_pace(mode: int) -> void:
	if car:
		car.physics.pace_mode = clampi(mode, 0, 2)
		AudioManager.play("click", -12.0, 0.9 + 0.1 * mode)
	queue_redraw()


func _set_steer(p: Vector2) -> void:
	var v := clampf((p.x - _steer_center().x) / STEER_HALF_RANGE, -1.0, 1.0)
	_steer_value = 0.0 if absf(v) < DEADZONE else signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


func _set_pedal(p: Vector2) -> void:
	var v := clampf((_pedal_center().y - p.y) / PEDAL_HALF_RANGE, -1.0, 1.0)
	_pedal_value = 0.0 if absf(v) < DEADZONE else signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


func _set_throttle(p: Vector2) -> void:
	var r := _throttle_rect()
	var v := clampf((r.end.y - p.y) / r.size.y, 0.0, 1.0)
	_throttle_value = 0.0 if v < DEADZONE else (v - DEADZONE) / (1.0 - DEADZONE)


func _set_brake(p: Vector2) -> void:
	var r := _brake_rect()
	_brake_value = lerpf(BRAKE_MIN, 1.0, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0))


func _push() -> void:
	input.touch_steer_active = _steer_finger != -1
	input.touch_steer = _steer_value
	input.touch_pedal_active = _pedal_finger != -1
	input.touch_pedal = _pedal_value
	input.touch_throttle_active = _throttle_finger != -1
	input.touch_throttle = _throttle_value
	input.touch_brake_active = _brake_finger != -1
	input.touch_brake = _brake_value
	queue_redraw()


func release_all() -> void:
	_steer_finger = -1
	_pedal_finger = -1
	_throttle_finger = -1
	_brake_finger = -1
	_steer_value = 0.0
	_pedal_value = 0.0
	_throttle_value = 0.0
	_brake_value = 0.0
	if input:
		_push()


# ---------------------------------------------------------------- drawing

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
	if _split():
		_draw_split(white)
	else:
		_draw_pedal(white)
	_draw_pace()
	_draw_corner_card()


## The last corner, for a few seconds: entry, apex and exit speed and one line of coaching.
func _draw_corner_card() -> void:
	if car == null or car.style == null or car.style.last.is_empty():
		return
	var age := car.style._time - car.style.last_time
	if age > 3.2:
		return
	var font := get_theme_default_font()
	var r: Dictionary = car.style.last
	var alpha := clampf((3.2 - age) / 0.5, 0.0, 1.0)
	var box := Rect2(size.x * 0.5 - 230.0, size.y * 0.2, 460.0, 62.0)
	draw_rect(box, Color(0, 0, 0, 0.55 * alpha))
	var verdict: String = r["verdict"]
	var good := verdict.begins_with("CLEAN") or verdict.begins_with("GREAT") or verdict.begins_with("LATE BRAKING") or verdict.begins_with("CARRIED")
	var tone := Color("5fe08a") if good else Color("ffb347")
	draw_rect(Rect2(box.position, Vector2(6.0, box.size.y)), Color(tone, alpha))
	draw_string(font, box.position + Vector2(16, 24), "%s    IN %d  ·  APEX %d  ·  OUT %d km/h" % [r["name"], r["entry"], r["apex"], r["exit"]], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 16, Color(1, 1, 1, alpha))
	draw_string(font, box.position + Vector2(16, 49), verdict, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 15, Color(tone, alpha))


func _draw_split(white: Color) -> void:
	var font := get_theme_default_font()
	# --- brake button: the fill shows how hard you are braking
	var b := _brake_rect()
	var red := Color("ff5d5d")
	draw_rect(b, Color(0, 0, 0, 0.32))
	if _brake_finger != -1:
		var fill := b.size.y * _brake_value
		draw_rect(Rect2(b.position.x, b.end.y - fill, b.size.x, fill), Color(red, 0.55))
	draw_rect(b, Color(red, 0.85 if _brake_finger != -1 else 0.5), false, 3.0)
	draw_string(font, b.position + Vector2(0, b.size.y * 0.5 + 8.0), "BRAKE", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 20, white)
	draw_string(font, b.position + Vector2(0, 20.0), "light", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 12, Color(1, 1, 1, 0.45))
	draw_string(font, b.position + Vector2(0, b.size.y - 10.0), "full", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 12, Color(1, 1, 1, 0.45))
	# --- throttle slider
	var t := _throttle_rect()
	var green := Color("5fe08a")
	draw_rect(t, Color(0, 0, 0, 0.32))
	var level := t.size.y * _throttle_value
	draw_rect(Rect2(t.position.x, t.end.y - level, t.size.x, level), Color(green, 0.5))
	draw_rect(t, Color(green, 0.85 if _throttle_finger != -1 else 0.5), false, 3.0)
	for i in range(1, 4):
		var y := t.end.y - t.size.y * i / 4.0
		draw_line(Vector2(t.position.x, y), Vector2(t.position.x + 12.0, y), Color(1, 1, 1, 0.35), 2.0)
	var handle_y := t.end.y - level
	draw_rect(Rect2(t.position.x - 6.0, handle_y - 7.0, t.size.x + 12.0, 14.0), Color(green, 0.95 if _throttle_finger != -1 else 0.6))
	_arrow(Vector2(t.get_center().x, t.position.y - 14.0), Vector2.UP, Color(green, 0.7))
	draw_string(font, Vector2(t.position.x, t.end.y + 22.0), "THROTTLE", HORIZONTAL_ALIGNMENT_CENTER, t.size.x, 13, white)


func _draw_pedal(white: Color) -> void:
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


func _draw_pace() -> void:
	if car == null:
		return
	var font := get_theme_default_font()
	var mode := car.physics.pace_mode
	for i in 3:
		var r := _pace_rect(i)
		var color := Color(PACE_COLORS[i])
		draw_rect(r, Color(color, 0.75) if i == mode else Color(0, 0, 0, 0.32))
		draw_rect(r, Color(color, 0.9), false, 2.0)
		draw_string(font, r.position + Vector2(0, r.size.y * 0.5 + 5.0), VehiclePhysics.PACE_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.BLACK if i == mode else Color(1, 1, 1, 0.8))
	# Energy for PUSH: harvested under braking, spent deploying.
	var e := _energy_rect()
	var energy := car.physics.energy / 100.0
	draw_rect(e, Color(0, 0, 0, 0.4))
	var bar := Color("ff9d3a") if car.physics.deploying else Color("ffd34d")
	draw_rect(Rect2(e.position, Vector2(e.size.x * energy, e.size.y)), Color(bar, 0.85))
	draw_rect(e, Color(1, 1, 1, 0.5), false, 1.0)
	draw_string(font, e.position + Vector2(0, e.size.y + 14.0), "ENERGY %d%%" % int(round(energy * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, e.size.x, 12, Color(1, 1, 1, 0.75))


func _arrow(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal() * 7.0
	draw_colored_polygon(PackedVector2Array([tip + dir * 8.0, tip - dir * 4.0 + side, tip - dir * 4.0 - side]), color)
