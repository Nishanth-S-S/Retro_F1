extends Control
## Garage scene root. The screen is just the car: tap a part of it and the whole sidebar on
## the left becomes the picker for that hardpoint. Four simple bars summarise the build; the full
## engineering readout is one tap away under FULL STATS.

const PANEL_WIDTH := 410.0
## Which tuning slider belongs to which hardpoint.
const SLOT_SLIDERS := {"front_wing": "FRONT WING ANGLE", "rear_wing": "REAR WING ANGLE", "brakes": "BRAKE BIAS", "ballast": "BALLAST POSITION"}

var _config: VehiclePhysicsConfig = preload("res://data/physics/default_physics.tres")
var _stats: CarStats
var _active_slot := ""
var _selected_part: VehiclePart

var _workspace: BlueprintWorkspace
var _stats_panel: GarageUI
var _details: Control
var _drag: PartDragHandler
var _popup: InfoPopup
var _money_label: Label
var _bars: Dictionary = {}
var _balance: Label
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
var _workshop: WorkshopUI
## Sidebar widgets shown only while no hardpoint is selected.
var _summary_nodes: Array[Control] = []
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
	_workshop = WorkshopUI.new()
	add_child(_workshop)
	EventBus.setup_changed.connect(_refresh_all)
	EventBus.inventory_changed.connect(_refresh_all)
	EventBus.money_changed.connect(func(_amount: int) -> void: _money_label.text = UIKit.money(GameManager.money()))
	_show_picker("")
	_refresh_all()


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
		# Career teams can own several cars: tap to roll the next one into the bay.
		_car_button = UIKit.button("", 13)
		_car_button.custom_minimum_size = Vector2(210, 58)
		_car_button.pressed.connect(func() -> void:
			var cars := Career.cars()
			var index := 0
			for i in cars.size():
				if cars[i]["id"] == Career.active_car()["id"]:
					index = i
			Career.set_active_car(str(cars[(index + 1) % cars.size()]["id"]))
			_show_picker(""))
		row.add_child(_car_button)
		# Materials, factory, FIA check, who drives what, new cars.
		var workshop := UIKit.button("WORKSHOP", 14, true)
		workshop.custom_minimum_size = Vector2(130, 58)
		workshop.pressed.connect(func() -> void: _workshop.open())
		row.add_child(workshop)
	var tunnel := UIKit.button("WIND\nTUNNEL", 13)
	tunnel.custom_minimum_size = Vector2(110, 58)
	tunnel.pressed.connect(func() -> void: _tunnel.open())
	row.add_child(tunnel)
	var cash := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	cash.custom_minimum_size = Vector2(150, 58)
	row.add_child(cash)
	_money_label = UIKit.label(UIKit.money(GameManager.money()), 20, UIKit.GOOD)
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
	# Always-visible summary: four bars and the handling verdict.
	for term: String in ["TOP SPEED", "ACCELERATION", "CORNERING", "BRAKING"]:
		var bar := StatBar.new()
		bar.title = term
		bar.custom_minimum_size = Vector2(0, 30)
		box.add_child(bar)
		_bars[term] = bar
		_summary_nodes.append(bar)
	_balance = UIKit.label("", 15, UIKit.GOOD)
	box.add_child(_balance)
	_summary_nodes.append(_balance)
	_warning = UIKit.label("", 13, UIKit.BAD)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)
	# Overview (nothing selected).
	_overview = VBoxContainer.new()
	_overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overview.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_overview)
	var tip := UIKit.label("TAP A PART\nTO CHANGE IT", 22, UIKit.TEXT_DIM)
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
	_add_slider(_picker, "FRONT WING ANGLE", CarSetup.WING_ANGLE_MIN, CarSetup.WING_ANGLE_MAX, 1.0, func(v: float) -> void: GameManager.setup.front_wing_angle = int(v))
	_add_slider(_picker, "REAR WING ANGLE", CarSetup.WING_ANGLE_MIN, CarSetup.WING_ANGLE_MAX, 1.0, func(v: float) -> void: GameManager.setup.rear_wing_angle = int(v))
	_add_slider(_picker, "BRAKE BIAS", 0.48, 0.66, 0.01, func(v: float) -> void: GameManager.setup.brake_bias = v)
	_add_slider(_picker, "BALLAST POSITION", 0.0, 1.0, 1.0 / (CarSetup.BALLAST_STEPS - 1), func(v: float) -> void: GameManager.setup.ballast_position = v)
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
	test.custom_minimum_size = Vector2(0, 64)
	test.pressed.connect(func() -> void: _launch(GameManager.MODE_TEST))
	box.add_child(test)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	box.add_child(modes)
	_summary_nodes.append(test)
	_summary_nodes.append(modes)
	var stats := UIKit.button("FULL STATS", 15)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.custom_minimum_size = Vector2(0, 44)
	stats.pressed.connect(func() -> void: _details.visible = true)
	modes.add_child(stats)
	var hq := UIKit.button("TEAM HQ" if Career.active() else "MENU", 15)
	hq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hq.custom_minimum_size = Vector2(0, 44)
	hq.pressed.connect(func() -> void: SceneManager.goto("career" if Career.active() else "menu"))
	modes.add_child(hq)


func _build_details() -> void:
	_details = Control.new()
	_details.set_anchors_preset(Control.PRESET_FULL_RECT)
	_details.visible = false
	add_child(_details)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_details.visible = false)
	_details.add_child(dim)
	_stats_panel = GarageUI.new()
	_place(_stats_panel, 0.0, 0.0, 0.0, 1.0, 12, 78, PANEL_WIDTH + 12, -124)
	_stats_panel.term_tapped.connect(func(term: String) -> void: _popup.open_term(term))
	_details.add_child(_stats_panel)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	_place(views, 0.0, 1.0, 0.0, 1.0, 12, -118, PANEL_WIDTH + 12, -70)
	_details.add_child(views)
	for overlay: String in ["MASS", "AERO"]:
		var b := UIKit.button("SHOW " + overlay, 13)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggled.connect(func(on: bool) -> void:
			if overlay == "MASS":
				_workspace.show_mass = on
			else:
				_workspace.show_aero = on)
		views.add_child(b)
	var close := UIKit.button("CLOSE", 16, true)
	_place(close, 0.0, 1.0, 0.0, 1.0, 12, -64, PANEL_WIDTH + 12, -12)
	close.pressed.connect(func() -> void: _details.visible = false)
	_details.add_child(close)


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
	_stats_panel.refresh(_stats, setup)
	_money_label.text = UIKit.money(GameManager.money())
	var g := VehiclePhysicsConfig.GRAVITY
	(_bars["TOP SPEED"] as StatBar).set_value(inverse_lerp(200.0, 310.0, _stats.top_speed * 3.6), "%d km/h" % int(_stats.top_speed * 3.6))
	(_bars["ACCELERATION"] as StatBar).set_value(inverse_lerp(250.0, 560.0, _stats.power_to_weight), "%d kW/t" % int(_stats.power_to_weight))
	var cornering := _stats.mech_grip_g + _stats.downforce_200 / (_stats.mass * g) * 0.5
	(_bars["CORNERING"] as StatBar).set_value(inverse_lerp(1.5, 2.4, cornering), "%.2f g" % cornering)
	(_bars["BRAKING"] as StatBar).set_value(inverse_lerp(1.9, 3.3, _stats.braking_g), "%.2f g" % _stats.braking_g)
	var label := _stats.balance_label()
	_balance.text = "HANDLING:  %s" % label.to_upper()
	_balance.add_theme_color_override("font_color", GarageUI.BALANCE_COLORS[CarStats.BALANCE_LABELS.find(label)])
	var missing := BuildValidator.missing_labels(setup)
	_warning.text = "" if missing.is_empty() else "CAR NOT READY  ·  missing %s" % ", ".join(missing)
	if Career.active():
		var car := Career.active_car()
		_car_button.text = "%s  OVR %d\nCAR %d OF %d  >" % [car["name"], int(round(Career.car_overall(car))), Career.cars().find(car) + 1, Career.cars().size()]
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
			"BALLAST POSITION":
				var ballast := setup.part("ballast")
				var has_ballast := ballast != null and ballast.mass > 0.0
				slider.set_value_no_signal(setup.ballast_position)
				slider.editable = has_ballast
				var step := int(round(setup.ballast_position * (CarSetup.BALLAST_STEPS - 1)))
				value.text = (["FRONT", "forward", "mid-front", "mid-rear", "rearward", "REAR"][step] if has_ballast else "fit ballast first")
	for child in _list.get_children():
		if child is PartCard:
			(child as PartCard).is_selected = (child as PartCard).part == _selected_part
			(child as PartCard).refresh()
	_refresh_detail()


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
		(_slider_cells[term] as Control).visible = SLOT_SLIDERS.get(slot, "") == term
	_rebuild_list()
	_refresh_detail()


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var parts := PartDB.parts_in(CarSetup.SLOT_CATEGORY[_active_slot]).duplicate()
	# Owned parts first, then purchasable, then story-locked.
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


func _rank(part: VehiclePart) -> int:
	if GameManager.is_owned(part.id):
		return 0
	return 1 if GameManager.is_unlocked(part.id) else 2 + GameManager.unlock_chapter_of(part.id)


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
	if not GameManager.is_unlocked(part.id):
		AudioManager.play("deny", -10.0)
	elif not GameManager.is_owned(part.id):
		if GameManager.buy_part(part.id):
			AudioManager.play("cash", -6.0)
			# Buying from a hardpoint's picker fits the part straight away.
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


## One labelled bar that animates and flashes green / red when the build changes.
class StatBar extends Control:
	var title := ""
	var _target := 0.0
	var _shown := 0.0
	var _text := ""
	var _flash := 0.0
	var _flash_color := UIKit.GOOD
	var _initialised := false

	func set_value(fraction: float, text: String) -> void:
		var f := clampf(fraction, 0.03, 1.0)
		if _initialised and absf(f - _target) > 0.002:
			_flash = 1.0
			_flash_color = UIKit.GOOD if f > _target else UIKit.BAD
		if not _initialised:
			_shown = f
		_initialised = true
		_target = f
		_text = text

	func _process(delta: float) -> void:
		_shown = lerpf(_shown, _target, minf(1.0, 9.0 * delta))
		_flash = maxf(0.0, _flash - delta * 1.2)
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)
		draw_string(font, Vector2(0, 12), _text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, UIKit.TEXT.lerp(_flash_color, _flash))
		var bar := Rect2(0.0, 18.0, size.x, 9.0)
		draw_rect(bar, UIKit.GRID_BOLD)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _shown, bar.size.y)), UIKit.ACCENT.lerp(_flash_color, _flash))
