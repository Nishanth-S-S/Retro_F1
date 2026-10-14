class_name HubPanels
extends RefCounted
## Sheets and cards opened from Team HQ: hiring staff, sponsors, the list of rival drivers
## who can be bought out of their contracts, and the full driver card.
## Every function takes the hub and builds with the hub's helpers.

const TAB_SCOUTING := 2
## Stat rows on a driver card: label, key, scouting phase that reveals it.
const CARD_STATS: Array = [
	["PACE", "pace", 1], ["STARTS", "starts", 1], ["RACECRAFT", "racecraft", 2], ["CONSISTENCY", "consistency", 2],
	["OVERTAKING", "overtaking", 2], ["DEFENDING", "defending", 2], ["TYRE CARE", "tyres", 2], ["WET WEATHER", "wet", 2], ["EGO", "ego", 3],
]


static func _engineer_face(e: Dictionary, size: float) -> Art:
	var team := Career.team(str(e["team"]))
	var color := Color(str(team["color"])) if not team.is_empty() else Color("6a7078")
	return Art.make(Vector2(size, size), func(a: Control) -> void:
		PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), e["look"], color, Color("d8e6dc")))


static func _button(text: String, width: float, accent: bool, action: Callable, size: int = 12) -> Button:
	var b := UIKit.button(text, size, accent)
	b.custom_minimum_size = Vector2(width, 44)
	b.pressed.connect(action)
	return b


# ---------------------------------------------------------------- hire staff (sheet)

## Everyone you could hire: free agents first, then rival staff who cost a buyout.
static func staff_sheet(hub: Control, note: String = "") -> void:
	var list: VBoxContainer = hub.open_sheet("HIRE STAFF  %d / %d" % [Career.engineers().size(), Career.max_engineers()], note)
	for e: Dictionary in Career.engineer_market():
		var id: String = e["id"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		list.add_child(line)
		line.add_child(_engineer_face(e, 76))
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
			staff_sheet(hub, "%s JOINS THE TEAM" % str(e["name"]).to_upper() if error == "" else error))
		line.add_child(b)


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


# ---------------------------------------------------------------- rival drivers (buyouts)

static func poach_list(hub: Control) -> void:
	var rep := int(Career.state()["reputation"])
	hub._text(hub._content, "PAY THE RELEASE CLAUSE TO SIGN.  YOUR REPUTATION: %d" % rep, 16, UIKit.TEXT_DIM)
	for d: Dictionary in Career.poach_targets():
		var id: String = d["id"]
		var team := Career.team(str(d["team"]))
		var frame := Frame.make(str(team["name"]).to_upper(), 4)
		hub._content.add_child(frame)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		frame.body.add_child(row)
		row.add_child(hub._face(id, 84))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		hub._text(info, "%s  ·  %d" % [str(d["name"]).to_upper(), int(d["age"])], 20)
		var need := Career.poach_reputation(d)
		hub._text(info, "OVR %d   ·   CLAUSE %s" % [Career.driver_overall(d), UIKit.money(Career.release_clause(d))], 17)
		hub._text(info, "%s A SEASON   ·   NEEDS REPUTATION %d" % [UIKit.money(float(d["salary"])), need], 14, UIKit.TEXT_DIM if rep >= need else UIKit.BAD)
		var card := UIKit.button("CARD", 15)
		card.custom_minimum_size = Vector2(100, 70)
		card.pressed.connect(func() -> void: driver_card(hub, id))
		row.add_child(card)
		if hub._pending_seat == id:
			var choices := VBoxContainer.new()
			choices.add_theme_constant_override("separation", 4)
			row.add_child(choices)
			var seats: Array = Career.lineup().duplicate()
			if Career.reserves().size() < Career.MAX_RESERVES:
				seats.append("reserve")
			for seat: String in seats:
				var text := "AS RESERVE" if seat == "reserve" else "FOR %s" % str(Career.driver(seat)["name"]).get_slice(" ", 1).to_upper()
				var b := UIKit.button(text, 14, true)
				b.custom_minimum_size = Vector2(210, 40)
				b.pressed.connect(func() -> void:
					var error := Career.sign_driver(id, seat)
					hub._pending_seat = ""
					hub._say("%s bought out of the contract and signed." % d["name"] if error == "" else error, error == "")
					hub._show_tab(TAB_SCOUTING))
				choices.add_child(b)
		else:
			var buy := UIKit.button("BUY OUT", 17, true)
			buy.custom_minimum_size = Vector2(140, 70)
			buy.pressed.connect(func() -> void:
				hub._pending_seat = id
				hub._show_tab(TAB_SCOUTING))
			row.add_child(buy)


# ---------------------------------------------------------------- the driver card

## Full-screen card for one driver. What it shows depends on how much of the scouting
## report existed when the contract was signed: phase 1 pace, phase 2 racecraft, phase 3
## ego, potential, favourite conditions and the kind of car they want.
static func driver_card(hub: Control, id: String) -> void:
	var d := Career.driver(id)
	if d.is_empty():
		return
	var level := Career.scout_level(d)
	var mine: bool = Career.lineup().has(id) or Career.reserves().has(id)
	var team := Career.team(str(d["team"]))
	var c1 := Color(str(team["color"])) if not team.is_empty() else Color("6a7078")
	var c2 := Color(str(team.get("color2", "#f4f6f2")))
	hub._close_modal()
	var modal := Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.add_child(modal)
	hub._modal = modal
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := UIKit.panel(UIKit.PANEL, c1)
	panel.custom_minimum_size = Vector2(1080, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	box.add_child(cols)
	# --- left: who they are
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 8)
	left.add_child(faces)
	faces.add_child(hub._face(id, 160))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	faces.add_child(side)
	side.add_child(Art.make(Vector2(76, 76), func(a: Control) -> void:
		a.draw_rect(Rect2(Vector2.ZERO, a.size), UIKit.BG_DEEP)
		PixelArt.draw_helmet(a, Rect2(Vector2.ZERO, a.size), c1, c2, int(d["number"]))))
	if not team.is_empty():
		side.add_child(Art.make(Vector2(76, 76), func(a: Control) -> void: PixelArt.draw_logo(a, Rect2(Vector2.ZERO, a.size), team)))
	hub._text(left, str(d["name"]).to_upper(), 22)
	hub._text(left, "#%d  ·  AGE %d  ·  %s" % [int(d["number"]), int(d["age"]), str(team.get("name", "FREE AGENT")).to_upper()], 12, UIKit.TEXT_DIM)
	hub._text(left, "SALARY %s  ·  RELEASE CLAUSE %s" % [UIKit.money(float(d["salary"])), UIKit.money(Career.release_clause(d))], 12, UIKit.TEXT_DIM)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	left.add_child(chips)
	if level >= 2:
		chips.add_child(Art.chip("OVR", Career.driver_overall(d), UIKit.WARM))
	else:
		chips.add_child(Art.chip("OVR ??", int(d.get("hype", 70)), Color("6a7078")))
	if level >= 3:
		var potential := Career.potential_overall(d)
		chips.add_child(Art.chip("POTENTIAL", potential, UIKit.LINE if potential > Career.driver_overall(d) + 3 else Color("23262e")))
	else:
		chips.add_child(Art.make(Vector2(74, 58), func(a: Control) -> void:
			a.draw_rect(Rect2(Vector2.ZERO, a.size), Color("6a7078"))
			a.draw_rect(Rect2(Vector2.ZERO, a.size), UIKit.INK, false, 3.0)
			a.draw_string(UIKit.font(), Vector2(0, 16), "POTENTIAL", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 10, Color.WHITE)
			a.draw_string(UIKit.font(), Vector2(0, 46), "??", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 28, Color.WHITE)))
	if Career.is_injured(id):
		hub._text(left, "INJURED  -  OUT %d RACES" % int(d["injured"]), 13, UIKit.BAD)
	if level < 3:
		var why := "Signed without a full scouting report (%d/3). What the scouts never wrote down stays unknown." % level if mine else "Scouting report %d/3. Finish it BEFORE signing to see everything." % level
		var note: Label = hub._text(left, why, 11, UIKit.BAD)
		note.custom_minimum_size = Vector2(260, 0)
	# --- middle: every stat
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	cols.add_child(mid)
	hub._text(mid, "STATS", 12, UIKit.HOT)
	for stat: Array in CARD_STATS:
		if level >= int(stat[2]):
			mid.add_child(Art.rating_bar(stat[0], float(d[stat[1]]), UIKit.WARM if stat[1] == "ego" else UIKit.LINE, 330.0))
		else:
			hub._text(mid, "%-13s ??   (scouting phase %d)" % [stat[0], int(stat[2])], 11, UIKit.TEXT_DIM)
	if mine:
		mid.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 330.0))
	# --- right: where and in what they are quick
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	hub._text(right, "RACES BEST WHEN", 12, UIKit.HOT)
	if level >= 3:
		hub._text(right, "WEATHER    %s" % Career.weather_label(d), 12)
		hub._text(right, "HOME TRACK %s  (-%.2f s a lap)" % [GameManager.TRACK_NAMES.get(d["home"], "?"), Career.HOME_GAIN], 12, UIKit.GOOD)
		hub._text(right, "LOVES      %s CIRCUITS  (-%.2f s)" % [d["strong"], Career.TYPE_GAIN], 12, UIKit.GOOD)
		hub._text(right, "STRUGGLES  %s CIRCUITS  (+%.2f s)" % [d["weak"], Career.TYPE_GAIN], 12, UIKit.BAD)
		var kinds := PackedStringArray()
		for track_id: String in GameManager.TRACKS:
			var form := Career.track_form(d, track_id)
			if form != 0.0:
				kinds.append("%s %+.2f" % [GameManager.TRACK_NAMES[track_id], -form])
		hub._text(right, "BY TRACK   %s" % "   ".join(kinds), 11, UIKit.TEXT_DIM)
		hub._text(right, "CAR        WANTS %s" % Career.car_taste(d), 12)
	else:
		hub._text(right, "Weather, home track, favourite circuits and the car they want are on the last page of the scouting report.", 12, UIKit.TEXT_DIM)
	hub._text(right, "YOUR CARS", 12, UIKit.HOT)
	for car: Dictionary in Career.cars():
		var car_id: String = car["id"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		right.add_child(line)
		var fit := Career.car_fit(d, car)
		var has: bool = Career.lineup().has(id) and Career.car_for(id)["id"] == car_id
		var label: Label = hub._text(line, "%s  OVR %d  FIT %s" % [car["name"], int(round(Career.car_overall(car))), str(fit) if level >= 3 else "??"], 12, UIKit.GOOD if fit >= 80 and level >= 3 else UIKit.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Career.lineup().has(id):
			var b := UIKit.button("DRIVES IT" if has else "ASSIGN", 11, has)
			b.custom_minimum_size = Vector2(120, 34)
			b.disabled = has
			b.pressed.connect(func() -> void:
				Career.assign_car(id, car_id)
				driver_card(hub, id))
			line.add_child(b)
	var close := UIKit.button("CLOSE", 15, true)
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void:
		hub._close_modal()
		hub._show_tab(hub._tab))
	box.add_child(close)
	AudioManager.play("click", -10.0)
