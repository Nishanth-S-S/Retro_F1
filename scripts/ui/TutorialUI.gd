class_name TutorialUI
extends Control
## Paged how-to-play overlay. Opens automatically the first time a save is used.

const PAGES := [
	{"title": "WELCOME, BOSS", "art": "portrait", "text": "You run a racing team. Pick one of 11 teams, hire drivers, find sponsors, develop the car - and keep the owners happy.\n\nEvery screen has a black title bar at the top and a back button. Red buttons are the main action."},
	{"title": "TEAM HQ", "art": "logo", "text": "HQ has six tabs: HQ, DRIVERS, SCOUTING, SPONSORS, FACTORY and STANDINGS.\n\nThe three numbers in the header rate your CAR, your DRIVERS and the whole TEAM out of 99.\n\nWatch BOARD confidence. If it hits zero you are fired."},
	{"title": "YOUR PHONE", "art": "phone", "text": "The phone in the HQ header is your inbox. Drivers text you after races, your race engineer reports damage bills, and rival bosses send offers.\n\nOffers have ACCEPT and DECLINE buttons. CONTACTS shows a profile for everyone in the paddock."},
	{"title": "RACE DAY", "art": "flag", "text": "Press GO TO RACE and choose how to run it:\n\nDRIVE IT - you race the car yourself.\nPIT WALL - call tires, pit stops, pace and team orders lap by lap.\nQUICK SIM - skip straight to the result."},
	{"title": "DRIVING", "art": "car", "text": "Left thumb steers. Right thumb is one pedal: up for throttle, down for brake. On a keyboard use WASD or the arrows.\n\nBrake before the corner, turn in, then feed the power back on. Hitting things fills the DAMAGE bar - at 100% the car is destroyed."},
	{"title": "THE GARAGE", "art": "helmet", "text": "Tap any part of the car to swap it. Better parts unlock when you level up the R&D LAB in the FACTORY tab.\n\nYou can build the car yourself, or pay your engineers to choose and fit an upgrade for you.\n\nGood luck."},
]

var _page := 0
var _title: Control
var _text: Label
var _art: Art
var _next: Button
var _counter: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 60
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_title = UIKit.title_bar("TUTORIAL")
	box.add_child(_title)
	var panel := UIKit.panel(UIKit.PANEL, UIKit.LINE)
	box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)
	_art = Art.make(Vector2(240, 240), _paint)
	row.add_child(_art)
	_text = UIKit.label("", 17)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(520, 280)
	row.add_child(_text)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)
	var back := UIKit.button("< BACK", 18)
	back.custom_minimum_size = Vector2(150, 56)
	back.pressed.connect(func() -> void: _show(maxi(0, _page - 1)))
	foot.add_child(back)
	_counter = UIKit.label("", 16, UIKit.TEXT_DIM)
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(_counter)
	var skip := UIKit.button("SKIP", 18)
	skip.custom_minimum_size = Vector2(120, 56)
	skip.pressed.connect(close)
	foot.add_child(skip)
	_next = UIKit.button("NEXT >", 18, true)
	_next.custom_minimum_size = Vector2(190, 56)
	_next.pressed.connect(func() -> void:
		if _page >= PAGES.size() - 1:
			close()
		else:
			_show(_page + 1))
	foot.add_child(_next)


func open() -> void:
	visible = true
	_show(0)


func close() -> void:
	visible = false
	if not bool(GameManager.profile.get("tutorial_seen", false)):
		GameManager.profile["tutorial_seen"] = true
		GameManager.save()


func _show(index: int) -> void:
	_page = index
	var page: Dictionary = PAGES[index]
	_title.set_meta("title", page["title"])
	_title.queue_redraw()
	_text.text = page["text"]
	_counter.text = "%d / %d" % [index + 1, PAGES.size()]
	_next.text = "LET'S GO" if index == PAGES.size() - 1 else "NEXT >"
	_art.queue_redraw()


func _paint(a: Control) -> void:
	var r := Rect2(Vector2.ZERO, a.size)
	a.draw_rect(r, UIKit.BG_DEEP)
	match str(PAGES[_page]["art"]):
		"portrait":
			PixelArt.draw_portrait(a, r.grow(-16.0), PixelArt.default_look(), UIKit.WARM, Color("d8e6dc"))
		"logo":
			PixelArt.draw_logo(a, r.grow(-40.0), {"color": "#c8201e", "color2": "#f4f6f2", "logo": "shield", "short": "HQ"})
		"phone":
			PixelArt.draw_phone(a, Vector2(72, 44), 12.0, 1)
		"flag":
			PixelArt.draw_flag(a, Vector2(50, 50), 16.0, Color.WHITE, UIKit.INK, Color("c9ccd1"))
		"car":
			a.draw_rect(Rect2(0, 70, a.size.x, 100), Color("1c1e22"))
			PixelArt.draw_checker(a, Rect2(190, 70, 16, 100), 8.0, Color.WHITE, UIKit.INK)
			PixelArt.draw_car(a, Vector2(20, 84), 6.0, UIKit.WARM, Color("f4f6f2"))
		"helmet":
			PixelArt.draw_helmet(a, r.grow(-24.0), UIKit.WARM, Color("f4f6f2"), 2)
	a.draw_rect(r, UIKit.LINE, false, 2.0)
