class_name HubPanels
extends RefCounted
## Cards and full-screen views opened from Team HQ: the card data for every kind of person,
## the full driver / staff / manager cards, hiring staff, sponsors and the season review.
## Every function takes the hub and builds with the hub's helpers.

const TAB_DRIVERS := 1
const TAB_SCOUTING := 2
## Stat rows on a driver card: label, key, scouting phase that reveals it.
const CARD_STATS: Array = [
	["PACE", "pace", 1], ["STARTS", "starts", 1], ["RACECRAFT", "racecraft", 2], ["CONSISTENCY", "consistency", 2],
	["OVERTAKING", "overtaking", 2], ["DEFENDING", "defending", 2], ["TYRE CARE", "tyres", 2], ["WET WEATHER", "wet", 2], ["EGO", "ego", 3],
]
const STAFF_NOTES := {
	"OWNER'S OFFICE": "Signs the cheques and judges you on results.",
	"RACE ENGINEER": "Talks to your drivers on the radio and reports after every race.",
	"TECHNICAL DIRECTOR": "Runs the factory and keeps an eye on the cost cap.",
	"CHIEF SCOUT": "Watches the junior series and sends you free reports.",
}


static func _team_color(team_id: String) -> Color:
	var t := Career.team(team_id)
	return Color(str(t["color"])) if not t.is_empty() else Color("6a7078")


## Makes a whole panel tappable, with a small press-in animation.
static func clickable(node: Control, action: Callable) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
			return
		node.pivot_offset = node.size * 0.5
		if event.pressed:
			node.create_tween().tween_property(node, "scale", Vector2(0.96, 0.96), 0.06)
		else:
			var t := node.create_tween()
			t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if Rect2(Vector2.ZERO, node.size).has_point(event.position):
				AudioManager.play("click", -12.0)
				t.tween_callback(action))
	return node


## The same press-in animation for a Button.
static func press_anim(b: BaseButton) -> BaseButton:
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
	b.button_up.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return b


static func grid(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	parent.add_child(flow)
	return flow


# ---------------------------------------------------------------- full-screen frame

## Full-screen card view with a BACK button in the top left. Returns [top row, body].
## `back` defaults to returning to the hub page.
static func open_full(hub: Control, title: String, color: Color, back: Callable = Callable()) -> Array:
	hub._close_modal()
	var modal := Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.add_child(modal)
	hub._modal = modal
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	modal.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var back_button := UIKit.button("<-  BACK", 18)
	back_button.custom_minimum_size = Vector2(150, 54)
	back_button.pressed.connect(func() -> void:
		if back.is_valid():
			back.call()
		else:
			hub._close_modal()
			hub._show_tab(hub._tab))
	head.add_child(press_anim(back_button))
	head.add_child(UIKit.title_bar(title, 54.0))
	var band := ColorRect.new()
	band.color = color
	band.custom_minimum_size = Vector2(0, 6)
	root.add_child(band)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	body.add_child(top)
	return [top, body]


static func _portrait(look: Dictionary, color: Color, size: float) -> Art:
	return Art.make(Vector2(size, size), func(a: Control) -> void:
		PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), look, color, Color("d8e6dc")))


static func _column(parent: Control, width: float = 0.0) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	if width > 0.0:
		col.custom_minimum_size = Vector2(width, 0)
	else:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	return col


static func _action(parent: Control, text: String, accent: bool, action: Callable, disabled: bool = false) -> Button:
	var b := UIKit.button(text, 17, accent)
	b.custom_minimum_size = Vector2(0, 62)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = disabled
	b.pressed.connect(action)
	parent.add_child(press_anim(b))
	return b


static func _chip_box(parent: Control) -> HBoxContainer:
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	parent.add_child(chips)
	return chips


# ---------------------------------------------------------------- the driver card

## Everything about a driver. What it shows depends on how much of the scouting report
## existed when the contract was signed: phase 1 pace, phase 2 racecraft, phase 3 ego,
## potential, favourite conditions and the kind of car they want.
static func driver_card(hub: Control, id: String, note: String = "") -> void:
	var d := Career.driver(id)
	if d.is_empty():
		return
	var level := Career.scout_level(d)
	var racing: bool = Career.lineup().has(id)
	var bench: bool = Career.reserves().has(id)
	var mine := racing or bench
	var team := Career.team(str(d["team"]))
	var color := _team_color(str(d["team"]))
	var made := open_full(hub, str(d["name"]), color)
	var top: HBoxContainer = made[0]
	var body: VBoxContainer = made[1]
	if note != "":
		body.move_child(hub._text(body, note, 18, UIKit.ACCENT), 0)
	# --- who
	var left := _column(top, 300)
	left.add_child(_portrait(Career.person(id)["look"], color, 220))
	hub._text(left, "#%d  ·  AGE %d" % [int(d["number"]), int(d["age"])], 18)
	hub._text(left, str(team.get("name", "FREE AGENT")).to_upper(), 16, UIKit.TEXT_DIM)
	hub._text(left, "%s A SEASON" % UIKit.money(float(d["salary"])), 16, UIKit.TEXT_DIM)
	var chips := _chip_box(left)
	chips.add_child(Art.chip("OVR", Career.driver_overall(d), UIKit.WARM) if level >= 2 else Art.chip("OVR ?", int(d.get("hype", 70)), Color("6a7078")))
	if level >= 3:
		chips.add_child(Art.chip("POTENTIAL", Career.potential_overall(d), UIKit.LINE))
	if Career.is_injured(id):
		hub._text(left, "INJURED  ·  %d RACES" % int(d["injured"]), 18, UIKit.BAD)
	if level < 3:
		hub._text(left, ("SIGNED WITHOUT A FULL REPORT" if mine else "SCOUT REPORT %d/3" % level), 15, UIKit.BAD)
	# --- stats
	var mid := _column(top, 400)
	hub._text(mid, "STATS", 14, UIKit.HOT)
	for stat: Array in CARD_STATS:
		if level >= int(stat[2]):
			mid.add_child(Art.rating_bar(stat[0], float(d[stat[1]]), UIKit.WARM if stat[1] == "ego" else UIKit.LINE, 390.0))
		else:
			hub._text(mid, "%-13s ??" % stat[0], 14, UIKit.TEXT_DIM)
	if mine:
		mid.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 390.0))
		mid.add_child(Art.rating_bar("FITNESS", Career.fitness(d), UIKit.GOOD if Career.fitness(d) >= 60 else UIKit.BAD, 390.0))
	# --- conditions and cars
	var right := _column(top)
	hub._text(right, "RACES BEST", 14, UIKit.HOT)
	if level >= 3:
		hub._text(right, Career.weather_label(d).get_slice("  -", 0), 18)
		hub._text(right, "HOME: %s" % GameManager.TRACK_NAMES.get(d["home"], "?"), 18, UIKit.GOOD)
		hub._text(right, "LOVES %s" % d["strong"], 18, UIKit.GOOD)
		hub._text(right, "HATES %s" % d["weak"], 18, UIKit.BAD)
		hub._text(right, "WANTS %s" % Career.car_taste(d), 15)
	else:
		hub._text(right, "UNKNOWN", 18, UIKit.TEXT_DIM)
	if racing:
		hub._text(right, "CAR", 14, UIKit.HOT)
		for car: Dictionary in Career.cars():
			var car_id: String = car["id"]
			var has: bool = Career.car_for(id)["id"] == car_id
			var fit := Career.car_fit(d, car)
			_action(right, "%s   FIT %s%s" % [car["name"], str(fit) if level >= 3 else "??", "   (DRIVES IT)" if has else ""], has, func() -> void:
				Career.assign_car(id, car_id)
				driver_card(hub, id), has)
	# --- recent form: what the in-season rating updates are based on
	var log: Array = d.get("log", [])
	var form := Frame.make("RECENT FORM", 6)
	body.add_child(form)
	if log.is_empty():
		hub._text(form.body, "NO RACES OR PRACTICE YET THIS SEASON", 16, UIKit.TEXT_DIM)
	else:
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 6)
		form.body.add_child(strip)
		for entry: Dictionary in log:
			var score := float(entry["s"])
			var tag := str(entry["r"])
			strip.add_child(Art.make(Vector2(110, 56), func(a: Control) -> void:
				a.draw_rect(Rect2(Vector2.ZERO, a.size), UIKit.GOOD if score > 0.3 else (UIKit.BAD if score < -0.3 else Color("6a7078")))
				a.draw_rect(Rect2(Vector2.ZERO, a.size), UIKit.INK, false, 2.0)
				a.draw_string(UIKit.font(), Vector2(0, 26), tag, HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 18, Color.WHITE)
				a.draw_string(UIKit.font(), Vector2(0, 46), "%+.1f" % score, HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 13, Color.WHITE)))
		hub._text(form.body, "RATING CHANGE FROM FORM THIS SEASON: %+d OVR" % int(d.get("form_change", 0)), 15, UIKit.TEXT_DIM)
	# --- what you can do
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	if bench:
		for seat: String in Career.lineup():
			_action(actions, "RACE INSTEAD OF %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper(), true, func() -> void:
				var error := Career.promote_reserve(id, seat)
				driver_card(hub, id, "NOW IN A RACE SEAT" if error == "" else error))
		_action(actions, "RELEASE", false, func() -> void:
			Career.release_reserve(id)
			hub._close_modal()
			hub._say("%s released." % d["name"])
			hub._show_tab(TAB_DRIVERS))
		_action(actions, "ADJUST", false, func() -> void: training_screen(hub, id))
	elif racing:
		for r: String in Career.reserves():
			_action(actions, "BENCH FOR %s" % str(Career.driver(r)["name"]).get_slice(" ", 1).to_upper(), false, func() -> void:
				var error := Career.promote_reserve(r, id)
				driver_card(hub, id, "MOVED TO THE BENCH" if error == "" else error))
		_action(actions, "RELEASE", false, func() -> void:
			var error := Career.release_driver(id)
			if error != "":
				driver_card(hub, id, error)
				return
			hub._close_modal()
			hub._say("%s released." % d["name"])
			hub._show_tab(TAB_DRIVERS))
		_action(actions, "ADJUST", false, func() -> void: training_screen(hub, id))
	elif str(d["team"]) == "":
		if level < 3:
			_action(actions, "SCOUT  %s" % UIKit.money(Career.scout_cost(d)), false, func() -> void:
				driver_card(hub, id, "" if Career.scout(id) else "NOT ENOUGH CASH"))
		var fee := Career.driver_buyout(d)
		_action(actions, "SIGN  %s" % (UIKit.money(fee) if fee > 0 else "FREE"), true, func() -> void:
			var error := Career.sign_driver(id, "reserve")
			driver_card(hub, id, "SIGNED  -  ON YOUR BENCH, RACE THEM FROM HERE" if error == "" else error))
	else:
		_action(actions, "BUY OUT  %s   (NEEDS REPUTATION %d)" % [UIKit.money(Career.release_clause(d)), Career.poach_reputation(d)], true, func() -> void:
			var error := Career.sign_driver(id, "reserve")
			driver_card(hub, id, "SIGNED  -  ON YOUR BENCH, RACE THEM FROM HERE" if error == "" else error))
	AudioManager.play("click", -10.0)


# ---------------------------------------------------------------- training (ADJUST)

## How hard a driver trains between races, full screen.
static func training_screen(hub: Control, id: String) -> void:
	var d := Career.driver(id)
	var color := _team_color(str(d["team"]))
	var made := open_full(hub, "TRAINING  ·  %s" % str(d["name"]).get_slice(" ", 1).to_upper(), color, func() -> void: driver_card(hub, id))
	var top: HBoxContainer = made[0]
	var body: VBoxContainer = made[1]
	top.add_child(_portrait(Career.person(id)["look"], color, 160))
	var info := _column(top)
	hub._text(info, str(d["name"]).to_upper(), 26)
	info.add_child(Art.rating_bar("FITNESS", Career.fitness(d), UIKit.GOOD if Career.fitness(d) >= 60 else UIKit.BAD, 520.0))
	info.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 520.0))
	hub._text(info, "OVR %d  ·  POTENTIAL %s  ·  ABOUT %+.2f PACE A RACE AT THIS SETTING" % [Career.driver_overall(d), str(Career.potential_overall(d)) if Career.scout_level(d) >= 3 else "??", Career.development_rate(d)], 16, UIKit.TEXT_DIM)
	var notes := ["Recovery week: fitness and morale come back, little learning.", "The usual programme: steady learning, fitness holds.",
		"Double sessions: faster learning, fitness drops race by race.", "Everything, every day: the fastest learning, but below 40 fitness they can break down."]
	for i in Career.TRAINING_NAMES.size():
		var chosen := Career.training(id) == i
		_action(body, "%s   ·   LEARNING x%.1f   ·   FITNESS %+d   ·   MORALE %+d\n%s" % [Career.TRAINING_NAMES[i], Career.TRAINING_GAIN[i], Career.TRAINING_FITNESS[i], Career.TRAINING_MORALE[i], notes[i]], chosen, func() -> void:
			Career.set_training(id, i)
			training_screen(hub, id))
	var sim_on: bool = d.get("sim", false)
	_action(body, "SIMULATOR PROGRAMME: %s   ·   %s A RACE   ·   EXTRA LEARNING, NO FITNESS COST" % ["ON" if sim_on else "OFF", UIKit.money(Career.SIMULATOR_COST)], sim_on, func() -> void:
		d["sim"] = not sim_on
		GameManager.save()
		training_screen(hub, id))
	hub._text(body, "Racing teaches more than training: points finishes count most. Young drivers learn fastest; a star team-mate mentors a youngster.", 14, UIKit.TEXT_DIM)


# ---------------------------------------------------------------- practice

## Practice and test days: choose a programme and up to two drivers (reserves too), then
## run the session - or drive it yourself.
static func practice_sheet(hub: Control, results: Array = []) -> void:
	var event := Career.day_event()
	var made := open_full(hub, "TEST DAY" if event["type"] == "test" else "FREE PRACTICE", UIKit.LINE)
	var body: VBoxContainer = made[1]
	if not results.is_empty():
		hub._text(body, "SESSION OVER", 24)
		for row: Dictionary in results:
			hub._text(body, "P%d   %s   ·   %+.2f PACE" % [int(row["position"]), str(row["name"]).to_upper(), float(row["gain"])], 20)
		hub._text(body, "Weekend bonuses and form are on the drivers' cards.", 15, UIKit.TEXT_DIM)
		return
	if not hub.has_meta("practice_program"):
		hub.set_meta("practice_program", "setup")
		hub.set_meta("practice_drivers", Career.lineup().duplicate())
	var program: String = hub.get_meta("practice_program")
	var chosen: Array = hub.get_meta("practice_drivers")
	hub._text(body, "PROGRAMME", 14, UIKit.HOT)
	for key: String in Career.PRACTICE_PROGRAMS:
		var p: Dictionary = Career.PRACTICE_PROGRAMS[key]
		_action(body, "%s\n%s" % [p["name"], p["note"]], key == program, func() -> void:
			hub.set_meta("practice_program", key)
			practice_sheet(hub))
	hub._text(body, "DRIVERS  (UP TO TWO CARS)", 14, UIKit.HOT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	for id: String in Career.lineup() + Career.reserves():
		var on := chosen.has(id)
		var d := Career.driver(id)
		_action(row, "%s\n%s" % [str(d["name"]).get_slice(" ", 1).to_upper(), "RACE SEAT" if Career.lineup().has(id) else "RESERVE"], on, func() -> void:
			if on:
				chosen.erase(id)
			elif chosen.size() < 2:
				chosen.append(id)
			practice_sheet(hub))
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 10)
	body.add_child(go)
	_action(go, "RUN THE SESSION", true, func() -> void:
		practice_sheet(hub, Career.run_practice(program, chosen)), chosen.is_empty())
	_action(go, "DRIVE IT YOURSELF  (%s)" % (str(Career.driver(chosen[0])["name"]).get_slice(" ", 1).to_upper() if not chosen.is_empty() else "-"), false, func() -> void:
		Career.prepare_practice(chosen[0]), chosen.is_empty())
	_action(go, "SKIP THE SESSION", false, func() -> void:
		Career.skip_practice()
		hub._close_modal()
		hub._show_tab(hub._tab))


# ---------------------------------------------------------------- staff and people

static func staff_card(hub: Control, id: String, note: String = "") -> void:
	var e := Career.engineer(id)
	var spec: Dictionary = Career.ENGINEER_SPECS[e["spec"]]
	var hired: bool = Career.engineers().has(id)
	var color := _team_color(str(e["team"]))
	var made := open_full(hub, str(e["name"]), color)
	var top: HBoxContainer = made[0]
	var body: VBoxContainer = made[1]
	top.add_child(_portrait(e["look"], color, 240))
	var info := _column(top)
	hub._text(info, str(spec["name"]), 28)
	hub._text(info, str(spec["note"]).to_upper(), 18, UIKit.TEXT_DIM)
	var chips := _chip_box(info)
	chips.add_child(Art.chip("SKILL", int(e["skill"]), UIKit.WARM))
	chips.add_child(Art.chip("AGE", int(e["age"]), Color("23262e")))
	hub._text(info, "%s A SEASON" % UIKit.money(float(e["salary"])), 20)
	var employer := Career.team(str(e["team"]))
	hub._text(info, "WORKS FOR %s" % str(employer.get("name", "NOBODY")).to_upper(), 18, UIKit.TEXT_DIM)
	if note != "":
		hub._text(info, note, 18, UIKit.ACCENT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	if hired:
		_action(actions, "FIRE   (%s SEVERANCE)" % UIKit.money(float(e["salary"]) * 0.25), false, func() -> void:
			hub._say(Career.fire_engineer(id))
			hub._close_modal()
			hub._show_tab(0))
	else:
		var fee := Career.engineer_buyout(e)
		_action(actions, "HIRE" if fee == 0 else "POACH  -  %s BUYOUT" % UIKit.money(fee), true, func() -> void:
			var error := Career.hire_engineer(id)
			staff_card(hub, id, "HIRED" if error == "" else error))


static func person_card(hub: Control, id: String) -> void:
	var p := Career.person(id)
	var color := _team_color(str(p["team"]))
	var made := open_full(hub, str(p["name"]), color)
	var top: HBoxContainer = made[0]
	top.add_child(_portrait(p["look"], color, 240))
	var info := _column(top)
	hub._text(info, str(p["role"]), 28)
	hub._text(info, str(Career.team(str(p["team"])).get("name", "")).to_upper(), 18, UIKit.TEXT_DIM)
	hub._text(info, str(STAFF_NOTES.get(p["role"], "")), 20)
	var count := 0
	for m: Dictionary in Career.state()["inbox"]:
		if m["from"] == id:
			count += 1
	hub._text(info, "%d MESSAGES ON YOUR PHONE" % count, 16, UIKit.TEXT_DIM)


# ---------------------------------------------------------------- the manager card

## You: the deal with the owners, your rating, history, how safe the job is, and the
## teams that would hire you (they pay your release fee).
static func manager_card(hub: Control, note: String = "") -> void:
	var c := Career.state()
	var contract := Career.manager_contract()
	var color := _team_color(str(c["team"]))
	var made := open_full(hub, str(c["manager"]["name"]), color)
	var top: HBoxContainer = made[0]
	var body: VBoxContainer = made[1]
	if note != "":
		body.move_child(hub._text(body, note, 18, UIKit.ACCENT), 0)
	top.add_child(_portrait(c["manager"]["look"], color, 240))
	var info := _column(top, 420)
	hub._text(info, "TEAM PRINCIPAL  ·  %s" % str(Career.my_team()["name"]).to_upper(), 20)
	var chips := _chip_box(info)
	chips.add_child(Art.chip("RATING", Career.manager_rating(), UIKit.WARM))
	chips.add_child(Art.chip("SEASONS", (c.get("history", []) as Array).size() + 1, Color("23262e")))
	var years := maxi(0, int(contract["years"]))
	hub._text(info, "DEAL  %s A YEAR" % UIKit.money(float(contract["salary"])), 22)
	hub._text(info, "EXPIRES END OF SEASON %d  (%d YEAR%s LEFT)" % [int(c["season"]) + maxi(0, years - 1), years, "" if years == 1 else "S"], 16, UIKit.TEXT_DIM)
	hub._text(info, "EARNED SO FAR  %s" % UIKit.money(float(c["manager"].get("earned", 0))), 16, UIKit.TEXT_DIM)
	var job := _column(top)
	hub._text(job, "JOB SECURITY", 14, UIKit.HOT)
	hub._text(job, Career.job_security(), 30, UIKit.GOOD if int(c["board"]) >= 40 else UIKit.BAD)
	job.add_child(Art.rating_bar("BOARD", int(c["board"]), UIKit.GOOD if int(c["board"]) >= 40 else UIKit.BAD, 420.0))
	job.add_child(Art.rating_bar("REPUTATION", int(c["reputation"]), UIKit.LINE, 420.0))
	hub._text(job, "TARGET: %s" % Career.board_target_text().to_upper(), 16, UIKit.TEXT_DIM)
	var history := Frame.make("HISTORY", 4)
	body.add_child(history)
	var past: Array = c.get("history", [])
	if past.is_empty():
		hub._text(history.body, "FIRST SEASON IN CHARGE", 18, UIKit.TEXT_DIM)
	for h: Dictionary in past:
		var t := Career.team(str(h["team"]))
		hub._text(history.body, "SEASON %d   %-18s P%d  (TARGET P%d)   %d PTS   %d WIN%s" % [int(h["season"]), str(t.get("name", "?")).to_upper().left(18), int(h["position"]), int(h["expected"]), int(h["points"]), int(h["wins"]), "" if int(h["wins"]) == 1 else "S"], 17, UIKit.GOOD if int(h["position"]) <= int(h["expected"]) else UIKit.BAD)
	var market := Frame.make("TEAMS THAT WANT YOU", 6)
	body.add_child(market)
	var offers := Career.interested_teams()
	if offers.is_empty():
		hub._text(market.body, "NOBODY YET  -  WIN MORE RACES", 18, UIKit.TEXT_DIM)
	for offer: Dictionary in offers:
		var t: Dictionary = offer["team"]
		var team_id: String = t["id"]
		_action(market.body, "%s   ·   %s A YEAR, 2 YEARS   ·   THEY PAY YOUR %s RELEASE FEE" % [str(t["name"]).to_upper(), UIKit.money(float(offer["salary"])), UIKit.money(float(offer["fee"]))], false, func() -> void:
			hub._show_modal("SWITCH TEAMS", str(t["name"]).to_upper(), "Leave %s for %s? Your cars, engineers and sponsor stay behind." % [Career.my_team()["name"], t["name"]], [
				["MOVE TO %s" % str(t["short"]), func() -> void:
					Career.move_to_team(team_id)
					Career.state()["season_review"] = {}
					GameManager.save()
					hub._close_modal()
					SceneManager.goto("career")],
				["STAY", func() -> void: manager_card(hub)]]))


# ---------------------------------------------------------------- hire staff

static func staff_sheet(hub: Control) -> void:
	var made := open_full(hub, "HIRE STAFF  %d / %d" % [Career.engineers().size(), Career.max_engineers()], UIKit.LINE)
	var body: VBoxContainer = made[1]
	for e: Dictionary in Career.engineer_market():
		var id: String = e["id"]
		var frame := Frame.make("", 4)
		body.add_child(frame)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		frame.body.add_child(line)
		line.add_child(_portrait(e["look"], _team_color(str(e["team"])), 76))
		var spec: Dictionary = Career.ENGINEER_SPECS[e["spec"]]
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		line.add_child(info)
		hub._text(info, str(e["name"]).to_upper(), 20)
		hub._text(info, "%s   ·   %s A SEASON" % [spec["name"], UIKit.money(float(e["salary"]))], 15, UIKit.TEXT_DIM)
		line.add_child(Art.chip("SKILL", int(e["skill"]), UIKit.LINE.darkened(0.2) if int(e["skill"]) >= 75 else Color("23262e")))
		var fee := Career.engineer_buyout(e)
		var b := UIKit.button("HIRE" if fee == 0 else "POACH\n%s" % UIKit.money(fee), 17, true)
		b.custom_minimum_size = Vector2(170, 66)
		b.pressed.connect(func() -> void:
			var error := Career.hire_engineer(id)
			staff_card(hub, id, "HIRED" if error == "" else error))
		line.add_child(press_anim(b))
		clickable(frame, func() -> void: staff_card(hub, id))


# ---------------------------------------------------------------- sponsors (sheet)

static func sponsor_sheet(hub: Control, note: String = "") -> void:
	var c := Career.state()
	var sponsor: Dictionary = c["sponsor"]
	var current := "NO SPONSOR" if sponsor.is_empty() else "%s   ·   %s A RACE   ·   %d RACES LEFT" % [str(sponsor["name"]).to_upper(), UIKit.money(sponsor["per_race"]), int(sponsor["races_left"])]
	var list: VBoxContainer = hub.open_sheet("SPONSORS", note if note != "" else current)
	var offers: Array = c["sponsor_offers"]
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var ok := int(c["reputation"]) >= int(offer["min_rep"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		list.add_child(line)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		line.add_child(info)
		hub._text(info, str(offer["name"]).to_upper(), 22)
		hub._text(info, "%s NOW   ·   %s A RACE   ·   %d RACES" % [UIKit.money(offer["signing"]), UIKit.money(offer["per_race"]), int(offer["races"])], 16)
		if not ok:
			hub._text(info, "NEEDS REPUTATION %d  (YOU: %d)" % [int(offer["min_rep"]), int(c["reputation"])], 14, UIKit.BAD)
		var nego := UIKit.button("HAGGLE", 16)
		nego.custom_minimum_size = Vector2(150, 66)
		nego.disabled = offer["negotiated"]
		nego.pressed.connect(func() -> void: sponsor_sheet(hub, Career.negotiate_sponsor(i).to_upper()))
		line.add_child(nego)
		var sign_button := UIKit.button("SIGN", 18, true)
		sign_button.custom_minimum_size = Vector2(150, 66)
		sign_button.disabled = not ok
		sign_button.pressed.connect(func() -> void:
			var error := Career.sign_sponsor(i)
			sponsor_sheet(hub, "DEAL SIGNED" if error == "" else error))
		line.add_child(sign_button)
	if offers.is_empty():
		hub._text(list, "NO OFFERS RIGHT NOW", 18, UIKit.TEXT_DIM)


# ---------------------------------------------------------------- season review

## Shown at HQ when a season ends: the result, then on into the next season - or, if your
## contract has run out, the renewal or a move.
static func season_review(hub: Control) -> void:
	var c := Career.state()
	var r: Dictionary = c["season_review"]
	var body := "P%d IN THE CONSTRUCTORS   ·   PRIZE %s\nDRIVERS' CHAMPION: %s\nCONSTRUCTORS' CHAMPION: %s" % [int(r["position"]), UIKit.money(float(r["payout"])), str(r["champion"]).to_upper(), str(r.get("team_champion", "?")).to_upper()]
	var options: Array = []
	match str(r.get("contract", "")):
		"renew":
			var contract := Career.manager_contract()
			body += "\n\nYour contract is up. The owners offer a new one."
			options.append(["SIGN: %s A YEAR FOR 2 YEARS" % UIKit.money(float(contract["salary"]) * 1.1), func() -> void:
				Career.renew_contract()
				hub._close_modal()
				hub._show_tab(0)])
			options.append(["LOOK AT OTHER TEAMS", func() -> void: manager_card(hub, "CHOOSE YOUR NEXT TEAM - OR CLOSE AND SIGN THE RENEWAL")])
		"expired":
			body += "\n\nYour contract is up and the owners will not renew it."
			if Career.interested_teams().is_empty():
				options.append(["START A NEW CAREER", func() -> void:
					Career.end_career()
					SceneManager.goto("career_start")])
			else:
				options.append(["SEE THE TEAMS THAT WANT YOU", func() -> void: manager_card(hub, "PICK YOUR NEXT TEAM")])
		_:
			options.append(["START SEASON %d" % int(c["season"]), func() -> void:
				c["season_review"] = {}
				GameManager.save()
				hub._close_modal()
				hub._show_tab(0)])
	hub._show_modal("SEASON %d COMPLETE" % int(r["season"]), "SEASON REVIEW", body, options)
