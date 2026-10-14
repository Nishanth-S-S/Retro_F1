class_name GarageUI
extends PanelContainer
## Live engineering readout on the right of the garage. Deliberately a list of separate
## statistics - there is no single "car score", because every build is a trade-off.

signal term_tapped(term: String)

const BALANCE_COLORS: Array[Color] = [Color("d32f2f"), Color("c98a1a"), Color("1e8a4a"), Color("c98a1a"), Color("d32f2f")]

var _values: Dictionary = {}       # term -> Label
var _previous: Dictionary = {}     # term -> float
var _balance_label: Label
var _balance_detail: Label
var _balance_bar: BalanceBar
var _ready_label: Label
var _challenge_box: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.PANEL, 0.94), UIKit.LINE, 8, 1, 12))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	scroll.add_child(box)
	box.add_child(UIKit.label("CAR STATISTICS", 13, UIKit.ACCENT))
	for term: String in ["WEIGHT", "POWER", "POWER / WEIGHT", "TOP SPEED", "0-100 KM/H", "MECH GRIP", "AERO GRIP", "BRAKING", "WEIGHT DIST", "AERO DIST"]:
		_add_row(box, term)
	box.add_child(UIKit.spacer(6))
	var balance_title := _term_button("HANDLING BALANCE", 13, UIKit.ACCENT)
	box.add_child(balance_title)
	_balance_bar = BalanceBar.new()
	_balance_bar.custom_minimum_size = Vector2(0, 26)
	box.add_child(_balance_bar)
	_balance_label = UIKit.label("Neutral", 20, UIKit.GOOD)
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_balance_label)
	_balance_detail = UIKit.label("", 11, UIKit.TEXT_DIM)
	_balance_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_balance_detail)
	_ready_label = UIKit.label("", 12, UIKit.BAD)
	_ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ready_label)
	box.add_child(UIKit.spacer(6))
	box.add_child(UIKit.label("ENGINEERING CHALLENGES", 13, UIKit.ACCENT))
	_challenge_box = VBoxContainer.new()
	_challenge_box.add_theme_constant_override("separation", 2)
	box.add_child(_challenge_box)


func _term_button(term: String, size: int, color: Color) -> Button:
	var b := Button.new()
	b.text = term
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 28)
	b.pressed.connect(func() -> void: term_tapped.emit(term))
	return b


func _add_row(parent: Control, term: String) -> void:
	var row := HBoxContainer.new()
	var name_button := _term_button(term, 12, UIKit.TEXT_DIM)
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_button)
	var value := UIKit.label("-", 15)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	parent.add_child(row)
	_values[term] = value


## `better` is +1 when a higher number is good, -1 when lower is good, 0 when neutral.
func _show(term: String, text: String, number: float, better: float) -> void:
	var label: Label = _values[term]
	label.text = text
	if _previous.has(term) and absf(number - float(_previous[term])) > 0.0005:
		var improved := (number - float(_previous[term])) * better
		var flash := UIKit.ACCENT if better == 0.0 else (UIKit.GOOD if improved > 0.0 else UIKit.BAD)
		label.add_theme_color_override("font_color", flash)
		var tween := label.create_tween()
		tween.tween_interval(0.5)
		tween.tween_method(func(c: Color) -> void: label.add_theme_color_override("font_color", c), flash, UIKit.TEXT, 0.6)
	_previous[term] = number


func refresh(stats: CarStats, setup: CarSetup) -> void:
	_show("WEIGHT", "%d kg" % int(round(stats.mass)), stats.mass, -1.0)
	_show("POWER", "%d kW" % int(stats.power_kw), stats.power_kw, 1.0)
	_show("POWER / WEIGHT", "%d kW/t" % int(round(stats.power_to_weight)), stats.power_to_weight, 1.0)
	if stats.top_speed > 0.0:
		_show("TOP SPEED", "%d km/h  ·  %s" % [int(stats.top_speed * 3.6), stats.top_speed_limited_by.to_lower()], stats.top_speed, 1.0)
		_show("0-100 KM/H", "%.2f s" % stats.accel_0_100, stats.accel_0_100, -1.0)
	else:
		_show("TOP SPEED", "-", 0.0, 1.0)
		_show("0-100 KM/H", "-", 0.0, -1.0)
	_show("MECH GRIP", "%.2f g" % stats.mech_grip_g, stats.mech_grip_g, 1.0)
	_show("AERO GRIP", "%d kg @200" % int(stats.downforce_200 / VehiclePhysicsConfig.GRAVITY), stats.downforce_200, 1.0)
	_show("BRAKING", "%.2f g" % stats.braking_g, stats.braking_g, 1.0)
	_show("WEIGHT DIST", "F %.1f%%  ·  R %.1f%%" % [stats.front_weight * 100.0, (1.0 - stats.front_weight) * 100.0], stats.front_weight, 0.0)
	_show("AERO DIST", "F %.1f%%  ·  R %.1f%%" % [stats.front_aero * 100.0, (1.0 - stats.front_aero) * 100.0], stats.front_aero, 0.0)
	var label := stats.balance_label()
	var idx := CarStats.BALANCE_LABELS.find(label)
	_balance_label.text = label.to_upper()
	_balance_label.add_theme_color_override("font_color", BALANCE_COLORS[idx])
	_balance_detail.text = "low speed: %s\nhigh speed: %s" % [CarStats.balance_label_for(stats.balance_low).to_lower(), CarStats.balance_label_for(stats.balance_high).to_lower()]
	_balance_bar.set_balance(stats.balance_index, stats.balance_low, stats.balance_high)
	var report := BuildValidator.missing_labels(setup)
	_ready_label.text = "" if report.is_empty() else "CAR NOT READY  ·  missing: %s" % ", ".join(report)
	_ready_label.visible = not report.is_empty()
	for child in _challenge_box.get_children():
		child.queue_free()
	for challenge: Dictionary in GameManager.challenges:
		var done := GameManager.is_challenge_done(challenge["id"])
		var line := UIKit.label("%s %s\n    %s" % ["✓" if done else "○", challenge["title"], challenge["description"]], 11, UIKit.GOOD if done else UIKit.TEXT_DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_challenge_box.add_child(line)


## Five-zone understeer <-> oversteer strip with markers for low speed, high speed and overall.
class BalanceBar extends Control:
	var _index := 0.0
	var _low := 0.0
	var _high := 0.0
	var _shown := 0.0

	func set_balance(index: float, low: float, high: float) -> void:
		_index = index
		_low = low
		_high = high

	func _process(delta: float) -> void:
		if absf(_shown - _index) > 0.0002:
			_shown = lerpf(_shown, _index, minf(1.0, 8.0 * delta))
			queue_redraw()

	func _x(value: float) -> float:
		return size.x * (0.5 + clampf(value / 0.2, -0.5, 0.5))

	func _draw() -> void:
		var edges := [-0.1, -CarStats.BALANCE_STRONG, -CarStats.BALANCE_MILD, CarStats.BALANCE_MILD, CarStats.BALANCE_STRONG, 0.1]
		for i in 5:
			var x0 := _x(edges[i])
			var x1 := _x(edges[i + 1])
			draw_rect(Rect2(x0 + 1.0, 8.0, x1 - x0 - 2.0, 8.0), Color(GarageUI.BALANCE_COLORS[i], 0.55))
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, 26), "UNDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIKit.TEXT_DIM)
		draw_string(font, Vector2(0, 26), "OVER", HORIZONTAL_ALIGNMENT_RIGHT, size.x, 9, UIKit.TEXT_DIM)
		# Small ticks: low-speed (L) and high-speed (H) balance.
		for info: Array in [[_low, "L"], [_high, "H"]]:
			var x := _x(info[0])
			draw_line(Vector2(x, 5.0), Vector2(x, 19.0), UIKit.TEXT_DIM, 1.5)
			draw_string(font, Vector2(x - 3.0, 4.0), info[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UIKit.TEXT_DIM)
		var mx := _x(_shown)
		draw_colored_polygon(PackedVector2Array([Vector2(mx, 9.0), Vector2(mx - 6.0, 0.0), Vector2(mx + 6.0, 0.0)]), UIKit.TEXT)
		draw_line(Vector2(mx, 6.0), Vector2(mx, 18.0), UIKit.TEXT, 2.0)
