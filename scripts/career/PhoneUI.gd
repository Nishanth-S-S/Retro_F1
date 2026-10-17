class_name PhoneUI
extends Control
## Your phone: texts from drivers, staff and rival bosses (some carry offers), plus a
## contacts list with a profile card for everyone in the paddock.

signal closed

const STAFF_NOTES := {
	"OWNER'S OFFICE": "Signs the cheques. Reads the standings every Monday. Not known for patience.",
	"RACE ENGINEER": "Runs your cars at the track. Texts you the damage report after every race.",
	"TECHNICAL DIRECTOR": "Leads the factory. Will tell you where an upgrade pays off - and when the cost cap is close.",
	"CHIEF SCOUT": "Watches the junior leagues so you don't have to. Sometimes sends a free tip.",
	"TEAM PRINCIPAL": "Your opposite number. Friendly at dinner, ruthless in the stewards' room.",
}

var _tab := 0
var _list: VBoxContainer
var _profile: VBoxContainer
var _tab_buttons: Array[Button] = []
var _note: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	center.add_child(row)
	# --- the handset
	var phone := UIKit.panel(UIKit.PANEL, UIKit.INK)
	phone.custom_minimum_size = Vector2(560, 660)
	row.add_child(phone)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	phone.add_child(body)
	body.add_child(UIKit.title_bar("PHONE", 44.0))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	for i in 2:
		var b := UIKit.button(["MESSAGES", "CONTACTS"][i], 14)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _show_tab(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var close := UIKit.button("X", 14, true)
	close.custom_minimum_size = Vector2(54, 46)
	close.pressed.connect(func() -> void:
		Career.mark_read()
		closed.emit()
		queue_free())
	tabs.add_child(close)
	_note = UIKit.label("", 12, UIKit.ACCENT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	# --- profile card
	var card := Frame.make("PROFILE", 6)
	card.custom_minimum_size = Vector2(430, 660)
	row.add_child(card)
	_profile = card.body
	_show_tab(0)
	_show_profile("engineer")


func _team_color(team_id: String) -> Color:
	var t := Career.team(team_id)
	return Color(str(t["color"])) if not t.is_empty() else Color("6a7078")


func _face(id: String, size: float) -> Art:
	var p := Career.person(id)
	return Art.make(Vector2(size, size), func(a: Control) -> void:
		if not p.is_empty():
			PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), p["look"], _team_color(p["team"]), Color("d8e6dc")))


func _show_tab(index: int) -> void:
	_tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if index == 0:
		_build_messages()
	else:
		_build_contacts()


func _build_messages() -> void:
	var inbox: Array = Career.state()["inbox"]
	if inbox.is_empty():
		_list.add_child(UIKit.label("No messages yet.", 13, UIKit.TEXT_DIM))
	for i in inbox.size():
		var m: Dictionary = inbox[i]
		var p := Career.person(m["from"])
		if p.is_empty():
			continue
		var bubble := UIKit.panel(Color("fff4f2") if not m["read"] else UIKit.PANEL, UIKit.BAD if not m["done"] else UIKit.GRID_BOLD)
		_list.add_child(bubble)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		bubble.add_child(row)
		var face := Button.new()
		face.flat = true
		face.focus_mode = Control.FOCUS_NONE
		face.custom_minimum_size = Vector2(64, 64)
		var art := _face(m["from"], 64)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.add_child(art)
		var sender: String = m["from"]
		face.pressed.connect(func() -> void: _show_profile(sender))
		row.add_child(face)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var team_short: String = Career.team(p["team"]).get("short", "FREE")
		col.add_child(UIKit.label("%s  ·  %s %s  ·  S%d R%d%s" % [str(p["name"]).to_upper(), p["role"], team_short, int(m["season"]), int(m["round"]) + 1, "" if m["read"] else "  NEW"], 10, UIKit.TEXT_DIM if m["read"] else UIKit.BAD))
		var text := UIKit.label(m["text"], 14)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(410, 0)
		col.add_child(text)
		if not m["done"]:
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 8)
			col.add_child(actions)
			for accept: bool in [true, false]:
				# Offers can name their own buttons (a poaching approach is "release" or "counter").
				var b := UIKit.button(str(m["offer"].get("yes" if accept else "no", "ACCEPT" if accept else "DECLINE")), 13, accept)
				b.custom_minimum_size = Vector2(200 if m["offer"].has("yes") else 130, 42)
				b.pressed.connect(func() -> void:
					_note.text = Career.resolve_offer(i, accept)
					AudioManager.play("cash" if accept else "click", -8.0)
					_show_tab(0))
				actions.add_child(b)


func _build_contacts() -> void:
	var last_team := "?"
	for id: String in Career.contacts():
		var p := Career.person(id)
		if p.is_empty():
			continue
		if p["team"] != last_team:
			last_team = p["team"]
			var t := Career.team(last_team)
			_list.add_child(UIKit.label(str(t.get("name", "FREE AGENTS")).to_upper(), 11, UIKit.ACCENT))
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.pressed.connect(func() -> void:
			AudioManager.play("click", -12.0)
			_show_profile(id))
		_list.add_child(b)
		var art := _face(id, 44)
		art.position = Vector2(8, 4)
		art.size = Vector2(44, 44)
		b.add_child(art)
		var name_label := UIKit.label("%s\n%s" % [str(p["name"]).to_upper(), p["role"]], 12)
		name_label.position = Vector2(64, 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_label)


func _show_profile(id: String) -> void:
	for child in _profile.get_children():
		_profile.remove_child(child)
		child.queue_free()
	var p := Career.person(id)
	if p.is_empty():
		return
	var team := Career.team(p["team"])
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_profile.add_child(top)
	top.add_child(_face(id, 160))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	top.add_child(side)
	if not team.is_empty():
		var t := team
		side.add_child(Art.make(Vector2(72, 72), func(a: Control) -> void: PixelArt.draw_logo(a, Rect2(Vector2.ZERO, a.size), t)))
	# The helmet is for a team's two race drivers only, not reserves or juniors.
	if p["kind"] == "driver" and Career.is_race_driver(id):
		var d := Career.driver(id)
		var c1 := _team_color(p["team"])
		var c2 := Color(str(team.get("color2", "#ffffff")))
		side.add_child(Art.make(Vector2(72, 72), func(a: Control) -> void:
			a.draw_rect(Rect2(Vector2.ZERO, a.size), UIKit.BG_DEEP)
			PixelArt.draw_helmet(a, Rect2(Vector2.ZERO, a.size), c1, c2, int(d["number"]))))
	_profile.add_child(UIKit.label(str(p["name"]).to_upper(), 22))
	_profile.add_child(UIKit.label("%s  ·  %s" % [p["role"], str(team.get("name", "Free agent")).to_upper()], 12, UIKit.ACCENT))
	if p["kind"] == "driver":
		var d := Career.driver(id)
		_profile.add_child(UIKit.label("#%d   AGE %d   SALARY %s   %d PTS" % [int(d["number"]), int(d["age"]), UIKit.money(float(d["salary"])), int(Career.state()["points"].get(id, 0))], 12, UIKit.TEXT_DIM))
		if Career.scout_level(d) < 3:
			_profile.add_child(UIKit.label("Scouting report %d/3 - full numbers in SCOUTING." % Career.scout_level(d), 12, UIKit.TEXT_DIM))
		else:
			_profile.add_child(Art.rating_bar("OVERALL", Career.driver_overall(d), UIKit.WARM, 400.0))
			for info: Array in [["PACE", d["pace"]], ["RACECRAFT", d["racecraft"]], ["CONSISTENT", d["consistency"]], ["EGO", d["ego"]]]:
				_profile.add_child(Art.rating_bar(info[0], float(info[1]), UIKit.LINE, 400.0))
		if Career.is_injured(id):
			_profile.add_child(UIKit.label("INJURED - OUT %d RACES" % int(d["injured"]), 13, UIKit.BAD))
		if Career.lineup().has(id):
			_profile.add_child(Art.rating_bar("MORALE", float(d["morale"]), UIKit.GOOD if int(d["morale"]) >= 45 else UIKit.BAD, 400.0))
			_profile.add_child(UIKit.label("YOUR DRIVER%s" % ("  ·  NUMBER ONE" if Career.state()["number_one"] == id else ""), 12, UIKit.GOOD))
	else:
		var note := UIKit.label(str(STAFF_NOTES.get(p["role"], "")), 13, UIKit.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(390, 0)
		_profile.add_child(note)
		if p["role"] == "TEAM PRINCIPAL" and not team.is_empty():
			_profile.add_child(Art.rating_bar("CAR", Career.car_rating(team["id"]), UIKit.LINE, 400.0))
			_profile.add_child(Art.rating_bar("TEAM", Career.team_rating(team["id"]), UIKit.WARM, 400.0))
			_profile.add_child(UIKit.label("CHAMPIONSHIP: %d PTS" % int(Career.state()["team_points"][team["id"]]), 12, UIKit.TEXT_DIM))
	var count := 0
	for m: Dictionary in Career.state()["inbox"]:
		if m["from"] == id:
			count += 1
	_profile.add_child(UIKit.label("%d message%s from this contact." % [count, "" if count == 1 else "s"], 11, UIKit.TEXT_DIM))
