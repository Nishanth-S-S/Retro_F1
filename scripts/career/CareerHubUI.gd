extends Control
## Team HQ. Four pages on a bar along the bottom: HQ, DRIVERS, SCOUTING, STANDINGS.
## Everything about the cars lives in the garage; staff and sponsors open as sheets from
## the HQ page. Dilemma events pop up here after each race.

const TABS: PackedStringArray = ["HQ", "DRIVERS", "SCOUTING", "STANDINGS"]
const TAB_SCOUTING := 2

var _tab := 0
var _content: VBoxContainer
var _header: HBoxContainer
var _tab_buttons: Array[Button] = []
var _toast: Label
var _modal: Control
var _pending_seat := ""
## Scouting page: false = free agents and juniors, true = rival drivers with release clauses.
var _show_rivals := false


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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	_toast = UIKit.label("", 16, UIKit.ACCENT)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.visible = false
	root.add_child(_toast)
	# Page bar along the bottom, with the race button at its end.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	for i in TABS.size():
		var b := UIKit.button(TABS[i], 20)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 66)
		b.pressed.connect(func() -> void: _show_tab(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var race := UIKit.button("RACE  >", 24, true)
	race.custom_minimum_size = Vector2(250, 66)
	race.pressed.connect(func() -> void: SceneManager.goto("raceday"))
	bar.add_child(race)
	EventBus.money_changed.connect(func(_a: int) -> void: _build_header())
	_show_tab(0)
	_check_interrupts.call_deferred()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


func _say(text: String, good: bool = true) -> void:
	_toast.text = text
	_toast.visible = text != ""
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
	# The garage is one tap away from every page.
	var garage := UIKit.button("GARAGE", 15, true)
	garage.custom_minimum_size = Vector2(120, 58)
	garage.pressed.connect(func() -> void: SceneManager.goto("garage"))
	_header.add_child(garage)
	var cash := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	cash.custom_minimum_size = Vector2(150, 58)
	var cash_label := UIKit.label(UIKit.money(GameManager.money()), 20, UIKit.GOOD if GameManager.money() >= 0 else UIKit.BAD)
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
		3: _tab_standings()


func _card(parent: Control = null, caption: String = "") -> VBoxContainer:
	var frame := Frame.make(caption, 6)
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
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	return row


func _text(parent: Control, text: String, size: int = 16, color: Color = UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _big(text: String, accent: bool, action: Callable, size: int = 20, height: float = 70.0) -> Button:
	var b := UIKit.button(text, size, accent)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, height)
	b.pressed.connect(action)
	return b


func _face(id: String, size: float) -> Art:
	var p := Career.person(id)
	var team := Career.team(str(p.get("team", "")))
	var color := Color(str(team["color"])) if not team.is_empty() else Color("6a7078")
	return Art.make(Vector2(size, size), func(a: Control) -> void:
		if not p.is_empty():
			PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), p["look"], color, Color("d8e6dc")))


# ---------------------------------------------------------------- HQ

func _tab_hq() -> void:
	var c := Career.state()
	var team := Career.my_team()
	var row := _columns()
	# --- next race
	var next := _card(row, "ROUND %d / %d" % [int(c["round"]) + 1, Career.calendar.size()])
	var round_info := Career.next_round()
	_text(next, str(round_info["name"]).to_upper(), 28)
	_text(next, "%s  ·  RAIN %d%%" % [TrackTheme.label(Career.round_track()), int(float(round_info["rain"]) * 100.0)], 16, UIKit.TEXT_DIM)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	next.add_child(chips)
	var seats := Career.lineup()
	var drivers_avg := (Career.driver_overall(Career.driver(seats[0])) + Career.driver_overall(Career.driver(seats[1]))) / 2
	chips.add_child(Art.chip("CAR", int(round(Career.car_rating(c["team"]))), UIKit.LINE.darkened(0.3)))
	chips.add_child(Art.chip("DRIVERS", drivers_avg, Color("23262e")))
	chips.add_child(Art.chip("TEAM", Career.team_rating(c["team"]), UIKit.WARM))
	chips.add_child(Art.chip("POSITION", Career.team_position(), Color("23262e")))
	var alerts := PackedStringArray()
	for car: Dictionary in Career.cars():
		if not Career.car_violations(car).is_empty():
			alerts.append("%s IS ILLEGAL" % car["name"])
	for id: String in seats:
		if Career.is_injured(id):
			alerts.append("%s INJURED" % str(Career.driver(id)["name"]).get_slice(" ", 1).to_upper())
	if (c["sponsor"] as Dictionary).is_empty():
		alerts.append("NO SPONSOR")
	if Career.reserves().is_empty():
		alerts.append("NO RESERVE")
	if not alerts.is_empty():
		_text(next, "  ·  ".join(alerts.slice(0, 3)), 16, UIKit.BAD)
	# --- the boss
	var me := _card(row, "SEASON %d" % int(c["season"]))
	var manager: Dictionary = c["manager"]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	me.add_child(line)
	line.add_child(Art.make(Vector2(128, 128), func(a: Control) -> void:
		PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), manager["look"], Color(str(team["color"])), Color("d8e6dc"))))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	line.add_child(info)
	_text(info, str(manager["name"]), 24)
	_text(info, Career.board_target_text().to_upper(), 16, UIKit.HOT)
	var board := int(c["board"])
	info.add_child(Art.rating_bar("BOARD", board, UIKit.GOOD if board >= 50 else (Color("e0a23a") if board >= 25 else UIKit.BAD), 340.0))
	var report: Dictionary = c["last_report"]
	if not report.is_empty():
		var parts := PackedStringArray()
		for m: Dictionary in report["mine"]:
			parts.append("DNF" if m["dnf"] else "P%d" % int(m["position"]))
		_text(info, "LAST RACE  %s" % " / ".join(parts), 16, UIKit.TEXT_DIM)
	# --- the three places you go from here
	var actions := _columns()
	var sponsor: Dictionary = c["sponsor"]
	actions.add_child(_big("SPONSOR: %s" % (str(sponsor["name"]).to_upper() if not sponsor.is_empty() else "NONE"), false, func() -> void: HubPanels.sponsor_sheet(self)))
	actions.add_child(_big("SCHEDULE", false, _show_schedule))
	# --- staff roster
	var income := Career.research_income()
	var staff := _card(null, "STAFF  %d / %d   ·   %d RESEARCH   ·   +%d A WEEK" % [Career.engineers().size(), Career.max_engineers(), int(c["rp"]), int(income["total"])])
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 10)
	staff.add_child(roster)
	for id: String in Career.engineers():
		roster.add_child(_staff_tile(id))
	var hire := UIKit.button("+ HIRE", 22, true)
	hire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire.custom_minimum_size = Vector2(150, 150)
	hire.pressed.connect(func() -> void: HubPanels.staff_sheet(self))
	roster.add_child(hire)


## One member of staff on the HQ roster: face, name, job and skill. Tap for details / fire.
func _staff_tile(id: String) -> Button:
	var e := Career.engineer(id)
	var color := Color(str(Career.my_team()["color"]))
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(176, 150)
	var art := Art.make(Vector2.ZERO, func(a: Control) -> void:
		var f := UIKit.font()
		PixelArt.draw_portrait(a, Rect2(10, 8, 80, 80), e["look"], color, Color("d8e6dc"))
		a.draw_rect(Rect2(100, 14, 66, 62), UIKit.LINE.darkened(0.2) if int(e["skill"]) >= 75 else Color("23262e"))
		a.draw_string(f, Vector2(100, 60), str(int(e["skill"])), HORIZONTAL_ALIGNMENT_CENTER, 66, 32, Color.WHITE)
		a.draw_string(f, Vector2(0, 112), str(e["name"]).get_slice(" ", 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 16, UIKit.TEXT)
		a.draw_string(f, Vector2(0, 134), str(Career.ENGINEER_SPECS[e["spec"]]["short"]), HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 13, UIKit.TEXT_DIM))
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(art)
	tile.pressed.connect(func() -> void:
		AudioManager.play("click", -12.0)
		_show_modal(str(Career.ENGINEER_SPECS[e["spec"]]["name"]), str(e["name"]).to_upper(), "SKILL %d   ·   %s A SEASON\n%s" % [int(e["skill"]), UIKit.money(float(e["salary"])), Career.ENGINEER_SPECS[e["spec"]]["note"]], [
			["KEEP", _close_modal],
			["FIRE  (%s SEVERANCE)" % UIKit.money(float(e["salary"]) * 0.25), func() -> void:
				_close_modal()
				_say(Career.fire_engineer(id))
				_show_tab(0)]]))
	return tile


# ---------------------------------------------------------------- DRIVERS

func _driver_card(parent: Control, id: String) -> void:
	var d := Career.driver(id)
	var team := Career.my_team()
	var box := _card(parent, "#%d%s" % [int(d["number"]), "  ·  NO.1" if Career.state()["number_one"] == id else ""])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	box.add_child(line)
	line.add_child(_face(id, 128))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	line.add_child(info)
	_text(info, str(d["name"]).to_upper(), 24)
	_text(info, "AGE %d  ·  %s" % [int(d["age"]), UIKit.money(float(d["salary"]))], 16, UIKit.TEXT_DIM)
	if Career.is_injured(id):
		_text(info, "INJURED  ·  %d RACE%s" % [int(d["injured"]), "" if int(d["injured"]) == 1 else "S"], 18, UIKit.BAD)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	line.add_child(side)
	side.add_child(Art.chip("OVR", Career.driver_overall(d), UIKit.WARM))
	side.add_child(Art.make(Vector2(74, 56), func(a: Control) -> void:
		PixelArt.draw_helmet(a, Rect2(Vector2.ZERO, a.size), Color(str(team["color"])), Color(str(team["color2"])), int(d["number"]))))
	var car := Career.car_for(id)
	var fit := Career.car_fit(d, car)
	box.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 420.0))
	box.add_child(Art.rating_bar("CAR FIT", fit, UIKit.GOOD if fit >= 75 else (Color("e0a23a") if fit >= 60 else UIKit.BAD), 420.0))
	box.add_child(_big("DRIVER CARD", true, func() -> void: HubPanels.driver_card(self, id), 18, 56.0))


func _tab_drivers() -> void:
	var row := _columns()
	for id: String in Career.lineup():
		_driver_card(row, id)
	var bench := _card(null, "RESERVES  %d / %d" % [Career.reserves().size(), Career.MAX_RESERVES])
	if Career.reserves().is_empty():
		_text(bench, "EMPTY BENCH", 18, UIKit.BAD)
	for id: String in Career.reserves():
		var d := Career.driver(id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		bench.add_child(line)
		line.add_child(_face(id, 72))
		var label := _text(line, "%s\nOVR %d  ·  AGE %d" % [str(d["name"]).to_upper(), Career.driver_overall(d), int(d["age"])], 18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _pending_seat == id:
			for seat: String in Career.lineup():
				var swap_button := UIKit.button("FOR %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper(), 16, true)
				swap_button.custom_minimum_size = Vector2(210, 60)
				swap_button.pressed.connect(func() -> void:
					var error := Career.promote_reserve(id, seat)
					_pending_seat = ""
					_say("%s promoted." % d["name"] if error == "" else error, error == "")
					_show_tab(1))
				line.add_child(swap_button)
		else:
			for info: Array in [["CARD", func() -> void: HubPanels.driver_card(self, id)], ["PROMOTE", func() -> void:
				_pending_seat = id
				_show_tab(1)], ["RELEASE", func() -> void:
				Career.release_reserve(id)
				_say("%s released." % d["name"])
				_show_tab(1)]]:
				var b := UIKit.button(info[0], 16)
				b.custom_minimum_size = Vector2(140, 60)
				b.pressed.connect(info[1])
				line.add_child(b)


# ---------------------------------------------------------------- SCOUTING

func _tab_scouting() -> void:
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 8)
	_content.add_child(views)
	for rivals: bool in [false, true]:
		var view := UIKit.button("RIVAL DRIVERS" if rivals else "FREE AGENTS", 18)
		view.toggle_mode = true
		view.button_pressed = _show_rivals == rivals
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.custom_minimum_size = Vector2(0, 54)
		view.pressed.connect(func() -> void:
			_show_rivals = rivals
			_pending_seat = ""
			_show_tab(TAB_SCOUTING))
		views.add_child(view)
	if _show_rivals:
		HubPanels.poach_list(self)
		return
	for d: Dictionary in Career.market():
		var id: String = d["id"]
		var level := Career.scout_level(d)
		var frame := Frame.make("", 4)
		_content.add_child(frame)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		frame.body.add_child(row)
		row.add_child(_face(id, 84))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		_text(info, "%s  ·  %d" % [str(d["name"]).to_upper(), int(d["age"])], 20)
		# Each scouting phase uncovers more of the report.
		var now := "%d" % Career.driver_overall(d) if level >= 2 else "%d-%d" % [int(d.get("hype", 70)) - 7, int(d.get("hype", 70)) + 7]
		var potential := "%d" % Career.potential_overall(d) if level >= 3 else "??"
		_text(info, "OVR %s   ·   POTENTIAL %s" % [now, potential], 17, UIKit.GOOD if level >= 3 and Career.potential_overall(d) >= 85 else UIKit.TEXT)
		_text(info, "%s A SEASON   ·   FEE %s" % [UIKit.money(float(d["salary"])), UIKit.money(float(d.get("buyout", 0)))], 14, UIKit.TEXT_DIM)
		row.add_child(Art.make(Vector2(58, 24), func(a: Control) -> void:
			for i in 3:
				a.draw_rect(Rect2(i * 19.0, 4, 15, 15), UIKit.GOOD if i < level else UIKit.GRID_BOLD)))
		if _pending_seat == id:
			var choices := VBoxContainer.new()
			choices.add_theme_constant_override("separation", 4)
			row.add_child(choices)
			var seat_options: Array = Career.lineup().duplicate()
			if Career.reserves().size() < Career.MAX_RESERVES:
				seat_options.append("reserve")
			for seat: String in seat_options:
				var text := "AS RESERVE" if seat == "reserve" else "FOR %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper()
				var swap_button := UIKit.button(text, 14, true)
				swap_button.custom_minimum_size = Vector2(210, 40)
				swap_button.pressed.connect(func() -> void:
					var error := Career.sign_driver(id, seat)
					_pending_seat = ""
					_say("%s signed." % d["name"] if error == "" else error, error == "")
					_show_tab(TAB_SCOUTING))
				choices.add_child(swap_button)
		else:
			if level < 3:
				var scout := UIKit.button("SCOUT\n%s" % UIKit.money(Career.scout_cost(d)), 15)
				scout.custom_minimum_size = Vector2(120, 70)
				scout.pressed.connect(func() -> void:
					if not Career.scout(id):
						_say("Not enough cash to scout.", false)
					_show_tab(TAB_SCOUTING))
				row.add_child(scout)
			var card := UIKit.button("CARD", 15)
			card.custom_minimum_size = Vector2(100, 70)
			card.pressed.connect(func() -> void: HubPanels.driver_card(self, id))
			row.add_child(card)
			var sign_button := UIKit.button("SIGN", 17, true)
			sign_button.custom_minimum_size = Vector2(110, 70)
			sign_button.pressed.connect(func() -> void:
				_pending_seat = id
				_show_tab(TAB_SCOUTING))
			row.add_child(sign_button)


# ---------------------------------------------------------------- STANDINGS

func _tab_standings() -> void:
	var row := _columns()
	var drivers := _card(row, "DRIVERS")
	var rows := Career.standings_drivers()
	for i in mini(rows.size(), 22):
		var r: Dictionary = rows[i]
		var mine: bool = r["team"] == Career.state()["team"]
		_text(drivers, "%2d  %-18s %3d" % [i + 1, str(r["name"]).get_slice(" ", 1).to_upper().left(18), int(r["points"])], 17, UIKit.BAD if mine else UIKit.TEXT)
	var teams_card := _card(row, "TEAMS")
	var trows := Career.standings_teams()
	for i in trows.size():
		var r: Dictionary = trows[i]
		var mine: bool = r["id"] == Career.state()["team"]
		_text(teams_card, "%2d  %-18s %3d" % [i + 1, str(r["name"]).to_upper().left(18), int(r["points"])], 17, UIKit.BAD if mine else UIKit.TEXT)


# ---------------------------------------------------------------- events and endings

func _check_interrupts() -> void:
	if Career.state().get("fired", false):
		_show_modal("BOARD DECISION", "YOU HAVE BEEN FIRED", "%s have run out of patience." % str(Career.my_team()["owner"]).capitalize(), [["START A NEW CAREER", func() -> void:
			Career.end_career()
			SceneManager.goto("career_start")]])
		return
	var event := Career.pending_event()
	if event.is_empty():
		return
	var options: Array = []
	var list: Array = event["options"]
	for i in list.size():
		options.append(["%s\n%s" % [list[i]["text"], list[i]["outcome"]], func() -> void:
			var outcome := Career.resolve_event(i)
			_show_modal(event["category"], "OUTCOME", outcome, [["OK", func() -> void:
				_close_modal()
				_show_tab(_tab)
				_check_interrupts()]])])
	_show_modal(event["category"], "DECISION", "%s\n\nWHY NOW: %s" % [event["text"], event["why"]], options)


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
					status = str(r["result"])
		elif i == int(c["round"]):
			status = "<  NEXT"
		lines.append("%2d  %-26s %s" % [i + 1, str(info["name"]).to_upper().left(26), status])
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
	var wide := 940.0 if title == "DECISION" else 700.0
	panel.custom_minimum_size = Vector2(wide, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.label(category, 14, UIKit.HOT))
	box.add_child(UIKit.label(title, 26))
	var text := UIKit.label(body, 17)
	if title != "SCHEDULE":
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(wide - 30.0, 0)
	box.add_child(text)
	box.add_child(UIKit.spacer(4))
	for option: Array in options:
		var b := UIKit.button(option[0], 15 if title == "DECISION" else 17)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(wide - 30.0, 78 if title == "DECISION" else 56)
		b.pressed.connect(option[1])
		box.add_child(b)
	AudioManager.play("beep", -12.0)


## A large scrolling sheet over the page (hire staff, sponsors). Returns the list to fill.
func open_sheet(title: String, note: String = "") -> VBoxContainer:
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
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1040, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIKit.title_bar(title, 50.0))
	if note != "":
		box.add_child(UIKit.label(note, 16, UIKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var close := UIKit.button("DONE", 20, true)
	close.custom_minimum_size = Vector2(0, 60)
	close.pressed.connect(func() -> void:
		_close_modal()
		_show_tab(_tab))
	box.add_child(close)
	return list
