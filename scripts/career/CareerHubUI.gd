extends Control
## Team HQ. One screen, six tabs: HQ, DRIVERS, SCOUTING, SPONSORS, FACTORY, STANDINGS.
## Dilemma events pop up here after each race.

const TABS: PackedStringArray = ["HQ", "DRIVERS", "SCOUTING", "SPONSORS", "FACTORY", "STANDINGS"]

var _tab := 0
var _content: VBoxContainer
var _header: HBoxContainer
var _tab_buttons: Array[Button] = []
var _toast: Label
var _modal: Control
var _pending_seat := ""


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Career.active():
		SceneManager.call_deferred("goto", "career_start")
		return
	AudioManager.play_music(true)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 10)
	root.add_child(_header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	for i in TABS.size():
		var b := UIKit.button(TABS[i], 14)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func() -> void: _show_tab(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)
	_toast = UIKit.label("", 13, UIKit.ACCENT)
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_toast)
	var race := UIKit.button("", 20, true)
	race.custom_minimum_size = Vector2(420, 56)
	race.text = "GO TO RACE  >  %s" % str(Career.next_round()["name"]).to_upper()
	race.pressed.connect(func() -> void: SceneManager.goto("raceday"))
	foot.add_child(race)
	EventBus.money_changed.connect(func(_a: int) -> void: _build_header())
	_show_tab(0)
	_check_interrupts.call_deferred()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _say(text: String, good: bool = true) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", UIKit.ACCENT if good else UIKit.BAD)
	AudioManager.play("click" if good else "deny", -10.0)


# ---------------------------------------------------------------- header

func _build_header() -> void:
	for child in _header.get_children():
		child.queue_free()
	var team := Career.my_team()
	var back := UIKit.button("<-", 22)
	back.custom_minimum_size = Vector2(84, 58)
	back.pressed.connect(func() -> void: SceneManager.goto("menu"))
	_header.add_child(back)
	_header.add_child(Art.make(Vector2(58, 58), func(a: Control) -> void: PixelArt.draw_logo(a, Rect2(Vector2.ZERO, a.size), team)))
	_header.add_child(UIKit.title_bar(str(team["name"])))
	var cash := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	cash.custom_minimum_size = Vector2(140, 58)
	var cash_label := UIKit.label(UIKit.money(GameManager.money()), 18, UIKit.GOOD if GameManager.money() >= 0 else UIKit.BAD)
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cash.add_child(cash_label)
	_header.add_child(cash)
	var phone := Button.new()
	phone.focus_mode = Control.FOCUS_NONE
	phone.custom_minimum_size = Vector2(66, 58)
	phone.pressed.connect(_open_phone)
	var unread := Career.unread_count()
	var icon := Art.make(Vector2.ZERO, func(a: Control) -> void: PixelArt.draw_phone(a, Vector2(a.size.x * 0.5 - 14.0, 9.0), 3.5, unread))
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phone.add_child(icon)
	_header.add_child(phone)


func _show_tab(index: int) -> void:
	_tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	_build_header()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match index:
		0: _tab_hq()
		1: _tab_drivers()
		2: _tab_scouting()
		3: _tab_sponsors()
		4: _tab_factory()
		5: _tab_standings()


func _card(parent: Control = null, caption: String = "") -> VBoxContainer:
	var frame := Frame.make(caption, 4)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent else _content).add_child(frame)
	return frame.body


func _open_phone() -> void:
	AudioManager.play("click", -10.0)
	var phone := PhoneUI.new()
	add_child(phone)
	phone.closed.connect(func() -> void: _show_tab(_tab))


func _columns() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	return row


func _text(parent: Control, text: String, size: int = 13, color: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- tabs

func _tab_hq() -> void:
	var c := Career.state()
	var team := Career.my_team()
	var row := _columns()
	var me := _card(row, "TEAM PRINCIPAL")
	var manager: Dictionary = c["manager"]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	me.add_child(line)
	line.add_child(Art.make(Vector2(144, 144), func(a: Control) -> void:
		PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), manager["look"], Color(str(team["color"])), Color("d8e6dc"))))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	line.add_child(info)
	_text(info, str(manager["name"]), 22)
	_text(info, "TARGET: %s" % Career.board_target_text().to_upper(), 13, UIKit.HOT)
	var board := int(c["board"])
	info.add_child(Art.rating_bar("BOARD", board, UIKit.GOOD if board >= 50 else (Color("e0a23a") if board >= 25 else UIKit.BAD), 320.0))
	info.add_child(Art.rating_bar("REPUTATION", int(c["reputation"]), UIKit.LINE, 320.0))
	if int(c["promise"]) > 0:
		_text(info, "PODIUM PROMISED: %d RACES LEFT" % int(c["promise"]), 12, UIKit.BAD)
	var next := _card(row, "SEASON %d  ·  ROUND %d/%d" % [int(c["season"]), int(c["round"]) + 1, Career.calendar.size()])
	var round_info := Career.next_round()
	_text(next, str(round_info["name"]).to_upper(), 22)
	_text(next, "RAIN %d%%   ·   P%d IN THE CHAMPIONSHIP" % [int(float(round_info["rain"]) * 100.0), Career.team_position()], 12, UIKit.TEXT_DIM)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	next.add_child(chips)
	var seats := Career.lineup()
	var drivers_avg := (Career.driver_overall(Career.driver(seats[0])) + Career.driver_overall(Career.driver(seats[1]))) / 2
	chips.add_child(Art.chip("CAR", int(round(Career.car_rating(c["team"]))), UIKit.LINE.darkened(0.3)))
	chips.add_child(Art.chip("DRIVERS", drivers_avg, Color("23262e")))
	chips.add_child(Art.chip("TEAM", Career.team_rating(c["team"]), UIKit.WARM))
	var schedule := UIKit.button("SEASON SCHEDULE", 13)
	schedule.custom_minimum_size = Vector2(0, 44)
	schedule.pressed.connect(_show_schedule)
	next.add_child(schedule)
	var alerts := PackedStringArray()
	if (c["sponsor"] as Dictionary).is_empty():
		alerts.append("NO TITLE SPONSOR")
	if Career.reserves().is_empty():
		alerts.append("NO RESERVE DRIVER")
	for id: String in seats:
		if Career.is_injured(id):
			alerts.append("%s INJURED (%d)" % [str(Career.driver(id)["name"]).get_slice(" ", 1).to_upper(), int(Career.driver(id)["injured"])])
	if not alerts.is_empty():
		_text(next, "   ·   ".join(alerts), 12, UIKit.BAD)
	var report: Dictionary = c["last_report"]
	if not report.is_empty():
		var parts := PackedStringArray()
		for m: Dictionary in report["mine"]:
			parts.append("%s %s" % [str(m["name"]).get_slice(" ", 1).to_upper(), "DNF" if m["dnf"] else "P%d" % int(m["position"])])
		_text(next, "LAST RACE:  %s" % "   ".join(parts), 13, UIKit.TEXT_DIM)
		if report.has("season"):
			var s: Dictionary = report["season"]
			_text(next, "SEASON %d: P%d, PRIZE %s" % [int(s["season"]), int(s["position"]), UIKit.money(s["payout"])], 13, UIKit.ACCENT)


func _face(id: String, size: float) -> Art:
	var p := Career.person(id)
	var team := Career.team(str(p.get("team", "")))
	var color := Color(str(team["color"])) if not team.is_empty() else Color("6a7078")
	return Art.make(Vector2(size, size), func(a: Control) -> void:
		if not p.is_empty():
			PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), p["look"], color, Color("d8e6dc")))


func _driver_card(parent: Control, id: String) -> void:
	var d := Career.driver(id)
	var team := Career.my_team()
	var injured := Career.is_injured(id)
	var box := _card(parent, "#%d" % int(d["number"]))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	box.add_child(line)
	line.add_child(_face(id, 112))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	line.add_child(info)
	_text(info, str(d["name"]).to_upper(), 19)
	var status := "AGE %d  ·  %s" % [int(d["age"]), UIKit.money(float(d["salary"]))]
	if Career.state()["number_one"] == id:
		status += "  ·  NO.1"
	_text(info, status, 11, UIKit.TEXT_DIM)
	if injured:
		_text(info, "INJURED  -  OUT %d RACE%s" % [int(d["injured"]), "" if int(d["injured"]) == 1 else "S"], 14, UIKit.BAD)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	line.add_child(side)
	side.add_child(Art.chip("OVR", Career.driver_overall(d), UIKit.WARM))
	side.add_child(Art.make(Vector2(74, 52), func(a: Control) -> void:
		PixelArt.draw_helmet(a, Rect2(Vector2.ZERO, a.size), Color(str(team["color"])), Color(str(team["color2"])), int(d["number"]))))
	box.add_child(Art.rating_bar("PACE", float(d["pace"]), UIKit.LINE, 420.0))
	box.add_child(Art.rating_bar("EGO", float(d["ego"]), UIKit.WARM, 420.0))
	box.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 420.0))


func _tab_drivers() -> void:
	var row := _columns()
	for id: String in Career.lineup():
		_driver_card(row, id)
	var bench := _card(null, "RESERVES  %d/%d" % [Career.reserves().size(), Career.MAX_RESERVES])
	if Career.reserves().is_empty():
		_text(bench, "Empty bench. If a race driver is injured you will be stuck with a stand-in rookie. Sign a reserve in SCOUTING.", 12, UIKit.BAD)
	for id: String in Career.reserves():
		var d := Career.driver(id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		bench.add_child(line)
		line.add_child(_face(id, 60))
		var label := _text(line, "%s\nOVR %d  ·  AGE %d  ·  %s" % [str(d["name"]).to_upper(), Career.driver_overall(d), int(d["age"]), UIKit.money(float(d["salary"]) * Career.RESERVE_SALARY_SHARE)], 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _pending_seat == id:
			for seat: String in Career.lineup():
				var swap_button := UIKit.button("FOR %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper(), 12, true)
				swap_button.custom_minimum_size = Vector2(170, 44)
				swap_button.pressed.connect(func() -> void:
					var error := Career.promote_reserve(id, seat)
					_pending_seat = ""
					_say("%s promoted to a race seat." % d["name"] if error == "" else error, error == "")
					_show_tab(1))
				line.add_child(swap_button)
		else:
			var promote := UIKit.button("PROMOTE", 12)
			promote.custom_minimum_size = Vector2(120, 44)
			promote.pressed.connect(func() -> void:
				_pending_seat = id
				_show_tab(1))
			line.add_child(promote)
			var release := UIKit.button("RELEASE", 12)
			release.custom_minimum_size = Vector2(120, 44)
			release.pressed.connect(func() -> void:
				Career.release_reserve(id)
				_say("%s released." % d["name"])
				_show_tab(1))
			line.add_child(release)


func _tab_scouting() -> void:
	_text(_content, "SALARY CAP  %s / %s        A FULL REPORT TAKES 3 PHASES: %s, %s, %s" % [UIKit.money(Career.salary_total()), UIKit.money(Career.SALARY_CAP), UIKit.money(Career.SCOUT_COSTS[0]), UIKit.money(Career.SCOUT_COSTS[1]), UIKit.money(Career.SCOUT_COSTS[2])], 12, UIKit.TEXT_DIM)
	for d: Dictionary in Career.market():
		var id: String = d["id"]
		var level := Career.scout_level(d)
		var source := "FREE AGENT"
		if d.get("junior", false):
			source = "%s  ·  %s ACADEMY" % [d["league"], Career.team(d["academy"])["short"]]
		var frame := Frame.make("%s  ·  AGE %d" % [source, int(d["age"])], 4)
		_content.add_child(frame)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		frame.body.add_child(row)
		row.add_child(_face(id, 72))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		_text(info, str(d["name"]).to_upper(), 16)
		# Each phase uncovers more of the report.
		var pace := "%d" % int(d["pace"]) if level >= 1 else "??"
		var craft := "%d" % int(d["racecraft"]) if level >= 2 else "??"
		var steady := "%d" % int(d["consistency"]) if level >= 2 else "??"
		var ego := "%d" % int(d["ego"]) if level >= 3 else "??"
		var now := "%d" % Career.driver_overall(d) if level >= 2 else "%d-%d" % [int(d.get("hype", 70)) - 7, int(d.get("hype", 70)) + 7]
		_text(info, "OVR %s    PACE %s    CRAFT %s    STEADY %s    EGO %s" % [now, pace, craft, steady, ego], 12)
		var potential := Career.potential_overall(d)
		if level >= 3:
			_text(info, "POTENTIAL OVR %d%s" % [potential, "   -   A FUTURE STAR" if potential >= 88 else ("   -   ALREADY PEAKED" if potential <= Career.driver_overall(d) + 3 else "")], 13, UIKit.GOOD if potential >= 85 else (UIKit.BAD if potential <= Career.driver_overall(d) + 3 else UIKit.TEXT))
		else:
			_text(info, "POTENTIAL OVR ??   (REPORT %d/3)" % level, 12, UIKit.TEXT_DIM)
		_text(info, "SALARY %s   BUYOUT %s" % [UIKit.money(float(d["salary"])), UIKit.money(float(d.get("buyout", 0)))], 11, UIKit.TEXT_DIM)
		row.add_child(Art.make(Vector2(46, 20), func(a: Control) -> void:
			for i in 3:
				a.draw_rect(Rect2(i * 15.0, 4, 12, 12), UIKit.GOOD if i < level else UIKit.GRID_BOLD)))
		if _pending_seat == id:
			var choices := VBoxContainer.new()
			choices.add_theme_constant_override("separation", 4)
			row.add_child(choices)
			var seat_options: Array = Career.lineup().duplicate()
			if Career.reserves().size() < Career.MAX_RESERVES:
				seat_options.append("reserve")
			for seat: String in seat_options:
				var text := "AS RESERVE" if seat == "reserve" else "REPLACE %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper()
				var swap_button := UIKit.button(text, 11, true)
				swap_button.custom_minimum_size = Vector2(180, 36)
				swap_button.pressed.connect(func() -> void:
					var error := Career.sign_driver(id, seat)
					_pending_seat = ""
					_say("%s signed." % d["name"] if error == "" else error, error == "")
					_show_tab(2))
				choices.add_child(swap_button)
		else:
			if level < 3:
				var scout := UIKit.button("SCOUT\n%s" % UIKit.money(Career.scout_cost(d)), 12)
				scout.custom_minimum_size = Vector2(110, 56)
				scout.pressed.connect(func() -> void:
					if Career.scout(id):
						_say("Scouting phase %d complete on %s." % [Career.scout_level(d), d["name"]])
					else:
						_say("Not enough cash for the next scouting phase.", false)
					_show_tab(2))
				row.add_child(scout)
			var sign_button := UIKit.button("SIGN", 13, true)
			sign_button.custom_minimum_size = Vector2(100, 56)
			sign_button.pressed.connect(func() -> void:
				_pending_seat = id
				_show_tab(2))
			row.add_child(sign_button)


func _tab_sponsors() -> void:
	var c := Career.state()
	var current := _card()
	var sponsor: Dictionary = c["sponsor"]
	_text(current, "TITLE SPONSOR", 11, UIKit.TEXT_DIM)
	if sponsor.is_empty():
		_text(current, "NONE", 20, UIKit.BAD)
	else:
		_text(current, str(sponsor["name"]).to_upper(), 20)
		_text(current, "%s per race  ·  %s per podium  ·  %d races left" % [UIKit.money(sponsor["per_race"]), UIKit.money(sponsor["podium_bonus"]), int(sponsor["races_left"])], 12, UIKit.TEXT_DIM)
	_text(_content, "OFFERS ON THE TABLE  (signing replaces the current deal)", 12, UIKit.TEXT_DIM)
	var offers: Array = c["sponsor_offers"]
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var panel := UIKit.panel(UIKit.PANEL, UIKit.GRID_BOLD)
		_content.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", -2)
		row.add_child(info)
		_text(info, "%s  (%s)" % [str(offer["name"]).to_upper(), offer["kind"]], 16)
		var ok := int(c["reputation"]) >= int(offer["min_rep"])
		_text(info, "Signing %s  ·  %s per race  ·  %s per podium  ·  %d races  ·  needs reputation %d" % [UIKit.money(offer["signing"]), UIKit.money(offer["per_race"]), UIKit.money(offer["podium_bonus"]), int(offer["races"]), int(offer["min_rep"])], 11, UIKit.TEXT_DIM if ok else UIKit.BAD)
		var nego := UIKit.button("NEGOTIATE", 12)
		nego.custom_minimum_size = Vector2(120, 40)
		nego.disabled = offer["negotiated"]
		nego.pressed.connect(func() -> void:
			var result := Career.negotiate_sponsor(i)
			_say(result, result.contains("improved"))
			_show_tab(3))
		row.add_child(nego)
		var sign_button := UIKit.button("SIGN", 12, true)
		sign_button.custom_minimum_size = Vector2(90, 40)
		sign_button.pressed.connect(func() -> void:
			var error := Career.sign_sponsor(i)
			_say("Deal signed." if error == "" else error, error == "")
			_show_tab(3))
		row.add_child(sign_button)


func _tab_factory() -> void:
	var c := Career.state()
	var car := _card(null, "THE CAR")
	var build := Career.build_rating()
	var f: Dictionary = c["factory"]
	_text(car, "CAR RATING %d" % int(round(Career.car_rating(c["team"]))), 20)
	_text(car, "team baseline %d   +   your garage build %+.1f   +   factory %+.1f   +   one-off developments %+.1f" % [int(c["team_cars"][c["team"]]), (build - 60.0) * 0.6, (int(f["aero"]) + int(f["power"])) * 1.5, float(c["car_bonus"])], 12, UIKit.TEXT_DIM)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	car.add_child(actions)
	var garage := UIKit.button("BUILD IT YOURSELF  >  GARAGE", 14, true)
	garage.custom_minimum_size = Vector2(320, 46)
	garage.pressed.connect(func() -> void: SceneManager.goto("garage"))
	actions.add_child(garage)
	var commission := UIKit.button("PAY THE ENGINEERS TO UPGRADE IT (+25%)", 14)
	commission.custom_minimum_size = Vector2(420, 46)
	commission.pressed.connect(func() -> void:
		var message := Career.commission_package()
		_say(message, message.begins_with("Engineers"))
		_show_tab(4))
	actions.add_child(commission)
	_text(car, "Cost cap: %s spent of %s this season. Parts and factory upgrades all count." % [UIKit.money(c["cap_spent"]), UIKit.money(Career.COST_CAP)], 12, UIKit.TEXT_DIM)
	for dept: String in Career.DEPARTMENTS:
		var panel := UIKit.panel(UIKit.PANEL, UIKit.GRID_BOLD)
		_content.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		panel.add_child(row)
		var level := int(f[dept])
		var max_level := Career.rd_tiers.size() if dept == "rd" else Career.FACTORY_MAX
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", -2)
		row.add_child(info)
		_text(info, "%s   LEVEL %d/%d" % [Career.DEPARTMENTS[dept]["name"], level, max_level], 16)
		var note: String = Career.DEPARTMENTS[dept]["note"]
		if dept == "rd" and level < max_level:
			var names := PackedStringArray()
			for id: String in Career.rd_tiers[level]["unlocks"]:
				names.append(PartDB.get_part(id).display_name)
			note = "next level unlocks: " + ", ".join(names)
		_text(info, note, 11, UIKit.TEXT_DIM)
		var pips := level
		row.add_child(Art.make(Vector2(max_level * 18.0, 20), func(a: Control) -> void:
			for i in max_level:
				a.draw_rect(Rect2(i * 18.0, 3, 13, 13), UIKit.ACCENT if i < pips else UIKit.GRID_BOLD)))
		var b := UIKit.button("MAX" if level >= max_level else "UPGRADE %s" % UIKit.money(Career.upgrade_cost(dept)), 12)
		b.custom_minimum_size = Vector2(170, 42)
		b.disabled = level >= max_level
		b.pressed.connect(func() -> void:
			var error := Career.upgrade(dept)
			_say("%s upgraded." % Career.DEPARTMENTS[dept]["name"] if error == "" else error, error == "")
			_show_tab(4))
		row.add_child(b)


func _tab_standings() -> void:
	var row := _columns()
	var drivers := _card(row, "DRIVERS")
	var rows := Career.standings_drivers()
	for i in mini(rows.size(), 22):
		var r: Dictionary = rows[i]
		var mine: bool = r["team"] == Career.state()["team"]
		var team_short: String = Career.team(r["team"]).get("short", "---")
		_text(drivers, "%2d  %-20s %s  %3d" % [i + 1, str(r["name"]).to_upper().left(20), team_short, int(r["points"])], 12, UIKit.BAD if mine else UIKit.TEXT)
	var teams_card := _card(row, "CONSTRUCTORS")
	var trows := Career.standings_teams()
	for i in trows.size():
		var r: Dictionary = trows[i]
		var mine: bool = r["id"] == Career.state()["team"]
		_text(teams_card, "%2d  %-20s %3d   CAR %d  TEAM %d" % [i + 1, str(r["name"]).to_upper().left(20), int(r["points"]), int(Career.car_rating(r["id"])), Career.team_rating(r["id"])], 12, UIKit.BAD if mine else UIKit.TEXT)


# ---------------------------------------------------------------- events and endings

func _check_interrupts() -> void:
	if Career.state().get("fired", false):
		_show_modal("BOARD DECISION", "YOU HAVE BEEN FIRED", "%s have run out of patience. Your pass no longer opens the factory gate." % str(Career.my_team()["owner"]).capitalize(), [["START A NEW CAREER", func() -> void:
			Career.end_career()
			SceneManager.goto("career_start")]])
		return
	var event := Career.pending_event()
	if event.is_empty():
		return
	var options: Array = []
	var list: Array = event["options"]
	for i in list.size():
		options.append([list[i]["text"], func() -> void:
			var outcome := Career.resolve_event(i)
			_show_modal(event["category"], "OUTCOME", outcome, [["OK", func() -> void:
				_close_modal()
				_show_tab(_tab)
				_check_interrupts()]])])
	_show_modal(event["category"], "DECISION", event["text"], options)


func _show_schedule() -> void:
	var c := Career.state()
	var lines := PackedStringArray()
	var done: Array = c.get("results", [])
	for i in Career.calendar.size():
		var info: Dictionary = Career.calendar[i]
		var status := ""
		if i < int(c["round"]):
			for r: Dictionary in done:
				if int(r["round"]) == i:
					status = "%s   WON BY %s" % [r["result"], str(r["winner"]).get_slice(" ", 1).to_upper()]
		elif i == int(c["round"]):
			status = "<  NEXT RACE"
		lines.append("%2d  %-26s %-13s %s" % [i + 1, str(info["name"]).to_upper().left(26), GameManager.TRACK_NAMES.get(info.get("track", ""), ""), status])
	_show_modal("SEASON %d" % int(c["season"]), "SCHEDULE", "\n".join(lines), [["CLOSE", _close_modal]])


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _show_modal(category: String, title: String, body: String, options: Array) -> void:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	panel.custom_minimum_size = Vector2(860 if title == "SCHEDULE" else 640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.label(category, 12, UIKit.HOT))
	box.add_child(UIKit.label(title, 24))
	var text := UIKit.label(body, 13 if title == "SCHEDULE" else 16)
	if title != "SCHEDULE":
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(610, 0)
	box.add_child(text)
	box.add_child(UIKit.spacer(4))
	for option: Array in options:
		var b := UIKit.button(option[0], 15)
		b.custom_minimum_size = Vector2(0, 48)
		b.pressed.connect(option[1])
		box.add_child(b)
	AudioManager.play("beep", -12.0)
