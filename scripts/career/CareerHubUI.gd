extends Control
## Team HQ. Four pages on a bar along the bottom: HQ, DRIVERS, SCOUTING, STANDINGS.
## Every person is a card; tapping one opens their full-screen card (HubPanels). The
## garage is reached from the race page. Dilemma events pop up here after each race.

const TABS: PackedStringArray = ["HQ", "DRIVERS", "SCOUTING", "STANDINGS"]
const TAB_SCOUTING := 2

var _tab := 0
var _content: VBoxContainer
var _header: HBoxContainer
var _tab_buttons: Array[Button] = []
var _toast: Label
var _modal: Control
## Scouting page: false = free agents and juniors, true = rival drivers with release clauses.
var _show_rivals := false
var _day_button: Button
## Controls the HQ tutorial points at.
var _marks: Dictionary = {}


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
	# The day button: race / qualify on a race weekend, otherwise on to the next day.
	_day_button = UIKit.button("", 22, true)
	_day_button.custom_minimum_size = Vector2(250, 66)
	_day_button.pressed.connect(_on_day_button)
	bar.add_child(HubPanels.press_anim(_day_button))
	EventBus.money_changed.connect(func(_a: int) -> void: _build_header())
	_show_tab(0)
	_marks["phone"] = _header.get_child(_header.get_child_count() - 1)
	CoachMarks.run_once(self, "hq", func() -> Array: return [
		[null, "This is TEAM HQ. You're the team principal - everything starts here."],
		[_marks["today"], "TODAY: the date and what's on. Race weekends are practice Friday, qualifying Saturday, race Sunday."],
		[_day_button, "This button shows today's job - PRACTICE, QUALIFYING or RACE. Once it's done it says NEXT: tap it to sim a day, a week, a month or to the next race."],
		[_marks["coach"], "You. Tap your card for your contract, rating, history and teams that want you."],
		[_marks["hire"], "Hire engineers and staff. Better engineers bring more research points every week."],
		[_tab_buttons[1], "DRIVERS: your race drivers and reserves. Tap a card to train, swap or release them."],
		[_tab_buttons[2], "SCOUTING: scout young talent and sign drivers - or buy stars out of their contracts."],
		[_marks["phone"], "Your PHONE: messages, offers and rival teams trying to poach your people."],
	])
	if Career.last_note != "":
		_say(Career.last_note)
		Career.last_note = ""
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


## Bottom-right button: today's job until it is done (PRACTICE, REST, QUALIFYING, RACE), then NEXT.
func _refresh_day_button() -> void:
	var kind := str(Career.day_event()["type"])
	if Career.day_done():
		_day_button.text = "NEXT  >"
	elif kind == "race":
		_day_button.text = "RACE  >"
	elif kind == "quali":
		_day_button.text = "QUALIFYING  >"
	elif kind == "rest":
		_day_button.text = "REST  >"
	else:
		_day_button.text = "PRACTICE  >"


func _on_day_button() -> void:
	var kind := str(Career.day_event()["type"])
	if not Career.day_done():
		if kind == "race" or kind == "quali":
			SceneManager.goto("raceday")
		elif kind == "rest":
			HubPanels.rest_sheet(self)
		else:
			HubPanels.practice_sheet(self)
		return
	var picker := SimPicker.new()
	add_child(picker)
	picker.chosen.connect(func(span: String) -> void:
		var before := Career.date_text()
		var moved := Career.sim_ahead(span)
		if moved > 0:
			DayTransition.play(self, before, Career.date_text(), moved)
		_show_tab(_tab))


func _show_tab(index: int) -> void:
	_tab = index
	_refresh_day_button()
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
	# --- today: the date, what is on, the news, and moving time on
	var event := Career.day_event()
	var next := _card(row, "SEASON %d  ·  ROUND %d / %d" % [int(c["season"]), int(c["round"]) + 1, Career.calendar.size()])
	_marks["today"] = next.get_parent()
	_text(next, Career.date_text(), 30)
	_text(next, Career.day_title(event), 18, UIKit.HOT)
	var round_info := Career.next_round()
	var until := Career.race_day(int(c["round"])) - Career.today()
	_text(next, "NEXT: %s  ·  %s  ·  %s" % [str(round_info["name"]).to_upper(), Career.format_label(round_info), "TODAY" if until == 0 else "IN %d DAY%s" % [until, "" if until == 1 else "S"]], 15, UIKit.TEXT_DIM)
	var kind := str(event["type"])
	if kind == "practice" and not Career.practice_done():
		next.add_child(HubPanels.press_anim(_big("RUN PRACTICE", true, func() -> void: HubPanels.practice_sheet(self), 18, 56.0)))
	elif kind == "rest" and not Career.day_done():
		next.add_child(HubPanels.press_anim(_big("PLAN RECOVERY", true, func() -> void: HubPanels.rest_sheet(self), 18, 56.0)))
	var latest: Array = Career.news().slice(0, 2)
	for item: Dictionary in latest:
		_text(next, "NEWS  %s:  %s" % [Career.date_text(int(item["day"])), item["text"]], 13, UIKit.TEXT_DIM)
	var alerts := PackedStringArray()
	for car: Dictionary in Career.cars():
		if not Career.car_violations(car).is_empty():
			alerts.append("%s IS ILLEGAL" % car["name"])
	for id: String in Career.lineup():
		if Career.is_injured(id):
			alerts.append("%s INJURED" % str(Career.driver(id)["name"]).get_slice(" ", 1).to_upper())
	if not alerts.is_empty():
		_text(next, "  ·  ".join(alerts.slice(0, 3)), 15, UIKit.BAD)
	# --- the coach (you): tap for contract, rating, history and offers
	var me := _card(row, "SEASON %d" % int(c["season"]))
	_marks["coach"] = me.get_parent()
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
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	me.add_child(chips)
	chips.add_child(Art.chip("CAR", int(round(Career.car_rating(c["team"]))), UIKit.LINE.darkened(0.3)))
	chips.add_child(Art.chip("TEAM", Career.team_rating(c["team"]), UIKit.WARM))
	chips.add_child(Art.chip("POS", Career.team_position(), Color("23262e")))
	chips.add_child(Art.chip("RESEARCH", Career.rp(), UIKit.LINE.darkened(0.3)))
	chips.add_child(Art.chip("PIT CREW", int(c["factory"].get("pit", 0)), Color("23262e")))
	HubPanels.clickable(me.get_parent(), func() -> void: HubPanels.manager_card(self))
	var actions := _columns()
	var sponsor: Dictionary = c["sponsor"]
	actions.add_child(_big("SPONSOR: %s" % (str(sponsor["name"]).to_upper() if not sponsor.is_empty() else "NONE"), false, func() -> void: HubPanels.sponsor_sheet(self)))
	actions.add_child(_big("SCHEDULE", false, _show_schedule))
	# --- staff roster
	var income := Career.research_income()
	var staff := _card(null, "STAFF  %d / %d   ·   %d RESEARCH   ·   +%d A WEEK" % [Career.engineers().size(), Career.max_engineers(), Career.rp(), int(income["total"])])
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 10)
	staff.add_child(roster)
	for id: String in Career.engineers():
		roster.add_child(_staff_tile(id))
	# The pit crew: the one thing money still buys for racing - faster stops.
	var crew_level := int(c["factory"].get("pit", 0))
	var crew_cost := Career.pit_crew_cost()
	var crew := UIKit.button("PIT CREW\nLEVEL %d / %d\n%s" % [crew_level, Career.FACTORY_MAX, ("UPGRADE " + UIKit.money(crew_cost)) if crew_cost > 0 else "MAXED"], 15)
	crew.custom_minimum_size = Vector2(176, 150)
	crew.disabled = crew_cost <= 0
	crew.pressed.connect(func() -> void:
		var error := Career.upgrade_pit_crew()
		_say("Pit crew upgraded - faster stops." if error == "" else error, error == "")
		_show_tab(0))
	roster.add_child(HubPanels.press_anim(crew))
	var hire := UIKit.button("+ HIRE", 22, true)
	_marks["hire"] = hire
	hire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire.custom_minimum_size = Vector2(150, 150)
	hire.pressed.connect(func() -> void: HubPanels.staff_sheet(self))
	roster.add_child(HubPanels.press_anim(hire))


## One member of staff on the HQ roster: face, name, job and skill. Tap for their card.
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
		HubPanels.staff_card(self, id))
	return HubPanels.press_anim(tile)


# ---------------------------------------------------------------- DRIVERS

## A driver's card on the DRIVERS page. Race drivers and reserves look the same; tap
## anywhere on it for the full card.
func _driver_card(parent: Control, id: String) -> void:
	var d := Career.driver(id)
	var team := Career.my_team()
	var racing := Career.lineup().has(id)
	var box := _card(parent, "#%d  ·  %s%s" % [int(d["number"]), "RACE SEAT" if racing else "RESERVE", "  ·  NO.1" if Career.state()["number_one"] == id else ""])
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
	box.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 420.0))
	box.add_child(Art.rating_bar("FITNESS", Career.fitness(d), UIKit.GOOD if Career.fitness(d) >= 60 else UIKit.BAD, 420.0))
	var car := Career.car_for(id)
	var fit := Career.car_fit(d, car)
	box.add_child(Art.rating_bar("CAR FIT", fit, UIKit.GOOD if fit >= 75 else (Color("e0a23a") if fit >= 60 else UIKit.BAD), 420.0))
	HubPanels.clickable(box.get_parent(), func() -> void: HubPanels.driver_card(self, id))


func _tab_drivers() -> void:
	var row := _columns()
	for id: String in Career.lineup():
		_driver_card(row, id)
	if Career.reserves().is_empty():
		_text(_content, "NO RESERVES  -  SIGN ONE IN SCOUTING", 18, UIKit.BAD)
		return
	# Reserves use the same card, two to a row like the race seats.
	var bench := Career.reserves()
	for i in range(0, bench.size(), 2):
		var pair := _columns()
		for id: String in bench.slice(i, i + 2):
			_driver_card(pair, id)
		if pair.get_child_count() == 1:
			var gap := Control.new()
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pair.add_child(gap)


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
			_show_tab(TAB_SCOUTING))
		views.add_child(view)
	for d: Dictionary in (Career.poach_targets() if _show_rivals else Career.market()):
		_scout_row(d)


## One prospect: tap the row for the full card; SCOUT and SIGN work straight from here.
## Signing puts the driver on your bench.
func _scout_row(d: Dictionary) -> void:
	var id: String = d["id"]
	var level := Career.scout_level(d)
	var rival := str(d["team"]) != ""
	var frame := Frame.make(str(Career.team(str(d["team"])).get("name", "")).to_upper() if rival else "", 4)
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
	var now := "%d" % Career.driver_overall(d) if level >= 2 else "%d-%d" % [int(d.get("hype", 70)) - 7, int(d.get("hype", 70)) + 7]
	var potential := "%d" % Career.potential_overall(d) if level >= 3 else "??"
	_text(info, "OVR %s   ·   POTENTIAL %s" % [now, potential], 17, UIKit.GOOD if level >= 3 and Career.potential_overall(d) >= 85 else UIKit.TEXT)
	var fee := Career.release_clause(d) if rival else Career.driver_buyout(d)
	_text(info, "%s A SEASON   ·   %s %s" % [UIKit.money(float(d["salary"])), "CLAUSE" if rival else "FEE", UIKit.money(float(fee))], 14, UIKit.TEXT_DIM)
	if not rival:
		row.add_child(Art.make(Vector2(58, 24), func(a: Control) -> void:
			for i in 3:
				a.draw_rect(Rect2(i * 19.0, 4, 15, 15), UIKit.GOOD if i < level else UIKit.GRID_BOLD)))
		if level < 3:
			var scout := UIKit.button("SCOUT\n%s" % UIKit.money(Career.scout_cost(d)), 15)
			scout.custom_minimum_size = Vector2(120, 70)
			scout.pressed.connect(func() -> void:
				if not Career.scout(id):
					_say("Not enough cash to scout.", false)
				_show_tab(TAB_SCOUTING))
			row.add_child(HubPanels.press_anim(scout))
	var sign_button := UIKit.button("BUY OUT" if rival else "SIGN", 17, true)
	sign_button.custom_minimum_size = Vector2(120, 70)
	sign_button.pressed.connect(func() -> void:
		var error := Career.sign_driver(id, "reserve")
		_say("%s signed - on your bench." % d["name"] if error == "" else error, error == "")
		_show_tab(TAB_SCOUTING))
	row.add_child(HubPanels.press_anim(sign_button))
	HubPanels.clickable(frame, func() -> void: HubPanels.driver_card(self, id))


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
	if not (Career.state().get("season_review", {}) as Dictionary).is_empty() and not Career.state().get("fired", false):
		HubPanels.season_review(self)
		return
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
		lines.append("%2d  %-10s %-22s %-8s %s" % [i + 1, Career.date_text(Career.race_day(i)), str(info["name"]).to_upper().left(22), "SPRINT" if str(info.get("format", "gp")) == "sprint" else ("FINALE x2" if info.get("double", false) else "GP"), status])
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
