extends Control
## Road to Glory home: your driver, the next race (drive it or simulate it), the championship,
## your last result and the milestones so far. Story scenes play here as they come up.

var _root: VBoxContainer
var _busy := false


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music(true)
	if not Glory.active() and not Glory.state().get("retired", false):
		SceneManager.goto("glory_start")
		return
	_build()
	if Glory.active():
		if not Glory.season_over():
			Glory.before_race()
		_play_scenes()


func _draw() -> void:
	UIKit.draw_backdrop(self, Rect2(Vector2.ZERO, size))


## Plays every queued scene in turn, then refreshes the page.
func _play_scenes() -> void:
	var id := Glory.next_scene()
	if id == "":
		_build()
		return
	var content := GloryStory.scene(id)
	if (content["lines"] as Array).is_empty():
		Glory.scene_done(id)
		_play_scenes()
		return
	StoryScene.play(self, content["lines"], content.get("choices", []), func(key: String) -> void:
		var action := GloryStory.choose(id, key)
		if action == "test":
			Glory.prepare_test()
		elif action == "complete":
			_show_complete()
		else:
			_play_scenes())


func _build() -> void:
	for child in get_children():
		if not child is StoryScene:
			child.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	move_child(margin, 0)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	var g := Glory.state()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_root.add_child(head)
	var back := UIKit.button("<-", 22)
	back.custom_minimum_size = Vector2(84, 58)
	back.pressed.connect(func() -> void: SceneManager.goto("menu"))
	head.add_child(back)
	var title := "ROAD TO GLORY  ·  %s" % Glory.SERIES[g["series"]]["name"] if g.get("phase", "climb") == "climb" else "FORMULA ONE  ·  %d" % int(g["year"])
	head.add_child(UIKit.title_bar(title))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	_root.add_child(cols)
	_driver_column(cols)
	_race_column(cols)
	_table_column(cols)


func _driver_column(parent: Control) -> void:
	var g := Glory.state()
	var you := Glory.me()
	var t := Glory.my_team()
	var frame := Frame.make("#%d  ·  AGE %d" % [int(you["number"]), int(you["age"])], 6)
	frame.custom_minimum_size = Vector2(390, 0)
	parent.add_child(frame)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	frame.body.add_child(top)
	var color := Color(str(t.get("color", "#c8201e")))
	var look: Dictionary = you["look"]
	top.add_child(Art.make(Vector2(120, 120), func(a: Control) -> void: PixelArt.draw_portrait(a, Rect2(Vector2.ZERO, a.size), look, color, Color("d8e6dc"))))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	info.add_child(UIKit.label(str(you["name"]).to_upper(), 20))
	info.add_child(UIKit.label(str(t.get("name", "")).to_upper(), 14, UIKit.TEXT_DIM))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	info.add_child(chips)
	chips.add_child(Art.chip("OVR", Glory.overall(), UIKit.WARM))
	chips.add_child(Art.chip("POTENTIAL", Career.potential_overall(you), UIKit.LINE))
	if g["phase"] == "climb":
		chips.add_child(Art.chip("F1 BUZZ", Glory._f1_interest(), Color("23262e")))
	for stat: Array in HubPanels.CARD_STATS:
		if stat[1] == "ego":
			continue
		frame.body.add_child(Art.rating_bar(stat[0], float(you[stat[1]]), UIKit.LINE, 360.0, Career.stat_cap(you, stat[1])))
	frame.body.add_child(Art.rating_bar("FITNESS", float(you.get("fitness", 90)), UIKit.GOOD, 360.0))
	var academy := str(g.get("academy", ""))
	frame.body.add_child(UIKit.label("ACADEMY: %s" % (Glory.ACADEMIES[academy]["name"] if academy != "" else "INDEPENDENT"), 12, UIKit.TEXT_DIM))


func _race_column(parent: Control) -> void:
	var g := Glory.state()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)
	if g.get("retired", false):
		var done := Frame.make("CAREER OVER", 8)
		done.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(done)
		var s: Dictionary = g["stats"]
		done.body.add_child(UIKit.label("%d STARTS  ·  %d WINS  ·  %d PODIUMS  ·  %d TITLES" % [int(s["starts"]), int(s["wins"]), int(s["podiums"]), int(s["titles"])], 20))
		_milestones(done.body)
		return
	var next := Frame.make("ROUND %d OF %d" % [int(g["round"]) + 1, Glory.rounds()], 8)
	col.add_child(next)
	if Glory.season_over():
		next.body.add_child(UIKit.label("SEASON COMPLETE", 26))
	else:
		next.body.add_child(UIKit.label(Glory.round_name(), 28))
		next.body.add_child(UIKit.label("%s  ·  STARTS P%d" % [GameManager.TRACK_NAMES.get(Glory.round_track(), ""), Glory.grid_position()], 18, UIKit.TEXT_DIM))
		var objective: Dictionary = g.get("objective", {})
		if not objective.is_empty():
			next.body.add_child(UIKit.label("OBJECTIVE: %s" % objective["text"], 16, Color("ffb347")))
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 10)
		next.body.add_child(buttons)
		var drive := UIKit.button("DRIVE\nTHE RACE", 24, true)
		drive.custom_minimum_size = Vector2(0, 110)
		drive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drive.pressed.connect(func() -> void: Glory.prepare_drive())
		buttons.add_child(drive)
		var sim := UIKit.button("SIMULATE", 20)
		sim.custom_minimum_size = Vector2(0, 110)
		sim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sim.pressed.connect(func() -> void:
			Glory.quick_sim()
			_build()
			_play_scenes())
		buttons.add_child(sim)
		next.body.add_child(UIKit.label("AT THE WHEEL: YOUR STATS DECIDE HOW MUCH OF THE CAR YOU CAN USE", 11, UIKit.TEXT_DIM))
	# Last result.
	var last: Dictionary = g.get("last", {})
	if not last.is_empty():
		var res := Frame.make("LAST RACE  ·  %s" % last["race"], 6)
		res.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(res)
		var pos := int(last["position"])
		res.body.add_child(UIKit.label("YOU: %s  (FROM P%d)" % ["DNF" if pos == 0 else "P%d" % pos, int(last["grid"])], 22, UIKit.GOOD if pos > 0 and pos <= 3 else UIKit.TEXT))
		for r: Dictionary in last["rows"]:
			if int(r["pos"]) <= 5 or r["id"] == "me":
				res.body.add_child(UIKit.label("%s%d  %s%s" % ["> " if r["id"] == "me" else "  ", int(r["pos"]), str(r["name"]).to_upper(), "  DNF" if r["dnf"] else ""], 14, UIKit.HOT if r["id"] == "me" else UIKit.TEXT))
	if g["phase"] == "f1":
		var retire := UIKit.button("RETIRE FROM RACING", 15)
		retire.custom_minimum_size = Vector2(0, 50)
		retire.pressed.connect(func() -> void:
			StoryScene.play(self, [["manager", "Are you sure? There's no coming back."]], [["no", "KEEP RACING"], ["yes", "RETIRE"]], func(key: String) -> void:
				if key == "yes":
					Glory.retire()
				_build()))
		col.add_child(retire)


func _table_column(parent: Control) -> void:
	var g := Glory.state()
	var frame := Frame.make("CHAMPIONSHIP", 4)
	frame.custom_minimum_size = Vector2(360, 0)
	parent.add_child(frame)
	var rows := Glory.standings()
	for i in rows.size():
		var r: Dictionary = rows[i]
		if i >= 10 and r["id"] != "me":
			continue
		var mine: bool = r["id"] == "me"
		var cast: bool = Glory.CAST.has(r["id"])
		var t := Glory.team(str(r["team"]))
		frame.body.add_child(UIKit.label("%2d  %-20s %4d" % [i + 1, str(r["name"]).to_upper().substr(0, 20), int(r["points"])], 14, UIKit.HOT if mine else (UIKit.ACCENT if cast else UIKit.TEXT)))
		if mine or cast:
			frame.body.get_child(frame.body.get_child_count() - 1).tooltip_text = str(t.get("name", ""))
	if g["phase"] == "climb":
		frame.body.add_child(UIKit.spacer(6))
		frame.body.add_child(UIKit.label("RIVALS IN ORANGE", 11, UIKit.TEXT_DIM))
	var news: Array = g.get("news", [])
	for line: String in news.slice(0, 3):
		frame.body.add_child(UIKit.label(line.to_upper(), 11, UIKit.TEXT_DIM))


func _milestones(parent: Control) -> void:
	for m: Dictionary in Glory.state()["milestones"]:
		parent.add_child(UIKit.label("%d  ·  %s" % [int(m["year"]), m["text"]], 16))


## The end of The Climb: the road you took, then the career that is yours from here.
func _show_complete() -> void:
	var overlay := ColorRect.new()
	overlay.color = UIKit.BG
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	box.add_child(UIKit.title_bar("ROAD TO GLORY COMPLETE", 58.0))
	for m: Dictionary in Glory.state()["milestones"]:
		var l := UIKit.label("%s" % m["text"], 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		var arrow := UIKit.label("|", 12, UIKit.TEXT_DIM)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(arrow)
	var s: Dictionary = Glory.state()["stats"]
	var stats := UIKit.label("%d STARTS  ·  %d WINS  ·  %d PODIUMS" % [int(s["starts"]), int(s["wins"]), int(s["podiums"])], 16, UIKit.TEXT_DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats)
	var welcome := UIKit.label("WELCOME TO FORMULA ONE.\nYOUR STORY IS NOW YOURS.", 28, UIKit.HOT)
	welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(welcome)
	var go := UIKit.button("CONTINUE CAREER", 22, true)
	go.custom_minimum_size = Vector2(420, 64)
	go.pressed.connect(func() -> void:
		Glory.join_f1()
		overlay.queue_free()
		_build()
		_play_scenes())
	box.add_child(go)
