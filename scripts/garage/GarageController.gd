extends Control
## Garage scene root. The screen is just the car: tap a part of it and the whole sidebar on
## the left becomes the picker for that hardpoint. Everything is told as an overall rating, with
## the raw stat in small grey text underneath. Research points develop parts and upgrade levels;
## money never buys car parts.

const PANEL_WIDTH := 410.0
## Which tuning slider belongs to which hardpoint.
const SLOT_SLIDERS := {"front_wing": ["FRONT WING ANGLE"], "rear_wing": ["REAR WING ANGLE"], "brakes": ["BRAKE BIAS"], "ballast": ["BALLAST POSITION"],
	"chassis": ["RIDE HEIGHT", "BODY SET"], "tires": ["TYRE PRESSURE"], "front_suspension": ["ANTI-ROLL BALANCE"], "rear_suspension": ["ANTI-ROLL BALANCE"]}

## The five ratings in the sidebar summary (names from CarRatings).
const SUMMARY: PackedStringArray = ["TOP SPEED", "ACCELERATION", "CORNERING", "BRAKING", "BALANCE", "AERODYNAMICS"]

var _config: VehiclePhysicsConfig = preload("res://data/physics/default_physics.tres")
var _stats: CarStats
var _active_slot := ""
var _selected_part: VehiclePart

var _workspace: BlueprintWorkspace
var _details: Control
var _card_list: VBoxContainer
var _card_overall: Label
var _drag: PartDragHandler
var _popup: InfoPopup
var _money_label: Label
var _rows: Dictionary = {}
var _ovr_label: Label
var _upgrade_info: Label
var _upgrade_button: Button
var _cars_overlay: Control
var _warning: Label
var _overview: VBoxContainer
var _picker: VBoxContainer
var _picker_title: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _detail: Label
var _remove_button: Button
var _sliders: Dictionary = {}
var _slider_values: Dictionary = {}
var _slider_cells: Dictionary = {}
var _drag_scroll := 0
var _tunnel: WindTunnelUI
## Sidebar widgets shown only while no hardpoint is selected.
var _summary_nodes: Array[Control] = []
var _marks: Dictionary = {}
var _car_button: Button


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music(true)
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_workspace = BlueprintWorkspace.new()
	_place(_workspace, 0.0, 0.0, 1.0, 1.0, PANEL_WIDTH + 20, 78, -12, -12)
	add_child(_workspace)
	_workspace.slot_tapped.connect(_on_slot_tapped)
	_build_top_bar()
	_build_side_panel()
	_build_details()
	_drag = PartDragHandler.new()
	_drag.workspace = _workspace
	add_child(_drag)
	_drag.dropped.connect(_on_part_dropped)
	_popup = InfoPopup.new()
	add_child(_popup)
	_tunnel = WindTunnelUI.new()
	add_child(_tunnel)
	EventBus.setup_changed.connect(_refresh_all)
	EventBus.inventory_changed.connect(_refresh_all)
	EventBus.money_changed.connect(func(_amount: int) -> void: _refresh_all())
	EventBus.research_changed.connect(func(_amount: int) -> void: _refresh_all())
	_show_picker("")
	_refresh_all()
	CoachMarks.run_once(self, "garage", func() -> Array:
		var steps: Array = [
			[_workspace, "This is your car. Tap any part of it - wings, engine, tyres - to swap it, upgrade it or tune it."],
			[_marks["rp"], "RESEARCH POINTS develop new parts and upgrade levels. Money never buys car parts."],
			[_marks["ovr"], "Everything is measured in OVERALL. Every part, upgrade and setup change moves it."],
			[_marks["tunnel"], "The WIND TUNNEL shows your car in 3D and lights up its weakest areas."],
		]
		steps.append([_marks["test"], "TEST CAR takes it out on track so you can feel what you changed."])
		return steps)


func _place(node: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	node.anchor_left = al
	node.anchor_top = at
	node.anchor_right = ar
	node.anchor_bottom = ab
	node.offset_left = ol
	node.offset_top = ot
	node.offset_right = o_r
	node.offset_bottom = ob


# ---------------------------------------------------------------- construction

func _build_top_bar() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_place(row, 0.0, 0.0, 1.0, 0.0, 12, 10, -12, 68)
	add_child(row)
	var back := UIKit.button("<-", 22)
	back.custom_minimum_size = Vector2(84, 58)
	back.pressed.connect(func() -> void: SceneManager.goto("career" if Career.active() else "menu"))
	row.add_child(back)
	row.add_child(UIKit.title_bar("GARAGE"))
	if Career.active():
		# Career teams can own several cars: pick one, build another or scrap one.
		_car_button = UIKit.button("", 13)
		_car_button.custom_minimum_size = Vector2(230, 58)
		_car_button.pressed.connect(_open_cars)
		row.add_child(_car_button)
	var tunnel := UIKit.button("WIND\nTUNNEL", 13)
	_marks["tunnel"] = tunnel
	tunnel.custom_minimum_size = Vector2(110, 58)
	tunnel.pressed.connect(func() -> void: _tunnel.open())
	row.add_child(tunnel)
	var cash := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	_marks["rp"] = cash
	cash.custom_minimum_size = Vector2(170, 58)
	row.add_child(cash)
	_money_label = UIKit.label("", 20, UIKit.PURPLE)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cash.add_child(_money_label)


func _build_side_panel() -> void:
	var panel := UIKit.panel()
	_place(panel, 0.0, 0.0, 0.0, 1.0, 12, 78, PANEL_WIDTH + 12, -12)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	# Summary (nothing selected): one big overall, then five ratings with the raw stat in grey.
	_ovr_label = UIKit.label("", 40, UIKit.WARM)
	_marks["ovr"] = _ovr_label
	box.add_child(_ovr_label)
	_summary_nodes.append(_ovr_label)
	for term: String in SUMMARY:
		var r := RatingRow.new()
		r.title = term
		r.custom_minimum_size = Vector2(0, 44)
		box.add_child(r)
		_rows[term] = r
		_summary_nodes.append(r)
	_warning = UIKit.label("", 13, UIKit.BAD)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)
	# Overview (nothing selected).
	_overview = VBoxContainer.new()
	_overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overview.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_overview)
	var tip := UIKit.label("TAP A PART OF THE CAR TO CHANGE IT", 15, UIKit.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overview.add_child(tip)
	# Picker (a hardpoint is selected).
	_picker = VBoxContainer.new()
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker.add_theme_constant_override("separation", 6)
	box.add_child(_picker)
	var head := HBoxContainer.new()
	_picker.add_child(head)
	_picker_title = UIKit.label("", 28, UIKit.HOT)
	_picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_picker_title)
	var close := UIKit.button("DONE", 18, true)
	close.custom_minimum_size = Vector2(120, 54)
	close.pressed.connect(func() -> void: _show_picker(""))
	head.add_child(close)
	# Upgrade level for this part type: research points make every car's part better.
	var up := HBoxContainer.new()
	up.add_theme_constant_override("separation", 8)
	_picker.add_child(up)
	_upgrade_info = UIKit.label("", 15, UIKit.TEXT)
	_upgrade_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upgrade_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_info.custom_minimum_size = Vector2(240, 0)
	up.add_child(_upgrade_info)
	_upgrade_button = UIKit.button("UPGRADE", 14, true)
	_upgrade_button.custom_minimum_size = Vector2(120, 52)
	_upgrade_button.pressed.connect(func() -> void:
		if GameManager.upgrade_dev(CarSetup.SLOT_CATEGORY[_active_slot]):
			AudioManager.play("snap", -5.0)
			_workspace.snap_feedback(_active_slot)
		else:
			AudioManager.play("deny", -10.0))
	up.add_child(_upgrade_button)
	_marks["upgrade"] = up
	_add_slider(_picker, "FRONT WING ANGLE", CarSetup.WING_ANGLE_MIN, CarSetup.WING_ANGLE_MAX, 1.0, func(v: float) -> void: GameManager.setup.front_wing_angle = int(v))
	_add_slider(_picker, "REAR WING ANGLE", CarSetup.WING_ANGLE_MIN, CarSetup.WING_ANGLE_MAX, 1.0, func(v: float) -> void: GameManager.setup.rear_wing_angle = int(v))
	_add_slider(_picker, "BRAKE BIAS", 0.48, 0.66, 0.01, func(v: float) -> void: GameManager.setup.brake_bias = v)
	_add_slider(_picker, "BALLAST POSITION", 0.0, 1.0, 1.0 / (CarSetup.BALLAST_STEPS - 1), func(v: float) -> void: GameManager.setup.ballast_position = v)
	_add_slider(_picker, "RIDE HEIGHT", 1, 10, 1.0, func(v: float) -> void: GameManager.setup.ride_height = int(v))
	_add_slider(_picker, "TYRE PRESSURE", 1, 10, 1.0, func(v: float) -> void: GameManager.setup.tyre_pressure = int(v))
	_add_slider(_picker, "ANTI-ROLL BALANCE", -5, 5, 1.0, func(v: float) -> void: GameManager.setup.anti_roll = int(v))
	_add_body_picker(_picker)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_detail = UIKit.label("", 14, UIKit.TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	_picker.add_child(_detail)
	_remove_button = UIKit.button("REMOVE", 15)
	_remove_button.custom_minimum_size = Vector2(0, 48)
	_remove_button.pressed.connect(func() -> void:
		GameManager.remove_part(_active_slot)
		AudioManager.play("deny", -14.0, 1.4))
	_picker.add_child(_remove_button)
	# Actions.
	var test := UIKit.button("TEST CAR", 26, true)
	_marks["test"] = test
	test.custom_minimum_size = Vector2(0, 64)
	test.pressed.connect(func() -> void: _launch(GameManager.MODE_TEST))
	box.add_child(test)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	box.add_child(modes)
	_summary_nodes.append(test)
	_summary_nodes.append(modes)
	var stats := UIKit.button("CAR CARD", 15)
	_marks["card"] = stats
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.custom_minimum_size = Vector2(0, 44)
	stats.pressed.connect(func() -> void:
		_refresh_car_card()
		_details.visible = true)
	modes.add_child(stats)
	var hq := UIKit.button("TEAM HQ" if Career.active() else "MENU", 15)
	hq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hq.custom_minimum_size = Vector2(0, 44)
	hq.pressed.connect(func() -> void: SceneManager.goto("career" if Career.active() else "menu"))
	modes.add_child(hq)


## The car card: overall plus every rating, full screen. Opened from CAR CARD.
func _build_details() -> void:
	_details = Control.new()
	_details.set_anchors_preset(Control.PRESET_FULL_RECT)
	_details.visible = false
	add_child(_details)
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_details.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_details.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var back := UIKit.button("<-  BACK", 18)
	back.custom_minimum_size = Vector2(150, 54)
	back.pressed.connect(func() -> void: _details.visible = false)
	head.add_child(back)
	head.add_child(UIKit.title_bar("CAR CARD", 54.0))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var team := Career.my_team() if Career.active() else {"color": "#c8201e", "color2": "#f4f6f2"}
	left.add_child(Art.make(Vector2(300, 150), func(a: Control) -> void:
		a.draw_rect(Rect2(Vector2.ZERO, a.size), Color("3a3d45"))
		PixelArt.draw_checker(a, Rect2(0, a.size.y - 12.0, a.size.x, 12), 12.0, Color.WHITE, UIKit.INK)
		PixelArt.draw_car(a, Vector2(20, 30), 10.0, Color(str(team["color"])), Color(str(team["color2"])))))
	_card_overall = UIKit.label("", 64, UIKit.WARM)
	_card_overall.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_card_overall)
	var hint := UIKit.label("EVERY PART, UPGRADE AND SETUP CHANGE MOVES THESE NUMBERS", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	left.add_child(hint)
	_card_list = VBoxContainer.new()
	_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list.add_theme_constant_override("separation", 6)
	body.add_child(_card_list)


func _refresh_car_card() -> void:
	if _card_list == null:
		return
	for child in _card_list.get_children():
		child.queue_free()
	var card := _card(GameManager.setup)
	_card_overall.text = "OVR %d" % _ovr(GameManager.setup)
	if Career.active():
		_card_list.add_child(UIKit.label("%s %s  ·  POTENTIAL %d" % [str(Career.my_team()["name"]).to_upper(), card["model"], int(card["potential"])], 15, UIKit.HOT))
		var tunnel := float(card["tunnel"])
		if tunnel >= 0.5:
			_card_list.add_child(UIKit.label("+%d OVR FROM WIND TUNNEL KNOWLEDGE" % int(round(tunnel)), 13, UIKit.GOOD))
	for r: Array in card["ratings"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_card_list.add_child(row)
		var name := UIKit.label(str(r[0]), 17)
		name.custom_minimum_size = Vector2(220, 0)
		row.add_child(name)
		var value := int(r[1])
		row.add_child(Art.make(Vector2(300, 26), func(a: Control) -> void:
			a.draw_rect(Rect2(0, 6, a.size.x, 14), UIKit.GRID_BOLD)
			a.draw_rect(Rect2(0, 6, a.size.x * value / 99.0, 14), UIKit.GOOD if value >= 75 else (UIKit.LINE if value >= 55 else UIKit.BAD))))
		row.add_child(UIKit.label("%d" % value, 26))
		var ceiling := ("  ·  MAX %d" % int(r[4])) if r.size() > 4 else ""
		var detail := UIKit.label("%s  ·  %s%s" % [r[2], r[3], ceiling], 12, UIKit.TEXT_DIM)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.clip_text = true
		row.add_child(detail)


func _add_body_picker(parent: Control) -> void:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	parent.add_child(cell)
	cell.add_child(UIKit.label("BODY SET", 13, UIKit.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	cell.add_child(grid)
	for id: String in CarSetup.BODY_SETS:
		var b := UIKit.button(str(CarSetup.BODY_SETS[id]["name"]), 11)
		b.toggle_mode = true
		b.set_meta("body", id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func() -> void:
			GameManager.setup.body = id
			EventBus.setup_changed.emit()
			GameManager.save())
		grid.add_child(b)
	_sliders["BODY SET"] = HSlider.new()      # placeholder so the refresh loop finds the term
	_slider_values["BODY SET"] = Label.new()
	_slider_cells["BODY SET"] = cell


func _add_slider(parent: Control, term: String, min_value: float, max_value: float, step: float, apply: Callable) -> void:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", -2)
	parent.add_child(cell)
	var head := HBoxContainer.new()
	cell.add_child(head)
	var name_button := Button.new()
	name_button.text = term + "  (?)"
	name_button.flat = true
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.add_theme_font_size_override("font_size", 12)
	name_button.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.pressed.connect(func() -> void: _popup.open_term(term))
	head.add_child(name_button)
	var value := UIKit.label("", 15, UIKit.ACCENT)
	head.add_child(value)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(150, 30)
	slider.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		# Sliders edit the setup directly; announce it so every readout recalculates live.
		EventBus.setup_changed.emit())
	slider.drag_ended.connect(func(_changed: bool) -> void:
		GameManager.save()
		AudioManager.play("click", -14.0, 0.8))
	cell.add_child(slider)
	_sliders[term] = slider
	_slider_values[term] = value
	_slider_cells[term] = cell


# ---------------------------------------------------------------- refresh

func _refresh_all() -> void:
	var setup := GameManager.setup
	_stats = CarStats.compute(setup, _config)
	_workspace.refresh(_stats)
	_refresh_car_card()
	_money_label.text = "%d RP\nRESEARCH" % GameManager.research()
	var overall := _ovr(setup)
	_ovr_label.text = "CAR OVR %d" % overall
	var card := _card(setup)
	for r: Array in card["ratings"]:
		if _rows.has(r[0]):
			(_rows[r[0]] as RatingRow).set_value(int(r[1]), str(r[2]))
	var missing := BuildValidator.missing_labels(setup)
	_warning.text = "" if missing.is_empty() else "CAR NOT READY  ·  missing %s" % ", ".join(missing)
	if Career.active():
		var car := Career.active_car()
		_car_button.text = "%s  ·  OVR %d\nCAR %d OF %d  ·  CHANGE >" % [car["name"], overall, Career.cars().find(car) + 1, Career.cars().size()]
		var faults := Career.car_violations(car)
		if missing.is_empty() and not faults.is_empty():
			_warning.text = "ILLEGAL UNDER FIA RULES  ·  %s" % "  ·  ".join(faults)
	_warning.visible = _warning.text != ""
	for term: String in _sliders:
		var slider: HSlider = _sliders[term]
		var value: Label = _slider_values[term]
		match term:
			"FRONT WING ANGLE":
				slider.set_value_no_signal(setup.front_wing_angle)
				slider.editable = setup.part("front_wing") != null
				value.text = str(setup.front_wing_angle)
			"REAR WING ANGLE":
				slider.set_value_no_signal(setup.rear_wing_angle)
				slider.editable = setup.part("rear_wing") != null
				value.text = str(setup.rear_wing_angle)
			"BRAKE BIAS":
				slider.set_value_no_signal(setup.brake_bias)
				value.text = "%d%% front" % int(round(setup.brake_bias * 100.0))
			"RIDE HEIGHT":
				slider.set_value_no_signal(setup.ride_height)
				value.text = "%d  %s" % [setup.ride_height, "LOW" if setup.ride_height <= 3 else ("HIGH" if setup.ride_height >= 8 else "MID")]
			"TYRE PRESSURE":
				slider.set_value_no_signal(setup.tyre_pressure)
				value.text = "%d  %s" % [setup.tyre_pressure, "SOFT" if setup.tyre_pressure <= 3 else ("HARD" if setup.tyre_pressure >= 8 else "MID")]
			"ANTI-ROLL BALANCE":
				slider.set_value_no_signal(setup.anti_roll)
				value.text = "%+d  %s" % [setup.anti_roll, "STIFF FRONT" if setup.anti_roll > 0 else ("STIFF REAR" if setup.anti_roll < 0 else "EVEN")]
			"BODY SET":
				for b: Button in (_slider_cells[term] as Control).find_children("*", "Button", true, false):
					b.button_pressed = str(b.get_meta("body")) == setup.body
			"BALLAST POSITION":
				var ballast := setup.part("ballast")
				var has_ballast := ballast != null and ballast.mass > 0.0
				slider.set_value_no_signal(setup.ballast_position)
				slider.editable = has_ballast
				var step := int(round(setup.ballast_position * (CarSetup.BALLAST_STEPS - 1)))
				value.text = (["FRONT", "forward", "mid-front", "mid-rear", "rearward", "REAR"][step] if has_ballast else "fit ballast first")
		if term != "BODY SET":
			value.text += "  ·  OVR %d" % overall
	_refresh_cards(overall)
	_refresh_upgrade(overall)
	_refresh_detail()


## The overall shown everywhere in the garage: the career car overall, or the car card's
## overall in free play.
func _ovr(setup: CarSetup) -> int:
	return int(round(float(_card(setup)["overall"])))


## The car card for a build: in a career the team's real car model moved by the build,
## otherwise the plain physics ratings.
func _card(setup: CarSetup) -> Dictionary:
	if Career.active():
		return Career.car_card(setup)
	return CarRatings.compute(setup, _stats if setup == GameManager.setup and _stats else CarStats.compute(setup, _config))


## What fitting each listed part would do to the overall.
func _refresh_cards(overall: int) -> void:
	for child in _list.get_children():
		if not child is PartCard:
			continue
		var card := child as PartCard
		card.is_selected = card.part == _selected_part
		var trial := CarSetup.from_dict(GameManager.setup.to_dict())
		if _active_slot != "":
			trial.install(_active_slot, card.part.id)
		var after := _ovr(trial)
		card.ovr_delta = after - overall
		card.ovr_line = ("OVR %d" % overall) if GameManager.setup.parts.get(_active_slot, "") == card.part.id else "OVR %d -> %d" % [overall, after]
		card.refresh()


func _refresh_upgrade(overall: int) -> void:
	if _active_slot == "":
		return
	var category: String = CarSetup.SLOT_CATEGORY[_active_slot]
	var has_levels := GameManager.DEV_CATEGORIES.has(category)
	(_marks["upgrade"] as Control).visible = has_levels
	if not has_levels:
		return
	var level := GameManager.dev_level(category)
	var cost := GameManager.dev_cost(category)
	if cost <= 0:
		_upgrade_info.text = "LEVEL %d  ·  MAXED OUT" % level
		_upgrade_button.disabled = true
		_upgrade_button.text = "MAX"
		return
	var trial := CarSetup.from_dict(GameManager.setup.to_dict())
	trial.dev = GameManager.setup.dev.duplicate()
	trial.dev[category] = level + 1
	var gain := _ovr(trial) - overall
	_upgrade_info.text = "UPGRADE  LEVEL %d -> %d  ·  OVR %+d\n%s" % [level, level + 1, gain, GameManager.DEV_EFFECTS[category]]
	_upgrade_button.text = "%d RP" % cost
	_upgrade_button.disabled = GameManager.research() < cost


func _refresh_detail() -> void:
	if _active_slot == "":
		return
	var installed := GameManager.setup.part(_active_slot)
	_detail.text = _selected_part.description if _selected_part else (installed.description if installed else "")
	_remove_button.visible = installed != null and _active_slot != "chassis"
	_remove_button.text = "REMOVE %s" % (CarSetup.SLOT_LABELS[_active_slot] as String).to_upper()


## Opens the parts picker for a hardpoint ("" closes it).
func _show_picker(slot: String) -> void:
	_active_slot = slot
	_selected_part = null
	_workspace.select_slot(slot)
	_picker.visible = slot != ""
	_overview.visible = slot == ""
	# A selected hardpoint takes over the whole sidebar.
	for node in _summary_nodes:
		node.visible = slot == ""
	if slot == "":
		return
	_picker_title.text = (CarSetup.SLOT_LABELS[slot] as String).to_upper()
	for term: String in _slider_cells:
		(_slider_cells[term] as Control).visible = (SLOT_SLIDERS.get(slot, []) as Array).has(term)
	_rebuild_list()
	_refresh_upgrade(_ovr(GameManager.setup))
	_refresh_detail()


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var parts := PartDB.parts_in(CarSetup.SLOT_CATEGORY[_active_slot]).duplicate()
	# Owned parts first, then the cheapest research.
	parts.sort_custom(func(a: VehiclePart, b: VehiclePart) -> bool: return _rank(a) < _rank(b))
	for part: VehiclePart in parts:
		var card := (load("res://scenes/components/PartCard.tscn") as PackedScene).instantiate() as PartCard
		card.setup(part)
		_list.add_child(card)
		card.selected.connect(_on_card_selected)
		card.action_pressed.connect(_on_card_action)
		card.drag_started.connect(_on_drag_started)
		card.drag_moved.connect(func(pos: Vector2) -> void:
			_scroll.scroll_vertical = _drag_scroll
			_drag.move(pos))
		card.drag_released.connect(func(pos: Vector2) -> void: _drag.release(pos))
	_scroll.scroll_vertical = 0
	_refresh_cards(_ovr(GameManager.setup))


func _rank(part: VehiclePart) -> int:
	if GameManager.is_owned(part.id):
		return 0
	return 1 + GameManager.research_cost(part.id)


# ---------------------------------------------------------------- interaction

func _on_slot_tapped(slot: String) -> void:
	if slot != "":
		AudioManager.play("click", -12.0)
	_show_picker(slot)


func _on_card_selected(part: VehiclePart) -> void:
	_selected_part = part
	for child in _list.get_children():
		if child is PartCard:
			(child as PartCard).is_selected = (child as PartCard).part == part
			(child as PartCard).refresh()
	_refresh_detail()


func _on_card_action(part: VehiclePart) -> void:
	_selected_part = part
	if not GameManager.is_owned(part.id):
		if GameManager.unlock_part(part.id):
			AudioManager.play("cash", -6.0)
			# Researching from a hardpoint's picker fits the part straight away.
			_install(part, _active_slot)
		else:
			AudioManager.play("deny", -10.0)
	else:
		_install(part, _active_slot)


func _on_drag_started(part: VehiclePart, card: PartCard) -> void:
	_drag_scroll = _scroll.scroll_vertical
	_selected_part = part
	_drag.begin(part, card.get_global_mouse_position())


func _on_part_dropped(part: VehiclePart, slot: String) -> void:
	_install(part, slot)


func _install(part: VehiclePart, slot: String) -> void:
	if slot == "" or not GameManager.install_part(slot, part.id):
		AudioManager.play("deny", -10.0)
		return
	if slot != _active_slot:
		_show_picker(slot)
	_workspace.snap_feedback(slot)
	AudioManager.play("snap", -5.0)
	_refresh_detail()


func _launch(mode: String) -> void:
	if not BuildValidator.is_ready(GameManager.setup):
		AudioManager.play("deny", -8.0)
		_popup.open("CAR NOT READY", BuildValidator.report(GameManager.setup).replace("CAR NOT READY\n\n", ""))
		return
	GameManager.save()
	GameManager.start_free_session(mode)


## Career car list: switch car, build another (money) or scrap one.
func _open_cars() -> void:
	if _cars_overlay:
		_cars_overlay.queue_free()
	_cars_overlay = Control.new()
	_cars_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cars_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_cars())
	_cars_overlay.add_child(shade)
	var panel := UIKit.panel()
	_place(panel, 0.5, 0.5, 0.5, 0.5, -300, -190, 300, 190)
	_cars_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UIKit.label("YOUR CARS", 24, UIKit.HOT))
	var note := UIKit.label("", 13, UIKit.BAD)
	for c: Dictionary in Career.cars():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var active: bool = c["id"] == Career.active_car()["id"]
		var pick := UIKit.button("%s  ·  OVR %d%s" % [c["name"], int(round(Career.car_overall(c))), "  (IN GARAGE)" if active else ""], 15, active)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.custom_minimum_size = Vector2(0, 50)
		var id := str(c["id"])
		pick.pressed.connect(func() -> void:
			Career.set_active_car(id)
			_close_cars()
			_show_picker(""))
		row.add_child(pick)
		var scrap := UIKit.button("SCRAP", 13)
		scrap.custom_minimum_size = Vector2(90, 50)
		scrap.disabled = Career.cars().size() <= 1
		scrap.pressed.connect(func() -> void:
			Career.scrap_car(id)
			_open_cars()
			_show_picker(""))
		row.add_child(scrap)
	var build := UIKit.button("BUILD NEW CAR  ·  %s" % Career.money_text(Career.NEW_CAR_COST), 16, true)
	build.custom_minimum_size = Vector2(0, 54)
	build.pressed.connect(func() -> void:
		var why := Career.build_new_car()
		if why == "":
			AudioManager.play("cash", -6.0)
			_open_cars()
			_show_picker("")
		else:
			note.text = why
			AudioManager.play("deny", -10.0))
	box.add_child(build)
	box.add_child(note)
	var hint := UIKit.label("A new car is a copy of the one in the garage. Choose who drives which car on the driver card.", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var close := UIKit.button("CLOSE", 15)
	close.custom_minimum_size = Vector2(0, 46)
	close.pressed.connect(_close_cars)
	box.add_child(close)


func _close_cars() -> void:
	if _cars_overlay:
		_cars_overlay.queue_free()
		_cars_overlay = null


## One rating: name, a big number and a bar, with the raw stat in small grey text below.
## Flashes green / red when the build changes it.
class RatingRow extends Control:
	var title := ""
	var _value := 0
	var _shown := 0.0
	var _text := ""
	var _flash := 0.0
	var _flash_color := UIKit.GOOD
	var _initialised := false

	func set_value(value: int, text: String) -> void:
		if _initialised and value != _value:
			_flash = 1.0
			_flash_color = UIKit.GOOD if value > _value else UIKit.BAD
		if not _initialised:
			_shown = value
		_initialised = true
		_value = value
		_text = text

	func _process(delta: float) -> void:
		_shown = lerpf(_shown, _value, minf(1.0, 9.0 * delta))
		_flash = maxf(0.0, _flash - delta * 1.2)
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var col := UIKit.TEXT.lerp(_flash_color, _flash)
		draw_string(font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT)
		draw_string(font, Vector2(0, 22), "%d" % _value, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 24, col)
		var bar := Rect2(150.0, 9.0, size.x - 200.0, 9.0)
		draw_rect(bar, UIKit.GRID_BOLD)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_shown / 99.0, 0.03, 1.0), bar.size.y)), UIKit.ACCENT.lerp(_flash_color, _flash))
		draw_string(font, Vector2(0, 38), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT_DIM)
