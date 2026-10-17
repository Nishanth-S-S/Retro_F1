class_name HUDController
extends CanvasLayer
## In-race HUD, kept deliberately sparse: position and lap, a live leaderboard, lap time
## and delta, status bars (fuel, tyre wear, damage) with the tyre rule, a BOX button, pit
## arrows when the car needs a stop, and gear / speed.

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
var _map: Art
var _cockpit: Art
var _speed_lines: Art
var _driver_view := false
var _tyres: HFlowContainer
var _tyre_note: Label
var _drs: Button
var _box: Button
var _pit_alert: Label
var _pit_arrow: Art
var _pulse := 0.0
## Controls the race tutorial points at.
var marks: Dictionary = {}
var _map_points := PackedVector2Array()


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
	_root.add_child(FatigueMeter.make(self))
	EventBus.driver_message.connect(show_message)
	EventBus.settings_changed.connect(_refresh_settings)


func setup(race_manager: RaceManager) -> void:
	manager = race_manager
	var racing := manager.mode == GameManager.MODE_RACE
	_position_label.visible = racing
	_board.visible = racing
	_build_map()
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
	var cam := UIKit.button("CAM", 14)
	cam.custom_minimum_size = Vector2(70, 46)
	cam.pressed.connect(func() -> void:
		GameManager.set_setting("camera_mode", 1 - int(GameManager.setting("camera_mode")))
		GameManager.save())
	box.add_child(cam)
	marks["cam"] = cam
	var reset := UIKit.button("RESET", 14)
	reset.custom_minimum_size = Vector2(80, 46)
	reset.pressed.connect(func() -> void: manager.reset_player())
	box.add_child(reset)
	marks["reset"] = reset
	var pause := UIKit.button("II", 16)
	pause.custom_minimum_size = Vector2(52, 46)
	pause.pressed.connect(func() -> void: manager.toggle_pause())
	box.add_child(pause)
	_status = Art.make(Vector2(176, 104), _paint_status)
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.size = Vector2(176, 104)
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
	# Driver's view: speed streaks at the edges and an F1 steering wheel at the bottom.
	_speed_lines = Art.make(Vector2.ZERO, _paint_speed_lines)
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.visible = false
	_root.add_child(_speed_lines)
	_root.move_child(_speed_lines, 0)
	_cockpit = Art.make(Vector2(340, 170), _paint_wheel)
	_cockpit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cockpit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cockpit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cockpit.size = Vector2(340, 170)
	_cockpit.position = Vector2(-170, -150)
	_cockpit.visible = false
	_root.add_child(_cockpit)
	# Tyre choice during a pit stop.
	var tyre_box := VBoxContainer.new()
	tyre_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tyre_box.offset_left = 220
	tyre_box.offset_right = -220
	tyre_box.offset_top = -330
	tyre_box.offset_bottom = -170
	tyre_box.add_theme_constant_override("separation", 6)
	_root.add_child(tyre_box)
	_tyre_note = _shadowed("", 18, AMBER)
	_tyre_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tyre_box.add_child(_tyre_note)
	_tyres = HFlowContainer.new()
	_tyres.alignment = FlowContainer.ALIGNMENT_CENTER
	_tyres.add_theme_constant_override("h_separation", 6)
	_tyres.add_theme_constant_override("v_separation", 6)
	tyre_box.add_child(_tyres)
	# DRS: lights up on a straight within a second of the car ahead; tap to open the flap.
	_drs = UIKit.button("DRS", 22)
	_drs.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_drs.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_drs.size = Vector2(176, 66)
	_drs.position = Vector2(-190, 322)
	_drs.pressed.connect(func() -> void: manager.open_drs())
	_drs.visible = GameManager.session_mode == GameManager.MODE_RACE
	_root.add_child(_drs)
	# BOX: tap once and the car pits itself at the next pit entry.
	_box = UIKit.button("BOX", 20)
	_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_box.size = Vector2(176, 58)
	_box.position = Vector2(-190, 396)
	_box.pressed.connect(func() -> void: manager.toggle_box())
	_box.visible = GameManager.session_mode != GameManager.MODE_TIME_TRIAL
	_root.add_child(_box)
	marks["box"] = _box

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
	# "BOX THIS LAP" banner and an arrow pointing at the pit entry when a stop is needed.
	_pit_alert = _shadowed("", 22, AMBER)
	_pit_alert.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pit_alert.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pit_alert.position.y = 128
	_pit_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_pit_alert)
	_pit_arrow = Art.make(Vector2.ZERO, _paint_pit_arrow)
	_pit_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pit_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pit_arrow)
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
	var panel := DifficultyPanel.new()
	var diff := UIKit.button("DIFFICULTY: %s" % Difficulty.mode_name(), 14)
	diff.pressed.connect(func() -> void: panel.open())
	panel.closed.connect(func() -> void: diff.text = "DIFFICULTY: %s" % Difficulty.mode_name())
	box.add_child(diff)
	_root.add_child(panel)


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
		_pit_label.text = "PIT STOP  %.1f" % manager.pit_timer
	_gauge.queue_redraw()
	if _driver_view:
		_cockpit.queue_redraw()
		_speed_lines.queue_redraw()
	_drs.visible = manager.mode == GameManager.MODE_RACE and manager.pit_phase == ""
	_drs.disabled = not manager.drs_available
	_drs.text = "DRS OPEN" if manager.drs_open else "DRS"
	_pulse += delta
	var reason := manager.pit_reason()
	var need := manager.state == RaceManager.State.RACING and manager.pit_phase == "" and (reason != "" or manager.box_armed)
	_box.visible = GameManager.session_mode != GameManager.MODE_TIME_TRIAL and manager.pit_phase == "" and manager.state == RaceManager.State.RACING
	_box.text = "BOX ARMED\nTAP TO CANCEL" if manager.box_armed else ("BOX  ·  %s" % reason if reason != "" else "BOX")
	_box.add_theme_font_size_override("font_size", 14 if manager.box_armed or reason != "" else 20)
	_box.modulate = Color.WHITE.lerp(AMBER, 0.5 + 0.5 * sin(_pulse * 8.0)) if reason != "" and not manager.box_armed else Color.WHITE
	_pit_alert.visible = need
	if need:
		_pit_alert.text = ("BOX BOX  ·  PITTING NEXT ENTRY" if manager.box_armed else "BOX THIS LAP  ·  %s" % reason) + "  ·  %d m" % int(_to_pit_entry())
		_pit_alert.modulate.a = 0.65 + 0.35 * sin(_pulse * 6.0)
	_pit_arrow.visible = need
	if need:
		_pit_arrow.queue_redraw()
	_slow_timer -= delta
	if _slow_timer > 0.0:
		return
	_slow_timer = 0.15
	_position_label.text = "P%d" % manager.positions.position_of(manager.player)
	var lap_number := timer.laps_completed + 1
	_lap_label.text = "LAP %d/%d" % [mini(lap_number, GameManager.race_laps), GameManager.race_laps] if manager.mode == GameManager.MODE_RACE else "LAP %d" % lap_number
	_board.queue_redraw()
	_status.queue_redraw()
	if _map:
		_map.queue_redraw()


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
	# Twenty cars do not fit: the top three, then the cars around you.
	var shown: Array[int] = []
	var me := order.find(manager.player)
	for i in order.size():
		if i < 3 or (absi(i - me) <= 2 and shown.size() < 8) or (order.size() <= 8):
			shown.append(i)
	for row in shown.size():
		var i := shown[row]
		var car := order[i]
		var y := 3.0 + row * 23.0
		if row > 0 and shown[row - 1] != i - 1:
			a.draw_line(Vector2(6, y - 1.0), Vector2(a.size.x - 6.0, y - 1.0), DIM, 1.0)
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
	var f := UIKit.font()
	var y := 0.0
	if car.uses_fuel:
		_bar(a, y, "FUEL", car.fuel / 100.0, GREEN if car.fuel > 25.0 else RED)
		y += 24.0
	# Tyre degradation: compound colour chip, budget left, and the bar fading green -> red.
	var life := manager.tyre_life()
	var hot := p.front_tire.is_overheating() or p.rear_tire.is_overheating()
	var wear_col := RED.lerp(AMBER, clampf(life / 0.5, 0.0, 1.0)).lerp(GREEN, clampf((life - 0.5) / 0.3, 0.0, 1.0))
	_bar(a, y, "TYRES", life, RED if hot and fmod(_pulse, 0.5) < 0.25 else wear_col)
	var compound: Color = CarVisual.COMPOUND_COLORS.get(car.setup.parts.get("tires", ""), Color.WHITE)
	a.draw_circle(Vector2(50, y + 7.0), 5.0, compound)
	# The tyre budget: the bar is what is left to spend before the stop, and the tick is where
	# an even spend to the planned stop would be by now (bar short of the tick = overspending).
	var target := car.tyre_target()
	if target >= 0.0:
		var tx := 58.0 + (a.size.x - 58.0) * target
		a.draw_rect(Rect2(tx - 1.5, y - 2.0, 3.0, 18.0), AMBER if life < target - 0.05 else Color(1, 1, 1, 0.95))
	y += 24.0
	var hurt := car.damage / 100.0
	_bar(a, y, "DAMAGE", hurt, GREEN.lerp(AMBER, clampf(hurt * 2.0, 0.0, 1.0)).lerp(RED, clampf(hurt * 2.0 - 1.0, 0.0, 1.0)))
	y += 24.0
	# The two-compound rule: what is still owed.
	var rule := manager.tyre_rule_text()
	if rule != "":
		var col := AMBER if manager.stop_required() else GREEN
		a.draw_string_outline(f, Vector2(0, y + 11.0), rule, HORIZONTAL_ALIGNMENT_LEFT, a.size.x, 10, 4, Color(0, 0, 0, 0.8))
		a.draw_string(f, Vector2(0, y + 11.0), rule, HORIZONTAL_ALIGNMENT_LEFT, a.size.x, 10, col)


## Metres to the pit entry along the track.
func _to_pit_entry() -> float:
	var t := manager.track
	return fposmod(t.pit_start - manager.player.progress, t.length)


## A big arrow at the edge of a ring around the car, pointing at the pit entry.
func _paint_pit_arrow(a: Control) -> void:
	if manager == null or manager.player == null:
		return
	var t := manager.track
	var canvas := a.get_viewport().get_canvas_transform()
	var car_screen := canvas * manager.player.global_position
	var target := canvas * t.position_at(t.pit_start + 10.0, -(t.half_width + TrackData.PIT_WIDTH * 0.55))
	var dir := (target - car_screen).normalized()
	if dir == Vector2.ZERO:
		return
	var at := car_screen + dir * 120.0
	if car_screen.distance_to(target) < 140.0:
		at = target - dir * 30.0
	var col := AMBER.lerp(Color.WHITE, 0.25 + 0.25 * sin(_pulse * 8.0))
	var side := dir.orthogonal()
	var pts := PackedVector2Array([at + dir * 30.0, at + side * 20.0, at + side * 8.0 - dir * 4.0, at + side * 8.0 - dir * 26.0, at - side * 8.0 - dir * 26.0, at - side * 8.0 - dir * 4.0, at - side * 20.0])
	var outline := pts.duplicate()
	outline.append(pts[0])
	a.draw_colored_polygon(pts, col)
	a.draw_polyline(outline, Color(0, 0, 0, 0.8), 3.0)
	var f := UIKit.font()
	a.draw_string_outline(f, at - dir * 44.0 + Vector2(-30, 6), "PIT", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, 5, Color(0, 0, 0, 0.85))
	a.draw_string(f, at - dir * 44.0 + Vector2(-30, 6), "PIT", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, AMBER)


# ---------------------------------------------------------------- track map

const MAP_SIZE := Vector2(176, 132)


## Mini map of the circuit, top right under the status bars: every car is a dot.
func _build_map() -> void:
	var track := manager.track
	var b := track.bounds
	var inner := MAP_SIZE - Vector2(20, 30)
	var fit := minf(inner.x / maxf(b.size.x, 1.0), inner.y / maxf(b.size.y, 1.0))
	var origin := Vector2(10, 22) + (inner - b.size * fit) * 0.5
	_map_points.clear()
	for i in range(0, track.count, 3):
		_map_points.append(origin + (track.points[i] - b.position) * fit)
	_map_points.append(_map_points[0])
	_map = Art.make(MAP_SIZE, _paint_map)
	_map.set_meta("fit", fit)
	_map.set_meta("origin", origin)
	_map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map.size = MAP_SIZE
	_map.position = Vector2(-190, 178)
	_root.add_child(_map)


func _paint_map(a: Control) -> void:
	if manager == null or _map_points.size() < 3:
		return
	var f := UIKit.font()
	a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(0, 0, 0, 0.5))
	a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(1, 1, 1, 0.25), false, 2.0)
	a.draw_string(f, Vector2(6, 14), GameManager.TRACK_NAMES.get(GameManager.track_id, "TRACK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, WHITE)
	var wet := manager.weather
	a.draw_string(f, Vector2(0, 14), WeatherFX.NAMES[wet], HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 6.0, 10, Color("7fd4ff") if wet > 0 else AMBER)
	# The circuit width: 6.32 car widths, the FIA ratio for a permanent circuit.
	a.draw_string(f, Vector2(6, a.size.y - 6.0), "%.2f CAR WIDTHS WIDE" % (manager.track.half_width * 2.0 / TrackData.CAR_WIDTH), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.7))
	a.draw_polyline(_map_points, Color(0, 0, 0, 0.9), 7.0)
	a.draw_polyline(_map_points, Color(0.9, 0.92, 0.95), 3.0)
	# Start / finish line.
	a.draw_rect(Rect2(_map_points[0] - Vector2(3, 3), Vector2(6, 6)), Color.WHITE)
	a.draw_rect(Rect2(_map_points[0] - Vector2(3, 3), Vector2(3, 3)), Color.BLACK)
	a.draw_rect(Rect2(_map_points[0], Vector2(3, 3)), Color.BLACK)
	var fit: float = a.get_meta("fit")
	var origin: Vector2 = a.get_meta("origin")
	var b := manager.track.bounds
	for car in manager.cars:
		if car == manager.player:
			continue
		var p := origin + (car.global_position - b.position) * fit
		a.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.BLACK)
		a.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), car.body_color)
	var me := origin + (manager.player.global_position - b.position) * fit
	a.draw_rect(Rect2(me - Vector2(5, 5), Vector2(10, 10)), Color.BLACK)
	a.draw_rect(Rect2(me - Vector2(4, 4), Vector2(8, 8)), RED)
	a.draw_rect(Rect2(me - Vector2(2, 2), Vector2(4, 4)), WHITE)


## Pit stop tyre picker: one button per compound the team owns. Empty list hides it.
func show_tyre_choice(options: Array, chosen: String, required: bool) -> void:
	for child in _tyres.get_children():
		child.queue_free()
	_tyre_note.text = ""
	if options.is_empty():
		return
	_tyre_note.text = "PICK TYRES%s" % ("  -  A DIFFERENT DRY COMPOUND IS REQUIRED" if required else "")
	for id: String in options:
		var part := PartDB.get_part(id)
		var b := UIKit.button(part.display_name.to_upper(), 13, id == chosen)
		b.custom_minimum_size = Vector2(130, 52)
		b.add_theme_color_override("font_outline_color", Color.BLACK)
		var tire_id := id
		b.pressed.connect(func() -> void: manager.choose_tyre(tire_id))
		var band := ColorRect.new()
		band.color = CarVisual.COMPOUND_COLORS.get(id, Color.WHITE)
		band.custom_minimum_size = Vector2(0, 6)
		band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		band.offset_top = -10
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(band)
		_tyres.add_child(b)


func set_driver_view(on: bool) -> void:
	_driver_view = on
	_cockpit.visible = on
	_speed_lines.visible = on
	_gauge.visible = not on


func _paint_speed_lines(a: Control) -> void:
	var car := manager.player if manager else null
	if car == null:
		return
	var t := clampf((car.speed - 30.0) / 50.0, 0.0, 1.0)
	# Vignette that tightens with speed.
	for i in 6:
		var inset := i * 14.0
		a.draw_rect(Rect2(inset, inset, a.size.x - inset * 2.0, a.size.y - inset * 2.0), Color(0, 0, 0, 0.05 + 0.05 * t), false, 14.0)
	if t <= 0.0:
		return
	var centre := a.size * Vector2(0.5, 0.42)
	var phase := fmod(manager.race_time * 3.0, 1.0)
	for k in 26:
		var ang := TAU * k / 26.0 + sin(k * 7.3) * 0.1
		var dir := Vector2.RIGHT.rotated(ang)
		var start := 0.62 + fmod(phase + k * 0.37, 1.0) * 0.3
		var p0 := centre + dir * a.size.length() * 0.5 * start
		var p1 := centre + dir * a.size.length() * 0.5 * minf(start + 0.12 * t, 1.0)
		a.draw_line(p0, p1, Color(1, 1, 1, 0.22 * t), 3.0)


## Dashboard in the driver's view: rev lights across the top, gear and speed in the
## middle, DRS and pit status lights. It stays still - only the numbers move.
func _paint_wheel(a: Control) -> void:
	var car := manager.player if manager else null
	if car == null or car.physics.stats == null:
		return
	var f := UIKit.font()
	var p := car.physics
	a.draw_set_transform(Vector2(a.size.x * 0.5, 104), 0.0, Vector2.ONE)
	var ink := Color("0e1013")
	a.draw_rect(Rect2(-132, -54, 264, 104), ink)
	a.draw_rect(Rect2(-126, -48, 252, 92), Color("23262e"))
	var frac := clampf(p.display_rpm / p.engine.redline_rpm, 0.0, 1.0)
	for i in 15:
		var lit := float(i) / 15.0 < frac
		var c := Color("2f6fde") if i >= 12 else (Color("ff3b30") if i >= 8 else Color("37d45a"))
		a.draw_rect(Rect2(-112 + i * 15.0, -44, 11, 9), c if lit else Color(c, 0.18))
	a.draw_rect(Rect2(-62, -30, 124, 62), Color("0a0c0f"))
	a.draw_rect(Rect2(-62, -30, 124, 62), Color("3a3f48"), false, 2.0)
	var gear := p.transmission.gear
	a.draw_string(f, Vector2(-62, 18), "R" if gear < 0 else ("N" if gear == 0 else str(gear)), HORIZONTAL_ALIGNMENT_CENTER, 62, 42, Color("ffb347") if p.transmission.is_shifting() else Color.WHITE)
	a.draw_string(f, Vector2(0, 8), "%d" % int(car.speed_kmh()), HORIZONTAL_ALIGNMENT_CENTER, 62, 24, Color.WHITE)
	a.draw_string(f, Vector2(0, 24), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 62, 10, DIM)
	var lights := [[-100, 4, "DRS", Color("37d45a") if manager.drs_open else (Color("f5c542") if manager.drs_available else Color("3a3f48"))],
		[-100, 30, "PIT", Color("f5c542") if manager.pit_phase != "" else Color("3a3f48")],
		[100, 4, "DMG", GREEN.lerp(RED, clampf(car.damage / 80.0, 0.0, 1.0))],
		[100, 30, "TYR", GREEN.lerp(RED, clampf(1.0 - minf(p.front_tire.wear, p.rear_tire.wear), 0.0, 1.0) * 1.6)]]
	for info: Array in lights:
		a.draw_circle(Vector2(info[0], info[1]), 10.0, info[3])
		a.draw_circle(Vector2(info[0], info[1]), 4.0, ink)
		a.draw_string(f, Vector2(float(info[0]) - 30.0 + (0.0 if info[0] < 0 else 44.0), float(info[1]) + 4.0), str(info[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, DIM)
	a.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
