class_name HUDController
extends CanvasLayer
## In-race HUD, kept deliberately sparse: position and lap, a live leaderboard, lap time
## and delta, three status bars (fuel, tires, damage), and gear / speed.

const MESSAGE_TIME := 1.6
const WHITE := Color.WHITE
const DIM := Color(1, 1, 1, 0.7)
const RED := Color("ff5d5d")
const GREEN := Color("5fe08a")
const AMBER := Color("ffb347")

var manager: RaceManager

var _root: Control
var _position_label: Label
var _lap_label: Label
var _time_label: Label
var _delta_label: Label
var _message_label: Label
var _message_timer := 0.0
var _countdown_box: HBoxContainer
var _countdown_lights: Array[Panel] = []
var _go_label: Label
var _pit_label: Label
var _board: Art
var _status: Art
var _gauge: Art
var _pause_overlay: Control
var _shift_box: VBoxContainer
var _slow_timer := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.theme()
	add_child(_root)
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_bottom()
	_build_overlays()
	_build_pause()
	EventBus.driver_message.connect(show_message)
	EventBus.settings_changed.connect(_refresh_settings)


func setup(race_manager: RaceManager) -> void:
	manager = race_manager
	var racing := manager.mode == GameManager.MODE_RACE
	_position_label.visible = racing
	_board.visible = racing
	_refresh_settings()


func _refresh_settings() -> void:
	_shift_box.visible = not bool(GameManager.setting("automatic"))


# ---------------------------------------------------------------- construction

func _shadowed(text: String, size: int, color: Color = WHITE) -> Label:
	var l := UIKit.label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 8)
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_position_label = _shadowed("P1", 34)
	_lap_label = _shadowed("LAP 1", 20)
	_lap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_position_label)
	row.add_child(_lap_label)
	_board = Art.make(Vector2(188, 8 * 23 + 6), _paint_board)
	box.add_child(UIKit.spacer(6))
	box.add_child(_board)


func _build_top_center() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.position.y = 6
	box.add_theme_constant_override("separation", -6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_time_label = _shadowed("0:00.000", 30)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label = _shadowed("", 20, GREEN)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time_label)
	box.add_child(_delta_label)


func _build_top_right() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.position = Vector2(-14, 10)
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	if GameManager.session_mode == GameManager.MODE_TEST:
		var garage := UIKit.button("GARAGE", 14, true)
		garage.custom_minimum_size = Vector2(104, 46)
		garage.pressed.connect(func() -> void: manager.leave_to("garage"))
		box.add_child(garage)
	var reset := UIKit.button("RESET", 14)
	reset.custom_minimum_size = Vector2(80, 46)
	reset.pressed.connect(func() -> void: manager.reset_player())
	box.add_child(reset)
	var pause := UIKit.button("II", 16)
	pause.custom_minimum_size = Vector2(52, 46)
	pause.pressed.connect(func() -> void: manager.toggle_pause())
	box.add_child(pause)
	_status = Art.make(Vector2(176, 74), _paint_status)
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.size = Vector2(176, 74)
	_status.position = Vector2(-190, 66)
	_root.add_child(_status)


func _build_bottom() -> void:
	_gauge = Art.make(Vector2(230, 70), _paint_gauge)
	_gauge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gauge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_gauge.size = Vector2(230, 70)
	_gauge.position = Vector2(-115, -80)
	_root.add_child(_gauge)
	# Manual shift buttons, reachable by the right thumb beside the pedal.
	_shift_box = VBoxContainer.new()
	_shift_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_shift_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_shift_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_shift_box.position = Vector2(-290, -220)
	_shift_box.add_theme_constant_override("separation", 12)
	_root.add_child(_shift_box)
	for info: Array in [["SHIFT +", true], ["SHIFT -", false]]:
		var b := UIKit.button(info[0], 16)
		b.custom_minimum_size = Vector2(110, 84)
		var up: bool = info[1]
		b.pressed.connect(func() -> void:
			if up:
				manager.player.input.shift_up = true
			else:
				manager.player.input.shift_down = true)
		_shift_box.add_child(b)


func _build_overlays() -> void:
	_message_label = _shadowed("", 24, AMBER)
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.position.y = 92
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.modulate.a = 0.0
	_root.add_child(_message_label)
	_pit_label = _shadowed("", 54, WHITE)
	_pit_label.set_anchors_preset(Control.PRESET_CENTER)
	_pit_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pit_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pit_label.position.y -= 150
	_pit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pit_label.visible = false
	_root.add_child(_pit_label)
	_countdown_box = HBoxContainer.new()
	_countdown_box.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_box.position.y -= 120
	_countdown_box.add_theme_constant_override("separation", 14)
	_countdown_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_countdown_box)
	for i in 3:
		var light := Panel.new()
		light.custom_minimum_size = Vector2(54, 54)
		_countdown_box.add_child(light)
		_countdown_lights.append(light)
	_go_label = _shadowed("GO", 84, GREEN)
	_go_label.set_anchors_preset(Control.PRESET_CENTER)
	_go_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_go_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_go_label.position.y -= 110
	_go_label.modulate.a = 0.0
	_root.add_child(_go_label)


func _build_pause() -> void:
	_pause_overlay = ColorRect.new()
	(_pause_overlay as ColorRect).color = Color(0, 0, 0, 0.6)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_root.add_child(_pause_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.add_child(UIKit.title_bar("PAUSED", 52.0))
	var career := not GameManager.career_race.is_empty()
	var entries := [["RESUME", func() -> void: manager.toggle_pause(), true]]
	if career:
		entries.append(["RETIRE FROM RACE", func() -> void: manager.finish_session(), false])
	else:
		entries.append(["RESTART", func() -> void: manager.restart(), false])
		entries.append(["FINISH  -  RESULTS", func() -> void: manager.finish_session(), false])
		entries.append(["GARAGE", func() -> void: manager.leave_to("garage"), false])
		entries.append(["MAIN MENU", func() -> void: manager.leave_to("menu"), false])
	for entry: Array in entries:
		var b := UIKit.button(entry[0], 18, entry[2])
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(entry[1])
		box.add_child(b)
	var cam := UIKit.button("", 14)
	var refresh := func() -> void: cam.text = "CAMERA ROTATION: %s" % ("ON" if bool(GameManager.setting("camera_rotation")) else "OFF")
	refresh.call()
	cam.pressed.connect(func() -> void:
		GameManager.set_setting("camera_rotation", not bool(GameManager.setting("camera_rotation")))
		GameManager.save()
		refresh.call())
	box.add_child(cam)


# ---------------------------------------------------------------- runtime

func set_paused(paused: bool) -> void:
	_pause_overlay.visible = paused


func show_message(text: String, color: Color = AMBER) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)
	_message_label.modulate.a = 1.0
	_message_timer = MESSAGE_TIME


## `lights_on` 0..3 red lights; -1 hides the gantry.
func set_countdown(lights_on: int) -> void:
	_countdown_box.visible = lights_on >= 0
	for i in _countdown_lights.size():
		var on := i < lights_on
		_countdown_lights[i].add_theme_stylebox_override("panel", UIKit.box(Color(0.95, 0.12, 0.1) if on else Color(0.12, 0.02, 0.02, 0.9), Color(0, 0, 0, 0.9), 27, 3, 0))


func flash_go() -> void:
	_go_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_go_label, "modulate:a", 0.0, 0.35)


## Sector colours are no longer shown on the HUD; kept so callers stay simple.
func flash_sector(_index: int, _color: Color) -> void:
	pass


func _process(delta: float) -> void:
	if manager == null or manager.player == null:
		return
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer < 0.4:
			_message_label.modulate.a = maxf(0.0, _message_timer / 0.4)
	var timer := manager.player_timer
	_time_label.text = LapTimer.format_time(timer.current_time(manager.race_time)) if timer.started else "OUT LAP"
	_time_label.add_theme_color_override("font_color", WHITE if timer.current_valid else RED)
	if timer.started and manager.has_delta:
		_delta_label.text = LapTimer.format_time(manager.live_delta, true)
		_delta_label.add_theme_color_override("font_color", GREEN if manager.live_delta <= 0.0 else RED)
	else:
		_delta_label.text = ""
	_pit_label.visible = manager.pit_timer > 0.0
	if _pit_label.visible:
		_pit_label.text = "PIT  %.1f" % manager.pit_timer
	_gauge.queue_redraw()
	_slow_timer -= delta
	if _slow_timer > 0.0:
		return
	_slow_timer = 0.15
	_position_label.text = "P%d" % manager.positions.position_of(manager.player)
	var lap_number := timer.laps_completed + 1
	_lap_label.text = "LAP %d/%d" % [mini(lap_number, GameManager.RACE_LAPS), GameManager.RACE_LAPS] if manager.mode == GameManager.MODE_RACE else "LAP %d" % lap_number
	_board.queue_redraw()
	_status.queue_redraw()


# ---------------------------------------------------------------- widgets

func _total_progress(car: VehicleController) -> float:
	var timer := manager.timers[manager.cars.find(car)]
	return timer.laps_completed * manager.track.length + car.progress - (0.0 if timer.started else manager.track.length)


## Live running order with gaps to the leader.
func _paint_board(a: Control) -> void:
	if manager == null or manager.positions.order.is_empty():
		return
	var f := UIKit.font()
	var order := manager.positions.order
	var leader := order[0]
	var lead_total := _total_progress(leader)
	a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(0, 0, 0, 0.5))
	for i in order.size():
		var car := order[i]
		var y := 3.0 + i * 23.0
		if car == manager.player:
			a.draw_rect(Rect2(0, y, a.size.x, 22), Color(0.78, 0.13, 0.12, 0.9))
		a.draw_rect(Rect2(26, y + 4.0, 6, 14), car.body_color)
		a.draw_string(f, Vector2(6, y + 16.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)
		a.draw_string(f, Vector2(38, y + 16.0), car.driver_name.get_slice(" ", car.driver_name.get_slice_count(" ") - 1).to_upper().left(9), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)
		var gap := "" if i == 0 else "+%.1f" % ((lead_total - _total_progress(car)) / maxf(leader.speed, 25.0))
		a.draw_string(f, Vector2(0, y + 16.0), gap, HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 6.0, 12, DIM)


func _bar(a: Control, y: float, title: String, fraction: float, color: Color) -> void:
	var f := UIKit.font()
	a.draw_string_outline(f, Vector2(0, y + 11.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.75))
	a.draw_string(f, Vector2(0, y + 11.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WHITE)
	var x := 58.0
	var w := a.size.x - x
	a.draw_rect(Rect2(x - 2.0, y, w + 4.0, 14), Color(0, 0, 0, 0.6))
	a.draw_rect(Rect2(x, y + 2.0, w * clampf(fraction, 0.0, 1.0), 10), color)


func _paint_status(a: Control) -> void:
	var car := manager.player
	var p := car.physics
	if p.stats == null:
		return
	var y := 0.0
	if car.uses_fuel:
		_bar(a, y, "FUEL", car.fuel / 100.0, GREEN if car.fuel > 25.0 else RED)
		y += 24.0
	var tires := minf(p.front_tire.wear, p.rear_tire.wear)
	var hot := p.front_tire.is_overheating() or p.rear_tire.is_overheating()
	_bar(a, y, "TIRES", tires, RED if hot or tires < 0.5 else GREEN)
	y += 24.0
	var hurt := car.damage / 100.0
	_bar(a, y, "DAMAGE", hurt, GREEN.lerp(AMBER, clampf(hurt * 2.0, 0.0, 1.0)).lerp(RED, clampf(hurt * 2.0 - 1.0, 0.0, 1.0)))


func _paint_gauge(a: Control) -> void:
	var car := manager.player if manager else null
	if car == null or car.physics.stats == null:
		return
	var f := UIKit.font()
	var p := car.physics
	a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(0, 0, 0, 0.55))
	var segments := 14
	var frac := clampf(p.display_rpm / p.engine.redline_rpm, 0.0, 1.0)
	var seg_w := (a.size.x - 16.0) / segments
	for i in segments:
		var lit := float(i) / segments < frac
		var c := RED if i >= segments - 2 else (AMBER if i >= segments - 5 else WHITE)
		a.draw_rect(Rect2(8.0 + i * seg_w, 7.0, seg_w - 3.0, 8.0), c if lit else Color(1, 1, 1, 0.14))
	var gear := p.transmission.gear
	a.draw_string(f, Vector2(14, 58), "R" if gear < 0 else str(gear), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, AMBER if p.transmission.is_shifting() else WHITE)
	a.draw_string(f, Vector2(0, 56), "%d" % int(car.speed_kmh()), HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 50.0, 36, WHITE)
	a.draw_string(f, Vector2(0, 56), "km/h", HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 10.0, 11, DIM)
