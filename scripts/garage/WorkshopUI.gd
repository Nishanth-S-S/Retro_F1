class_name WorkshopUI
extends Control
## Career workshop overlay in the garage: everything about the car that is not a part.
## Left: the car in the bay (overall, FIA legality, who drives it, build / scrap).
## Right: upgrades - materials bought with research points, factory departments with cash.

var _left: VBoxContainer
var _list: VBoxContainer
var _note: Label
var _title: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	_title = UIKit.title_bar("WORKSHOP", 50.0)
	root.add_child(_title)
	_note = UIKit.label("", 16, UIKit.ACCENT)
	root.add_child(_note)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(400, 0)
	_left.add_theme_constant_override("separation", 8)
	cols.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var close := UIKit.button("DONE", 20, true)
	close.custom_minimum_size = Vector2(0, 60)
	close.pressed.connect(func() -> void: visible = false)
	root.add_child(close)


func open() -> void:
	_refresh("")
	visible = true


func _label(parent: Control, text: String, size: int, color: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	parent.add_child(l)
	return l


func _done(error: String, success: String) -> void:
	AudioManager.play("cash" if error == "" else "deny", -8.0)
	EventBus.inventory_changed.emit()
	_refresh(success if error == "" else error)


func _refresh(note: String) -> void:
	var c := Career.state()
	var car := Career.active_car()
	var id: String = car["id"]
	_title.set_meta("title", "WORKSHOP  -  %s" % car["name"])
	_title.queue_redraw()
	_note.text = note if note != "" else "%d RESEARCH   ·   %s CASH" % [int(c["rp"]), UIKit.money(GameManager.money())]
	for box: Control in [_left, _list]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	# --- the car
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_left.add_child(top)
	top.add_child(Art.chip("OVR", int(round(Career.car_overall(car))), UIKit.WARM))
	var faults := Career.car_violations(car)
	var status := UIKit.label("LEGAL" if faults.is_empty() else "ILLEGAL", 26, UIKit.GOOD if faults.is_empty() else UIKit.BAD)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(status)
	for fault: String in faults:
		_label(_left, fault, 15, UIKit.BAD)
	var rules := Career.regs()
	var banned := PackedStringArray()
	for part_id: String in rules["banned"]:
		banned.append(PartDB.get_part(part_id).display_name.to_upper())
	_label(_left, "FIA:  MIN %d KG   ·   WING MAX %d%s" % [int(rules["min_weight"]), int(rules["max_wing"]), ("\nBANNED: " + ", ".join(banned)) if not banned.is_empty() else ""], 15, UIKit.TEXT_DIM)
	_label(_left, "WHO DRIVES IT", 14, UIKit.HOT)
	for driver_id: String in Career.lineup():
		var d := Career.driver(driver_id)
		var has: bool = Career.car_for(driver_id)["id"] == id
		var b := UIKit.button("%s   FIT %d" % [str(d["name"]).get_slice(" ", 1).to_upper(), Career.car_fit(d, car)], 18, has)
		b.custom_minimum_size = Vector2(0, 58)
		b.disabled = has
		b.pressed.connect(func() -> void:
			Career.assign_car(driver_id, id)
			_done("", "%s NOW DRIVES THE %s" % [str(d["name"]).get_slice(" ", 1).to_upper(), car["name"]]))
		_left.add_child(b)
	_label(_left, "GARAGE  %d / %d CARS" % [Career.cars().size(), Career.MAX_CARS], 14, UIKit.HOT)
	var build := UIKit.button("BUILD NEW CAR   %s" % UIKit.money(Career.NEW_CAR_COST), 17)
	build.custom_minimum_size = Vector2(0, 58)
	build.disabled = Career.cars().size() >= Career.MAX_CARS
	build.pressed.connect(func() -> void: _done(Career.build_new_car(), "NEW CAR BUILT  -  TAP THE CAR BUTTON TO SWITCH"))
	_left.add_child(build)
	if Career.cars().size() > 1:
		var scrap := UIKit.button("SCRAP THIS CAR", 17)
		scrap.custom_minimum_size = Vector2(0, 58)
		scrap.pressed.connect(func() -> void:
			var message := Career.scrap_car(id)
			_done("", message.to_upper()))
		_left.add_child(scrap)
	# --- upgrades
	_row_header("MATERIALS   ·   RESEARCH POINTS")
	for area: String in Career.MATERIAL_AREAS:
		var spec: Dictionary = Career.MATERIAL_AREAS[area]
		var tier := int(car["materials"].get(area, 0))
		var cost := Career.material_cost(car, area)
		_upgrade_row(str(spec["name"]), str(spec["tiers"][tier]), tier, 4, "MAX" if cost == 0 else "%d RP" % cost, cost == 0 or int(c["rp"]) < cost, func() -> void:
			_done(Career.upgrade_material(id, area), "%s UPGRADED" % spec["name"]))
	_row_header("FACTORY   ·   CASH")
	for dept: String in Career.DEPARTMENTS:
		var level := int(c["factory"][dept])
		var max_level := Career.rd_tiers.size() if dept == "rd" else Career.FACTORY_MAX
		var info: String = Career.DEPARTMENTS[dept]["note"]
		_upgrade_row(str(Career.DEPARTMENTS[dept]["name"]), info.to_upper(), level, max_level, "MAX" if level >= max_level else UIKit.money(Career.upgrade_cost(dept)), level >= max_level, func() -> void:
			_done(Career.upgrade(dept), "%s UPGRADED" % Career.DEPARTMENTS[dept]["name"]))


func _row_header(text: String) -> void:
	_list.add_child(UIKit.label(text, 14, UIKit.HOT))


func _upgrade_row(title: String, detail: String, level: int, max_level: int, price: String, locked: bool, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_list.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	info.add_child(UIKit.label(title, 18))
	info.add_child(UIKit.label(detail, 12, UIKit.TEXT_DIM))
	var pips := Art.make(Vector2(max_level * 20.0, 24), func(a: Control) -> void:
		for i in max_level:
			a.draw_rect(Rect2(i * 20.0, 4, 15, 15), UIKit.ACCENT if i < level else UIKit.GRID_BOLD))
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	var b := UIKit.button(price, 17, not locked)
	b.custom_minimum_size = Vector2(150, 56)
	b.disabled = locked
	b.pressed.connect(action)
	row.add_child(b)
